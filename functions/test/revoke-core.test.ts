import { test } from 'node:test';
import assert from 'node:assert/strict';
import { decideTransition } from '../src/billing/purchase-lifecycle';
import { readPurchase, readEffective } from '../src/billing/schema-v2';
import { parseVoidedObservation } from '../src/billing/voided-purchase-api';
import { effectiveUpdate } from '../src/billing/effective-update';
import { aggregateGrants } from '../src/aggregate';
import { readAccount } from '../src/accounts/account-lifecycle';
import { grant, now, purchase } from './fixtures';
const ledger = readPurchase(purchase());
const account = readAccount({ schemaVersion: 1, state: 'ACTIVE', generation: 1, updatedAt: now, deletionStartedAt: null, deletedAt: null });
const terminal = readPurchase({ ...ledger, purchaseState: 'CANCELED', revokedAt: now, revokeReason: 'ENTITLEMENT_REVOKED', lifecycleRevision: 2 });
for (const state of ['ACTIVE','DELETING','DELETED'] as const) {
  test(`authoritative revoke allowed on ${state} without granting`, () => {
    const d = decideTransition(ledger, 'entitlementRevoked', { ...account, state }, 1, 1);
    assert.equal(d.outcome, 'apply'); assert.ok(!('reason' in d)); assert.equal(d.grantRequired, false); assert.equal(d.lifecycleRevision, 2);
  });
}
for (const observation of ['purchased','acknowledged','acknowledgmentPending','acknowledgmentRetry','pending'] as const) {
  test(`terminal revoke rejects ${observation}`, () => assert.equal(decideTransition(terminal, observation, account, 2, 1).outcome, 'rejected'));
}
test('duplicate revoke preserves revision', () => {
  const result = decideTransition(terminal, 'entitlementRevoked', account, 2, 1);
  assert.equal(result.outcome, 'noop'); assert.ok(!('reason' in result)); assert.equal(result.lifecycleRevision, 2);
});
test('stale revoke revision is fenced', () => assert.deepEqual(decideTransition(terminal, 'entitlementRevoked', account, 1, 1), { outcome: 'stale', reason: 'staleLifecycleRevision' }));
test('stale account generation fenced for negative transition', () => assert.equal(decideTransition(ledger, 'entitlementRevoked', account, 1, 2).outcome, 'stale'));
test('pending cancellation cannot revoke purchased', () => assert.equal(decideTransition(ledger, 'pendingCanceled', account, 1, 1).outcome, 'rejected'));
test('pending cancellation terminal without active grant', () => {
  const pending = readPurchase({ ...ledger, purchaseState: 'PENDING' });
  const result = decideTransition(pending, 'pendingCanceled', account, 1, 1);
  assert.ok(!('reason' in result)); assert.equal(result.purchaseState, 'CANCELED'); assert.equal(result.grantRequired, false);
});
for (const source of ['PROMO','ADMIN','TEST','PLAY_PURCHASE'] as const) {
  test(`other ${source} grant survives revoke and effective revision is semantic`, () => {
    const play = grant({ source: 'PLAY_PURCHASE' }), other = grant({ source });
    const prior = readEffective(aggregateGrants([play, other], now, 3));
    const next = effectiveUpdate([{ ...play, status: 'REVOKED', revokedAt: now }, other], now, prior);
    if (source === 'PLAY_PURCHASE') assert.equal(next, null);
    else { assert.equal(next!.active, true); assert.deepEqual(next!.sources, [source]); assert.equal(next!.revision, 4); assert.equal(effectiveUpdate([other], now, next!), null); }
  });
}
test('last Play revoke becomes Free; inactive accounts cannot gain from promo', () => {
  const prior = readEffective(aggregateGrants([grant({ source: 'PLAY_PURCHASE' })], now, 1));
  const next = effectiveUpdate([], now, prior)!;
  assert.equal(next.active, false); assert.equal(next.revision, 2);
  assert.equal(effectiveUpdate([grant()], now, prior, false)!.active, false);
});
const dto = { packageName: 'com.bronxii.kuktam', productId: 'kuktam_pro_lifetime', purchaseToken: 'synthetic', state: 'entitlementRevoked', authoritative: true, testPurchase: true };
for (const state of ['financialRefund','pendingCanceled','unknown','entitlementRevoked']) {
  test(`adapter distinguishes ${state}`, () => assert.equal(parseVoidedObservation({ ...dto, state }).state, state));
}
test('malformed, extra fields and missing authority rejected', () => {
  for (const value of [null, {}, { ...dto, extra: true }, { ...dto, authoritative: 'yes' }, { ...dto, state: 'refundMeansRevoke' }]) assert.throws(() => parseVoidedObservation(value));
});
