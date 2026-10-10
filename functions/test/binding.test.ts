import test from 'node:test';
import assert from 'node:assert/strict';
import { AccountBinding, authenticatedUid } from '../src/billing/account-binding';
import { parsePlayPurchase } from '../src/billing/play-purchase-api';
import { tokenHash } from '../src/billing/verify-purchase';

const key = Buffer.alloc(32, 42); // synthetic key, never used by an app/backend
test('binding is deterministic, opaque, UID-specific and Play-length-compatible', () => {
  const binding = new AccountBinding(key);
  const alice = binding.forAuthenticatedAccount({ uid: 'alice' });
  assert.equal(alice, new AccountBinding(key).forAuthenticatedAccount({ uid: 'alice' }));
  assert.notEqual(alice, binding.forAuthenticatedAccount({ uid: 'bob' }));
  assert.notEqual(alice, new AccountBinding(Buffer.alloc(32, 43)).forAuthenticatedAccount({ uid: 'alice' }));
  assert.match(alice, /^v1_[A-Za-z0-9_-]{43}$/);
  assert.ok(alice.length <= 64);
  assert.ok(!alice.includes('alice'));
  assert.ok(binding.matches({ uid: 'alice' }, alice));
  assert.ok(!binding.matches({ uid: 'bob' }, alice));
  assert.ok(!binding.matches({ uid: 'alice' }, null));
  assert.ok(!binding.matches({ uid: 'alice' }, 'bad'));
});
test('binding copies secret and refuses missing/short server key', () => {
  const mutable = Buffer.alloc(32, 1);
  const binding = new AccountBinding(mutable);
  const before = binding.forAuthenticatedAccount({ uid: 'alice' });
  mutable.fill(2);
  assert.equal(before, binding.forAuthenticatedAccount({ uid: 'alice' }));
  assert.throws(() => new AccountBinding(Buffer.alloc(0)));
  assert.throws(() => new AccountBinding(Buffer.alloc(31)));
});
test('auth context validation', () => {
  for (const context of [null, undefined, { uid: '' }, { uid: 'a/b' }, { uid: ' a' }, { uid: 'x'.repeat(129) }]) {
    assert.throws(() => authenticatedUid(context), { message: 'unauthenticated' });
  }
});
test('stable token key contains no raw token', () => {
  assert.match(tokenHash('synthetic-token'), /^[a-f0-9]{64}$/);
  assert.equal(tokenHash('synthetic-token'), tokenHash('synthetic-token'));
  assert.notEqual(tokenHash('synthetic-token'), tokenHash('other'));
});
test('runtime API boundary rejects undefined, arrays, extra fields and unknown state', () => {
  for (const value of [undefined, [], {}, { purchaseState: 'PURCHASED' }]) {
    assert.throws(() => parsePlayPurchase(value), { message: 'malformedPlayResponse' });
  }
});
