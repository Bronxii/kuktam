import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { initializeApp, deleteApp, App } from 'firebase-admin/app';
import { Firestore, Timestamp, getFirestore } from 'firebase-admin/firestore';
import { requireLocalEmulator } from './emulator-guard';
import { AccountBinding } from '../src/billing/account-binding';
import { AccountLifecycleStore } from '../src/accounts/account-lifecycle-store';
import { LifecycleStore } from '../src/billing/lifecycle-store';
import { LifecycleError } from '../src/billing/lifecycle-error';
import { readPurchase } from '../src/billing/schema-v2';
import { PACKAGE_NAME, PRODUCT_ID } from '../src/billing/play-purchase-api';
import { tokenHash, playGrantId } from '../src/billing/verify-purchase';
import { FakePlayApi } from './fake-play-api';
import { purchase, now, grant } from './fixtures';
requireLocalEmulator(process.env);
let app: App, db: Firestore;
before(() => { app = initializeApp({ projectId: 'demo-kuktam-local' }, 'n4b-foundation'); db = getFirestore(app); });
after(async () => { if (app) await deleteApp(app); });
let sequence = 0;
const binding = new AccountBinding(Buffer.alloc(32, 57));
function deferred<T>() { let resolve!: (v: T) => void; const promise = new Promise<T>(r => { resolve = r; }); return { resolve, promise }; }
async function setup() {
  const uid = `n4b-${++sequence}`, context = { uid }, token = `synthetic-n4b-${sequence}`, hash = tokenHash(token);
  let time = now;
  const accounts = new AccountLifecycleStore(db, binding, () => time), store = new LifecycleStore(db, () => time);
  await accounts.initializeActive(context); const opaque = await accounts.register(context, 1);
  const response = { packageName: PACKAGE_NAME, productId: PRODUCT_ID, purchaseToken: token, purchaseState: 'PURCHASED',
    acknowledgementState: 'PENDING', obfuscatedExternalAccountId: opaque, testPurchase: false };
  const ledger = db.doc(`billingPurchases/${hash}`), marker = db.doc(`accountLifecycle/${uid}`);
  const grants = db.collection(`users/${uid}/entitlementGrants`), effective = db.doc(`users/${uid}/entitlements/pro`);
  const commit = (revision = 0, generation = 1, value: unknown = response) => store.commit(context,
    { purchase: value, expectedLifecycleRevision: revision, expectedAccountGeneration: generation });
  return { uid, context, token, hash, opaque, response, accounts, store, ledger, marker, grants, effective, commit,
    tick: () => { time = Timestamp.fromMillis(time.toMillis() + 1000); } };
}
test('active account + registry -> ledger/grant/effective atomic v2', async () => {
  const s = await setup(); assert.equal(binding.keyVersion, 'v1');
  assert.deepEqual(await s.commit(), { outcome: 'committed', lifecycleRevision: 1, granted: true });
  assert.equal((await s.grants.get()).size, 1);
  assert.equal((await s.effective.get()).data()!.schemaVersion, 2);
  const ledger = readPurchase((await s.ledger.get()).data()); assert.equal(ledger.accountGeneration, 1); assert.equal(ledger.bindingKeyVersion, 'v1');
});
test('same writer replay does not increase revisions; freshness is separate', async () => {
  const s = await setup(); await s.commit(); const effective = await s.effective.get(); s.tick(); await s.commit(1);
  assert.equal((await s.ledger.get()).data()!.lifecycleRevision, 1);
  assert.ok(effective.updateTime!.isEqual((await s.effective.get()).updateTime!));
  assert.ok((await s.ledger.get()).data()!.lastCheckedAt.toMillis() > now.toMillis());
});
test('duplicate concurrent writers have one durable grant and no extra revision', async () => {
  const s = await setup(); const result = await Promise.all([s.commit(), s.commit(), s.commit()]);
  assert.equal(result.filter(r => r.outcome === 'committed').length, 1);
  assert.equal(result.filter(r => r.outcome === 'stale').length, 2);
  assert.equal((await s.grants.get()).size, 1); assert.equal((await s.effective.get()).data()!.revision, 1);
});
test('lookup in flight then deleting: no grant', async () => {
  const s = await setup(), api = new FakePlayApi(), entered = deferred<void>(), release = deferred<unknown>();
  api.handlers.set(s.token, async () => { entered.resolve(); return release.promise; });
  const task = (async () => { const observation = await api.lookup({ packageName: PACKAGE_NAME, productId: PRODUCT_ID, purchaseToken: s.token }); return s.commit(0, 1, observation); })();
  await entered.promise; await s.accounts.advance(s.context, 1, 'DELETING'); release.resolve(s.response);
  assert.equal((await task).outcome, 'stale'); assert.equal((await s.grants.get()).size, 0); assert.equal((await s.ledger.get()).exists, false);
});
test('lookup ready, deletion precedes transaction: rejected without grant', async () => {
  const s = await setup(); const observation = s.response; await s.accounts.advance(s.context, 1, 'DELETING');
  assert.equal((await s.commit(0, 2, observation)).outcome, 'rejected'); assert.equal((await s.grants.get()).size, 0);
});
test('concurrent verify/delete serializes at marker; later verification always denied', async () => {
  const s = await setup(); const [result] = await Promise.all([s.commit(), s.accounts.advance(s.context, 1, 'DELETING')]);
  assert.ok(result.outcome === 'committed' || result.outcome === 'stale');
  assert.equal((await s.commit(result.outcome === 'committed' ? 1 : 0, 2)).outcome, 'rejected');
  assert.equal((await s.grants.get()).size, result.outcome === 'committed' ? 1 : 0);
});
test('deleting after committed grant only changes marker in this scope; deleted never reactivates', async () => {
  const s = await setup(); await s.commit(); await s.accounts.advance(s.context, 1, 'DELETING');
  assert.equal((await s.grants.get()).size, 1); // cleanup explicitly deferred
  await s.accounts.advance(s.context, 2, 'DELETED');
  assert.equal((await s.commit(1, 3)).outcome, 'rejected');
  await assert.rejects(s.accounts.initializeActive(s.context), LifecycleError);
});
test('stale account generation cannot write; missing marker is not active', async () => {
  const s = await setup(); assert.equal((await s.commit(0, 9)).outcome, 'stale'); await s.marker.delete();
  await assert.rejects(s.commit(), LifecycleError); assert.equal((await s.grants.get()).size, 0);
});
test('terminal higher revision wins over stale purchased observation', async () => {
  const s = await setup(); await s.commit();
  // Seed future revoke outcome only; N4B.2 contains no revoke processor.
  const data = (await s.ledger.get()).data()!;
  await s.ledger.update({ lifecycleRevision: 2, purchaseState: 'CANCELED', revokedAt: now });
  assert.equal((await s.commit(1)).outcome, 'stale'); assert.equal((await s.commit(2)).outcome, 'rejected');
  assert.equal((await s.ledger.get()).data()!.lifecycleRevision, 2); assert.equal(data.lifecycleRevision, 1);
});
test('pending has no grant; purchased and ack transitions bump lifecycle only', async () => {
  const s = await setup(); await s.commit(0, 1, { ...s.response, purchaseState: 'PENDING' });
  assert.equal((await s.grants.get()).size, 0); assert.equal((await s.effective.get()).exists, false);
  await s.commit(1); assert.equal((await s.ledger.get()).data()!.lifecycleRevision, 2);
  await s.commit(2, 1, { ...s.response, acknowledgementState: 'ACKNOWLEDGED' });
  assert.equal((await s.ledger.get()).data()!.lifecycleRevision, 3); assert.equal((await s.effective.get()).data()!.revision, 1);
  assert.equal((await s.commit(3)).outcome, 'stale');
});
test('v1 ledger explicit upgrade preserves delivery subdocument and new operational fields', async () => {
  const s = await setup(); await s.ledger.set({ ...purchase(), packageName: PACKAGE_NAME, productId: PRODUCT_ID,
    purchaseToken: s.token, boundUid: s.uid, accountBinding: s.opaque, testPurchase: false });
  const delivery = s.ledger.collection('acknowledgment').doc('state'); await delivery.set({ test: 'unchanged' });
  assert.equal(readPurchase((await s.ledger.get()).data()).schemaVersion, 2);
  assert.equal((await s.ledger.get()).data()!.schemaVersion, 1); // read is not migration
  await s.commit(1); assert.equal((await s.ledger.get()).data()!.schemaVersion, 2);
  const nextCheck = Timestamp.fromMillis(now.toMillis() + 50000);
  assert.equal(await s.store.recordCheck(s.context, s.hash, 1, 1, nextCheck, 'TEMPORARY'), true);
  await s.commit(1); const data = (await s.ledger.get()).data()!;
  assert.equal(data.nextCheckAt.toMillis(), nextCheck.toMillis()); assert.equal(data.lifecycleRevision, 1);
  assert.deepEqual((await delivery.get()).data(), { test: 'unchanged' });
});
test('operational write fences stale generation/revision and changes no effective revision', async () => {
  const s = await setup(); await s.commit();
  assert.equal(await s.store.recordCheck(s.context, s.hash, 0, 1, null, 'TEMPORARY'), false);
  assert.equal(await s.store.recordCheck(s.context, s.hash, 1, 1, now, 'CONFIGURATION'), true);
  assert.equal((await s.effective.get()).data()!.revision, 1); assert.equal((await s.ledger.get()).data()!.lifecycleRevision, 1);
  await s.accounts.advance(s.context, 1, 'DELETING');
  assert.equal(await s.store.recordCheck(s.context, s.hash, 1, 1, null, null), false);
});
test('binding registration idempotent, lookup backend-only, tombstone prevents reuse', async () => {
  const s = await setup(); assert.equal(await s.accounts.register(s.context, 1), s.opaque);
  const found = await s.accounts.lookup(s.opaque); assert.equal(found!.state, 'ACTIVE'); assert.equal(found!.keyVersion, 'v1');
  await s.accounts.advance(s.context, 1, 'DELETING'); await s.accounts.tombstone(s.context, s.opaque, 2);
  const tombstone = await s.accounts.lookup(s.opaque); assert.equal(tombstone!.state, 'TOMBSTONED'); assert.equal('uid' in tombstone!, false);
  await assert.rejects(s.accounts.register(s.context, 2), LifecycleError);
});
test('wrong UID registry and owner conflicts create no grant', async () => {
  const a = await setup(), b = await setup();
  await assert.rejects(b.commit(0, 1, { ...b.response, obfuscatedExternalAccountId: a.opaque }), LifecycleError);
  assert.equal((await b.grants.get()).size, 0);
  await a.commit(); await assert.rejects(b.commit(1, 1, { ...b.response, purchaseToken: a.token }), LifecycleError);
});
test('corrupt grant aborts ledger/effective atomically', async () => {
  const s = await setup(); await s.grants.doc(playGrantId(s.hash)).set({ broken: true });
  await assert.rejects(s.commit(), LifecycleError); assert.equal((await s.ledger.get()).exists, false); assert.equal((await s.effective.get()).exists, false);
});
test('new independent source increments effective once, missing grant repairs without false revision', async () => {
  const s = await setup(); await s.commit(); await s.grants.doc('promo').set(grant({ source: 'PROMO' }));
  await s.commit(1); assert.equal((await s.effective.get()).data()!.revision, 2);
  await s.grants.doc(playGrantId(s.hash)).delete(); await s.commit(1);
  assert.equal((await s.effective.get()).data()!.revision, 2); assert.equal((await s.grants.get()).size, 2);
});

test('strict unknown fields in existing v2 prevent destructive overwrite', async () => {
  const s = await setup(); await s.commit(); await s.ledger.update({ futureField: 'retain' });
  await assert.rejects(s.commit(1), LifecycleError);
  assert.equal((await s.ledger.get()).data()!.futureField, 'retain');
});
test('stale entitlement is repaired once; unchanged v1 effective remains readable', async () => {
  const s = await setup(); await s.commit();
  await s.effective.update({ schemaVersion: 1, active: false, sources: [], revision: 7 });
  await s.commit(1); assert.equal((await s.effective.get()).data()!.revision, 8);
  await s.commit(1); assert.equal((await s.effective.get()).data()!.revision, 8);
});
test('tombstone on active account cannot be registered or used to grant', async () => {
  const s = await setup(); const ref = db.doc(`billingAccountBindings/${s.opaque}`);
  await ref.set({ schemaVersion: 1, state: 'TOMBSTONED', keyVersion: 'v1', createdAt: now, updatedAt: now });
  await assert.rejects(s.accounts.register(s.context, 1), LifecycleError);
  await assert.rejects(s.commit(), LifecycleError); assert.equal((await s.grants.get()).size, 0);
});
