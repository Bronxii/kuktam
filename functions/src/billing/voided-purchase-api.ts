import { PlayPurchaseQuery } from './play-purchase-api';

export type VoidedState = 'entitlementRevoked' | 'financialRefund' | 'pendingCanceled' | 'unknown';
/** Trusted server adapter DTO, not a client request or raw financial notification.
 * A future adapter must establish entitlement revocation separately from refund.
 * Request identity may be supplied by the authenticated lookup, not an event hint.
 * No event timestamp can substitute for a fresh lookup and local revision fence. */
export interface VoidedObservation {
  readonly packageName: string;
  readonly productId: string;
  readonly purchaseToken: string;
  readonly state: VoidedState;
  readonly authoritative: boolean;
  readonly testPurchase: boolean;
}
export interface VoidedPurchaseApi {
  lookup(query: PlayPurchaseQuery, options?: { signal: AbortSignal }): Promise<unknown | null>;
}
export class VoidedLookupError extends Error {
  constructor(readonly code: 'unavailable' | 'configuration') { super(code); }
}
export function parseVoidedObservation(value: unknown): VoidedObservation {
  const bad = () => { throw new TypeError('invalidVoidedObservation'); };
  if (!value || typeof value !== 'object' || Array.isArray(value)) return bad();
  const v = value as Record<string, unknown>;
  const keys = ['packageName','productId','purchaseToken','state','authoritative','testPurchase'];
  if (Object.keys(v).length !== keys.length || keys.some(k => !(k in v))) return bad();
  for (const key of ['packageName','productId','purchaseToken']) {
    if (typeof v[key] !== 'string' || !(v[key] as string).trim()) return bad();
  }
  if (!['entitlementRevoked','financialRefund','pendingCanceled','unknown'].includes(v.state as string) ||
    typeof v.authoritative !== 'boolean' || typeof v.testPurchase !== 'boolean') return bad();
  return Object.freeze({ ...v }) as unknown as VoidedObservation;
}
export type RevokeResult = { readonly outcome:
  'purchaseRevoked' | 'refundWithoutRevoke' | 'pendingCanceled' | 'revokeAlreadyApplied' |
  'voidedLookupUnavailable' | 'voidedLookupConfigError' | 'recheckRequired' |
  'staleObservation' | 'lifecycleConflict'; readonly reason?: string };
