import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseEnvelope, dedupeKey, MAX_PAYLOAD_BYTES } from '../src/billing/rtdn/notification';
import { PACKAGE_NAME, PRODUCT_ID } from '../src/billing/play-purchase-api';
export const source = 'local:kuktam-rtdn';
export function payload(body: Record<string, unknown> = { oneTimeProductNotification: { version: '1.0', notificationType: 1, purchaseToken: 'synthetic-token', sku: PRODUCT_ID } }) {
  return { version: '1.0', packageName: PACKAGE_NAME, eventTimeMillis: '1791321600000', ...body };
}
export function envelope(value: unknown = payload(), messageId = 'message-1') {
  return { source, messageId, publishTime: '2026-10-07T00:00:00Z', data: Buffer.from(JSON.stringify(value)).toString('base64') };
}
function outcome(value: unknown) { const p = parseEnvelope(value, source); return typeof p === 'string' ? p : p.notification.rejection ?? p.notification.category; }
test('valid one-time, token hash only for identity; stable collision-safe key', () => {
  const p = parseEnvelope(envelope(), source); assert.notEqual(typeof p, 'string'); if (typeof p === 'string') return;
  assert.equal(p.notification.category, 'oneTime'); assert.equal(p.notification.tokenHash?.length, 64);
  assert.equal(p.key, dedupeKey(source, 'message-1')); assert.notEqual(dedupeKey('ab','c'), dedupeKey('a','bc'));
});
test('valid voided accepts real shape without sku or version in body', () => {
  assert.equal(outcome(envelope(payload({ voidedPurchaseNotification: { purchaseToken: 'synthetic', orderId: 'synthetic-order', productType: 2, refundType: 1 } }))), 'voided');
});
test('valid test notification', () => assert.equal(outcome(envelope(payload({ testNotification: { version: '1.0' } }))), 'test'));
for (const [name, modify] of Object.entries({
  base64: () => ({ ...envelope(), data: '!!!!' }),
  noncanonicalBase64: () => ({ ...envelope(), data: 'Zh==' }),
  json: () => ({ ...envelope(), data: Buffer.from('{').toString('base64') }),
  utf8: () => ({ ...envelope(), data: Buffer.from([0xff, 0xfe]).toString('base64') }),
  missingMessage: () => ({ ...envelope(), messageId: '' }),
  wrongSource: () => ({ ...envelope(), source: 'untrusted' }),
  oversized: () => ({ ...envelope(), data: 'A'.repeat(MAX_PAYLOAD_BYTES * 2) }),
  malformedTime: () => envelope({ ...payload(), eventTimeMillis: '1e10' }),
  timestampOverflow: () => envelope({ ...payload(), eventTimeMillis: '99999999999999999' }),
  missingTime: () => envelope({ ...payload(), eventTimeMillis: undefined }),
  invalidDate: () => ({ ...envelope(), publishTime: '2026-02-30T00:00:00Z' }),
  missingToken: () => envelope(payload({ oneTimeProductNotification: { version: '1.0', notificationType: 1, sku: PRODUCT_ID } })),
  multipleBodies: () => envelope({ ...payload(), testNotification: { version: '1.0' } }),
  bodyArray: () => envelope(payload({ oneTimeProductNotification: [] })),
  deeplyMalformed: () => ({ ...envelope(), data: Buffer.from('['.repeat(1000) + ']'.repeat(1000)).toString('base64') }),
})) test(`controlled malformed: ${name}`, () => assert.equal(outcome(modify()), 'malformedNotification'));
test('wrong package distinguished', () => assert.equal(outcome(envelope({ ...payload(), packageName: 'wrong' })), 'wrongPackage'));
for (const [name, value] of Object.entries({
  version: { ...payload(), version: '2.0' },
  bodyVersion: payload({ testNotification: { version: '2.0' } }),
  subscription: payload({ subscriptionNotification: { version: '1.0', notificationType: 1, purchaseToken: 'synthetic' } }),
  future: payload({ futureNotification: {} }),
  unknownType: payload({ oneTimeProductNotification: { version: '1.0', notificationType: 99, purchaseToken: 'synthetic', sku: PRODUCT_ID } }),
  otherProduct: payload({ oneTimeProductNotification: { version: '1.0', notificationType: 1, purchaseToken: 'synthetic', sku: 'other' } }),
  voidedSubscription: payload({ voidedPurchaseNotification: { purchaseToken: 'synthetic', orderId: 'synthetic', productType: 1, refundType: 1 } }),
})) test(`controlled unsupported: ${name}`, () => assert.equal(outcome(envelope(value)), 'unsupportedNotification'));
test('failure outcome never contains raw token or underlying JSON exception', () => {
  const p = parseEnvelope(envelope(payload({ oneTimeProductNotification: { version: '1.0', notificationType: 'bad', purchaseToken: 'secret-token' } })), source);
  assert.ok(!JSON.stringify(p).includes('secret-token'));
});
