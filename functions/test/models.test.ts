import test from 'node:test';
import assert from 'node:assert/strict';
import { Timestamp } from 'firebase-admin/firestore';
import { aggregateGrants } from '../src/aggregate';
import { parseEntitlement, parseGrant, parsePurchase, sources } from '../src/models';
import { requireLocalEmulator } from './emulator-guard';
import { grant, now, later, purchase } from './fixtures';

for (const source of sources) {
  test(`${source} permanent grants Pro`, () => {
    const result = aggregateGrants([grant({ source })], now, 1);
    assert.equal(result.active, true);
    assert.equal(result.validUntil, null);
    assert.deepEqual(result.sources, [source]);
  });
}
test('no active grants means inactive Free', () => {
  for (const grants of [[], [grant({ status: 'INACTIVE' })],
    [grant({ startsAt: later })], [grant({ revokedAt: now })],
    [grant({ status: 'REVOKED' })]]) {
    assert.equal(aggregateGrants(grants, now, 1).active, false);
  }
});
test('start inclusive and expiry exclusive at nanosecond boundaries', () => {
  const g = grant({ expiresAt: later });
  assert.equal(aggregateGrants([g], new Timestamp(now.seconds - 1, 999999999), 1).active, false);
  assert.equal(aggregateGrants([g], now, 1).active, true);
  assert.equal(aggregateGrants([g], new Timestamp(later.seconds - 1, 999999999), 1).active, true);
  assert.equal(aggregateGrants([g], later, 1).active, false);
});
for (const source of ['PROMO', 'ADMIN', 'TEST'] as const) {
  test(`Play revoke preserves independent ${source}`, () => {
    const input = [grant({ source: 'PLAY_PURCHASE', status: 'REVOKED' }), grant({ source })];
    assert.deepEqual(aggregateGrants(input, now, 1), aggregateGrants([...input].reverse(), now, 1));
    assert.deepEqual(aggregateGrants(input, now, 1).sources, [source]);
  });
}
test('latest active expiry and permanent grant OR', () => {
  const end = new Timestamp(later.seconds + 86400, 0);
  const input = [grant({ expiresAt: later }), grant({ source: 'ADMIN', expiresAt: end })];
  assert.equal(aggregateGrants(input, now, 2).validUntil?.isEqual(end), true);
  assert.equal(aggregateGrants([...input, grant()], now, 2).validUntil, null);
});
test('sources deduplicated, inputs unchanged, results immutable', () => {
  const input = [grant(), grant()];
  const result = aggregateGrants(input, now, 1);
  assert.deepEqual(result.sources, ['PROMO']);
  assert.equal(input.length, 2);
  assert.ok(Object.isFrozen(result));
  assert.ok(Object.isFrozen(result.sources));
});
test('grant period must be valid', () => {
  assert.throws(() => parseGrant(grant({ expiresAt: now })));
  assert.throws(() => parseGrant(grant({ startsAt: later, expiresAt: now })));
});
test('document parsers reject wrong types, extra personal fields and missing fields', () => {
  assert.throws(() => parseGrant({ ...grant(), source: 'UNKNOWN' }));
  assert.throws(() => parseGrant({ ...grant(), startsAt: new Date() }));
  assert.throws(() => parseGrant({ ...grant(), email: 'not-stored@example.invalid' }));
  assert.throws(() => parsePurchase({ ...purchase(), rawApiResponse: {} }));
  assert.throws(() => parsePurchase({ ...purchase(), boundUid: '' }));
  assert.throws(() => parsePurchase({}));
  assert.throws(() => aggregateGrants([], now, 0));
  assert.throws(() => parseEntitlement({ ...aggregateGrants([], now, 1), active: true }));
  assert.throws(() => parseEntitlement({ ...aggregateGrants([], now, 1), sources: ['PROMO', 'PROMO'] }));
});
test('bound ledger accepts synthetic purchase', () => {
  assert.deepEqual(parsePurchase(purchase()), purchase());
});
test('deleted-account tombstone rejects UID, binding and unnecessary raw token', () => {
  const { boundUid, accountBinding, purchaseToken, ...base } = purchase();
  const tombstone = { ...base, bindingState: 'ACCOUNT_DELETED', reconciliationRequired: false };
  assert.equal(parsePurchase(tombstone).bindingState, 'ACCOUNT_DELETED');
  assert.throws(() => parsePurchase({ ...tombstone, boundUid }));
  assert.throws(() => parsePurchase({ ...tombstone, accountBinding }));
  assert.throws(() => parsePurchase({ ...tombstone, purchaseToken }));
  assert.equal(parsePurchase({ ...tombstone, reconciliationRequired: true, purchaseToken }).bindingState,
    'ACCOUNT_DELETED');
  assert.throws(() => parsePurchase({ ...tombstone, reconciliationRequired: true }));
});
test('revoked tombstone needs timestamp', () => {
  const { boundUid: _uid, accountBinding: _binding, purchaseToken: _token, ...base } = purchase();
  const retired = { ...base, bindingState: 'REVOKED', reconciliationRequired: false };
  assert.throws(() => parsePurchase(retired));
  assert.equal(parsePurchase({ ...retired, revokedAt: now }).bindingState, 'REVOKED');
});
test('emulator guard fails closed for missing or production endpoints', () => {
  const safe = { FIRESTORE_EMULATOR_HOST: '127.0.0.1:8088',
    GCLOUD_PROJECT: 'demo-kuktam-local', GOOGLE_CLOUD_PROJECT: 'demo-kuktam-local',
    METADATA_SERVER_DETECTION: 'none' };
  requireLocalEmulator(safe);
  for (const bad of [{}, { ...safe, GCLOUD_PROJECT: 'kuktam-67768' },
    { ...safe, GOOGLE_CLOUD_PROJECT: 'kuktam-67768' },
    { ...safe, FIRESTORE_EMULATOR_HOST: 'firestore.googleapis.com:443' },
    { ...safe, FIRESTORE_EMULATOR_HOST: '127.0.0.1:8080' },
    { ...safe, METADATA_SERVER_DETECTION: 'ping-only' }]) {
    assert.throws(() => requireLocalEmulator(bad));
  }
});
