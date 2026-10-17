import { Timestamp } from 'firebase-admin/firestore';

const id = (v: unknown): v is string => typeof v === 'string' && /^[a-zA-Z0-9_-]{1,128}$/.test(v);
export interface FamilyMembership {
  householdId: string;
  role: 'owner' | 'member';
  state: 'RESERVED' | 'ACTIVE';
  operationId: string | null;
}
/** Read-only contract. No Phase 1 writer can reserve or activate a family. */
export function readFamilyMembership(raw: unknown): FamilyMembership {
  const v = raw as FamilyMembership;
  if (!v || Object.keys(v).sort().join(',') !== 'householdId,operationId,role,state' ||
      !id(v.householdId) || !['owner','member'].includes(v.role) ||
      !['RESERVED','ACTIVE'].includes(v.state) ||
      (v.state === 'RESERVED' ? !id(v.operationId) : v.operationId !== null)) {
    throw new Error('invalidFamilyMembership');
  }
  return v;
}

/** Existing v1 roots are private only after ownership and deterministic ID
 * have been checked by the caller. Never reinterpret an explicit family. */
export function validatePrivateRoot(v: FirebaseFirestore.DocumentData, uid: string): void {
  if (v.ownerUid !== uid || !(v.createdAt instanceof Timestamp) ||
      !(v.schemaVersion === 1 && v.kind === undefined && v.state === undefined && v.operationId === undefined ||
        v.schemaVersion === 2 && v.kind === 'private' && v.state === 'ACTIVE' && v.operationId === null)) {
    throw new Error('invalidPrivateHousehold');
  }
}
