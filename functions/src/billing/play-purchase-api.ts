import { VerificationError } from './errors';

export const PACKAGE_NAME = 'com.bronxii.kuktam';
export const PRODUCT_ID = 'kuktam_pro_lifetime';

export interface PlayPurchaseQuery {
  readonly packageName: typeof PACKAGE_NAME;
  readonly productId: typeof PRODUCT_ID;
  readonly purchaseToken: string;
}

export interface PlayPurchase {
  readonly packageName: string;
  readonly productId: string;
  readonly purchaseToken: string;
  readonly purchaseState: 'PENDING' | 'PURCHASED' | 'CANCELED';
  readonly acknowledgementState: 'PENDING' | 'ACKNOWLEDGED';
  readonly obfuscatedExternalAccountId: string | null;
  readonly testPurchase: boolean;
}

/** Trusted server-side adapter. Null means verified not-found, a thrown error
 * means unavailable. Unknown forces runtime validation at the trust boundary.
 * A future real adapter maps authenticated Google API data + request identity
 * into this DTO (fields are not necessarily all present in the raw Play API).
 * No HTTP implementation, consume or acknowledge operation exists in N3.
 */
export interface PlayPurchaseApi {
  lookup(query: PlayPurchaseQuery, options?: { signal: AbortSignal }): Promise<unknown | null>;
}

export function parsePlayPurchase(value: unknown): PlayPurchase {
  const bad = () => { throw new VerificationError('malformedPlayResponse'); };
  if (!value || typeof value !== 'object' || Array.isArray(value)) return bad();
  const v = value as Record<string, unknown>;
  const fields = ['packageName', 'productId', 'purchaseToken', 'purchaseState',
    'acknowledgementState', 'obfuscatedExternalAccountId', 'testPurchase'];
  if (Object.keys(v).length !== fields.length || fields.some(k => !(k in v))) return bad();
  for (const key of ['packageName', 'productId', 'purchaseToken']) {
    if (typeof v[key] !== 'string' || (v[key] as string).length === 0) return bad();
  }
  if (!['PENDING', 'PURCHASED', 'CANCELED'].includes(v.purchaseState as string) ||
    !['PENDING', 'ACKNOWLEDGED'].includes(v.acknowledgementState as string) ||
    (v.obfuscatedExternalAccountId !== null && typeof v.obfuscatedExternalAccountId !== 'string') ||
    typeof v.testPurchase !== 'boolean' ||
    (v.purchaseState === 'PENDING' && v.acknowledgementState !== 'PENDING')) return bad();
  return Object.freeze({ ...v }) as unknown as PlayPurchase;
}

/** Safe adapter failure classification; no upstream response/message retained. */
export class PlayLookupError extends Error {
  constructor(readonly code: 'unavailable' | 'configuration') { super(code); }
}