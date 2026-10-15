import { Firestore, Timestamp } from 'firebase-admin/firestore';
import { AccountBinding, authenticatedUid, AuthContext } from './account-binding';
import { VerificationError } from './errors';
import { PACKAGE_NAME, PRODUCT_ID, PlayPurchaseApi, PlayLookupError, parsePlayPurchase } from './play-purchase-api';
import { tokenHash } from './purchase-identity';
import { readPurchase, readEffective, EffectiveV2 } from './schema-v2';
import { AccountLifecycleStore } from '../accounts/account-lifecycle-store';
import { readAccount } from '../accounts/account-lifecycle';
import { CommitObservation, LifecycleStore } from './lifecycle-store';
import { LifecycleError } from './lifecycle-error';
export { tokenHash, playGrantId } from './purchase-identity';
export type VerificationResult = { readonly status: 'purchasePending' } | { readonly status: 'granted'; readonly entitlement: EffectiveV2; readonly fence: { readonly revision: number; readonly generation: number } };
function inputToken(request: unknown): string {
  if (!request || typeof request !== 'object' || Array.isArray(request) || Object.keys(request).some(k => !['purchaseToken','intent'].includes(k)) || ('intent' in request && (request as {intent:unknown}).intent !== 'restore') || !('purchaseToken' in request)) throw new VerificationError('invalidInput');
  const token = (request as { purchaseToken: unknown }).purchaseToken;
  if (typeof token !== 'string' || token.trim() !== token || !token || token.length > 4096) throw new VerificationError('invalidToken');
  return token;
}
/** Auth comes from the trusted callable or a backend worker. Only explicit
 * Restore of a verified deleted-account purchase may provision a new account
 * marker/binding. Existing DELETING/DELETED markers are never reactivated. */
export class PurchaseVerifier {
  constructor(private readonly db: Firestore, private readonly play: PlayPurchaseApi, private readonly binding: AccountBinding,
    private readonly clock: () => Timestamp = Timestamp.now, private readonly store: LifecycleStore = new LifecycleStore(db, clock)) {}
  async verify(context: AuthContext | null | undefined, request: unknown, ackRecovery?: CommitObservation['ackRecovery']): Promise<VerificationResult> {
    const uid = authenticatedUid(context), token = inputToken(request), hash = tokenHash(token);
    try {
      const doc = await this.db.doc(`billingPurchases/${hash}`).get();
      const ledger = doc.exists ? readPurchase(doc.data()) : null;
      const recovery = ledger?.bindingState === 'ACCOUNT_DELETED' && (request as {intent?:string}).intent === 'restore';
      if (ledger && !recovery && (ledger.bindingState !== 'BOUND' || ledger.boundUid !== uid)) throw new VerificationError('tokenAlreadyBound');
      if (ledger && (ledger.revokedAt !== null || ledger.purchaseState === 'CANCELED')) throw new VerificationError('purchaseNotOwned');
      const readActive = async () => {
        const marker = await this.db.doc(`accountLifecycle/${uid}`).get();
        if (!marker.exists) throw new LifecycleError('invalidTransition');
        const account = readAccount(marker.data());
        if (account.state !== 'ACTIVE') throw new LifecycleError(account.state === 'DELETING' ? 'accountDeleting' : 'accountDeleted');
        return account;
      };
      const before = recovery ? null : await readActive();
      let response: unknown;
      try { response = await this.play.lookup({ packageName: PACKAGE_NAME, productId: PRODUCT_ID, purchaseToken: token }); }
      catch (e) { throw new VerificationError(e instanceof PlayLookupError && e.code === 'configuration' ? 'playConfigurationError' : 'playUnavailable'); }
      if (response === null) throw new VerificationError('purchaseNotOwned');
      const play = parsePlayPurchase(response);
      if (play.packageName !== PACKAGE_NAME) throw new VerificationError('wrongPackage');
      if (play.productId !== PRODUCT_ID) throw new VerificationError('wrongProduct');
      if (play.purchaseToken !== token) throw new VerificationError('invalidToken');
      if (!recovery && !ledger?.recoveredFromDeletion && !this.binding.matches({ uid }, play.obfuscatedExternalAccountId)) throw new VerificationError('accountBindingMismatch');
      if (play.purchaseState === 'CANCELED') throw new VerificationError('purchaseNotOwned');
      if (recovery && play.purchaseState !== 'PURCHASED') throw new VerificationError('purchaseNotOwned');
      let localBinding: string | undefined;
      if (recovery) {
        const accounts = new AccountLifecycleStore(this.db,this.binding,this.clock);
        const active = await accounts.initializeActive({uid});
        localBinding = await accounts.register({uid},active.generation);
      }
      const account = before ?? await readActive();
      const observation = { purchase: play,
        expectedLifecycleRevision: ledger?.lifecycleRevision ?? 0, expectedAccountGeneration: account.generation, ...(ackRecovery ? {ackRecovery} : {}),
        ...(ledger?.bindingState === 'BOUND' && ledger.recoveredFromDeletion ? {recoveredBinding:ledger.accountBinding} : {}) };
      const result = recovery ? await this.store.recoverDeleted({uid},observation,localBinding!) : await this.store.commit({uid},observation);
      if (result.outcome !== 'committed') throw new LifecycleError(result.reason === 'staleAccountGeneration' ? 'staleAccountGeneration' :
        result.outcome === 'stale' ? 'staleLifecycleRevision' : 'verificationRejected');
      if (!result.granted) return { status: 'purchasePending' };
      return { status: 'granted', fence: {revision:result.lifecycleRevision,generation:account.generation}, entitlement: readEffective((await this.db.doc(`users/${uid}/entitlements/pro`).get()).data()) };
    } catch (e) {
      if (e instanceof VerificationError || e instanceof LifecycleError) throw e;
      throw new VerificationError('internalConflict');
    }
  }
}
