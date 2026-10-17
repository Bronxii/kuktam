import { createHash } from 'node:crypto';
import { Firestore, Timestamp, Transaction } from 'firebase-admin/firestore';
import { authenticatedUid, AuthContext } from '../billing/account-binding';
import { readAccount } from '../accounts/account-lifecycle';

export const privateHouseholdId = (uid: string) => 'private_' + createHash('sha256').update(uid).digest('hex');
/** Server-owned identity and migration. No client-supplied UID or household ID. */
export class HouseholdStore {
  constructor(private readonly db: Firestore) {}
  async ensure(context: AuthContext) {
    const uid = authenticatedUid(context);
    // Bound each invocation. A larger legacy list resumes on the next call.
    for (let page = 0; page < 10; page++) {
      const result = await this.page(uid);
      if (result.ready) return result;
    }
    return {schemaVersion: 1, ready: false};
  }
  async page(uid: string, limit = 50) {
    authenticatedUid({uid});
    if (!Number.isInteger(limit) || limit < 1 || limit > 50) throw new Error('invalidLimit');
    return this.db.runTransaction(async tx => {
      const accountRef = this.db.doc(`accountLifecycle/${uid}`);
      const account = await tx.get(accountRef);
      if (account.exists && readAccount(account.data()).state !== 'ACTIVE') throw new Error('accountUnavailable');
      const rootRef = this.db.doc(`users/${uid}`), root = await tx.get(rootRef);
      const id = root.get('activeHouseholdId') ?? privateHouseholdId(uid);
      if (typeof id !== 'string' || !/^[a-zA-Z0-9_-]{1,128}$/.test(id)) throw new Error('invalidHousehold');
      const householdRef = this.db.doc(`households/${id}`), memberRef = householdRef.collection('members').doc(uid);
      const household = await tx.get(householdRef), member = await tx.get(memberRef);
      if (household.exists && (!member.exists || !['owner','member'].includes(member.get('role')))) throw new Error('membershipMissing');
      if (!household.exists && (member.exists || id !== privateHouseholdId(uid))) throw new Error('invalidHousehold');
      const legacy = await tx.get(rootRef.collection('shopping').limit(limit));
      // Version is server-only and prevents legacy clients reopening the old list.
      const complete = legacy.empty;
      const targets = legacy.docs.map(d => householdRef.collection('shoppingItems').doc(d.id));
      const existing = targets.length ? await tx.getAll(...targets) : [];
      if (existing.some(d => d.exists)) throw new Error('migrationCollision');
      const now = Timestamp.now();
      if (!account.exists) tx.create(accountRef, {schemaVersion:1, state:'ACTIVE', generation:1,
        updatedAt:now, deletionStartedAt:null, deletedAt:null});
      if (!household.exists) {
        tx.create(householdRef, {schemaVersion:1, ownerUid:uid, createdAt:now});
        tx.create(memberRef, {role:'owner'});
      }
      if (!root.exists || root.get('activeHouseholdId') !== id || root.get('shoppingMigrationVersion') !== (complete ? 1 : 0)) {
        tx.set(rootRef, {activeHouseholdId:id, shoppingMigrationVersion:complete ? 1 : 0}, {merge:true});
      }
      legacy.docs.forEach((d,i) => { tx.create(targets[i]!, d.data()); tx.delete(d.ref); });
      return {schemaVersion:1, householdId:id, ready:complete};
    });
  }
}

/** Called before any deletion terminal transition; bounded and transactionally
 * fenced by the caller's DELETING lifecycle read. Shared ownership policy must
 * be implemented before joins ship: fail closed rather than delete family data. */
export async function cleanupPrivateHousehold(db: Firestore, tx: Transaction, uid: string, limit: number): Promise<boolean> {
  const owned = await tx.get(db.collection('households').where('ownerUid','==',uid).limit(1));
  if (owned.empty) return false;
  const home = owned.docs[0]!;
  const members = await tx.get(home.ref.collection('members').limit(2));
  if (members.docs.some(d => d.id !== uid)) throw new Error('sharedHouseholdCleanupRequiresPolicy');
  const items = await tx.get(home.ref.collection('shoppingItems').limit(limit));
  for (const item of items.docs) tx.delete(item.ref);
  if (items.empty) {
    for (const member of members.docs) tx.delete(member.ref);
    tx.delete(home.ref);
  }
  return true;
}
