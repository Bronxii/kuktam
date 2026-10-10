import { before, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeApp, deleteApp, App } from 'firebase-admin/app';
import { Firestore, Timestamp, getFirestore } from 'firebase-admin/firestore';
import { requireLocalEmulator } from './emulator-guard';
import { AccountBinding } from '../src/billing/account-binding';
import { AccountLifecycleStore } from '../src/accounts/account-lifecycle-store';
import { LifecycleStore } from '../src/billing/lifecycle-store';
import { PurchaseVerifier, tokenHash } from '../src/billing/verify-purchase';
import { PurchaseAcknowledger } from '../src/billing/acknowledge-purchase';
import { defaultRetryPolicy, newRecoveryGeneration } from '../src/billing/retry-policy';
import { FakePlayApi } from './fake-play-api';
import { FakeAcknowledgmentApi } from './fake-acknowledgment-api';
import { PACKAGE_NAME, PRODUCT_ID } from '../src/billing/play-purchase-api';
import { now } from './fixtures';
requireLocalEmulator(process.env);
let db: Firestore, app: App;
before(() => { app = initializeApp({ projectId: 'demo-kuktam-local' }, 'n4b3-integration'); db = getFirestore(app); });
after(async () => { if (app) await deleteApp(app); });
let sequence = 0;
const binding = new AccountBinding(Buffer.alloc(32, 68));
function deferred<T>() { let resolve!: (v: T) => void; const promise = new Promise<T>(r => { resolve = r; }); return { promise, resolve }; }
async function setup() {
  const uid = `n4b3-${++sequence}`, token = `synthetic-n4b3-${sequence}`, hash = tokenHash(token);
  let time = now;
  const clock = () => time;
  const accounts = new AccountLifecycleStore(db, binding, clock); await accounts.initializeActive({ uid }); await accounts.register({ uid }, 1);
  const play = new FakePlayApi(), ack = new FakeAcknowledgmentApi();
  const response = { packageName: PACKAGE_NAME, productId: PRODUCT_ID, purchaseToken: token, purchaseState: 'PURCHASED',
    acknowledgementState: 'PENDING', obfuscatedExternalAccountId: binding.forAuthenticatedAccount({ uid }), testPurchase: false };
  play.respond(token, response);
  const verifier = new PurchaseVerifier(db, play, binding, clock), store = new LifecycleStore(db, clock);
  const ledger = db.doc(`billingPurchases/${hash}`), state = ledger.collection('acknowledgment').doc('state');
  const effective = db.doc(`users/${uid}/entitlements/pro`);
  return { uid, token, hash, clock, accounts, play, ack, response, verifier, store, ledger, state, effective,
    verify: () => verifier.verify({ uid }, { purchaseToken: token }),
    run: () => new PurchaseAcknowledger(db, ack, clock, defaultRetryPolicy, () => 0.5).run(hash),
    advance: (ms = defaultRetryPolicy.leaseMs) => { time = Timestamp.fromMillis(time.toMillis() + ms); } };
}
async function code(p: Promise<unknown>, expected: string) { await assert.rejects(p, (e: any) => e.code === expected); }
for (const state of ['DELETING','DELETED'] as const) {
  test(`verification and ack denied before starting on ${state}`, async () => {
    const s = await setup(); await s.verify(); await s.accounts.advance({ uid: s.uid }, 1, 'DELETING');
    if (state === 'DELETED') await s.accounts.advance({ uid: s.uid }, 2, 'DELETED');
    await code(s.verify(), state === 'DELETED' ? 'accountDeleted' : 'accountDeleting');
    await code(s.run(), state === 'DELETED' ? 'accountDeleted' : 'accountDeleting'); assert.equal(s.ack.calls, 0);
  });
  test(`lookup in flight then ${state}: no grant`, async () => {
    const s = await setup(), entered = deferred<void>(), release = deferred<unknown>();
    s.play.handlers.set(s.token, async () => { entered.resolve(); return release.promise; });
    const task = s.verify(); await entered.promise; await s.accounts.advance({ uid: s.uid }, 1, 'DELETING');
    if (state === 'DELETED') await s.accounts.advance({ uid: s.uid }, 2, 'DELETED');
    release.resolve(s.response); await code(task, 'staleAccountGeneration'); assert.equal((await s.ledger.get()).exists, false);
  });
}
test('old purchased observation cannot overwrite newer terminal revision', async () => {
  const s = await setup(); await s.verify(); const entered = deferred<void>(), release = deferred<unknown>();
  s.play.handlers.set(s.token, async () => { entered.resolve(); return release.promise; });
  const task = s.verify(); await entered.promise; await s.ledger.update({ lifecycleRevision: 2, revokedAt: now, purchaseState: 'CANCELED' });
  release.resolve(s.response); await code(task, 'staleLifecycleRevision'); assert.equal((await s.ledger.get()).data()!.purchaseState, 'CANCELED');
});
test('ack in flight then deleting cannot restore disabled access', async () => {
  const s = await setup(); await s.verify(); const entered = deferred<void>(), release = deferred<unknown>();
  s.ack.handler = async () => { entered.resolve(); return release.promise; };
  const task = s.run(); await entered.promise;
  await s.accounts.advance({ uid: s.uid }, 1, 'DELETING'); release.resolve({ status: 'success' });
  const result = await task; assert.equal(result.status, 'stale'); assert.equal(result.reason, 'staleAccountGeneration');
  assert.equal((await s.ledger.get()).data()!.acknowledgementState, 'PENDING'); assert.equal((await s.effective.get()).data()!.active,false); assert.equal((await s.effective.get()).data()!.revision,2);
});
test('ack completion fenced by newer lifecycle revision', async () => {
  const s = await setup(); await s.verify(); const claim = await s.store.claimAck(s.hash, defaultRetryPolicy); assert.ok('claim' in claim);
  await s.ledger.update({ lifecycleRevision: 2, revokedAt: now });
  assert.equal((await s.store.completeAck(claim.claim, null, defaultRetryPolicy, () => 0)).status, 'stale');
});
test('operational timestamp updates do not invalidate ack fence', async () => {
  const s = await setup(); await s.verify(); const claim = await s.store.claimAck(s.hash, defaultRetryPolicy); assert.ok('claim' in claim);
  s.advance(1000); await s.store.recordCheck({ uid: s.uid }, s.hash, 1, 1, now, null);
  assert.equal((await s.store.completeAck(claim.claim, null, defaultRetryPolicy, () => 0)).status, 'acknowledged');
  assert.equal((await s.ledger.get()).data()!.lifecycleRevision, 2); assert.equal((await s.effective.get()).data()!.revision, 1);
});
test('old recovery generation and stale lease cannot commit', async () => {
  const s = await setup(); await s.verify(); const claim = await s.store.claimAck(s.hash, defaultRetryPolicy); assert.ok('claim' in claim);
  await s.state.update({ recoveryGeneration: 2 });
  assert.equal((await s.store.completeAck(claim.claim, null, defaultRetryPolicy, () => 0)).status, 'stale');
  await s.state.update({ recoveryGeneration: 1, leaseId: 'replacement' });
  assert.equal((await s.store.completeAck(claim.claim, null, defaultRetryPolicy, () => 0)).status, 'stale');
});
test('injected exponential retry, exhaustion preserves total and Pro; generation contract only', async () => {
  const s = await setup(); await s.verify(); const policy = { ...defaultRetryPolicy, attemptsPerGeneration: 3 };
  const worker = new PurchaseAcknowledger(db, s.ack, s.clock, policy, () => 0.5);
  s.ack.handler = async () => ({ status: 'temporaryFailure' });
  await worker.run(s.hash); let d = (await s.state.get()).data()!;
  assert.equal(d.nextRetryAt.toMillis() - d.lastAttemptAt.toMillis(), 60000);
  s.advance(60000); await worker.run(s.hash); d = (await s.state.get()).data()!;
  assert.equal(d.nextRetryAt.toMillis() - d.lastAttemptAt.toMillis(), 90000);
  s.advance(90000); assert.equal((await worker.run(s.hash)).status, 'acknowledgmentExhausted');
  d = (await s.state.get()).data()!; assert.equal(d.totalAttempts, 3); assert.equal(d.recoveryGeneration, 1);
  assert.equal((await s.effective.get()).data()!.active, true); assert.equal((await worker.run(s.hash)).status, 'acknowledgmentExhausted');
  assert.deepEqual(newRecoveryGeneration({ generation: 1, generationAttempts: 3, totalAttempts: 3 }, 1, policy),
    { generation: 2, generationAttempts: 0, totalAttempts: 3 });
});
test('external I/O timeout aborts adapter, late success cannot complete twice', async () => {
  const s = await setup(); await s.verify(); const release = deferred<unknown>(); let signal: AbortSignal | undefined;
  const api = { acknowledge: async (_q: unknown, options?: { signal: AbortSignal }) => { signal = options?.signal; return release.promise; } };
  const worker = new PurchaseAcknowledger(db, api, s.clock, { ...defaultRetryPolicy, ioTimeoutMs: 20 }, () => 0);
  assert.equal((await worker.run(s.hash)).status, 'acknowledgmentRetry'); assert.equal(signal!.aborted, true);
  release.resolve({ status: 'success' }); await Promise.resolve();
  assert.equal((await s.ledger.get()).data()!.acknowledgementState, 'PENDING');
});
test('Play success then local commit crash recovers after lease with alreadyAcknowledged', async () => {
  const s = await setup(); await s.verify();
  class CrashStore extends LifecycleStore { override async completeAck(..._args: Parameters<LifecycleStore['completeAck']>): ReturnType<LifecycleStore['completeAck']> { throw new Error('simulated lost process'); } }
  const worker = new PurchaseAcknowledger(db, s.ack, s.clock, defaultRetryPolicy, () => 0, new CrashStore(db, s.clock));
  await code(worker.run(s.hash), 'internalConflict'); assert.equal(s.ack.calls, 1); assert.equal((await s.state.get()).data()!.status, 'acknowledgmentPending');
  s.advance(); s.ack.handler = async () => ({ status: 'alreadyAcknowledged' }); assert.equal((await s.run()).status, 'acknowledged');
  assert.equal((await s.state.get()).data()!.totalAttempts, 2); assert.equal((await s.effective.get()).data()!.revision, 1);
});
test('v1 ledger and v1 lease recover safely into common v2 path', async () => {
  const s = await setup(); await s.verify(); const d = (await s.ledger.get()).data()!;
  for (const key of ['lifecycleRevision','lastCheckedAt','nextCheckAt','operationalError','accountGeneration','bindingKeyVersion']) delete d[key];
  d.schemaVersion = 1; await s.ledger.set(d);
  await s.state.set({ schemaVersion: 1, status: 'acknowledgmentPending', attemptCount: 2, lastAttemptAt: now,
    leaseId: 'crashed-v1', leaseUntil: Timestamp.fromMillis(now.toMillis() + defaultRetryPolicy.leaseMs), nextRetryAt: null, failure: null });
  assert.equal((await s.run()).status, 'busy'); s.advance(); assert.equal((await s.run()).status, 'acknowledged');
  const ack = (await s.state.get()).data()!; assert.equal(ack.schemaVersion, 2); assert.equal(ack.totalAttempts, 3);
  assert.equal((await s.ledger.get()).data()!.schemaVersion, 2); assert.equal((await s.ledger.get()).data()!.lifecycleRevision, 2);
});
test('malformed legacy ledger is structured failure, no external Play call', async () => {
  const s = await setup(); await s.ledger.set({ schemaVersion: 1, bad: true });
  await assert.rejects(s.verify(), (e: any) => ['invalidSchema','internalConflict'].includes(e.code)); assert.equal(s.play.calls, 0);
});
test('source-list change is an effective revision change even Pro stays active', async () => {
  const s = await setup(); await s.verify(); const ref = db.doc(`users/${s.uid}/entitlementGrants/promo`);
  await ref.set({ source: 'PROMO', status: 'ACTIVE', startsAt: now, expiresAt: null, createdAt: now, revokedAt: null });
  await s.verify(); assert.equal((await s.effective.get()).data()!.revision, 2);
  await ref.update({ status: 'REVOKED', revokedAt: now }); await s.verify();
  assert.equal((await s.effective.get()).data()!.revision, 3); assert.equal((await s.effective.get()).data()!.active, true);
});

