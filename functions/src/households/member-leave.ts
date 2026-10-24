import { createHash } from 'node:crypto';
import { Firestore, Timestamp } from 'firebase-admin/firestore';
import { authenticatedUid, AuthContext } from '../billing/account-binding';
import { readAccount } from '../accounts/account-lifecycle';
import { advanceShoppingEpoch } from '../shopping/mutation-store';
import { FamilyInviteStore } from './family-invites';
import { readInvite, inviteIdPattern, FamilyInviteError } from './invite-contract';
import { readFamilyMembership, validatePrivateRoot } from './household-contract';
import { privateHouseholdId } from './household-store';
import { joinOperationId, readJoinOperation } from './family-join';
import { readJoinCapacity } from './join-capacity';

export type LeaveCode='INVALID_ARGUMENT'|'FEATURE_DISABLED'|'NOT_ACTIVE_MEMBER'|'OWNER_CANNOT_LEAVE'|
  'IN_PROGRESS'|'ACCOUNT_UNAVAILABLE'|'STALE_MEMBERSHIP'|'INTEGRITY_REQUIRES_OPERATOR';
export class FamilyLeaveError extends Error {constructor(readonly code:LeaveCode){super(code);}}
const fail=(code:LeaveCode):never=>{throw new FamilyLeaveError(code);};
export const memberLeaveId=(uid:string,inviteId:string)=>'leave_'+createHash('sha256').update(JSON.stringify([uid,inviteId])).digest('hex');
const proof=<T>(read:()=>T):T=>{try{return read();}catch{return fail('INTEGRITY_REQUIRES_OPERATOR');}};

/** One atomic operation, no worker/lease workflow. Immutable DONE evidence is
 * tied to the JOIN incarnation, so an old retry can never leave a new membership.
 * Local rollout barrier matches the current undeployed Family JOIN milestone. */
