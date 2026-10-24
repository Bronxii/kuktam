import { Firestore, Transaction } from 'firebase-admin/firestore';
export interface JoinCapacity {schemaVersion:1|2|3;operationIds:string[];structuralOperationId?:string|null}
export function readJoinCapacity(raw:unknown):JoinCapacity {
  if(raw===undefined)return {schemaVersion:1,operationIds:[]};
  const v=raw as JoinCapacity;
  if(!v||![1,2,3].includes(v.schemaVersion)||Object.keys(v).sort().join(',')!==(v.schemaVersion===1?'operationIds,schemaVersion':'operationIds,schemaVersion,structuralOperationId')||
    !Array.isArray(v.operationIds)||v.operationIds.length>7||new Set(v.operationIds).size!==v.operationIds.length||v.operationIds.some(id=>!/^join_[a-f0-9]{64}$/.test(id))||
    v.schemaVersion===2&&!(v.structuralOperationId===null||typeof v.structuralOperationId==='string'&&v.operationIds.includes(v.structuralOperationId))||
    v.schemaVersion===3&&!(typeof v.structuralOperationId==='string'&&/^dissolve_[a-f0-9]{64}$/.test(v.structuralOperationId)))throw new Error('invalidJoinCapacity');
  return v;
}
/** v3 separates dissolution ownership from reserved JOIN seats; v1/v2 stay strict. */
export const dissolutionLocked=(cap:JoinCapacity)=>cap.schemaVersion===3;
/** Admission guard must run before lifecycle writes, in their transaction. */
export async function blockingJoin(db:Firestore,tx:Transaction,uid:string) {
  const index=await tx.get(db.doc(`familyMemberships/${uid}`));
  if(!index.exists)return null;
  const hid=index.get('householdId');
  if(typeof hid!=='string'||!/^[A-Za-z0-9_-]{1,128}$/.test(hid))throw new Error('invalidFamilyBinding');
  const cap=readJoinCapacity((await tx.get(db.doc(`familyJoinCapacity/${hid}`))).data());
  if(cap.structuralOperationId)return cap.structuralOperationId;
  if(index.get('state')==='RESERVED') {
    const id=index.get('operationId');
    if(typeof id!=='string'||!/^[A-Za-z0-9_-]{1,128}$/.test(id))throw new Error('invalidFamilyBinding');
    const op=await tx.get(db.doc(`familyOperations/${id}`));
    if(op.get('committedAt')!=null||op.get('status')==='OPERATOR')return id;
  }
  return null;
}
export async function assertNoCommittedJoin(db:Firestore,tx:Transaction,uid:string){
  if(await blockingJoin(db,tx,uid))throw new Error('JOIN_COMMITTED_IN_PROGRESS');
  await assertNoActiveFamilyDeletion(db,tx,uid);
}
/** Temporary admission barrier, not a Family deletion implementation. Unexpected
 * external Auth deletion still records its access barrier and fails cleanup closed. */
export async function assertNoActiveFamilyDeletion(db:Firestore,tx:Transaction,uid:string){
  const index=await tx.get(db.doc(`familyMemberships/${uid}`));
  if(index.get('state')==='ACTIVE')throw new Error('FAMILY_LIFECYCLE_NOT_READY');
}
