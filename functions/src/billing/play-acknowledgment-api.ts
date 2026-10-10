import { PlayPurchaseQuery } from './play-purchase-api';

export type AcknowledgmentReply = { readonly status: 'success' | 'alreadyAcknowledged' | 'temporaryFailure' | 'permanentFailure' };
/** Server-only adapter. Require bounded I/O timeout shorter than the lease.
 * Duplicate calls (including after ambiguous network errors) must be safe. */
export interface PlayAcknowledgmentApi {
  acknowledge(purchase: PlayPurchaseQuery, options?: { readonly signal: AbortSignal }): Promise<unknown>;
}
export class AcknowledgmentError extends Error {
  constructor(readonly code: 'invalidLifecycleTransition' | 'internalConflict') { super(code); }
}
export type AckFailure = 'acknowledgmentTemporaryFailure' | 'acknowledgmentPermanentFailure' | 'unexpectedResponse';