export class MemberLeaveStore {
  private readonly validation:FamilyInviteStore;
  constructor(private readonly db:Firestore,private readonly clock=Timestamp.now){
    this.validation=new FamilyInviteStore(db,{resolve:async()=>{throw new Error('notRequired');}},clock);
  }
  async leave(context:AuthContext,inviteId:string){
    const uid=authenticatedUid(context);
    if(typeof inviteId!=='string'||!inviteIdPattern.test(inviteId))fail('INVALID_ARGUMENT');
    if(process.env.K_SERVICE||process.env.FUNCTION_NAME||process.env.GCLOUD_PROJECT!=='demo-kuktam-local'||
      !/^(127\.0\.0\.1|localhost):[0-9]{1,5}$/.test(process.env.FIRESTORE_EMULATOR_HOST??''))fail('FEATURE_DISABLED');
    const id=memberLeaveId(uid,inviteId),joinId=joinOperationId(uid),p=privateHouseholdId(uid);
    return this.db.runTransaction(async tx=>{
      const ref=this.db.doc(`familyOperations/${id}`),receipt=await tx.get(ref);
      if(receipt.exists){
        const v=receipt.data()!;
        if(Object.keys(v).sort().join(',')!=='actorUid,createdAt,householdId,inviteId,joinOperationId,kind,leaseId,leaseUntil,nextAt,phase,privateHouseholdId,schemaVersion,status,updatedAt'||
          v.schemaVersion!==1||v.kind!=='MEMBER_LEAVE'||v.actorUid!==uid||v.inviteId!==inviteId||v.joinOperationId!==joinId||v.privateHouseholdId!==p||
          typeof v.householdId!=='string'||! /^[A-Za-z0-9_-]{1,128}$/.test(v.householdId)||v.householdId===p||
          v.phase!=='PRIVATE'||v.status!=='DONE'||v.nextAt!==null||v.leaseId!==null||v.leaseUntil!==null||
          !(v.createdAt instanceof Timestamp)||!(v.updatedAt instanceof Timestamp)||!v.createdAt.isEqual(v.updatedAt))fail('INTEGRITY_REQUIRES_OPERATOR');
        // Historical completion, not a claim about current membership/routing.
        return {schemaVersion:1,operationId:id,outcome:'DONE' as const};
      }
      const account=await tx.get(this.db.doc(`accountLifecycle/${uid}`));
      if(!account.exists||proof(()=>readAccount(account.data())).state!=='ACTIVE')fail('ACCOUNT_UNAVAILABLE');
      if((await tx.get(this.db.doc(`accountDeletions/${uid}`))).exists)fail('ACCOUNT_UNAVAILABLE');
      const index=await tx.get(this.db.doc(`familyMemberships/${uid}`));
      if(!index.exists)fail('NOT_ACTIVE_MEMBER');
      const binding=proof(()=>readFamilyMembership(index.data()));
      if(binding.role==='owner')fail('OWNER_CANNOT_LEAVE');
      if(binding.state!=='ACTIVE')fail('IN_PROGRESS');
      const user=await tx.get(this.db.doc(`users/${uid}`)),hid=binding.householdId;
      if(user.get('activeHouseholdId')!==hid||user.get('familyHouseholdId')!==hid||user.get('privateHouseholdId')!==p||user.get('shoppingMigrationVersion')!==1||hid===p)fail('INTEGRITY_REQUIRES_OPERATOR');
      const cap=await tx.get(this.db.doc(`familyJoinCapacity/${hid}`)),capacity=proof(()=>readJoinCapacity(cap.data()));
      if(capacity.structuralOperationId)fail('IN_PROGRESS');
      if(!cap.exists||capacity.operationIds.includes(joinId))fail('INTEGRITY_REQUIRES_OPERATOR');
      const source=await tx.get(this.db.doc(`households/${p}`)),sm=await tx.get(source.ref.collection('members').doc(uid));
      if(!source.exists||source.get('schemaVersion')!==2||sm.get('role')!=='owner')fail('INTEGRITY_REQUIRES_OPERATOR');
      proof(()=>validatePrivateRoot(source.data()!,uid));
      const home=await tx.get(this.db.doc(`households/${hid}`)),member=await tx.get(home.ref.collection('members').doc(uid));
      if(home.get('ownerUid')===uid)fail('OWNER_CANNOT_LEAVE');
      if(typeof home.get('ownerUid')!=='string'||member.get('role')!=='member')fail('INTEGRITY_REQUIRES_OPERATOR');
      // Reuse structural validators; no Pro check, email lookup or admission gate.
      // Only translate explicit domain validation failures, never network errors.
      let family,members;
      try{
        family=await this.validation.owner(tx,home.get('ownerUid'));
        members=await this.validation.members(tx,family);
      }catch(e){if(e instanceof FamilyInviteError)fail('INTEGRITY_REQUIRES_OPERATOR');throw e;}
      if(family.householdId!==hid||members.length+capacity.operationIds.length>8||!members.some(m=>m.memberId===uid&&m.role==='member'))fail('INTEGRITY_REQUIRES_OPERATOR');
      const joinDoc=await tx.get(this.db.doc(`familyOperations/${joinId}`));
      const join=proof(()=>readJoinOperation(joinDoc.data(),joinId));
      if(join.inviteId!==inviteId)fail('STALE_MEMBERSHIP');
      if(join.phase!=='ACTIVE'||join.status!=='DONE'||join.householdId!==hid||join.sourceHouseholdId!==p||join.ownerUid!==home.get('ownerUid'))fail('INTEGRITY_REQUIRES_OPERATOR');
      const inviteDoc=await tx.get(this.db.doc(`familyInvites/${inviteId}`));
      const invite=proof(()=>readInvite(inviteDoc.data()));
      if(invite.status!=='USED'||invite.operationId!==joinId||invite.usedByUid!==uid||invite.householdId!==hid||invite.createdByUid!==join.ownerUid)fail('INTEGRITY_REQUIRES_OPERATOR');
      const now=this.clock();
      // Reads of the shared capacity guard and membership query serialize against
      // JOIN admission/commit. No externally visible leave lock/lease is necessary
      // for this single commit; no foreign reservation or lock is rewritten.
      tx.delete(member.ref);tx.delete(index.ref);
      tx.update(user.ref,{activeHouseholdId:p,familyHouseholdId:null});
      tx.update(source.ref,advanceShoppingEpoch(now));
      tx.create(ref,{schemaVersion:1,kind:'MEMBER_LEAVE',actorUid:uid,householdId:hid,privateHouseholdId:p,
        joinOperationId:joinId,inviteId,phase:'PRIVATE',status:'DONE',createdAt:now,updatedAt:now,
        nextAt:null,leaseId:null,leaseUntil:null});
      return {schemaVersion:1,operationId:id,outcome:'DONE' as const};
    });
  }
}
