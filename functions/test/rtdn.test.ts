import { before, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeApp, deleteApp, App } from 'firebase-admin/app';
import { Firestore, Timestamp, Transaction, getFirestore } from 'firebase-admin/firestore';
import { requireLocalEmulator } from './emulator-guard';
import { AccountBinding } from '../src/billing/account-binding';
import { AccountLifecycleStore } from '../src/accounts/account-lifecycle-store';
import { PurchaseVerifier } from '../src/billing/verify-purchase';
import { PurchaseRevoker } from '../src/billing/revoke-purchase';
import { PurchaseAcknowledger } from '../src/billing/acknowledge-purchase';
import { LifecycleStore } from '../src/billing/lifecycle-store';
import { tokenHash, playGrantId } from '../src/billing/purchase-identity';
import { defaultRetryPolicy } from '../src/billing/retry-policy';
import { PACKAGE_NAME, PRODUCT_ID, PlayLookupError } from '../src/billing/play-purchase-api';
import { RtdnProcessor } from '../src/billing/rtdn/processor';
import { RtdnInboxStore, InboxClaim, readInbox } from '../src/billing/rtdn/inbox-store';
import { parseEnvelope, dedupeKey } from '../src/billing/rtdn/notification';
import { FakePlayApi } from './fake-play-api';
import { FakeVoidedApi } from './fake-voided-api';
import { FakeAcknowledgmentApi } from './fake-acknowledgment-api';
import { delivery, rtdnSource } from './rtdn-fixtures';
import { now, grant } from './fixtures';
requireLocalEmulator(process.env);
let db: Firestore, app: App, sequence = 0;
before(() => { app = initializeApp({ projectId: 'demo-kuktam-local' }, 'n4b5-rtdn'); db = getFirestore(app); });
after(async () => { if (app) await deleteApp(app); });
const binding = new AccountBinding(Buffer.alloc(32, 84));
function deferred<T>() { let resolve!: (v: T) => void; const promise = new Promise<T>(r => { resolve = r; }); return { promise, resolve }; }
async function setup(seed: 'none' | 'purchased' | 'pending' = 'purchased') {
  const uid = `n4b5-${++sequence}`, token = `synthetic-n4b5-${sequence}`, hash = tokenHash(token); let time = now;
  const clock = () => time, accounts = new AccountLifecycleStore(db, binding, clock);
  await accounts.initializeActive({ uid }); await accounts.register({ uid }, 1);
  const play = new FakePlayApi(), voided = new FakeVoidedApi(), ack = new FakeAcknowledgmentApi();
  const response = { packageName: PACKAGE_NAME, productId: PRODUCT_ID, purchaseToken: token,
    purchaseState: seed === 'pending' ? 'PENDING' : 'PURCHASED', acknowledgementState: 'PENDING',
    obfuscatedExternalAccountId: binding.forAuthenticatedAccount({ uid }), testPurchase: false };
  const observation = { packageName: PACKAGE_NAME, productId: PRODUCT_ID, purchaseToken: token, state: 'entitlementRevoked', authoritative: true, testPurchase: false };
  play.respond(token, response); voided.respond(observation);
  const verify = () => new PurchaseVerifier(db, play, binding, clock).verify({ uid }, { purchaseToken: token });
  if (seed !== 'none') await verify();
  const inbox = new RtdnInboxStore(db, clock, defaultRetryPolicy, () => 0.5);
  const service = (store: RtdnInboxStore = inbox) => new RtdnProcessor(db, rtdnSource, play, voided, binding, clock, store);
  const event = (id = '1', category = 'oneTime', type = 1, eventTime?: string) => delivery(token, `${uid}-${id}`, category, type, eventTime);
  const inboxRef = (id = '1') => db.doc(`rtdnInbox/${dedupeKey(rtdnSource, `${uid}-${id}`)}`);
  const ledger = db.doc(`billingPurchases/${hash}`), effective = db.doc(`users/${uid}/entitlements/pro`), playGrant = db.doc(`users/${uid}/entitlementGrants/${playGrantId(hash)}`);
  return { uid, token, hash, clock, accounts, play, voided, ack, response, observation, verify, inbox, service, event, inboxRef, ledger, effective, playGrant,
    advance: (ms = defaultRetryPolicy.leaseMs) => { time = Timestamp.fromMillis(time.toMillis() + ms); },
    revoke: () => new PurchaseRevoker(db, voided, new LifecycleStore(db, clock)).run(token),
    acknowledge: () => new PurchaseAcknowledger(db, ack, clock, defaultRetryPolicy, () => 0.5).run(hash) };
}
async function receive(s: Awaited<ReturnType<typeof setup>>, id = '1') {
  const p = parseEnvelope(s.event(id), rtdnSource); assert.ok(typeof p !== 'string'); await s.inbox.receive(p); return p;
}
async function legacy(s: Awaited<ReturnType<typeof setup>>) {
  const d = (await s.ledger.get()).data()!;
  for (const k of ['lifecycleRevision','lastCheckedAt','nextCheckAt','operationalError','accountGeneration','bindingKeyVersion']) delete d[k];
  d.schemaVersion = 1; await s.ledger.set(d);
}
test('unknown token resolved via fresh Play binding then existing verifier: durable Pro, transient token purged', async () => {
  const s = await setup('none'); const p = await receive(s);
  assert.equal((await s.inboxRef().get()).data()!.transientToken, s.token);
  assert.equal((await s.service().process(p.key)).outcome, 'lifecycleApplied');
  assert.equal(s.play.calls, 2); assert.equal((await s.effective.get()).data()!.active, true);
  const event = (await s.inboxRef().get()).data()!; assert.equal(event.status, 'PROCESSED'); assert.equal(event.transientToken, undefined);
  assert.ok(!JSON.stringify(event).includes(s.token));
});
test('known ledger avoids raw token duplication; duplicate message skips lookup and revisions', async () => {
  const s = await setup(); await s.service().handle(s.event()); const calls = s.play.calls;
  assert.equal((await s.inboxRef().get()).data()!.transientToken, undefined);
  assert.equal((await s.service().handle(s.event())).outcome, 'duplicate'); assert.equal(s.play.calls, calls);
  await s.service().handle(s.event('2')); assert.equal((await s.ledger.get()).data()!.lifecycleRevision, 1);
  assert.equal((await s.effective.get()).data()!.revision, 1);
});
test('same source/message with different content is conflict, existing inbox immutable', async () => {
  const s = await setup(); await s.service().handle(s.event());
  const before = await s.inboxRef().get(); assert.equal((await s.service().handle(s.event('1','voided'))).outcome, 'messageConflict');
  assert.ok(before.updateTime!.isEqual((await s.inboxRef().get()).updateTime!));
});
test('notification PURCHASED does not grant when fresh state is PENDING', async () => {
  const s = await setup('none'); s.play.respond(s.token, { ...s.response, purchaseState: 'PENDING' });
  assert.equal((await s.service().handle(s.event())).outcome, 'processed'); assert.equal((await s.playGrant.get()).exists, false);
});
test('notification CANCELED does not revoke fresh PURCHASED', async () => {
  const s = await setup(); assert.equal((await s.service().handle(s.event('1','oneTime',2))).outcome, 'lifecycleApplied');
  assert.equal((await s.effective.get()).data()!.active, true); assert.equal(s.voided.calls, 0);
});
for (const [name, state, outcome, active] of [
  ['confirmed','entitlementRevoked','lifecycleApplied',false], ['refundOnly','financialRefund','processed',true],
  ['ambiguous','unknown','purchaseUnresolved',true],
] as const) test(`voided event ${name}: fresh N4B.4 decision`, async () => {
  const s = await setup(); s.voided.respond({ ...s.observation, state });
  assert.equal((await s.service().handle(s.event('1','voided'))).outcome, outcome); assert.equal((await s.effective.get()).data()!.active, active);
});
test('duplicate revoke different messages has no lifecycle/effective revision churn', async () => {
  const s = await setup(); await s.service().handle(s.event('1','voided')); await s.service().handle(s.event('2','voided'));
  assert.equal((await s.ledger.get()).data()!.lifecycleRevision, 2); assert.equal((await s.effective.get()).data()!.revision, 2);
});
test('newer revoke delivered first, ancient purchased later cannot reactivate', async () => {
  const s = await setup(); await s.service().handle(s.event('new','voided',1,'1791321700000'));
  assert.equal((await s.service().handle(s.event('old','oneTime',1,'1503349566168'))).outcome, 'staleNoOp');
  assert.equal((await s.effective.get()).data()!.active, false);
});
for (const category of ['oneTime','voided']) for (const config of [false,true]) test(`${category} API ${config ? 'config' : 'temporary'} failure retains Pro with durable safe status`, async () => {
  const s = await setup();
  if (category === 'oneTime') s.play.handlers.set(s.token, async () => { throw new PlayLookupError(config ? 'configuration' : 'unavailable'); });
  else s.voided.fail(config ? 'configuration' : 'unavailable');
  const r = await s.service().handle(s.event('1',category));
  assert.equal(r.outcome, config ? 'permanentConfigurationFailure' : 'retryablePlayFailure');
  assert.equal((await s.inboxRef().get()).data()!.status, config ? 'UNRESOLVED' : 'RETRY');
  assert.equal((await s.effective.get()).data()!.active, true); assert.ok(!JSON.stringify(r).includes(s.token));
  assert.equal((await s.service().handle(s.event('1',category))).outcome, config ? 'recoveryRequired' : 'retryDeferred');
});
for (const scenario of ['noBinding','unregistered','tombstoned']) test(`unknown token owner resolution: ${scenario}`, async () => {
  const s = await setup('none');
  if (scenario === 'noBinding') s.play.respond(s.token, { ...s.response, obfuscatedExternalAccountId: null });
  else if (scenario === 'unregistered') await db.doc(`billingAccountBindings/${s.response.obfuscatedExternalAccountId}`).delete();
  else await db.doc(`billingAccountBindings/${s.response.obfuscatedExternalAccountId}`).set({ schemaVersion: 1, state: 'TOMBSTONED', keyVersion: 'v1', createdAt: now, updatedAt: now });
  assert.equal((await s.service().handle(s.event())).outcome, scenario === 'tombstoned' ? 'bindingTombstoned' : 'purchaseUnresolved');
  assert.equal((await s.playGrant.get()).exists, false);
});
test('unknown voided owner may resolve but no invented ledger/grant is created', async () => {
  const s = await setup('none'); assert.equal((await s.service().handle(s.event('1','voided'))).outcome, 'purchaseUnresolved');
  assert.equal((await s.ledger.get()).exists, false); assert.equal((await s.effective.get()).exists, false);
});
for (const state of ['DELETING','DELETED'] as const) test(`${state} account cannot activate via RTDN binding resolution`, async () => {
  const s = await setup('none'); await s.accounts.advance({ uid: s.uid },1,'DELETING');
  if (state === 'DELETED') await s.accounts.advance({ uid: s.uid },2,'DELETED');
  assert.equal((await s.service().handle(s.event())).outcome, 'staleNoOp'); assert.equal((await s.playGrant.get()).exists, false);
});
for (const source of ['PROMO','ADMIN'] as const) test(`RTDN revoke keeps ${source}`, async () => {
  const s = await setup(); await db.doc(`users/${s.uid}/entitlementGrants/other`).set(grant({ source })); await s.verify();
  await s.service().handle(s.event('1','voided')); const e = (await s.effective.get()).data()!;
  assert.equal(e.active, true); assert.deepEqual(e.sources, [source]);
});
test('test notification no Play call, no ledger/grant mutation, inbox ignored', async () => {
  const s = await setup('none'); assert.equal((await s.service().handle(s.event('1','test'))).outcome, 'ignoredTestNotification');
  assert.equal(s.play.calls,0); assert.equal(s.voided.calls,0); assert.equal((await s.ledger.get()).exists,false);
  assert.equal((await s.inboxRef().get()).data()!.status,'IGNORED');
});
test('malformed identified event durable terminal, repeats do not retry', async () => {
  const s = await setup(), e = { ...s.event(), data: Buffer.from('{').toString('base64') };
  assert.equal((await s.service().handle(e)).outcome,'malformedNotification'); assert.equal((await s.service().handle(e)).outcome,'duplicate');
  assert.equal((await s.inboxRef().get()).data()!.attemptCount,0);
});
test('two simultaneous same-message workers: active lease cannot be stolen', async () => {
  const s = await setup(), entered = deferred<void>(), release = deferred<unknown>();
  s.play.handlers.set(s.token,async () => { entered.resolve(); return release.promise; });
  const first = s.service().handle(s.event()); await entered.promise;
  assert.equal((await s.service().handle(s.event())).outcome,'busyLease'); release.resolve(s.response);
  assert.equal((await first).outcome,'lifecycleApplied'); assert.equal((await s.inboxRef().get()).data()!.attemptCount,1);
});
test('crash after claim before lookup: expired lease takeover, old finish fenced', async () => {
  const s = await setup(), p = await receive(s), old = await s.inbox.claim(p.key); assert.ok(typeof old !== 'string');
  assert.equal(await s.inbox.claim(p.key),'busyLease'); s.advance();
  assert.equal((await s.service().process(p.key)).outcome,'lifecycleApplied');
  assert.equal(await s.inbox.finish(old,'PROCESSED','processed'),false); assert.equal((await s.inboxRef().get()).data()!.attemptCount,2);
});
test('expired worker late Play result cannot mutate lifecycle after takeover', async () => {
  const s = await setup('pending'), entered = deferred<void>(), release = deferred<unknown>();
  s.play.handlers.set(s.token,async () => { entered.resolve(); return release.promise; });
  const old = s.service().handle(s.event()); await entered.promise; s.advance();
  s.play.respond(s.token,s.response); assert.equal((await s.service().handle(s.event())).outcome,'processed');
  release.resolve({ ...s.response,purchaseState:'PURCHASED' }); assert.equal((await old).outcome,'staleNoOp');
  assert.equal((await s.playGrant.get()).exists,false); assert.equal((await s.ledger.get()).data()!.purchaseState,'PENDING');
});
test('process crash after fresh lookup before lifecycle write replays safely', async () => {
  const s = await setup('pending'); s.play.respond(s.token,{ ...s.response,purchaseState:'PURCHASED' });
  class CrashInbox extends RtdnInboxStore {
    override async assertLease(_tx: Transaction,_claim: InboxClaim): Promise<void> { throw new Error('synthetic process loss'); }
    override async finish(): Promise<boolean> { throw new Error('synthetic process loss'); }
  }
  assert.equal((await s.service(new CrashInbox(db,s.clock)).handle(s.event())).outcome,'internalConflict');
  assert.equal((await s.playGrant.get()).exists,false); s.advance();
  assert.equal((await s.service().handle(s.event())).outcome,'lifecycleApplied'); assert.equal((await s.effective.get()).data()!.revision,1);
});
test('lifecycle commit success + inbox commit failure: replay idempotent and finally processed', async () => {
  const s = await setup('none');
  class CrashInbox extends RtdnInboxStore { override async finish(): Promise<boolean> { throw new Error('synthetic commit crash'); } }
  assert.equal((await s.service(new CrashInbox(db,s.clock)).handle(s.event())).outcome,'internalConflict');
  assert.equal((await s.effective.get()).data()!.active,true); assert.equal((await s.inboxRef().get()).data()!.status,'PROCESSING');
  s.advance(); assert.equal((await s.service().handle(s.event())).outcome,'lifecycleApplied');
  assert.equal((await s.effective.get()).data()!.revision,1); assert.equal((await s.ledger.get()).data()!.lifecycleRevision,1);
});
test('RTDN verification vs direct verification produces one durable outcome', async () => {
  const s = await setup('none'); const results = await Promise.allSettled([s.service().handle(s.event()),s.verify()]);
  assert.equal(results.length,2); assert.equal((await s.effective.get()).data()!.revision,1);
  assert.equal((await db.collection(`users/${s.uid}/entitlementGrants`).get()).size,1);
});
test('RTDN revoke commits during direct verification lookup: stale purchase cannot activate', async () => {
  const s = await setup(), entered = deferred<void>(), release = deferred<unknown>();
  s.play.handlers.set(s.token,async () => { entered.resolve(); return release.promise; });
  const v = s.verify(); await entered.promise; await s.service().handle(s.event('1','voided')); release.resolve(s.response);
  await assert.rejects(v); assert.equal((await s.effective.get()).data()!.active,false);
});
test('RTDN revoke while ack external call in flight cancels completion', async () => {
  const s = await setup(), entered = deferred<void>(), release = deferred<unknown>();
  s.ack.handler=async () => { entered.resolve(); return release.promise; };
  const a=s.acknowledge(); await entered.promise; await s.service().handle(s.event('1','voided')); release.resolve({status:'success'});
  assert.equal((await a).status,'stale'); assert.equal((await s.effective.get()).data()!.active,false);
});
for (const state of ['DELETING','DELETED'] as const) test(`RTDN lookup races ${state}: old account generation denied`, async () => {
  const s=await setup('pending'), entered=deferred<void>(), release=deferred<unknown>();
  s.play.handlers.set(s.token,async () => { entered.resolve(); return release.promise; });
  const task=s.service().handle(s.event()); await entered.promise; await s.accounts.advance({uid:s.uid},1,'DELETING');
  if(state==='DELETED') await s.accounts.advance({uid:s.uid},2,'DELETED');
  release.resolve({...s.response,purchaseState:'PURCHASED'}); assert.equal((await task).outcome,'staleNoOp'); assert.equal((await s.playGrant.get()).exists,false);
});
test('RTDN stale lifecycle revision retry does not overwrite newer ack', async () => {
  const s=await setup(),entered=deferred<void>(),release=deferred<unknown>();
  s.play.handlers.set(s.token,async () => {entered.resolve();return release.promise;});
  const task=s.service().handle(s.event());await entered.promise;await s.acknowledge();release.resolve(s.response);
  assert.equal((await task).outcome,'staleNoOp');assert.equal((await s.ledger.get()).data()!.acknowledgementState,'ACKNOWLEDGED');
  assert.equal((await s.inboxRef().get()).data()!.status,'RETRY');
});
for(const category of ['oneTime','voided']) test(`v1 ledger RTDN ${category} safe v2 write`,async()=>{
  const s=await setup();await legacy(s);
  if(category==='voided') await s.ledger.collection('acknowledgment').doc('state').set({schemaVersion:1,status:'acknowledgmentPending',attemptCount:1,lastAttemptAt:now,leaseId:'old',leaseUntil:Timestamp.fromMillis(now.toMillis()+120000),nextRetryAt:null,failure:null});
  assert.equal((await s.service().handle(s.event('1',category))).outcome,'lifecycleApplied');
  assert.equal((await s.ledger.get()).data()!.schemaVersion,2);
  if(category==='voided') assert.equal((await s.ledger.collection('acknowledgment').doc('state').get()).data()!.status,'acknowledgmentCanceled');
});
test('retry budget bounded without scheduler; outstanding event remains operator-recoverable',async()=>{
  const s=await setup();s.play.handlers.set(s.token,async()=>{throw new PlayLookupError('unavailable');});
  const policy={...defaultRetryPolicy,attemptsPerGeneration:2},store=new RtdnInboxStore(db,s.clock,policy,()=>0);
  await s.service(store).handle(s.event());s.advance();await s.service(store).handle(s.event());s.advance();
  assert.equal((await s.service(store).handle(s.event())).outcome,'recoveryRequired');
  const r=readInbox((await s.inboxRef().get()).data());assert.equal(r.status,'UNRESOLVED');assert.equal(r.attemptCount,2);
  assert.equal((await s.effective.get()).data()!.active,true);
});

