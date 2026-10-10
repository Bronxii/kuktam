import { createHash } from 'node:crypto';
import { PACKAGE_NAME, PRODUCT_ID } from '../play-purchase-api';
import { tokenHash } from '../purchase-identity';

/** Source must be supplied by an authenticated, allowlisted transport, not JSON.
 * The local core does not authenticate Pub/Sub or expose a network endpoint. */
export interface RtdnEnvelope { readonly source: string; readonly messageId: string; readonly publishTime: string; readonly data: string; }
export const rtdnOutcomes = ['processed','duplicate','ignoredTestNotification','unsupportedNotification',
  'malformedNotification','wrongPackage','purchaseUnresolved','bindingTombstoned',
  'retryablePlayFailure','permanentConfigurationFailure','staleNoOp','lifecycleApplied',
  'busyLease','messageConflict','internalConflict','retryDeferred','recoveryRequired'] as const;
export type RtdnOutcome = typeof rtdnOutcomes[number];
export interface ParsedNotification {
  readonly category: 'oneTime' | 'voided' | 'test' | 'unsupported' | 'rejected';
  readonly notificationType: number | null;
  readonly eventTimeMillis: number | null;
  readonly token: string | null;
  readonly tokenHash: string | null;
  readonly rejection: RtdnOutcome | null;
}
export interface ParsedDelivery {
  readonly key: string; readonly source: string; readonly messageId: string;
  readonly publishTimeMillis: number; readonly fingerprint: string; readonly notification: ParsedNotification;
}
export const MAX_PAYLOAD_BYTES = 32768;
export function dedupeKey(source: string, messageId: string): string {
  return createHash('sha256').update(JSON.stringify([source, messageId])).digest('hex');
}
const object = (v: unknown): v is Record<string, unknown> => !!v && typeof v === 'object' && !Array.isArray(v);
const text = (v: unknown, max: number): v is string => typeof v === 'string' && v.length > 0 && v.length <= max && v.trim() === v;
const time = (v: unknown): v is string => typeof v === 'string' && /^(0|[1-9][0-9]{0,14})$/.test(v) && Number(v) <= 253402300799999;
/** Unsupported schemas/types are ignored, malformed supported bodies rejected.
 * No raw payload/exception text is returned on failure. Additive body fields are
 * ignored; exactly one *Notification body must be present. */
export function parseEnvelope(input: unknown, expectedSource: string): ParsedDelivery | RtdnOutcome {
  if (!object(input) || !text(input.source, 512) || input.source !== expectedSource || !text(input.messageId, 256) ||
    typeof input.publishTime !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?Z$/.test(input.publishTime) ||
    !Number.isFinite(Date.parse(input.publishTime)) || new Date(input.publishTime).toISOString().slice(0,19) !== input.publishTime.slice(0,19) ||
    typeof input.data !== 'string' || input.data.length > Math.ceil(MAX_PAYLOAD_BYTES / 3) * 4) return 'malformedNotification';
  const rejected = (code: RtdnOutcome): ParsedNotification => ({ category: code === 'unsupportedNotification' ? 'unsupported' : 'rejected',
    notificationType: null, eventTimeMillis: null, token: null, tokenHash: null, rejection: code });
  let n: ParsedNotification;
  try {
    if (!input.data || input.data.length > Math.ceil(MAX_PAYLOAD_BYTES / 3) * 4 ||
      !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(input.data)) throw new Error();
    const bytes = Buffer.from(input.data, 'base64');
    if (bytes.length > MAX_PAYLOAD_BYTES || bytes.toString('base64') !== input.data) throw new Error();
    const root: unknown = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes));
    if (!object(root) || !time(root.eventTimeMillis)) throw new Error();
    const bodies = Object.keys(root).filter(k => k.endsWith('Notification'));
    if (bodies.length !== 1 || !object(root[bodies[0]!])) throw new Error();
    const kind = bodies[0]!, body = root[kind] as Record<string, unknown>;
    if (root.packageName !== PACKAGE_NAME) n = rejected('wrongPackage');
    else if (root.version !== '1.0') n = rejected('unsupportedNotification');
    else if (!['oneTimeProductNotification','voidedPurchaseNotification','testNotification'].includes(kind)) n = rejected('unsupportedNotification');
    else if (kind !== 'voidedPurchaseNotification' && body.version !== '1.0') n = rejected('unsupportedNotification');
    else if (kind === 'testNotification') n = { category: 'test', notificationType: null, eventTimeMillis: Number(root.eventTimeMillis), token: null, tokenHash: null, rejection: null };
    else {
      if (!text(body.purchaseToken, 4096)) throw new Error();
      const type = kind === 'oneTimeProductNotification' ? body.notificationType : body.refundType;
      if (!Number.isSafeInteger(type)) throw new Error();
      if (kind === 'oneTimeProductNotification' && !text(body.sku, 256) ||
        kind === 'voidedPurchaseNotification' && (!text(body.orderId, 256) || !Number.isSafeInteger(body.productType))) throw new Error();
      const supported = [1,2].includes(type as number) && (kind === 'oneTimeProductNotification' ? body.sku === PRODUCT_ID : body.productType === 2);
      n = supported ? { category: kind === 'oneTimeProductNotification' ? 'oneTime' : 'voided', notificationType: type as number,
        eventTimeMillis: Number(root.eventTimeMillis), token: body.purchaseToken, tokenHash: tokenHash(body.purchaseToken), rejection: null } : rejected('unsupportedNotification');
    }
  } catch { n = rejected('malformedNotification'); }
  return { key: dedupeKey(input.source, input.messageId), source: input.source, messageId: input.messageId,
    publishTimeMillis: Date.parse(input.publishTime), fingerprint: createHash('sha256').update(input.publishTime).update('\0').update(input.data).digest('hex'), notification: n };
}
