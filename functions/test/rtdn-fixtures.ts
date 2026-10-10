import { PACKAGE_NAME, PRODUCT_ID } from '../src/billing/play-purchase-api';
export const rtdnSource = 'local:kuktam-rtdn';
export function delivery(token: string, messageId: string, category = 'oneTime', type = 1, eventTimeMillis = '1791321600000') {
  const body = category === 'oneTime' ? { oneTimeProductNotification: { version: '1.0', notificationType: type, purchaseToken: token, sku: PRODUCT_ID } } :
    category === 'voided' ? { voidedPurchaseNotification: { purchaseToken: token, orderId: 'synthetic-order', productType: 2, refundType: type } } :
    { testNotification: { version: '1.0' } };
  return { source: rtdnSource, messageId, publishTime: '2026-10-07T00:00:00Z', data: Buffer.from(JSON.stringify({ version: '1.0', packageName: PACKAGE_NAME, eventTimeMillis, ...body })).toString('base64') };
}
