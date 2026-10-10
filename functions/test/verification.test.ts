import { AccountLifecycleStore } from '../src/accounts/account-lifecycle-store';
import { LifecycleError } from '../src/billing/lifecycle-error';
import { before, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeApp, deleteApp, App } from 'firebase-admin/app';
import { getFirestore, Firestore, Timestamp } from 'firebase-admin/firestore';
import { requireLocalEmulator } from './emulator-guard';
import { FakePlayApi } from './fake-play-api';
import { AccountBinding } from '../src/billing/account-binding';
import { PlayPurchase, PACKAGE_NAME, PRODUCT_ID } from '../src/billing/play-purchase-api';
import { PurchaseVerifier, playGrantId, tokenHash } from '../src/billing/verify-purchase';
import { VerificationError, VerificationErrorCode } from '../src/billing/errors';
import { aggregateGrants } from '../src/aggregate';
import { grant, now, purchase } from './fixtures';

requireLocalEmulator(process.env);
let app: App;
let db: Firestore;
before(() => {
  app = initializeApp({ projectId: 'demo-kuktam-local' }, 'n3-verification');
  db = getFirestore(app);
});
after(async () => { if (app) await deleteApp(app); });
const binding = new AccountBinding(Buffer.alloc(32, 23)); // synthetic test key
let sequence = 0;
async function setup() {
  const uid = `n3-user-${++sequence}`;
  const token = `synthetic-n3-token-${sequence}`;
  const api = new FakePlayApi();
  let clock = now;
  const accounts = new AccountLifecycleStore(db, binding, () => now);
  await accounts.initializeActive({ uid }); await accounts.register({ uid }, 1);
  const verifier = new PurchaseVerifier(db, api, binding, () => clock);
  const response: PlayPurchase = {
    packageName: PACKAGE_NAME, productId: PRODUCT_ID, purchaseToken: token,
    purchaseState: 'PURCHASED', acknowledgementState: 'PENDING',
    obfuscatedExternalAccountId: binding.forAuthenticatedAccount({ uid }), testPurchase: false,
  };
  api.respond(token, response);
  const ledger = db.doc(`billingPurchases/${tokenHash(token)}`);
  const grants = db.collection(`users/${uid}/entitlementGrants`);
  const effective = db.doc(`users/${uid}/entitlements/pro`);
  const verify = () => verifier.verify({ uid }, { purchaseToken: token });
  const ledgerData = () => ({ ...purchase(), purchaseToken: token, boundUid: uid,
    accountBinding: response.obfuscatedExternalAccountId!, testPurchase: false });
  return { uid, token, api, verifier, response, ledger, grants, effective, verify, ledgerData,
    tick: () => { clock = new Timestamp(clock.seconds + 60, 0); } };
}
async function rejected(work: Promise<unknown>, code: VerificationErrorCode | 'staleLifecycleRevision') {
  await assert.rejects(work, error => (error instanceof VerificationError || error instanceof LifecycleError) && error.code === code && error.message === code);
}
async function noWrites(s: Awaited<ReturnType<typeof setup>>) {
  assert.equal((await s.ledger.get()).exists, false);
  assert.equal((await s.grants.get()).size, 0);
  assert.equal((await s.effective.get()).exists, false);
}

