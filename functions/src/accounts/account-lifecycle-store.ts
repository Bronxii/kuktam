import { Firestore, Timestamp, FieldValue } from 'firebase-admin/firestore';
import { AccountBinding, AuthContext, authenticatedUid } from '../billing/account-binding';
import { LifecycleError } from '../billing/lifecycle-error';
import { LifecycleStore } from '../billing/lifecycle-store';
import { AccountLifecycle, readAccount } from './account-lifecycle';
import { readBinding, bindingVersion } from './binding-registry';

/** Internal service. Context must come from verified Auth transport; never request JSON.
 * No automatic account activation during purchase commit and no deletion cleanup. */
export class AccountLifecycleStore {
  constructor(private readonly db: Firestore, private readonly binding: AccountBinding, private readonly clock: () => Timestamp = Timestamp.now) {}
  async initializeActive(context: AuthContext): Promise<AccountLifecycle> {
    const uid = authenticatedUid(context), ref = this.db.doc(`accountLifecycle/${uid}`);
    return this.db.runTransaction(async tx => {
      const doc = await tx.get(ref);
      if (doc.exists) {
        const current = readAccount(doc.data());
        if (current.state !== 'ACTIVE') throw new LifecycleError('accountInactive');
        return current;
      }
      const account = readAccount({ schemaVersion: 1, state: 'ACTIVE', generation: 1, updatedAt: this.clock(), deletionStartedAt: null, deletedAt: null });
      tx.create(ref, account); return account;
    });
  }
  async advance(context: AuthContext, expectedGeneration: number, target: AccountLifecycle['state']): Promise<AccountLifecycle> {
    return new LifecycleStore(this.db, this.clock).advanceAccountMarker(context, expectedGeneration, target);
  }
  async register(context: AuthContext, expectedGeneration: number): Promise<string> {
    const uid = authenticatedUid(context), opaque = this.binding.forAuthenticatedAccount(context);
    const keyVersion = bindingVersion(opaque), ref = this.db.doc(`billingAccountBindings/${opaque}`);
    return this.db.runTransaction(async tx => {
      const marker = await tx.get(this.db.doc(`accountLifecycle/${uid}`)), doc = await tx.get(ref);
      if (!marker.exists) throw new LifecycleError('accountInactive');
      const account = readAccount(marker.data());
      if (account.state !== 'ACTIVE') throw new LifecycleError('accountInactive');
      if (account.generation !== expectedGeneration) throw new LifecycleError('internalConflict');
      if (doc.exists) {
        const prior = readBinding(doc.data());
        if (prior.state !== 'ACTIVE' || prior.uid !== uid || prior.keyVersion !== keyVersion) throw new LifecycleError('bindingConflict');
      } else {
        const now = this.clock();
        tx.create(ref, readBinding({ schemaVersion: 1, state: 'ACTIVE', uid, keyVersion, createdAt: now, updatedAt: now }));
      }
      return opaque;
    });
  }
  async lookup(opaque: string) { bindingVersion(opaque); const doc = await this.db.doc(`billingAccountBindings/${opaque}`).get(); return doc.exists ? readBinding(doc.data()) : null; }
  /** Tombstones one known binding only. Not an account deletion/cleanup flow. */
  async tombstone(context: AuthContext, opaque: string, expectedGeneration: number): Promise<void> {
    const uid = authenticatedUid(context); bindingVersion(opaque);
    const ref = this.db.doc(`billingAccountBindings/${opaque}`);
    await this.db.runTransaction(async tx => {
      const marker = await tx.get(this.db.doc(`accountLifecycle/${uid}`)), doc = await tx.get(ref);
      if (!marker.exists || !doc.exists) throw new LifecycleError('internalConflict');
      const account = readAccount(marker.data()), prior = readBinding(doc.data());
      if (account.state === 'ACTIVE' || account.generation !== expectedGeneration) throw new LifecycleError('invalidTransition');
      if (prior.state === 'TOMBSTONED') return;
      if (prior.uid !== uid) throw new LifecycleError('bindingConflict');
      tx.update(ref, { state: 'TOMBSTONED', uid: FieldValue.delete(), updatedAt: this.clock() });
    });
  }
}
