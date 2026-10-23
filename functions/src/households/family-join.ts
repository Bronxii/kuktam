import { readTransfer } from './join-transfer-contract';
import { readJoinCapacity } from './join-capacity';
import { createHash } from 'node:crypto';
import { Firestore, Timestamp, Transaction } from 'firebase-admin/firestore';
import { AuthContext, authenticatedUid } from '../billing/account-binding';
import { FamilyInviteStore } from './family-invites';
import { FamilyInviteError, hashInviteToken, readInvite, readInviteSlots } from './invite-contract';
import { createOperationId, hasPro } from './family-create';
import { privateHouseholdId } from './household-store';
import { claimFamilyLease } from './operation-lease';

export type JoinMode='ADD'|'DELETE';
export const joinOperationId=(uid:string)=>'join_'+createHash('sha256').update(authenticatedUid({uid})).digest('hex');
export interface JoinOperation {
  schemaVersion:1|2; kind:'JOIN'; actorUid:string; ownerUid:string; inviteId:string;
  householdId:string; sourceHouseholdId:string; mode:JoinMode;
  phase:'RESERVED'|'READY_FOR_TRANSFER'|'SNAPSHOT_SOURCE'|'SOURCE_FENCED_WAITING_CONFIRMATION'|'COMMITTED_TRANSFER'|'CLEAN_SOURCE'|'TRANSFER_COMPLETE'|'ACTIVE'; status:'READY'|'ABORTED'|'OPERATOR'|'DONE';
  sourceItemCount:number; deleteReconfirmationRequired:boolean;
  createdAt:Timestamp; updatedAt:Timestamp; nextAt:Timestamp|null;
  leaseId:string|null; leaseUntil:Timestamp|null; lastOutcome:string|null;
}
const fields='actorUid,createdAt,deleteReconfirmationRequired,householdId,inviteId,kind,lastOutcome,leaseId,leaseUntil,mode,nextAt,ownerUid,phase,schemaVersion,sourceHouseholdId,sourceItemCount,status,updatedAt';
const uidValue=(v:unknown):v is string=>typeof v==='string'&&v.length>0&&v.length<=128&&!v.includes('/')&&v.trim()===v;
const identifier=(v:unknown):v is string=>typeof v==='string'&&/^[a-zA-Z0-9_-]{1,128}$/.test(v);
export function readJoinOperation(raw:unknown,id:string):JoinOperation {
  if((raw as JoinOperation)?.schemaVersion===2)return readTransfer(raw,id);
  const v=raw as JoinOperation;
  if(!v||Object.keys(v).sort().join(',')!==fields||v.schemaVersion!==1||v.kind!=='JOIN'||
    !uidValue(v.actorUid)||!uidValue(v.ownerUid)||v.actorUid===v.ownerUid||id!==joinOperationId(v.actorUid)||
    !identifier(v.householdId)||v.sourceHouseholdId!==privateHouseholdId(v.actorUid)||v.householdId===v.sourceHouseholdId||
    !/^[a-f0-9]{64}$/.test(v.inviteId)||!['ADD','DELETE'].includes(v.mode)||
    v.deleteReconfirmationRequired!==(v.mode==='DELETE')||!Number.isSafeInteger(v.sourceItemCount)||v.sourceItemCount<0||
    !['RESERVED','READY_FOR_TRANSFER'].includes(v.phase)||!['READY','ABORTED'].includes(v.status)||
    !(v.createdAt instanceof Timestamp)||!(v.updatedAt instanceof Timestamp)||
    !(v.status==='READY'?v.nextAt instanceof Timestamp:v.nextAt===null)||
    !(v.leaseId===null&&v.leaseUntil===null||identifier(v.leaseId)&&v.leaseUntil instanceof Timestamp)||
    !(v.lastOutcome===null||typeof v.lastOutcome==='string'))throw new Error('invalidJoinOperation');
  return v;
}
/** Phase 4A cannot complete a JOIN. Even an enabled production config cannot reserve. */
export function localJoinRuntime(project:string|undefined,host:string|undefined):boolean {
  return !!project?.startsWith('demo-')&&!!host&&/^(127\.0\.0\.1|localhost):[0-9]{1,5}$/.test(host);
}
const fail=(code:ConstructorParameters<typeof FamilyInviteError>[0]):never=>{throw new FamilyInviteError(code);};
export class FamilyJoinStore {
  private readonly validation:FamilyInviteStore;
  constructor(private readonly db:Firestore,private readonly clock=Timestamp.now,readonly leaseMs=120000) {
    if(!Number.isSafeInteger(leaseMs)||leaseMs<1000)throw new Error('invalidLease');
    // Reuse authoritative lifecycle/context/member validators; JOIN never resolves email.
    this.validation=new FamilyInviteStore(db,{resolve:async()=>{throw new Error('emailNotRequired');}},clock);
  }
  private async standalone(tx:Transaction,uid:string) {
    await this.validation.active(tx,uid);
    const p=privateHouseholdId(uid),user=await tx.get(this.db.doc(`users/${uid}`));
    if(user.get('privateHouseholdId')!==p||user.get('activeHouseholdId')!==p||
      user.get('familyHouseholdId')!==null||user.get('shoppingMigrationVersion')!==1)fail('ACCOUNT_NOT_READY');
    await this.validation.privateHome(tx,uid,p);
    return p;
  }
  private async family(tx:Transaction,owner:string,hid:string) {
    const family=await this.validation.owner(tx,owner);
    if(family.householdId!==hid)fail('FAMILY_UNAVAILABLE');
    if(!await hasPro(this.db,tx,owner,this.clock()))fail('OWNER_NOT_PRO');
    return this.validation.members(tx,family);
  }
  async reserve(context:AuthContext,token:string,mode:JoinMode):Promise<string> {
    const uid=authenticatedUid(context),inviteId=hashInviteToken(token),id=joinOperationId(uid);
    if(mode!=='ADD'&&mode!=='DELETE')fail('INVALID_ARGUMENT');
    if(process.env.K_SERVICE||process.env.FUNCTION_NAME||!localJoinRuntime(process.env.GCLOUD_PROJECT,process.env.FIRESTORE_EMULATOR_HOST))fail('FEATURE_DISABLED');
    return this.db.runTransaction(async tx=>{
      const gate=await tx.get(this.db.doc('familyRuntime/config'));
      if(gate.get('joinReservationEnabled')!==true)fail('FEATURE_DISABLED');
      const opRef=this.db.doc(`familyOperations/${id}`),old=await tx.get(opRef);
      const indexRef=this.db.doc(`familyMemberships/${uid}`),index=await tx.get(indexRef);
      const inviteRef=this.db.doc(`familyInvites/${inviteId}`),doc=await tx.get(inviteRef);
      if(!doc.exists)fail('NOT_FOUND');
      const invite=readInvite(doc.data());
      if(old.exists) {
        const op=readJoinOperation(old.data(),id);
        if(op.status!=='ABORTED') {
          if(op.inviteId!==inviteId||op.mode!==mode)fail('IN_PROGRESS');
          if(invite.status!=='RESERVED'||invite.operationId!==id||index.get('operationId')!==id||
            index.get('state')!=='RESERVED'||index.get('householdId')!==op.householdId||index.get('role')!=='member')fail('INVITE_STATE_UNAVAILABLE');
          return id;
        }
      }
      if(invite.status!=='PENDING')fail(invite.status==='RESERVED'?'IN_PROGRESS':invite.status);
      const now=this.clock();if(invite.expiresAt.toMillis()<=now.toMillis())fail('EXPIRED');
      if(invite.createdByUid===uid)fail('SELF_INVITE');
      if(index.exists)fail('ALREADY_IN_FAMILY');
      const create=await tx.get(this.db.doc(`familyOperations/${createOperationId(uid)}`));
      if(create.exists&&create.get('status')!=='ABORTED')fail('IN_PROGRESS');
      const p=await this.standalone(tx,uid),members=await this.family(tx,invite.createdByUid,invite.householdId);
      if(members.some(m=>m.memberId===uid))fail('ALREADY_MEMBER');
      const capRef=this.db.doc(`familyJoinCapacity/${invite.householdId}`),cap=await tx.get(capRef),capState=readJoinCapacity(cap.data()),ids=capState.operationIds;
      if(ids.includes(id))fail('INVITE_STATE_UNAVAILABLE');
      if(members.length+ids.length>=8)fail('FAMILY_FULL');
      const count=await tx.get(this.db.collection(`households/${p}/shoppingItems`).count());
      const op:JoinOperation={schemaVersion:1,kind:'JOIN',actorUid:uid,ownerUid:invite.createdByUid,inviteId,
        householdId:invite.householdId,sourceHouseholdId:p,mode,phase:'RESERVED',status:'READY',
        sourceItemCount:count.data().count,deleteReconfirmationRequired:mode==='DELETE',createdAt:now,updatedAt:now,
        nextAt:now,leaseId:null,leaseUntil:null,lastOutcome:null};
      tx.set(opRef,op);tx.update(inviteRef,{status:'RESERVED',operationId:id});
      tx.create(indexRef,{householdId:invite.householdId,role:'member',state:'RESERVED',operationId:id});
      tx.set(capRef,{...capState,operationIds:[...ids,id]});
      return id;
    });
  }
  claim(id:string) {return claimFamilyLease(this.db,id,raw=>readJoinOperation(raw,id),this.clock,this.leaseMs);}
  async step(id:string,leaseId:string):Promise<string> {
    return this.db.runTransaction(async tx=>{
      const ref=this.db.doc(`familyOperations/${id}`),doc=await tx.get(ref);
      if(doc.get('schemaVersion')===2){const {JoinTransferStore}=await import('./join-transfer');return new JoinTransferStore(this.db,this.clock).stepTransaction(tx,id,leaseId);}
      if(!doc.exists)throw new Error('missingOperation');
      const op=readJoinOperation(doc.data(),id),now=this.clock();
      if(op.status!=='READY')return op.status;
      if(op.leaseId!==leaseId||!op.leaseUntil||op.leaseUntil.toMillis()<=now.toMillis())return 'BUSY';
      const indexRef=this.db.doc(`familyMemberships/${op.actorUid}`),index=await tx.get(indexRef);
      const invRef=this.db.doc(`familyInvites/${op.inviteId}`),invDoc=await tx.get(invRef);
      const capRef=this.db.doc(`familyJoinCapacity/${op.householdId}`),cap=await tx.get(capRef),capState=readJoinCapacity(cap.data()),ids=capState.operationIds;
      const slotsRef=this.db.doc(`familyInviteSlots/${op.householdId}`),slots=await tx.get(slotsRef);
      const slotIds=slots.exists?readInviteSlots(slots.data()):[];
      const member=await tx.get(this.db.doc(`households/${op.householdId}/members/${op.actorUid}`));
      // Never undo an activated/foreign relationship. Phase 4B must change parser/dispatch.
      if(member.exists||index.exists&&(index.get('state')!=='RESERVED'||index.get('operationId')!==id||
        index.get('householdId')!==op.householdId||index.get('role')!=='member'))throw new Error('unsafeJoinOwnership');
      let reason:string|null=null;
      try {
        if(!invDoc.exists)fail('NOT_FOUND');
        const invite=readInvite(invDoc.data());
        if(invite.status!=='RESERVED'||invite.operationId!==id||invite.householdId!==op.householdId||invite.createdByUid!==op.ownerUid)
          fail('INVITE_STATE_UNAVAILABLE');
        if(invite.expiresAt.toMillis()<=now.toMillis())fail('EXPIRED');
        if(!index.exists||!ids.includes(id)||!slotIds.includes(op.inviteId))fail('INVITE_STATE_UNAVAILABLE');
        await this.standalone(tx,op.actorUid);
        const members=await this.family(tx,op.ownerUid,op.householdId);
        if(members.length+ids.length>8)fail('FAMILY_FULL');
      }catch(error){
        // Transport/Firestore errors are retried, never converted to destructive aborts.
        if(!(error instanceof FamilyInviteError))throw error;
        reason=error.code;
      }
      if(reason) {
        // No transfer has begun: release only this operation's claims. Conservatively
        // revoke its invite (never recycle an explicit claim after eligibility failure).
        if(index.exists)tx.delete(indexRef);
        tx.set(capRef,{...capState,operationIds:ids.filter(v=>v!==id)});
        const ownedInvite=invDoc.get('status')==='RESERVED'&&invDoc.get('operationId')===id;
        if(ownedInvite)
          tx.update(invRef,{status:'REVOKED',operationId:null});
        if(!invDoc.exists||ownedInvite)
          tx.set(slotsRef,{schemaVersion:1,inviteIds:slotIds.filter(v=>v!==op.inviteId)});
        tx.update(ref,{status:'ABORTED',lastOutcome:reason,nextAt:null,leaseId:null,leaseUntil:null,updatedAt:now});
        return 'ABORTED';
      }
      // Hard Phase 4A boundary. No transfer, fence, member activation or pointer write.
      tx.update(ref,{phase:'READY_FOR_TRANSFER',lastOutcome:'awaitingPhase4B',updatedAt:now});
      return 'READY_FOR_TRANSFER';
    });
  }
  async resume(id:string):Promise<string> {
    const lease=await this.claim(id);if(!lease)return 'notDueOrBusy';
    let failed=false;
    try{return await this.step(id,lease);}catch{failed=true;return 'retry';}
    finally {
      await this.db.runTransaction(async tx=>{
        const ref=this.db.doc(`familyOperations/${id}`),doc=await tx.get(ref);
        if(!doc.exists)return;
        const op=readJoinOperation(doc.data(),id),now=this.clock();
        if(op.status==='READY'&&op.leaseId===lease)tx.update(ref,{leaseId:null,leaseUntil:null,updatedAt:now,
          nextAt:Timestamp.fromMillis(now.toMillis()+(failed?30000:300000)),...(failed?{lastOutcome:'retry'}:{})});
      });
    }
  }
}
