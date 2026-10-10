import { defaultRetryPolicy } from '../src/billing/retry-policy';
const ACK_LEASE_MS = defaultRetryPolicy.leaseMs, ACK_RETRY_MS = defaultRetryPolicy.baseDelayMs, MAX_ACK_ATTEMPTS = defaultRetryPolicy.attemptsPerGeneration;
import { AccountLifecycleStore } from '../src/accounts/account-lifecycle-store';
import { LifecycleError } from '../src/billing/lifecycle-error';
import { before, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeApp, deleteApp, App } from 'firebase-admin/app';
import { getFirestore, Firestore, Timestamp } from 'firebase-admin/firestore';
import { requireLocalEmulator } from './emulator-guard';
import { FakePlayApi } from './fake-play-api';
import { FakeAcknowledgmentApi } from './fake-acknowledgment-api';
import { AccountBinding } from '../src/billing/account-binding';
import { PACKAGE_NAME, PRODUCT_ID } from '../src/billing/play-purchase-api';
import { PurchaseVerifier, playGrantId, tokenHash } from '../src/billing/verify-purchase';
import { PurchaseAcknowledger } from '../src/billing/acknowledge-purchase';
import { AcknowledgmentError } from '../src/billing/play-acknowledgment-api';
import { parseAckState } from '../src/billing/acknowledgment-state';
import { now } from './fixtures';
requireLocalEmulator(process.env);
let app: App;
let db: Firestore;
before(() => { app = initializeApp({ projectId: 'demo-kuktam-local' }, 'n4a'); db = getFirestore(app); });
after(async () => { if (app) await deleteApp(app); });
let sequence = 0;
const binding = new AccountBinding(Buffer.alloc(32, 44));
async function setup() {
  const uid = `n4a-${++sequence}`, token = `synthetic-n4a-${sequence}`, hash = tokenHash(token);
  let time = now;
  const play = new FakePlayApi(), api = new FakeAcknowledgmentApi();
  const response = { packageName: PACKAGE_NAME, productId: PRODUCT_ID, purchaseToken: token,
    purchaseState: 'PURCHASED', acknowledgementState: 'PENDING', testPurchase: true,
    obfuscatedExternalAccountId: binding.forAuthenticatedAccount({ uid }) };
  play.respond(token, response);
  const accounts = new AccountLifecycleStore(db, binding, () => now);
  await accounts.initializeActive({ uid }); await accounts.register({ uid }, 1);
  const verifier = new PurchaseVerifier(db, play, binding, () => time);
  const worker = () => new PurchaseAcknowledger(db, api, () => time);
  const ledger = db.doc(`billingPurchases/${hash}`), state = ledger.collection('acknowledgment').doc('state');
  const grant = db.doc(`users/${uid}/entitlementGrants/${playGrantId(hash)}`);
  const effective = db.doc(`users/${uid}/entitlements/pro`);
  return { uid, token, hash, play, api, response, ledger, state, grant, effective, worker,
    verify: () => verifier.verify({ uid }, { purchaseToken: token }), run: () => worker().run(hash),
    advance: (ms = ACK_LEASE_MS) => { time = Timestamp.fromMillis(time.toMillis() + ms); },
    pending: () => ({ schemaVersion: 1, status: 'acknowledgmentPending', attemptCount: 1, lastAttemptAt: time,
      leaseId: 'crashed-process', leaseUntil: Timestamp.fromMillis(time.toMillis() + ACK_LEASE_MS), nextRetryAt: null, failure: null }) };
}
async function rejects(p: Promise<unknown>, code: string) {
  await assert.rejects(p, e => (e instanceof AcknowledgmentError || e instanceof LifecycleError) && e.code === code && e.message === code);
}
function deferred<T>() { let resolve!: (value: T) => void; const promise = new Promise<T>(r => { resolve = r; }); return { promise, resolve }; }
async function unchangedPro(s: Awaited<ReturnType<typeof setup>>, revision = 1) {
  assert.equal((await s.grant.get()).data()!.status, 'ACTIVE');
  const effective = (await s.effective.get()).data()!;
  assert.equal(effective.active, true); assert.equal(effective.revision, revision);
}

