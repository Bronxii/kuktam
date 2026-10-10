import { Firestore } from 'firebase-admin/firestore';
import { readAccount } from '../accounts/account-lifecycle';
import { LifecycleStore } from './lifecycle-store';
import { readPurchase } from './schema-v2';
import { PACKAGE_NAME, PRODUCT_ID } from './play-purchase-api';
import { tokenHash } from './purchase-identity';
import { VoidedPurchaseApi, VoidedLookupError, parseVoidedObservation, RevokeResult } from './voided-purchase-api';

/** Internal backend operation, NOT an unauthenticated client endpoint.
 * Resolves ownership from the ledger before fresh external lookup. No writes here.
 * Unknown/unavailable/configuration observations preserve all durable state.
 * Callers decide when to retry; this operation never loops or schedules work. */
export class PurchaseRevoker {
  constructor(private readonly db: Firestore, private readonly api: VoidedPurchaseApi,
    private readonly store: LifecycleStore = new LifecycleStore(db)) {}
  async run(purchaseToken: string): Promise<RevokeResult> {
    if (typeof purchaseToken !== 'string' || !purchaseToken.trim()) return { outcome: 'lifecycleConflict' };
    try {
      const doc = await this.db.doc(`billingPurchases/${tokenHash(purchaseToken)}`).get();
      if (!doc.exists) return { outcome: 'recheckRequired', reason: 'ownerNotResolved' };
      const ledger = readPurchase(doc.data());
      if (ledger.bindingState !== 'BOUND' || ledger.purchaseToken !== purchaseToken ||
        ledger.packageName !== PACKAGE_NAME || ledger.productId !== PRODUCT_ID) return { outcome: 'lifecycleConflict' };
      const marker = await this.db.doc(`accountLifecycle/${ledger.boundUid}`).get();
      if (!marker.exists) return { outcome: 'lifecycleConflict' };
      const account = readAccount(marker.data());
      let response: unknown;
      try { response = await this.api.lookup({ packageName: PACKAGE_NAME, productId: PRODUCT_ID, purchaseToken }); }
      catch (e) { return { outcome: e instanceof VoidedLookupError && e.code === 'configuration' ? 'voidedLookupConfigError' : 'voidedLookupUnavailable' }; }
      if (response === null) return { outcome: 'recheckRequired', reason: 'notFound' };
      let observation;
      try { observation = parseVoidedObservation(response); }
      catch { return { outcome: 'recheckRequired', reason: 'malformedObservation' }; }
      if (observation.packageName !== PACKAGE_NAME || observation.productId !== PRODUCT_ID ||
        observation.purchaseToken !== purchaseToken || observation.testPurchase !== ledger.testPurchase) return { outcome: 'lifecycleConflict', reason: 'identityMismatch' };
      if (!observation.authoritative || observation.state === 'unknown') return { outcome: 'recheckRequired', reason: 'notAuthoritative' };
      if (observation.state === 'financialRefund') return { outcome: 'refundWithoutRevoke' };
      return await this.store.commitVoided(ledger.boundUid, { purchase: observation,
        expectedLifecycleRevision: ledger.lifecycleRevision, expectedAccountGeneration: account.generation });
    } catch { return { outcome: 'lifecycleConflict' }; }
  }
}
