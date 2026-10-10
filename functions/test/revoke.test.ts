import { before, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeApp, deleteApp, App } from 'firebase-admin/app';
import { Firestore, Transaction, getFirestore } from 'firebase-admin/firestore';
import { requireLocalEmulator } from './emulator-guard';
import { AccountBinding } from '../src/billing/account-binding';
import { AccountLifecycleStore } from '../src/accounts/account-lifecycle-store';
import { LifecycleStore } from '../src/billing/lifecycle-store';
import { PurchaseVerifier } from '../src/billing/verify-purchase';
import { PurchaseRevoker } from '../src/billing/revoke-purchase';
import { PurchaseAcknowledger } from '../src/billing/acknowledge-purchase';
import { tokenHash, playGrantId } from '../src/billing/purchase-identity';
import { defaultRetryPolicy } from '../src/billing/retry-policy';
import { FakePlayApi } from './fake-play-api';
import { FakeAcknowledgmentApi } from './fake-acknowledgment-api';
import { FakeVoidedApi } from './fake-voided-api';
import { PACKAGE_NAME, PRODUCT_ID } from '../src/billing/play-purchase-api';
import { now, grant } from './fixtures';
requireLocalEmulator(process.env);
let db: Firestore, app: App;
before(() => { app = initializeApp({ projectId: 'demo-kuktam-local' }, 'n4b4-revoke'); db = getFirestore(app); });
after(async () => { if (app) await deleteApp(app); });
let sequence = 0;
const binding = new AccountBinding(Buffer.alloc(32, 74));
function deferred<T>() { let resolve!: (v: T) => void; const promise = new Promise<T>(r => { resolve = r; }); return { promise, resolve }; }
async function setup(pending = false, testPurchase = false) {
  const uid = `n4b4-${++sequence}`, token = `synthetic-n4b4-${sequence}`, hash = tokenHash(token), clock = () => now;
  const accounts = new AccountLifecycleStore(db, binding, clock); await accounts.initializeActive({ uid }); await accounts.register({ uid }, 1);
  const play = new FakePlayApi(), api = new FakeVoidedApi(), ack = new FakeAcknowledgmentApi();
  const response = { packageName: PACKAGE_NAME, productId: PRODUCT_ID, purchaseToken: token,
    purchaseState: pending ? 'PENDING' : 'PURCHASED', acknowledgementState: 'PENDING',
    obfuscatedExternalAccountId: binding.forAuthenticatedAccount({ uid }), testPurchase };
  const observation = { packageName: PACKAGE_NAME, productId: PRODUCT_ID, purchaseToken: token,
    state: 'entitlementRevoked', authoritative: true, testPurchase };
  play.respond(token, response); api.respond(observation);
  const verifier = new PurchaseVerifier(db, play, binding, clock), store = new LifecycleStore(db, clock);
  const verify = () => verifier.verify({ uid }, { purchaseToken: token }); await verify();
  const ledger = db.doc(`billingPurchases/${hash}`), state = ledger.collection('acknowledgment').doc('state');
  const effective = db.doc(`users/${uid}/entitlements/pro`), playGrant = db.doc(`users/${uid}/entitlementGrants/${playGrantId(hash)}`);
  return { uid, token, hash, accounts, play, api, ack, response, observation, verifier, store, ledger, state, effective, playGrant, verify,
    run: () => new PurchaseRevoker(db, api, store).run(token),
    acknowledge: () => new PurchaseAcknowledger(db, ack, clock, defaultRetryPolicy, () => 0.5, store).run(hash) };
}
async function unchanged(ref: FirebaseFirestore.DocumentReference, before: FirebaseFirestore.DocumentSnapshot) {
  const after = await ref.get(); assert.equal(after.exists, before.exists);
  if (before.exists) assert.ok(before.updateTime!.isEqual(after.updateTime!));
}
test('confirmed revoke atomically removes only Play access, preserves owner and user data; replay no churn', async () => {
  const s = await setup();
  const recipe = db.doc(`users/${s.uid}/recipes/keep`), shopping = db.doc(`users/${s.uid}/shopping/keep`);
  await recipe.set({ name: 'kept' }); await shopping.set({ name: 'kept' });
  assert.equal((await s.run()).outcome, 'purchaseRevoked');
  const d = (await s.ledger.get()).data()!, g = (await s.playGrant.get()).data()!, e = (await s.effective.get()).data()!;
  assert.equal(d.lifecycleRevision, 2); assert.equal(d.purchaseState, 'CANCELED'); assert.ok(d.revokedAt.isEqual(now));
  assert.equal(d.boundUid, s.uid); assert.equal(d.purchaseToken, s.token); assert.equal(g.status, 'REVOKED');
  assert.equal(e.active, false); assert.equal(e.revision, 2); assert.deepEqual(e.sources, []);
  const refs = [s.ledger, s.playGrant, s.effective], snapshots = await Promise.all(refs.map(r => r.get()));
  assert.equal((await s.run()).outcome, 'revokeAlreadyApplied');
  for (let i = 0; i < refs.length; i++) await unchanged(refs[i]!, snapshots[i]!);
  assert.equal((await recipe.get()).data()!.name, 'kept'); assert.equal((await shopping.get()).data()!.name, 'kept');
  await assert.rejects(s.verify()); await assert.rejects(s.acknowledge()); assert.equal(s.ack.calls, 0);
});
for (const source of ['PROMO','ADMIN','TEST','PLAY_PURCHASE'] as const) {
  test(`revoke preserves unrelated ${source} grant and source revision semantics`, async () => {
    const s = await setup(), other = db.doc(`users/${s.uid}/entitlementGrants/other`);
    await other.set(grant({ source, sourceRef: 'another-source' })); await s.verify();
    const prior = await other.get(), revision = (await s.effective.get()).data()!.revision;
    assert.equal((await s.run()).outcome, 'purchaseRevoked'); await unchanged(other, prior);
    const e = (await s.effective.get()).data()!; assert.equal(e.active, true); assert.deepEqual(e.sources, [source]);
    assert.equal(e.revision, revision + (source === 'PLAY_PURCHASE' ? 0 : 1));
  });
}
for (const scenario of ['refund','notFound','unknown','notAuthoritative','temporary','configuration','malformed','wrongProduct','wrongPackage','wrongToken','wrongTestFlag'] as const) {
  test(`${scenario}: no false downgrade or ledger mutation`, async () => {
    const s = await setup();
    let expected = 'recheckRequired';
    if (scenario === 'refund') { s.api.respond({ ...s.observation, state: 'financialRefund' }); expected = 'refundWithoutRevoke'; }
    if (scenario === 'notFound') s.api.respond(null);
    if (scenario === 'unknown') s.api.respond({ ...s.observation, state: 'unknown' });
    if (scenario === 'notAuthoritative') s.api.respond({ ...s.observation, authoritative: false });
    if (scenario === 'temporary') { s.api.fail('unavailable'); expected = 'voidedLookupUnavailable'; }
    if (scenario === 'configuration') { s.api.fail('configuration'); expected = 'voidedLookupConfigError'; }
    if (scenario === 'malformed') s.api.respond({ status: 'revoked' });
    const identityKeys: Record<string, string> = { wrongProduct: 'productId', wrongPackage: 'packageName', wrongToken: 'purchaseToken', wrongTestFlag: 'testPurchase' };
    const key = identityKeys[scenario];
    if (key) { s.api.respond({ ...s.observation, [key]: key === 'testPurchase' ? true : 'wrong' }); expected = 'lifecycleConflict'; }
    const refs = [s.ledger, s.playGrant, s.effective], snapshots = await Promise.all(refs.map(r => r.get()));
    assert.equal((await s.run()).outcome, expected); assert.equal(s.api.calls, 1);
    for (let i = 0; i < refs.length; i++) await unchanged(refs[i]!, snapshots[i]!);
  });
}
test('pending cancellation is terminal without grant or artificial effective entitlement', async () => {
  const s = await setup(true); s.api.respond({ ...s.observation, state: 'pendingCanceled' });
  assert.equal((await s.run()).outcome, 'pendingCanceled'); assert.equal((await s.playGrant.get()).exists, false);
  assert.equal((await s.effective.get()).exists, false); const d = (await s.ledger.get()).data()!;
  assert.equal(d.revokedAt, null); assert.equal(d.revokeReason, 'PENDING_CANCELED'); assert.equal(d.lifecycleRevision, 2);
  assert.equal((await s.run()).outcome, 'revokeAlreadyApplied'); await assert.rejects(s.verify());
});
test('pending cancellation observation cannot revoke an already purchased grant', async () => {
  const s = await setup(); s.api.respond({ ...s.observation, state: 'pendingCanceled' });
  assert.equal((await s.run()).outcome, 'lifecycleConflict'); assert.equal((await s.effective.get()).data()!.active, true);
});
test('verify lookup in flight cannot reactivate after revoke', async () => {
  const s = await setup(), entered = deferred<void>(), release = deferred<unknown>();
  s.play.handlers.set(s.token, async () => { entered.resolve(); return release.promise; });
  const task = s.verify(); await entered.promise; assert.equal((await s.run()).outcome, 'purchaseRevoked');
  release.resolve(s.response); await assert.rejects(task, (e: any) => e.code === 'staleLifecycleRevision');
  assert.equal((await s.effective.get()).data()!.active, false);
});
test('ack claim invalidated; late completion stale; counters retained', async () => {
  const s = await setup(), claim = await s.store.claimAck(s.hash, defaultRetryPolicy); assert.ok('claim' in claim);
  assert.equal((await s.run()).outcome, 'purchaseRevoked');
  const state = (await s.state.get()).data()!; assert.equal(state.status, 'acknowledgmentCanceled'); assert.equal(state.leaseId, null); assert.equal(state.totalAttempts, 1);
  assert.equal((await s.store.completeAck(claim.claim, null, defaultRetryPolicy, () => 0)).status, 'stale');
  await assert.rejects(s.store.claimAck(s.hash, defaultRetryPolicy));
});
test('external ack success after revoke cannot overwrite terminal ledger', async () => {
  const s = await setup(), entered = deferred<void>(), release = deferred<unknown>();
  s.ack.handler = async () => { entered.resolve(); return release.promise; };
  const task = s.acknowledge(); await entered.promise; await s.run(); release.resolve({ status: 'success' });
  assert.equal((await task).status, 'stale'); assert.equal((await s.ledger.get()).data()!.purchaseState, 'CANCELED');
});
test('completed ack history survives later revoke', async () => {
  const s = await setup(); await s.acknowledge(); assert.equal((await s.run()).outcome, 'purchaseRevoked');
  assert.equal((await s.state.get()).data()!.status, 'acknowledged'); assert.equal((await s.ledger.get()).data()!.lifecycleRevision, 3);
});
test('duplicate workers have single durable revoke; retry is no-op', async () => {
  const s = await setup(); const results = await Promise.all([s.run(), s.run()]);
  assert.equal(results.filter(r => r.outcome === 'purchaseRevoked').length, 1);
  assert.ok(results.every(r => ['purchaseRevoked','staleObservation','revokeAlreadyApplied'].includes(r.outcome)));
  assert.equal((await s.ledger.get()).data()!.lifecycleRevision, 2); assert.equal((await s.effective.get()).data()!.revision, 2);
  assert.equal((await s.run()).outcome, 'revokeAlreadyApplied');
});
test('voided lookup in flight fenced by newer ack revision, fresh retry succeeds', async () => {
  const s = await setup(), entered = deferred<void>(), release = deferred<unknown>();
  s.api.handler = async () => { entered.resolve(); return release.promise; };
  const task = s.run(); await entered.promise; await s.acknowledge(); release.resolve(s.observation);
  assert.equal((await task).outcome, 'staleObservation'); assert.equal((await s.effective.get()).data()!.active, true);
  s.api.respond(s.observation); assert.equal((await s.run()).outcome, 'purchaseRevoked');
});
for (const state of ['DELETING','DELETED'] as const) {
  test(`revoke closes ${state} account without activation, promo record unchanged`, async () => {
    const s = await setup(), promo = db.doc(`users/${s.uid}/entitlementGrants/promo`); await promo.set(grant()); await s.verify();
    await s.accounts.advance({ uid: s.uid }, 1, 'DELETING'); if (state === 'DELETED') await s.accounts.advance({ uid: s.uid }, 2, 'DELETED');
    assert.equal((await s.run()).outcome, 'purchaseRevoked');
    assert.equal((await s.effective.get()).data()!.active, false); assert.equal((await promo.get()).data()!.status, 'ACTIVE');
    assert.equal((await db.doc(`accountLifecycle/${s.uid}`).get()).data()!.state, state);
  });
}
test('account generation changes during lookup: no stale revoke write, retry allowed', async () => {
  const s = await setup(), entered = deferred<void>(), release = deferred<unknown>();
  s.api.handler = async () => { entered.resolve(); return release.promise; };
  const task = s.run(); await entered.promise; await s.accounts.advance({ uid: s.uid }, 1, 'DELETING'); release.resolve(s.observation);
  assert.deepEqual(await task, { outcome: 'staleObservation', reason: 'staleAccountGeneration' });
  assert.equal((await s.playGrant.get()).data()!.status, 'ACTIVE'); s.api.respond(s.observation); assert.equal((await s.run()).outcome, 'purchaseRevoked');
});
test('v1 ledger terminal write recovers to v2 without preliminary migration', async () => {
  const s = await setup(false, true), data = (await s.ledger.get()).data()!;
  for (const key of ['lifecycleRevision','lastCheckedAt','nextCheckAt','operationalError','accountGeneration','bindingKeyVersion']) delete data[key];
  data.schemaVersion = 1; await s.ledger.set(data);
  assert.equal((await s.run()).outcome, 'purchaseRevoked'); const next = (await s.ledger.get()).data()!;
  assert.equal(next.schemaVersion, 2); assert.equal(next.testPurchase, true); assert.equal(next.boundUid, s.uid); assert.equal(next.lifecycleRevision, 2);
});
test('transaction failure after all writes queued rolls back ledger, grant, effective and ack; retry recovers', async () => {
  const s = await setup(); await s.store.claimAck(s.hash, defaultRetryPolicy);
  const refs = [s.ledger, s.playGrant, s.effective, s.state], snapshots = await Promise.all(refs.map(r => r.get()));
  let queued = false;
  const crashingDb = new Proxy(db, { get(target, key) {
    if (key === 'runTransaction') return (callback: (tx: Transaction) => Promise<unknown>) => target.runTransaction(async tx => {
      const result = await callback(tx); assert.deepEqual(result, { outcome: 'purchaseRevoked' });
      queued = true; throw new Error('synthetic precommit crash');
    }, { maxAttempts: 1 });
    const value = Reflect.get(target, key); return typeof value === 'function' ? value.bind(target) : value;
  } });
  const result = await new PurchaseRevoker(db, s.api, new LifecycleStore(crashingDb, () => now)).run(s.token);
  assert.equal(result.outcome, 'lifecycleConflict'); assert.equal(queued, true);
  for (let i = 0; i < refs.length; i++) await unchanged(refs[i]!, snapshots[i]!);
  assert.equal((await s.run()).outcome, 'purchaseRevoked');
});
test('crash after external lookup before writer is recoverable with fresh lookup', async () => {
  const s = await setup();
  class CrashStore extends LifecycleStore { override async commitVoided(): Promise<never> { throw new Error('synthetic process crash'); } }
  assert.equal((await new PurchaseRevoker(db, s.api, new CrashStore(db)).run(s.token)).outcome, 'lifecycleConflict');
  assert.equal((await s.effective.get()).data()!.active, true); assert.equal((await s.run()).outcome, 'purchaseRevoked'); assert.equal(s.api.calls, 2);
});