test('valid purchased atomically creates permanent grant, ledger and Pro', async () => {
  const s = await setup();
  const result = await s.verify();
  assert.equal(result.status, 'granted');
  const ledger = (await s.ledger.get()).data()!;
  assert.equal(ledger.boundUid, s.uid);
  assert.equal(ledger.acknowledgementState, 'PENDING'); // N3 never acknowledges
  const grants = await s.grants.get();
  assert.equal(grants.size, 1);
  assert.equal(grants.docs[0]!.id, playGrantId(tokenHash(s.token)));
  assert.equal(grants.docs[0]!.data().source, 'PLAY_PURCHASE');
  assert.equal(grants.docs[0]!.data().expiresAt, null);
  assert.equal((await s.effective.get()).data()!.active, true);
  assert.equal((await s.effective.get()).data()!.revision, 1);
  assert.ok(!JSON.stringify(result).includes(s.token));
});
test('pending binds token but creates neither grant nor entitlement or ack', async () => {
  const s = await setup();
  s.api.respond(s.token, { ...s.response, purchaseState: 'PENDING' });
  assert.deepEqual(await s.verify(), { status: 'purchasePending' });
  assert.equal((await s.grants.get()).size, 0);
  assert.equal((await s.effective.get()).exists, false);
  assert.equal((await s.ledger.get()).data()!.acknowledgementState, 'PENDING');
  const first = (await s.ledger.get()).updateTime;
  s.tick();
  await s.verify();
  assert.equal((await s.ledger.get()).data()!.lifecycleRevision, 1);
  s.api.respond(s.token, s.response);
  await s.verify();
  assert.equal((await s.grants.get()).size, 1);
});
for (const [label, patch, code] of [
  ['canceled', { purchaseState: 'CANCELED' }, 'purchaseNotOwned'],
  ['wrong package', { packageName: 'other.app' }, 'wrongPackage'],
  ['wrong product', { productId: 'other_product' }, 'wrongProduct'],
  ['wrong binding', { obfuscatedExternalAccountId: 'wrong' }, 'accountBindingMismatch'],
  ['missing binding', { obfuscatedExternalAccountId: null }, 'accountBindingMismatch'],
  ['wrong token echo', { purchaseToken: 'other' }, 'invalidToken'],
  ['malformed state', { purchaseState: 'UNRECOGNIZED' }, 'malformedPlayResponse'],
  ['invalid pending ack', { purchaseState: 'PENDING', acknowledgementState: 'ACKNOWLEDGED' }, 'malformedPlayResponse'],
  ['missing test flag', { testPurchase: undefined }, 'malformedPlayResponse'],
] as const) {
  test(`${label} rejected with no writes`, async () => {
    const s = await setup();
    s.api.respond(s.token, { ...s.response, ...patch });
    await rejected(s.verify(), code);
    await noWrites(s);
  });
}
test('not found and malformed response do not claim token', async () => {
  for (const [response, code] of [[null, 'purchaseNotOwned'], [{}, 'malformedPlayResponse']] as const) {
    const s = await setup(); s.api.respond(s.token, response);
    await rejected(s.verify(), code); await noWrites(s);
  }
});
test('unauthenticated and client privilege claims rejected before API/DB writes', async () => {
  const s = await setup();
  await rejected(s.verifier.verify(null, { purchaseToken: s.token }), 'unauthenticated');
  for (const claim of [{ uid: s.uid }, { isPro: true }, { purchased: true },
    { packageName: PACKAGE_NAME }, { productId: PRODUCT_ID }]) {
    await rejected(s.verifier.verify({ uid: s.uid }, { purchaseToken: s.token, ...claim }), 'invalidInput');
  }
  for (const token of ['', ' ', ' x ', 'x'.repeat(4097), 3]) {
    await rejected(s.verifier.verify({ uid: s.uid }, { purchaseToken: token }), 'invalidToken');
  }
  assert.equal(s.api.calls, 0);
  await noWrites(s);
});
test('backend constants populate adapter query', async () => {
  const s = await setup();
  s.api.handlers.set(s.token, query => {
    assert.equal(query.packageName, PACKAGE_NAME); assert.equal(query.productId, PRODUCT_ID);
    return s.response;
  });
  await s.verify();
});
test('replay across time does not write, duplicate grant or increase revision', async () => {
  const s = await setup();
  const first = await s.verify();
  const l = await s.ledger.get(); const e = await s.effective.get();
  s.tick();
  assert.deepEqual(await s.verify(), first);
  assert.equal((await s.ledger.get()).data()!.lifecycleRevision, l.data()!.lifecycleRevision);
  assert.ok((await s.effective.get()).updateTime!.isEqual(e.updateTime!));
  assert.equal((await s.grants.get()).size, 1);
});
test('same token second UID rejected without additional API call', async () => {
  const s = await setup(); await s.verify();
  await rejected(s.verifier.verify({ uid: `${s.uid}-other` }, { purchaseToken: s.token }), 'tokenAlreadyBound');
  assert.equal(s.api.calls, 1);
});
test('duplicate simultaneous verifies produce one ledger/grant/revision', async () => {
  const s = await setup();
  const results = await Promise.allSettled(Array.from({ length: 4 }, () => s.verify()));
  assert.ok(results.some(r => r.status === 'fulfilled'));
  for (const r of results) if (r.status === 'rejected') assert.equal(r.reason.code, 'staleLifecycleRevision');
  assert.equal((await s.grants.get()).size, 1);
  assert.equal((await s.effective.get()).data()!.revision, 1);
});
test('concurrent token claim by two UIDs has only one owner even with fake matching replies', async () => {
  const s = await setup();
  const otherUid = `${s.uid}-other`;
  const otherApi = new FakePlayApi();
  const accounts = new AccountLifecycleStore(db, binding, () => now);
  await accounts.initializeActive({ uid: otherUid }); await accounts.register({ uid: otherUid }, 1);
  let arrivals = 0;
  let release!: () => void;
  const barrier = new Promise<void>(resolve => { release = resolve; });
  const wait = async (response: PlayPurchase) => { if (++arrivals === 2) release(); await barrier; return response; };
  s.api.handlers.set(s.token, () => wait(s.response));
  otherApi.handlers.set(s.token, () => wait({ ...s.response,
    obfuscatedExternalAccountId: binding.forAuthenticatedAccount({ uid: otherUid }) }));
  const other = new PurchaseVerifier(db, otherApi, binding, () => now);
  const results = await Promise.allSettled([s.verify(), other.verify({ uid: otherUid }, { purchaseToken: s.token })]);
  assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
  const failure = results.find(r => r.status === 'rejected') as PromiseRejectedResult;
  assert.ok(['staleLifecycleRevision', 'bindingConflict'].includes(failure.reason.code));
  const owner = (await s.ledger.get()).data()!.boundUid;
  const loser = owner === s.uid ? otherUid : s.uid;
  assert.equal((await db.collection(`users/${loser}/entitlementGrants`).get()).size, 0);
  assert.equal((await db.doc(`users/${loser}/entitlements/pro`).get()).exists, false);
});
test('existing verified ledger with missing grant recovers', async () => {
  const s = await setup(); await s.ledger.set(s.ledgerData());
  await s.verify();
  assert.equal((await s.grants.get()).size, 1);
  assert.equal((await s.effective.get()).data()!.active, true);
});
test('grant already exists; stale entitlement recalculated once', async () => {
  const s = await setup(); await s.verify();
  await s.effective.set(aggregateGrants([], now, 7));
  await s.verify();
  assert.equal((await s.effective.get()).data()!.revision, 8);
  await s.verify();
  assert.equal((await s.effective.get()).data()!.revision, 8);
});
test('crash/lost response after commit followed by retry is idempotent', async () => {
  const s = await setup();
  await assert.rejects((async () => { await s.verify(); throw new Error('simulated lost response'); })());
  await s.verify();
  assert.equal((await s.grants.get()).size, 1);
  assert.equal((await s.effective.get()).data()!.revision, 1);
});
test('invalid persisted grant aborts whole transaction with no ledger or entitlement', async () => {
  const s = await setup();
  await s.grants.doc(playGrantId(tokenHash(s.token))).set(grant({ source: 'ADMIN' }));
  await rejected(s.verify(), 'internalConflict');
  assert.equal((await s.ledger.get()).exists, false);
  assert.equal((await s.effective.get()).exists, false);
});
test('Play unavailable and canceled replies never falsely revoke existing entitlement', async () => {
  const s = await setup(); await s.verify(); const prior = await s.effective.get();
  s.api.handlers.set(s.token, () => { throw new Error('raw exception with synthetic secret'); });
  await rejected(s.verify(), 'playUnavailable');
  s.api.respond(s.token, { ...s.response, purchaseState: 'CANCELED' });
  await rejected(s.verify(), 'purchaseNotOwned');
  assert.ok((await s.effective.get()).updateTime!.isEqual(prior.updateTime!));
});
test('unavailable first verification leaves no pending ownership reservation', async () => {
  const s = await setup(); s.api.handlers.set(s.token, () => { throw new Error('offline'); });
  await rejected(s.verify(), 'playUnavailable'); await noWrites(s);
  s.api.respond(s.token, s.response); await s.verify();
  assert.equal((await s.grants.get()).size, 1);
});
test('test purchase is recorded explicitly', async () => {
  const s = await setup(); s.api.respond(s.token, { ...s.response, testPurchase: true });
  await s.verify(); assert.equal((await s.ledger.get()).data()!.testPurchase, true);
});
test('existing independent promo remains when Play grant added', async () => {
  const s = await setup(); await s.grants.doc('promo').set(grant());
  await s.effective.set(aggregateGrants([grant()], now, 3));
  await s.verify();
  assert.deepEqual((await s.effective.get()).data()!.sources, ['PLAY_PURCHASE', 'PROMO']);
  assert.equal((await s.effective.get()).data()!.revision, 4);
});
test('already acknowledged response is preserved, never acknowledged by service', async () => {
  const s = await setup(); s.api.respond(s.token, { ...s.response, acknowledgementState: 'ACKNOWLEDGED' });
  await s.verify();
  assert.equal((await s.ledger.get()).data()!.acknowledgementState, 'ACKNOWLEDGED');
  s.api.respond(s.token, s.response); await rejected(s.verify(), 'staleLifecycleRevision');
});
test('purchased cannot regress to pending', async () => {
  const s = await setup(); await s.verify();
  s.api.respond(s.token, { ...s.response, purchaseState: 'PENDING' });
  await rejected(s.verify(), 'staleLifecycleRevision');
});
test('terminal tombstone cannot be rebound or resurrected', async () => {
  for (const state of ['ACCOUNT_DELETED', 'REVOKED']) {
    const s = await setup();
    const { boundUid: _uid, accountBinding: _binding, purchaseToken: _token, ...base } = s.ledgerData();
    await s.ledger.set({ ...base, bindingState: state, reconciliationRequired: false, revokedAt: now });
    await rejected(s.verify(), 'tokenAlreadyBound');
    assert.equal(s.api.calls, 0); assert.equal((await s.grants.get()).size, 0);
  }
});
test('tombstone written while Play lookup is pending wins over late valid result', async () => {
  const s = await setup();
  s.api.handlers.set(s.token, async () => {
    const { boundUid: _uid, accountBinding: _binding, purchaseToken: _token, ...base } = s.ledgerData();
    await s.ledger.set({ ...base, bindingState: 'ACCOUNT_DELETED', reconciliationRequired: false });
    return s.response;
  });
  await rejected(s.verify(), 'staleLifecycleRevision');
  assert.equal((await s.grants.get()).size, 0);
});
test('intervening non-identical ledger transition rejects stale API reply', async () => {
  const s = await setup(); await s.ledger.set({ ...s.ledgerData(), purchaseState: 'PENDING' });
  s.api.handlers.set(s.token, async () => {
    await s.ledger.set({ ...s.ledgerData(), acknowledgementState: 'ACKNOWLEDGED' });
    return s.response;
  });
  await rejected(s.verify(), 'staleLifecycleRevision');
  assert.equal((await s.grants.get()).size, 0);
});
test('revoked deterministic grant is not reactivated by valid purchase', async () => {
  const s = await setup(); await s.verify();
  await s.grants.doc(playGrantId(tokenHash(s.token))).update({ status: 'REVOKED', revokedAt: now });
  await rejected(s.verify(), 'internalConflict');
  assert.equal((await s.grants.get()).docs[0]!.data().status, 'REVOKED');
});
