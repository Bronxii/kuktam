import { before, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeApp, deleteApp, App } from 'firebase-admin/app';
import { getFirestore, Firestore, Timestamp } from 'firebase-admin/firestore';
import { requireLocalEmulator } from './emulator-guard';
import { AccountBinding } from '../src/billing/account-binding';
import { AccountLifecycleStore } from '../src/accounts/account-lifecycle-store';
import { PurchaseVerifier } from '../src/billing/verify-purchase';
import { PACKAGE_NAME, PRODUCT_ID } from '../src/billing/play-purchase-api';
import { MonetizationHandlers, transportResult } from '../src/transport/monetization';
import { FakePlayApi } from './fake-play-api';
import { now, grant } from './fixtures';
import { aggregateGrants } from '../src/aggregate';
requireLocalEmulator(process.env);
let db: Firestore, app: App, sequence = 0;
before(() => { app = initializeApp({ projectId: 'demo-kuktam-local' }, 'n53-transport'); db = getFirestore(app); });
after(async () => { await deleteApp(app); });
function setup() {
  const uid = `n53-${++sequence}`, binding = new AccountBinding(Buffer.alloc(32, 29));
  const accounts = new AccountLifecycleStore(db, binding, () => now), api = new FakePlayApi();
  const handlers = new MonetizationHandlers(db, accounts, new PurchaseVerifier(db, api, binding, () => now), () => now);
  const auth = { uid }, token = `n53-token-${sequence}`;
  api.respond(token, { packageName: PACKAGE_NAME, productId: PRODUCT_ID, purchaseToken: token,
    purchaseState: 'PURCHASED', acknowledgementState: 'PENDING',
    obfuscatedExternalAccountId: binding.forAuthenticatedAccount(auth), testPurchase: true });
  return { uid, auth, token, binding, accounts, api, handlers,
    prepare: () => handlers.prepareProPurchase({ auth, data: {} }),
    verify: () => handlers.verifyProPurchase({ auth, data: { productId: PRODUCT_ID, purchaseToken: token } }),
    proof: () => handlers.getEntitlementProof({ auth, data: {} }) };
}
for (const method of ['prepareProPurchase', 'verifyProPurchase', 'getEntitlementProof'] as const) {
  test(`${method}: no authenticated context rejected`, async () => {
    const s = setup(); assert.deepEqual(await transportResult(() => s.handlers[method]({ data: {} })), { schemaVersion: 1, error: 'unauthenticated' });
  });
  test(`${method}: body UID injection rejected`, async () => {
    const s = setup(); const data = method === 'verifyProPurchase' ? { productId: PRODUCT_ID, purchaseToken: s.token, uid: 'victim' } : { uid: 'victim' };
    assert.deepEqual(await transportResult(() => s.handlers[method]({ auth: s.auth, data })), { schemaVersion: 1, error: 'invalidArgument' });
  });
}
test('prepare creates stable binding idempotently, no entitlement/grant', async () => {
  const s = setup(); const a = await s.prepare(), b = await s.prepare();
  assert.deepEqual(a, b); assert.equal(a.opaqueAccountId, s.binding.forAuthenticatedAccount(s.auth));
  assert.equal((await db.doc(`users/${s.uid}/entitlements/pro`).get()).exists, false);
  assert.equal((await db.collection(`users/${s.uid}/entitlementGrants`).get()).empty, true);
});
for (const state of ['DELETING', 'DELETED'] as const) {
  test(`${state}: prepare and proof denied`, async () => {
    const s = setup(); await s.prepare(); await s.accounts.advance(s.auth, 1, 'DELETING');
    if (state === 'DELETED') await s.accounts.advance(s.auth, 2, 'DELETED');
    for (const action of [s.prepare, s.proof]) assert.deepEqual(await transportResult(action), { schemaVersion: 1, error: state === 'DELETING' ? 'accountDeleting' : 'accountDeleted' });
  });
}
test('tombstoned binding cannot be reused', async () => {
  const s = setup(); const p = await s.prepare();
  await db.doc(`billingAccountBindings/${p.opaqueAccountId}`).set({ schemaVersion: 1, state: 'TOMBSTONED', keyVersion: 'v1', createdAt: now, updatedAt: now });
  assert.deepEqual(await transportResult(s.prepare), { schemaVersion: 1, error: 'tokenBindingConflict' });
});
for (const token of ['', ' ', 42, 'x'.repeat(4097), null]) {
  test(`invalid token type/length ${typeof token}/${String(token).length}`, async () => {
    const s = setup(); assert.deepEqual(await transportResult(() => s.handlers.verifyProPurchase({ auth: s.auth, data: { productId: PRODUCT_ID, purchaseToken: token } })), { schemaVersion: 1, error: 'invalidArgument' });
  });
}
test('wrong product rejected', async () => {
  const s = setup(); assert.deepEqual(await transportResult(() => s.handlers.verifyProPurchase({ auth: s.auth, data: { productId: 'wrong', purchaseToken: s.token } })), { schemaVersion: 1, error: 'invalidArgument' });
});
test('prepare → verify → proof active; only auth UID owns grant; response has no token', async () => {
  const s = setup(); await s.prepare(); assert.deepEqual(await s.verify(), { schemaVersion: 1, outcome: 'verified' });
  const p = await s.proof(); assert.equal(p.active, true); assert.equal(p.proofIssuedAt, now.toMillis());
  assert.equal(JSON.stringify(p).includes(s.token), false); assert.equal('uid' in p, false);
  assert.equal((await db.collection(`users/${s.uid}/entitlementGrants`).get()).size, 1);
});
test('token replay different UID returns conflict without leakage', async () => {
  const s = setup(), other = setup(); await s.prepare(); await s.verify(); await other.prepare();
  const response = await transportResult(() => other.handlers.verifyProPurchase({ auth: other.auth, data: { productId: PRODUCT_ID, purchaseToken: s.token } }));
  assert.deepEqual(response, { schemaVersion: 1, error: 'tokenBindingConflict' });
});
test('pending verification never writes Pro', async () => {
  const s = setup(); await s.prepare(); s.api.respond(s.token, { packageName: PACKAGE_NAME, productId: PRODUCT_ID, purchaseToken: s.token, purchaseState: 'PENDING', acknowledgementState: 'PENDING', obfuscatedExternalAccountId: s.binding.forAuthenticatedAccount(s.auth), testPurchase: true });
  assert.deepEqual(await s.verify(), { schemaVersion: 1, outcome: 'pending' }); assert.equal((await s.proof()).active, false);
});
test('missing proof is virtual Free revision zero, no read-side writes', async () => {
  const s = setup(); const p = await s.proof(); assert.equal(p.active, false); assert.equal(p.revision, 0);
  assert.equal((await db.doc(`accountLifecycle/${s.uid}`).get()).exists, false);
});
for (const active of [true, false]) {
  test(`proof active=${active}; freshness comes from backend clock not verifiedAt`, async () => {
    const s = setup(); await s.prepare();
    await db.doc(`users/${s.uid}/entitlements/pro`).set(aggregateGrants(active ? [grant()] : [], now, 2));
    const later = new Timestamp(now.seconds + 100, 0);
    const h = new MonetizationHandlers(db, s.accounts, new PurchaseVerifier(db, s.api, s.binding), () => later);
    const p = await h.getEntitlementProof({ auth: s.auth, data: {} });
    assert.equal(p.active, active); assert.equal(p.proofIssuedAt, later.toMillis()); assert.equal(p.verifiedAt, now.toMillis());
  });
}
test('corrupt effective fails closed instead of hiding corruption as Free', async () => {
  const s = setup(); await s.prepare(); await db.doc(`users/${s.uid}/entitlements/pro`).set({ active: true });
  assert.deepEqual(await transportResult(s.proof), { schemaVersion: 1, error: 'internalMalformed' });
});
for (const data of [null, [], 'wrong', { x: 1 }]) {
  test(`malformed prepare ${JSON.stringify(data)}`, async () => {
    const s = setup(); assert.deepEqual(await transportResult(() => s.handlers.prepareProPurchase({ auth: s.auth, data })), { schemaVersion: 1, error: 'invalidArgument' });
  });
}
