import { PACKAGE_NAME } from '../billing/play-purchase-api';
export interface VoidedFeedQuery { readonly packageName: typeof PACKAGE_NAME; readonly startMs: number; readonly endMs: number; readonly pageToken: string | null; readonly limit: number; }
/** Discovery only, NEVER evidence to revoke. Fresh per-token lookup is mandatory.
 * Production uses Google's rolling 30-day defaults; query times are local job metadata.
 * Returned voidedTimeMillis need not fall within those local checkpoint times. */
export interface VoidedPurchaseFeed { list(query: VoidedFeedQuery, options?: { signal: AbortSignal }): Promise<unknown>; }
export interface VoidedFeedPage { readonly items: readonly { readonly purchaseToken: string; readonly voidedTimeMs: number }[]; readonly nextPageToken: string | null; }
export function parseFeed(value: unknown, limit: number): VoidedFeedPage {
  const v = value as VoidedFeedPage;
  if (!v || Object.keys(v).sort().join(',') !== 'items,nextPageToken' || !Array.isArray(v.items) || v.items.length > limit ||
    !(v.nextPageToken === null || typeof v.nextPageToken === 'string' && !!v.nextPageToken && v.nextPageToken.length <= 4096) ||
    v.items.some(i => !i || Object.keys(i).sort().join(',') !== 'purchaseToken,voidedTimeMs' || typeof i.purchaseToken !== 'string' ||
      !i.purchaseToken || i.purchaseToken.length > 4096 || i.purchaseToken.trim() !== i.purchaseToken ||
      !Number.isSafeInteger(i.voidedTimeMs) || i.voidedTimeMs < 0 || i.voidedTimeMs > 253402300799999)) throw new Error('invalidVoidedPage');
  return v;
}