test('known ledger still honors binding tombstone; no automatic transfer', async () => {
  const s = await setup(); await db.doc(`billingAccountBindings/${s.response.obfuscatedExternalAccountId}`).set({ schemaVersion: 1, state: 'TOMBSTONED', keyVersion: 'v1', createdAt: now, updatedAt: now });
  const before = await s.effective.get(); assert.equal((await s.service().handle(s.event())).outcome, 'bindingTombstoned');
  assert.ok(before.updateTime!.isEqual((await s.effective.get()).updateTime!));
});
test('unknown purchase config failure retains transient token for operator recovery, does not loop', async () => {
  const s = await setup('none'); s.play.handlers.set(s.token, async () => { throw new PlayLookupError('configuration'); });
  assert.equal((await s.service().handle(s.event())).outcome, 'permanentConfigurationFailure');
  const r = readInbox((await s.inboxRef().get()).data()); assert.equal(r.transientToken, s.token); assert.equal(r.nextRetryAt, null);
  s.advance(86400000); assert.equal((await s.service().handle(s.event())).outcome, 'recoveryRequired'); assert.equal(s.play.calls, 1);
});
test('RTDN fresh canceled lookup uses authoritative pending cancellation, not notification type', async () => {
  const s = await setup('pending'); s.play.respond(s.token, { ...s.response, purchaseState: 'CANCELED' });
  s.voided.respond({ ...s.observation, state: 'pendingCanceled' });
  assert.equal((await s.service().handle(s.event())).outcome, 'lifecycleApplied');
  assert.equal((await s.ledger.get()).data()!.revokeReason, 'PENDING_CANCELED'); assert.equal((await s.playGrant.get()).exists, false);
});
test('temporary failure then explicit replay performs fresh lookup and finalizes', async () => {
  const s = await setup(); s.play.handlers.set(s.token, async () => { throw new Error('synthetic secret upstream'); });
  assert.equal((await s.service().handle(s.event())).outcome, 'retryablePlayFailure');
  s.advance(); s.play.respond(s.token,s.response); assert.equal((await s.service().process(dedupeKey(rtdnSource,`${s.uid}-1`))).outcome,'lifecycleApplied');
  assert.equal((await s.inboxRef().get()).data()!.status,'PROCESSED');
});
test('receive/claim legacy ledger do not perform a preliminary migration', async () => {
  const s = await setup(); await legacy(s); const before = await s.ledger.get();
  const p = await receive(s); await s.inbox.claim(p.key);
  assert.equal((await s.ledger.get()).data()!.schemaVersion,1); assert.ok(before.updateTime!.isEqual((await s.ledger.get()).updateTime!));
});
test('invalid replay key is rejected without echoing token-shaped input', async () => {
  const s=await setup(); assert.deepEqual(await s.service().process(s.token), {outcome:'malformedNotification'});
});
test('corrupt inbox schema fails closed without Play call', async () => {
  const s=await setup('none'); await receive(s); await s.inboxRef().update({lastOutcome:'raw-unsafe-error'});
  assert.equal((await s.service().handle(s.event())).outcome,'internalConflict'); assert.equal(s.play.calls,0);
});

test('crash on final allowed claim becomes explicit UNRESOLVED without another lookup', async () => {
  const s = await setup(); const p = await receive(s);
  const store = new RtdnInboxStore(db, s.clock, { ...defaultRetryPolicy, attemptsPerGeneration: 1 }, () => 0);
  const claimed = await store.claim(p.key); assert.ok(typeof claimed !== 'string'); s.advance();
  assert.equal(await store.claim(p.key), 'recoveryRequired');
  const r = readInbox((await s.inboxRef().get()).data()); assert.equal(r.status, 'UNRESOLVED'); assert.equal(r.leaseId, null);
  assert.equal(r.lastOutcome, 'recoveryRequired'); assert.equal(r.attemptCount, 1);
});
