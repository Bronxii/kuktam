import { Firestore, Timestamp } from 'firebase-admin/firestore';
import { AccountLifecycleStore } from '../accounts/account-lifecycle-store';
import { readAccount } from '../accounts/account-lifecycle';
import { AuthContext, authenticatedUid } from '../billing/account-binding';
import { PurchaseVerifier } from '../billing/verify-purchase';
import { PRODUCT_ID } from '../billing/play-purchase-api';
import { readEffective } from '../billing/schema-v2';
import { VerificationError } from '../billing/errors';
import { LifecycleError } from '../billing/lifecycle-error';

export type TransportCode = 'unauthenticated' | 'permissionDenied' | 'accountDeleting' |
  'accountDeleted' | 'tokenBindingConflict' | 'supportRequired' | 'invalidArgument' |
  'retryableUnavailable' | 'configuration' | 'internalMalformed';
export class TransportError extends Error {
  constructor(readonly code: TransportCode) { super(code); }
}
/** request.auth MUST be supplied by an authenticated runtime, never body JSON.
 * Local transport-neutral handlers; deliberately no deployed Function export. */
export interface AuthenticatedRequest { readonly auth?: AuthContext | null; readonly data: unknown }
function input(value: unknown, fields: string[]): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value) ||
    Object.keys(value).length !== fields.length || fields.some(k => !(k in value))) {
    throw new TransportError('invalidArgument');
  }
  return value as Record<string, unknown>;
}
function safeError(e: unknown): TransportError {
  if (e instanceof TransportError) return e;
  if (e instanceof VerificationError || e instanceof LifecycleError) {
    switch (e.code) {
      case 'unauthenticated': return new TransportError('unauthenticated');
      case 'accountDeleting': return new TransportError('accountDeleting');
      case 'accountDeleted': return new TransportError('accountDeleted');
      case 'accountInactive': return new TransportError('supportRequired');
      case 'bindingConflict': case 'tokenAlreadyBound': case 'accountBindingMismatch':
        return new TransportError('tokenBindingConflict');
      case 'playUnavailable': case 'staleAccountGeneration': case 'staleLifecycleRevision':
        return new TransportError('retryableUnavailable');
      case 'playConfigurationError': return new TransportError('configuration');
      case 'invalidInput': case 'invalidToken': case 'wrongProduct': case 'wrongPackage':
        return new TransportError('invalidArgument');
      default: return new TransportError('internalMalformed');
    }
  }
  // SDK/network exception details are never serialized or logged.
  return new TransportError('retryableUnavailable');
}
export class MonetizationHandlers {
  constructor(private readonly db: Firestore, private readonly accounts: AccountLifecycleStore,
    private readonly verifier: Pick<PurchaseVerifier, 'verify'>, private readonly clock: () => Timestamp = Timestamp.now) {}
  private async run<T>(request: AuthenticatedRequest, body: (context: AuthContext) => Promise<T>): Promise<T> {
    try { return await body({ uid: authenticatedUid(request.auth) }); }
    catch (e) { throw safeError(e); }
  }
  prepareProPurchase(request: AuthenticatedRequest) {
    return this.run(request, async context => {
      input(request.data, []);
      // Existing initialization never reactivates a deleting/deleted marker.
      const existing = await this.db.doc(`accountLifecycle/${context.uid}`).get();
      if (existing.exists) {
        const account = readAccount(existing.data());
        if (account.state !== 'ACTIVE') throw new TransportError(account.state === 'DELETING' ? 'accountDeleting' : 'accountDeleted');
      }
      const marker = await this.accounts.initializeActive(context);
      const opaqueAccountId = await this.accounts.register(context, marker.generation);
      return { schemaVersion: 1, productId: PRODUCT_ID, opaqueAccountId };
    });
  }
  verifyProPurchase(request: AuthenticatedRequest) {
    return this.run(request, async context => {
      const restoring = !!request.data && typeof request.data === 'object' && 'intent' in request.data;
      const data = input(request.data, restoring ? ['productId', 'purchaseToken','intent'] : ['productId', 'purchaseToken']);
      if (restoring && data.intent !== 'restore') throw new TransportError('invalidArgument');
      if (data.productId !== PRODUCT_ID || typeof data.purchaseToken !== 'string' ||
        !data.purchaseToken || data.purchaseToken.trim() !== data.purchaseToken || data.purchaseToken.length > 4096) {
        throw new TransportError('invalidArgument');
      }
      try {
        const result = await this.verifier.verify(context, { purchaseToken: data.purchaseToken, ...(restoring ? {intent:'restore'} : {}) });
        return { schemaVersion: 1, outcome: result.status === 'granted' ? 'verified' : 'pending' };
      } catch (e) {
        if (e instanceof VerificationError && e.code === 'purchaseNotOwned' ||
          e instanceof LifecycleError && e.code === 'verificationRejected') {
          return { schemaVersion: 1, outcome: 'rejected' };
        }
        throw e;
      }
    });
  }
  getEntitlementProof(request: AuthenticatedRequest) {
    return this.run(request, async context => {
      input(request.data, []);
      return this.db.runTransaction(async tx => {
        const marker = await tx.get(this.db.doc(`accountLifecycle/${context.uid}`));
        const document = await tx.get(this.db.doc(`users/${context.uid}/entitlements/pro`));
        if (marker.exists) {
          const account = readAccount(marker.data());
          if (account.state !== 'ACTIVE') throw new TransportError(account.state === 'DELETING' ? 'accountDeleting' : 'accountDeleted');
        } else if (document.exists) { throw new TransportError('internalMalformed'); }
        const now = this.clock();
        // Missing document is virtual Free revision 0; never write on proof read.
        const e = document.exists ? readEffective(document.data()) : {
          active: false, validUntil: null, sources: [], revision: 0,
          verifiedAt: now, updatedAt: now,
        };
        if (e.updatedAt.toMillis() > now.toMillis() || e.verifiedAt.toMillis() > now.toMillis()) {
          throw new TransportError('internalMalformed');
        }
        return { schemaVersion: 1, active: e.active, sources: e.sources,
          validUntil: e.validUntil?.toMillis() ?? null, revision: e.revision,
          verifiedAt: e.verifiedAt.toMillis(), updatedAt: e.updatedAt.toMillis(),
          proofIssuedAt: now.toMillis() };
      });
    });
  }
}

/** Callable-compatible data envelope. Runtime integration must map verified
 * request.auth, enforce App Check/rate limits, and must not log request data. */
export async function transportResult(action: () => Promise<unknown>): Promise<unknown> {
  try { return await action(); }
  catch (e) { return { schemaVersion: 1, error: safeError(e).code }; }
}
