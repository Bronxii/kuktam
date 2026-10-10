import { Firestore, Timestamp } from 'firebase-admin/firestore';
import { AccountBinding } from '../account-binding';
import { bindingVersion, readBinding } from '../../accounts/binding-registry';
import { readPurchase } from '../schema-v2';
import { LifecycleStore } from '../lifecycle-store';
import { LifecycleError } from '../lifecycle-error';
import { PurchaseVerifier } from '../verify-purchase';
import { PurchaseRevoker } from '../revoke-purchase';
import { VerificationError } from '../errors';
import { PACKAGE_NAME, PRODUCT_ID, PlayPurchaseApi, PlayLookupError, parsePlayPurchase } from '../play-purchase-api';
import { VoidedPurchaseApi } from '../voided-purchase-api';
import { tokenHash } from '../purchase-identity';
import { parseEnvelope, RtdnOutcome } from './notification';
import { InboxClaim, InboxStatus, RtdnInboxStore } from './inbox-store';

export interface RtdnResult { readonly outcome: RtdnOutcome; readonly key?: string; }
/** Trusted local entrypoint. Authentication/topic allowlisting belongs to a future
 * transport. Only safe outcome + hashed event ID escape; claims and tokens do not. */
export class RtdnProcessor {
  constructor(private readonly db: Firestore, private readonly source: string,
    private readonly play: PlayPurchaseApi, private readonly voided: VoidedPurchaseApi,
    private readonly binding: AccountBinding, private readonly clock: () => Timestamp = Timestamp.now,
    private readonly inbox: RtdnInboxStore = new RtdnInboxStore(db, clock)) {}
  async handle(envelope: unknown): Promise<RtdnResult> {
    const parsed = parseEnvelope(envelope, this.source);
    if (typeof parsed === 'string') return { outcome: parsed };
    try {
      const received = await this.inbox.receive(parsed);
      if (received === 'messageConflict') return { key: parsed.key, outcome: 'messageConflict' };
      if (received === 'received' && (parsed.notification.rejection || parsed.notification.category === 'test')) {
        return { key: parsed.key, outcome: parsed.notification.rejection ?? 'ignoredTestNotification' };
      }
      return await this.process(parsed.key);
    } catch { return { key: parsed.key, outcome: 'internalConflict' }; }
  }
  /** Explicit replay hook for tests/future operators; no scheduler or loop. */
  async process(key: string): Promise<RtdnResult> {
    if (!/^[a-f0-9]{64}$/.test(key)) return { outcome: 'malformedNotification' };
    try {
      const claim = await this.inbox.claim(key);
      if (typeof claim === 'string') return { key, outcome: claim };
      let result: { status: Exclude<InboxStatus,'RECEIVED' | 'PROCESSING'>; outcome: RtdnOutcome };
      try { result = await this.apply(claim); }
      catch (e) {
        const configuration = e instanceof PlayLookupError && e.code === 'configuration' || e instanceof VerificationError && e.code === 'playConfigurationError';
        const stale = e instanceof LifecycleError && ['staleAccountGeneration','staleLifecycleRevision'].includes(e.code);
        const accountClosed = e instanceof LifecycleError && ['accountDeleting','accountDeleted'].includes(e.code);
        result = configuration ? { status: 'UNRESOLVED', outcome: 'permanentConfigurationFailure' } :
          accountClosed ? { status: 'IGNORED', outcome: 'staleNoOp' } :
          stale ? { status: 'RETRY', outcome: 'staleNoOp' } :
          { status: 'RETRY', outcome: 'retryablePlayFailure' };
      }
      const finished = await this.inbox.finish(claim, result.status, result.outcome);
      return { key, outcome: finished ? result.outcome : 'staleNoOp' };
    } catch { return { key, outcome: 'internalConflict' }; }
  }
  private async apply(claim: InboxClaim): Promise<{ status: Exclude<InboxStatus,'RECEIVED' | 'PROCESSING'>; outcome: RtdnOutcome }> {
    const unresolved = { status: 'UNRESOLVED', outcome: 'purchaseUnresolved' } as const;
    const r = claim.record;
    if (!r.tokenHash) return unresolved;
    const doc = await this.db.doc(`billingPurchases/${r.tokenHash}`).get();
    const ledger = doc.exists ? readPurchase(doc.data()) : null;
    if (ledger && ledger.bindingState !== 'BOUND') return { status: 'IGNORED', outcome: 'bindingTombstoned' };
    const token = ledger && 'purchaseToken' in ledger ? ledger.purchaseToken : r.transientToken;
    if (!token || tokenHash(token) !== r.tokenHash) return unresolved;
    let uid = ledger?.bindingState === 'BOUND' ? ledger.boundUid : null;
    if (!uid) {
      // Discovery never grants. Verification below performs its OWN fresh lookup
      // after it captures account/lifecycle fences; no cached observation adapter.
      const raw = await this.play.lookup({ packageName: PACKAGE_NAME, productId: PRODUCT_ID, purchaseToken: token });
      if (!raw) return unresolved;
      const p = parsePlayPurchase(raw);
      if (p.packageName !== PACKAGE_NAME || p.productId !== PRODUCT_ID || p.purchaseToken !== token) return unresolved;
      if (!p.obfuscatedExternalAccountId) return unresolved;
      const version = bindingVersion(p.obfuscatedExternalAccountId);
      const registry = await this.db.doc(`billingAccountBindings/${p.obfuscatedExternalAccountId}`).get();
      if (!registry.exists) return unresolved;
      const owner = readBinding(registry.data());
      if (owner.state !== 'ACTIVE') return { status: 'IGNORED', outcome: 'bindingTombstoned' };
      if (owner.keyVersion !== version || !this.binding.matches({ uid: owner.uid }, p.obfuscatedExternalAccountId)) return unresolved;
      uid = owner.uid;
    }
    // Known negative transitions can complete during deletion. Positive paths
    // must also honor a registry tombstone even if the ledger still has its UID.
    if (ledger?.bindingState === 'BOUND' && r.category === 'oneTime') {
      const doc = await this.db.doc(`billingAccountBindings/${ledger.accountBinding}`).get();
      if (!doc.exists) return unresolved;
      const owner = readBinding(doc.data());
      if (owner.state !== 'ACTIVE') return { status: 'IGNORED', outcome: 'bindingTombstoned' };
      if (owner.uid !== uid) return unresolved;
    }
    const store = new LifecycleStore(this.db, this.clock, tx => this.inbox.assertLease(tx, claim));
    const revoke = async () => {
      const result = await new PurchaseRevoker(this.db, this.voided, store).run(token);
      switch (result.outcome) {
        case 'purchaseRevoked': case 'pendingCanceled': return { status: 'PROCESSED', outcome: 'lifecycleApplied' } as const;
        case 'refundWithoutRevoke': case 'revokeAlreadyApplied': return { status: 'PROCESSED', outcome: 'processed' } as const;
        case 'voidedLookupConfigError': return { status: 'UNRESOLVED', outcome: 'permanentConfigurationFailure' } as const;
        case 'staleObservation': return { status: 'RETRY', outcome: 'staleNoOp' } as const;
        case 'recheckRequired': return unresolved;
        default: return { status: 'RETRY', outcome: 'retryablePlayFailure' } as const;
      }
    };
    if (r.category === 'voided') return revoke();
    if (ledger && (ledger.revokedAt !== null || ledger.purchaseState === 'CANCELED')) return { status: 'PROCESSED', outcome: 'staleNoOp' };
    try {
      const verified = await new PurchaseVerifier(this.db, this.play, this.binding, this.clock, store).verify({ uid }, { purchaseToken: token });
      return { status: 'PROCESSED', outcome: verified.status === 'granted' ? 'lifecycleApplied' : 'processed' };
    } catch (e) {
      // A CANCELED/absent purchase is NOT revoke evidence. Recheck via N4B.4.
      if (e instanceof VerificationError && e.code === 'purchaseNotOwned') return revoke();
      throw e;
    }
  }
}