test('stale account generation alone fences ack, even if marker still ACTIVE', async () => {
  const s = await setup(); await s.verify(); const claim = await s.store.claimAck(s.hash, defaultRetryPolicy); assert.ok('claim' in claim);
  await db.doc(`accountLifecycle/${s.uid}`).update({ generation: 2 });
  const result = await s.store.completeAck(claim.claim, null, defaultRetryPolicy, () => 0);
  assert.equal(result.status, 'stale'); assert.equal(result.reason, 'staleAccountGeneration');
});
test('v1 pending verification upgrades only via common lifecycle commit', async () => {
  const s = await setup(); s.play.respond(s.token, { ...s.response, purchaseState: 'PENDING' }); await s.verify();
  const d = (await s.ledger.get()).data()!;
  for (const key of ['lifecycleRevision','lastCheckedAt','nextCheckAt','operationalError','accountGeneration','bindingKeyVersion']) delete d[key];
  d.schemaVersion = 1; await s.ledger.set(d);
  s.play.respond(s.token, s.response); await s.verify();
  const result = (await s.ledger.get()).data()!; assert.equal(result.schemaVersion, 2); assert.equal(result.lifecycleRevision, 2);
  assert.equal((await s.effective.get()).data()!.active, true);
});

for (const elapsed of [defaultRetryPolicy.leaseMs - 1, defaultRetryPolicy.leaseMs, defaultRetryPolicy.leaseMs + 1]) {
 test(`closure: ack completion lease boundary ${elapsed}`, async () => {
  const s=await setup();await s.verify();const c=await s.store.claimAck(s.hash,defaultRetryPolicy);assert.ok('claim' in c);
  s.advance(elapsed);const r=await s.store.completeAck(c.claim,null,defaultRetryPolicy,()=>0.5);
  assert.equal(r.status,elapsed<defaultRetryPolicy.leaseMs?'acknowledged':'stale');
  assert.equal((await s.effective.get()).data()!.active,true);
 });
}
test('closure: ack completion one stored microsecond before expiry remains valid',async()=>{
 const s=await setup();await s.verify();const c=await s.store.claimAck(s.hash,defaultRetryPolicy);assert.ok('claim' in c);
 s.advance();const t=s.clock();await s.state.update({leaseUntil:new Timestamp(t.seconds,t.nanoseconds+1000)});
 assert.equal((await s.store.completeAck(c.claim,null,defaultRetryPolicy,()=>0.5)).status,'acknowledged');
});
test('closure: marker transition disables access atomically and replay preserves revision',async()=>{
 const s=await setup();await s.verify();await s.accounts.advance({uid:s.uid},1,'DELETING');
 const e=(await s.effective.get()).data()!;assert.equal(e.active,false);assert.equal(e.revision,2);
 await s.accounts.advance({uid:s.uid},2,'DELETING');assert.equal((await s.effective.get()).data()!.revision,2);
});

test('closure: submillisecond clock schedules ack retry without internal conflict',async()=>{
 const s=await setup();await s.verify();const precise=new Timestamp(now.seconds,1000);
 const store=new LifecycleStore(db,()=>precise),c=await store.claimAck(s.hash,defaultRetryPolicy);assert.ok('claim' in c);
 assert.equal((await store.completeAck(c.claim,'acknowledgmentTemporaryFailure',defaultRetryPolicy,()=>0.5)).status,'acknowledgmentRetry');
 assert.equal((await s.state.get()).data()!.nextRetryAt.toMillis(),now.toMillis()+60001);
});