test('durable grant/effective/claim exist before external ack; success writes ledger only', async () => {
  const s = await setup(); await s.verify();
  const before = await s.effective.get();
  s.api.handler = async query => {
    assert.deepEqual(query, { packageName: PACKAGE_NAME, productId: PRODUCT_ID, purchaseToken: s.token });
    await unchangedPro(s);
    assert.equal((await s.state.get()).data()!.status, 'acknowledgmentPending');
    return { status: 'success' };
  };
  assert.equal((await s.run()).status, 'acknowledged');
  assert.equal((await s.ledger.get()).data()!.acknowledgementState, 'ACKNOWLEDGED');
  assert.equal((await s.state.get()).data()!.attemptCount, 1);
  assert.ok(before.updateTime!.isEqual((await s.effective.get()).updateTime!));
});
for (const [label, patch] of Object.entries({ pending: { purchaseState: 'PENDING' }, canceled: { purchaseState: 'CANCELED' },
  package: { packageName: 'wrong' }, product: { productId: 'wrong' }, binding: { obfuscatedExternalAccountId: 'wrong' } })) {
  test(`${label} verification cannot lead to ack`, async () => {
    const s = await setup(); s.play.respond(s.token, { ...s.response, ...patch });
    if (label === 'pending') await s.verify(); else await assert.rejects(s.verify());
    await rejects(s.run(), 'invalidLifecycleTransition'); assert.equal(s.api.calls, 0);
  });
}
test('temporary failure retains Pro; retry hint enforced then restart succeeds', async () => {
  const s = await setup(); await s.verify(); s.api.handler = async () => ({ status: 'temporaryFailure' });
  assert.deepEqual(await s.run(), { status: 'acknowledgmentRetry', failure: 'acknowledgmentTemporaryFailure' });
  await unchangedPro(s);
  assert.equal((await s.run()).status, 'deferred'); assert.equal(s.api.calls, 1);
  s.advance(ACK_RETRY_MS); s.api.handler = async () => ({ status: 'success' });
  assert.equal((await s.worker().run(s.hash)).status, 'acknowledged');
  assert.equal((await s.state.get()).data()!.attemptCount, 2); await unchangedPro(s);
});
test('already acknowledged API reply succeeds; acknowledged ledger replays are no-op', async () => {
  const s = await setup(); await s.verify(); s.api.handler = async () => ({ status: 'alreadyAcknowledged' });
  await s.run(); const saved = await s.state.get();
  assert.equal((await s.run()).status, 'acknowledged'); assert.equal(s.api.calls, 1);
  assert.ok(saved.updateTime!.isEqual((await s.state.get()).updateTime!));
  s.play.respond(s.token, { ...s.response, acknowledgementState: 'ACKNOWLEDGED' });
  await s.verify(); await unchangedPro(s); assert.equal((await s.run()).status, 'acknowledged');
});
test('Play initially acknowledged requires no ack action', async () => {
  const s = await setup(); s.play.respond(s.token, { ...s.response, acknowledgementState: 'ACKNOWLEDGED' });
  await s.verify(); assert.equal((await s.run()).status, 'acknowledged'); assert.equal(s.api.calls, 0);
});
test('crash before ack: durable orphan claim recovered at lease boundary', async () => {
  const s = await setup(); await s.verify(); await s.state.set(s.pending());
  assert.equal((await s.run()).status, 'busy'); s.advance();
  assert.equal((await s.run()).status, 'acknowledged'); assert.equal(s.api.calls, 1);
  assert.equal((await s.state.get()).data()!.attemptCount, 2);
});
test('crash after Play success before final commit: restart safely repeats ack', async () => {
  const s = await setup(); await s.verify();
  // Persist the exact durable pre-crash boundary: claimed + remote acknowledged,
  // local ledger still pending. No test-only production hook is required.
  await s.state.set(s.pending()); s.api.handler = async () => ({ status: 'alreadyAcknowledged' });
  s.advance(); assert.equal((await s.run()).status, 'acknowledged'); await unchangedPro(s);
});
test('permanent error is durable and cannot loop; no false revoke', async () => {
  const s = await setup(); await s.verify(); s.api.handler = async () => ({ status: 'permanentFailure' });
  assert.deepEqual(await s.run(), { status: 'acknowledgmentFailed', failure: 'acknowledgmentPermanentFailure' });
  s.advance(); assert.equal((await s.run()).status, 'acknowledgmentFailed');
  assert.equal(s.api.calls, 1); await unchangedPro(s);
});
for (const [label, reply] of [['null', null], ['unknown', { status: 'surprise' }], ['extra', { status: 'success', raw: 'not stored' }]] as const) {
  test(`malformed ${label} response retries without marking acknowledged`, async () => {
    const s = await setup(); await s.verify(); s.api.handler = async () => reply;
    assert.deepEqual(await s.run(), { status: 'acknowledgmentRetry', failure: 'unexpectedResponse' });
    assert.equal((await s.ledger.get()).data()!.acknowledgementState, 'PENDING'); await unchangedPro(s);
  });
}
test('thrown adapter error is sanitized and retryable', async () => {
  const s = await setup(); await s.verify(); s.api.handler = async () => { throw Error('sensitive synthetic error'); };
  assert.deepEqual(await s.run(), { status: 'acknowledgmentRetry', failure: 'acknowledgmentTemporaryFailure' });
});
test('attempt budget stops repeated failures without loop or downgrade', async () => {
  const s = await setup(); await s.verify(); s.api.handler = async () => ({ status: 'temporaryFailure' });
  for (let i = 1; i <= MAX_ACK_ATTEMPTS; i++) { await s.run(); s.advance(defaultRetryPolicy.capDelayMs); }
  assert.equal((await s.run()).status, 'acknowledgmentExhausted'); assert.equal(s.api.calls, MAX_ACK_ATTEMPTS); await unchangedPro(s);
});
test('concurrent workers: active lease blocks second external action', async () => {
  const s = await setup(); await s.verify(); const entered = deferred<void>(), finish = deferred<unknown>();
  s.api.handler = async () => { entered.resolve(); return finish.promise; };
  const first = s.run(); await entered.promise;
  assert.equal((await s.run()).status, 'busy'); finish.resolve({ status: 'success' });
  assert.equal((await first).status, 'acknowledged'); assert.equal(s.api.calls, 1); await unchangedPro(s);
});
test('stale worker failure cannot overwrite newer successful owner', async () => {
  const s = await setup(); await s.verify(); const entered = deferred<void>(), finish = deferred<unknown>();
  s.api.handler = async () => { entered.resolve(); return finish.promise; };
  const old = s.run(); await entered.promise; s.advance();
  s.api.handler = async () => ({ status: 'success' }); assert.equal((await s.run()).status, 'acknowledged');
  finish.resolve({ status: 'permanentFailure' }); assert.equal((await old).status, 'stale');
  assert.equal((await s.state.get()).data()!.status, 'acknowledged'); await unchangedPro(s);
});
test('ledger version change fences late success; next verification/ack recovers', async () => {
  const s = await setup(); await s.verify(); const entered = deferred<void>(), finish = deferred<unknown>();
  s.api.handler = async () => { entered.resolve(); return finish.promise; };
  const old = s.run(); await entered.promise;
  await s.ledger.update({ acknowledgementState: 'ACKNOWLEDGED' });
  finish.resolve({ status: 'success' }); assert.equal((await old).status, 'stale');
  assert.equal((await s.run()).status, 'acknowledged'); assert.equal(s.api.calls, 1);
});
test('missing grant/effective must be repaired by verifier before ack', async () => {
  const s = await setup(); await s.verify(); await s.grant.delete();
  await rejects(s.run(), 'invalidLifecycleTransition'); assert.equal(s.api.calls, 0);
  await s.verify(); await s.effective.delete(); await rejects(s.run(), 'invalidLifecycleTransition');
  await s.verify(); assert.equal((await s.run()).status, 'acknowledged');
});
test('corrupt state rejected without replacing it or invoking adapter', async () => {
  const s = await setup(); await s.verify(); await s.state.set({ status: 'broken' });
  await rejects(s.run(), 'internalConflict'); assert.equal(s.api.calls, 0);
  assert.deepEqual((await s.state.get()).data(), { status: 'broken' });
});
test('impossible acknowledged job with pending ledger rejected', async () => {
  const s = await setup(); await s.verify();
  await s.state.set({ ...s.pending(), status: 'acknowledged', leaseId: null, leaseUntil: null });
  await rejects(s.run(), 'internalConflict'); assert.equal(s.api.calls, 0);
});
test('state parser rejects impossible lifecycle combinations', async () => {
  const s = await setup();
  for (const patch of [{ attemptCount: 0 }, { status: 'verified' }, { leaseId: null }, { nextRetryAt: now },
    { failure: 'acknowledgmentPermanentFailure' }, { extra: true }]) {
    assert.throws(() => parseAckState({ ...s.pending(), ...patch }), AcknowledgmentError);
  }
});

test('crashed final attempt ends in recoverable operational failure without new external call', async () => {
  const s = await setup(); await s.verify(); await s.state.set({ ...s.pending(), attemptCount: MAX_ACK_ATTEMPTS });
  s.advance(); assert.equal((await s.run()).status, 'acknowledgmentExhausted');
  assert.equal(s.api.calls, 0); await unchangedPro(s);
});
test('N3 replay during ack retains lease and creates no duplicate grant or revision', async () => {
  const s = await setup(); await s.verify(); const entered = deferred<void>(), finish = deferred<unknown>();
  s.api.handler = async () => { entered.resolve(); return finish.promise; };
  const task = s.run(); await entered.promise; await s.verify();
  assert.equal((await s.run()).status, 'busy'); finish.resolve({ status: 'success' });
  assert.equal((await task).status, 'acknowledged'); await unchangedPro(s);
  assert.equal((await db.collection(`users/${s.uid}/entitlementGrants`).get()).size, 1);
});
