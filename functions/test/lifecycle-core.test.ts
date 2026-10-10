import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Timestamp } from 'firebase-admin/firestore';
import { purchase, now } from './fixtures';
import { readPurchase, readEffective } from '../src/billing/schema-v2';
import { aggregateGrants } from '../src/aggregate';
import { LifecycleError } from '../src/billing/lifecycle-error';
import { readAccount, advanceAccount } from '../src/accounts/account-lifecycle';
import { readBinding } from '../src/accounts/binding-registry';
import { decideTransition } from '../src/billing/purchase-lifecycle';
import { beginAttempt, retryAt, newRecoveryGeneration, defaultRetryPolicy } from '../src/billing/retry-policy';
const account = () => readAccount({ schemaVersion: 1, state: 'ACTIVE', generation: 1, updatedAt: now, deletionStartedAt: null, deletedAt: null });

test('v1 normalization is immutable, pure and does not invent binding or freshness', () => {
  const v1 = purchase(), v2 = readPurchase(v1);
  assert.equal(v1.schemaVersion, 1); assert.equal(v2.schemaVersion, 2);
  assert.equal(v2.lifecycleRevision, 1); assert.equal(v2.lastCheckedAt, null); assert.equal(v2.accountGeneration, null);
  assert.deepEqual(readPurchase(v2), v2); assert.ok(Object.isFrozen(v2));
});
for (const [name, value] of Object.entries({ version: { ...purchase(), schemaVersion: 99 }, malformed: { ...purchase(), testPurchase: 'yes' },
  missing: { schemaVersion: 1 }, unknown: { ...purchase(), future: true }, missingV2: { ...purchase(), schemaVersion: 2 },
  revision: { ...readPurchase(purchase()), lifecycleRevision: 0 }, extraV2: { ...readPurchase(purchase()), future: 1 },
  referencePair: { ...readPurchase(purchase()), accountGeneration: 1 }, date: { ...readPurchase(purchase()), nextCheckAt: 'tomorrow' } })) {
  test(`strict schemas reject ${name}`, () => assert.throws(() => readPurchase(value), LifecycleError));
}
test('effective entitlement v1/v2 share semantic contract', () => {
  const v1 = aggregateGrants([], now, 1), v2 = readEffective(v1);
  assert.equal(v2.schemaVersion, 2); assert.deepEqual(readEffective(v2), v2);
  assert.throws(() => readEffective({ ...v2, extra: 1 })); assert.throws(() => readEffective({ ...v2, schemaVersion: 3 }));
});
test('pending to purchased and acknowledged monotonic transitions', () => {
  const pending = readPurchase({ ...purchase(), purchaseState: 'PENDING' });
  assert.equal(decideTransition(null, 'pending', account(), 0, 1).outcome, 'apply');
  const decision = decideTransition(pending, 'purchased', account(), 1, 1);
  assert.ok('lifecycleRevision' in decision); assert.equal(decision.lifecycleRevision, 2);
  const purchased = readPurchase(purchase());
  assert.equal(decideTransition(purchased, 'purchased', account(), 1, 1).outcome, 'noop');
  assert.equal(decideTransition(purchased, 'pending', account(), 1, 1).outcome, 'stale');
  assert.equal(decideTransition(purchased, 'acknowledged', account(), 1, 1).outcome, 'apply');
});
test('ack operational pending/retry do not increase lifecycle revision', () => {
  for (const event of ['acknowledgmentPending', 'acknowledgmentRetry'] as const) {
    const decision = decideTransition(readPurchase(purchase()), event, account(), 1, 1);
    assert.ok('lifecycleRevision' in decision); assert.equal(decision.lifecycleRevision, 1);
    assert.equal(decideTransition(null, event, account(), 0, 1).outcome, 'rejected');
  }
});
test('terminal/deleted/stale account/revision never reactivate', () => {
  const ledger = readPurchase(purchase());
  assert.equal(decideTransition(ledger, 'purchased', account(), 0, 1).outcome, 'stale');
  assert.equal(decideTransition(ledger, 'purchased', account(), 1, 0).outcome, 'stale');
  assert.equal(decideTransition(ledger, 'terminalInvalid', account(), 1, 1).outcome, 'rejected');
  for (const state of ['DELETING', 'DELETED'] as const) assert.equal(decideTransition(ledger, 'purchased',
    readAccount({ ...account(), state, deletionStartedAt: now, deletedAt: state === 'DELETED' ? now : null }), 1, 1).outcome, 'rejected');
  const terminal = readPurchase({ ...purchase(), revokedAt: now });
  assert.equal(decideTransition(terminal, 'purchased', account(), 1, 1).outcome, 'rejected');
  const ack = readPurchase({ ...purchase(), acknowledgementState: 'ACKNOWLEDGED' });
  assert.equal(decideTransition(ack, 'purchased', account(), 1, 1).outcome, 'stale');
});
test('account generation monotonic with idempotent same-state and no reversal', () => {
  const deleting = advanceAccount(account(), 'DELETING', 1, now);
  assert.equal(deleting.generation, 2); assert.equal(advanceAccount(deleting, 'DELETING', 2, now), deleting);
  const deleted = advanceAccount(deleting, 'DELETED', 2, now); assert.equal(deleted.generation, 3);
  assert.throws(() => advanceAccount(deleted, 'ACTIVE', 3, now)); assert.throws(() => advanceAccount(deleting, 'DELETED', 1, now));
  assert.throws(() => readAccount({ ...account(), state: 'DELETED' }));
});
test('binding active and minimal tombstone schemas reject UID in tombstone', () => {
  const base = { schemaVersion: 1, keyVersion: 'v1', createdAt: now, updatedAt: now };
  assert.equal(readBinding({ ...base, state: 'ACTIVE', uid: 'alice' }).state, 'ACTIVE');
  assert.equal(readBinding({ ...base, state: 'TOMBSTONED' }).state, 'TOMBSTONED');
  assert.throws(() => readBinding({ ...base, state: 'TOMBSTONED', uid: 'alice' }));
  assert.throws(() => readBinding({ ...base, keyVersion: 'bad', state: 'ACTIVE', uid: 'a' }));
});
test('retry first/minimum/exponential/cap/fake jitter', () => {
  const state = { generation: 1, generationAttempts: 1, totalAttempts: 1 };
  assert.equal(retryAt(state, 0, () => 0), 60000);
  assert.equal(retryAt({ ...state, generationAttempts: 3, totalAttempts: 3 }, 0, () => 0), 120000);
  assert.equal(retryAt({ ...state, generationAttempts: 3, totalAttempts: 3 }, 0, () => 0.5), 180000);
  assert.equal(retryAt({ ...state, generationAttempts: 7, totalAttempts: 7 }, 0, () => 0.5,
    { ...defaultRetryPolicy, capDelayMs: 120000 }), 90000);
  assert.throws(() => retryAt(state, 0, () => 1));
});
test('attempt budget and new recovery generation preserve total attempts', () => {
  let state = { generation: 1, generationAttempts: 0, totalAttempts: 0 };
  for (let i = 0; i < 8; i++) state = beginAttempt(state)!;
  assert.equal(beginAttempt(state), null); assert.equal(retryAt(state, 0, () => 0), null);
  const next = newRecoveryGeneration(state, 1); assert.deepEqual(next, { generation: 2, generationAttempts: 0, totalAttempts: 8 });
  assert.equal(beginAttempt(next)!.totalAttempts, 9);
  assert.throws(() => newRecoveryGeneration(state, 0)); assert.throws(() => newRecoveryGeneration(next, 2));
});
test('retry policy is injectable and enforces I/O shorter than lease', () => {
  const start = { generation: 1, generationAttempts: 0, totalAttempts: 0 };
  assert.throws(() => beginAttempt(start, { ...defaultRetryPolicy, ioTimeoutMs: 120000 }));
  assert.equal(beginAttempt(start, { ...defaultRetryPolicy, attemptsPerGeneration: 1 })!.generationAttempts, 1);
});

test('closure: account timestamps reject reversed single-nanosecond ordering',()=>{
 const later=new Timestamp(now.seconds,now.nanoseconds+1);
 assert.throws(()=>readAccount({schemaVersion:1,state:'DELETED',generation:3,
  updatedAt:later,deletionStartedAt:later,deletedAt:now}));
 assert.throws(()=>readAccount({schemaVersion:1,state:'DELETING',generation:2,
  updatedAt:now,deletionStartedAt:later,deletedAt:null}));
});
