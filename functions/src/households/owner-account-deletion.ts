import {FieldValue,Firestore,Timestamp} from 'firebase-admin/firestore';
import {authenticatedUid} from '../billing/account-binding';
import {epochPattern} from '../shopping/mutation-contract';
import {readAccount} from '../accounts/account-lifecycle';
import {familyLifecycleEnabled} from './owner-pro-loss';
import {readFamilyMembership,validatePrivateRoot} from './household-contract';
import {privateHouseholdId} from './household-store';
import {DissolutionPreparationStore,dissolutionId} from './dissolution-preparation';
import {DissolutionLifecycleDriver} from './dissolution-lifecycle-driver';
import {readPreservation} from './dissolution-preservation';
import {readDissolutionFinalizationReceipt} from './dissolution-finalization';
import {readJoinCapacity} from './join-capacity';
import {readInviteSlots} from './invite-contract';

type Phase='WAITING_DISSOLUTION'|'DISSOLUTION_IN_PROGRESS'|'WAITING_HISTORICAL_AUDIT'|'DETACHING_HISTORICAL_AUDIT'|'HISTORICAL_AUDIT_READY'|'OPERATOR';
type Intent={version:1;uid:string;role:'owner';reason:'OWNER_ACCOUNT_DELETION';accountGeneration:number;householdId:string;privateHouseholdId:string;householdCreatedAt:Timestamp;operationId:string;phase:Phase;createdAt:Timestamp;updatedAt:Timestamp;nextAt?:Timestamp;lastOutcome:string;completionEvidence:string|null};
const invalid=():never=>{throw new Error('ownerDeletionIntegrity');};
const proof=<T>(fn:()=>T):T=>{try{return fn();}catch{return invalid();}};
const terminal=(p:Phase)=>['WAITING_HISTORICAL_AUDIT','DETACHING_HISTORICAL_AUDIT','HISTORICAL_AUDIT_READY','OPERATOR'].includes(p);
export function readOwnerDeletionIntent(v:any,uid:string):Intent {
 if(!v||v.version!==1||v.uid!==uid||v.role!=='owner'||v.reason!=='OWNER_ACCOUNT_DELETION'||!Number.isSafeInteger(v.accountGeneration)||v.accountGeneration<1||typeof v.householdId!=='string'||!/^[A-Za-z0-9_-]{1,128}$/.test(v.householdId)||v.privateHouseholdId!==privateHouseholdId(uid)||v.operationId!==dissolutionId(uid,v.householdId)||!(v.householdCreatedAt instanceof Timestamp)||!(v.createdAt instanceof Timestamp)||!(v.updatedAt instanceof Timestamp)||!['WAITING_DISSOLUTION','DISSOLUTION_IN_PROGRESS','WAITING_HISTORICAL_AUDIT','DETACHING_HISTORICAL_AUDIT','HISTORICAL_AUDIT_READY','OPERATOR'].includes(v.phase)||typeof v.lastOutcome!=='string'||!(v.completionEvidence===null||v.completionEvidence===`familyOperations/${v.operationId}/finalization/state`)||['WAITING_HISTORICAL_AUDIT','DETACHING_HISTORICAL_AUDIT','HISTORICAL_AUDIT_READY'].includes(v.phase)&&v.completionEvidence===null||!terminal(v.phase)&&!(v.nextAt instanceof Timestamp))invalid();
 return v;
}
/** Preparation only. This class deliberately has no deletion engine or Auth API. */
export class OwnerAccountDeletionStore {
 constructor(private readonly db:Firestore,private readonly clock=Timestamp.now){}
 private local(){if(!familyLifecycleEnabled())throw new Error('FEATURE_DISABLED');}
 async admit(uid:string){
  this.local();authenticatedUid({uid});
  return this.db.runTransaction(async tx=>{
   const ref=this.db.doc(`familyOwnerDeletions/${uid}`),old=await tx.get(ref);
   if(old.exists)return readOwnerDeletionIntent(old.data(),uid);
   const index=await tx.get(this.db.doc(`familyMemberships/${uid}`));if(!index.exists)return null;
   const m=proof(()=>readFamilyMembership(index.data()));if(m.role!=='owner')return null;
   if(m.state!=='ACTIVE')invalid();
   const marker=await tx.get(this.db.doc(`accountLifecycle/${uid}`)),account=proof(()=>readAccount(marker.data()));
   if(account.state!=='ACTIVE'||(await tx.get(this.db.doc(`accountDeletions/${uid}`))).exists)invalid();
   const home=await tx.get(this.db.doc(`households/${m.householdId}`)),member=await tx.get(home.ref.collection('members').doc(uid)),user=await tx.get(this.db.doc(`users/${uid}`));
   const p=privateHouseholdId(uid),opId=dissolutionId(uid,m.householdId),op=await tx.get(this.db.doc(`familyOperations/${opId}`));
   // Existing dissolution may already own shopping fences; do not require an unfenced fallback here.
   if(home.get('schemaVersion')!==2||home.get('kind')!=='family'||home.get('state')!=='ACTIVE'||home.get('ownerUid')!==uid||!(home.get('createdAt') instanceof Timestamp)||member.get('role')!=='owner'||user.get('activeHouseholdId')!==m.householdId||user.get('familyHouseholdId')!==m.householdId||user.get('privateHouseholdId')!==p||user.get('shoppingMigrationVersion')!==1)invalid();
   if(op.exists&&(op.get('kind')!=='FAMILY_DISSOLUTION'||op.get('ownerUid')!==uid||op.get('householdId')!==m.householdId))invalid();
   const now=this.clock(),i:Intent={version:1,uid,role:'owner',reason:'OWNER_ACCOUNT_DELETION',accountGeneration:account.generation,householdId:m.householdId,privateHouseholdId:p,householdCreatedAt:home.get('createdAt'),operationId:opId,phase:op.exists?'DISSOLUTION_IN_PROGRESS':'WAITING_DISSOLUTION',createdAt:now,updatedAt:now,nextAt:now,lastOutcome:'authenticatedOwnerRequest',completionEvidence:null};
   tx.create(ref,i);return i;
  });
 }
 private async record(uid:string,phase:Phase,outcome:string){
  return this.db.runTransaction(async tx=>{
   const ref=this.db.doc(`familyOwnerDeletions/${uid}`),i=readOwnerDeletionIntent((await tx.get(ref)).data(),uid);
   if(terminal(i.phase))return i.phase;
   const marker=await tx.get(this.db.doc(`accountLifecycle/${uid}`)),account=proof(()=>readAccount(marker.data())),job=await tx.get(this.db.doc(`accountDeletions/${uid}`));
   if(account.state!=='ACTIVE'||account.generation!==i.accountGeneration||job.exists)invalid();
   const op=await tx.get(this.db.doc(`familyOperations/${i.operationId}`));
   if(phase==='WAITING_DISSOLUTION'&&op.exists)phase='DISSOLUTION_IN_PROGRESS';
   if(phase==='DISSOLUTION_IN_PROGRESS'&&!op.exists)invalid();
   tx.update(ref,{phase,updatedAt:this.clock(),lastOutcome:outcome,nextAt:terminal(phase)?FieldValue.delete():Timestamp.fromMillis(this.clock().toMillis()+60000)});return phase;
  });
 }
 /** Reuse the Phase 5 receipt, then atomically bind its terminal private-only state. */
 private async handoff(uid:string){
  return this.db.runTransaction(async tx=>{
   const ref=this.db.doc(`familyOwnerDeletions/${uid}`),i=readOwnerDeletionIntent((await tx.get(ref)).data(),uid);
   if(terminal(i.phase))return i.phase;
   const opRef=this.db.doc(`familyOperations/${i.operationId}`),opDoc=await tx.get(opRef),o=proof(()=>readPreservation(opDoc.data(),i.operationId));
   if(o.phase!=='DONE'||o.status!=='DONE'||o.ownerUid!==uid||o.householdId!==i.householdId||!o.householdCreatedAt.isEqual(i.householdCreatedAt))invalid();
   const receiptRef=opRef.collection('finalization').doc('state'),receipt=await tx.get(receiptRef),r=proof(()=>readDissolutionFinalizationReceipt(receipt.data(),o));
   const marker=await tx.get(this.db.doc(`accountLifecycle/${uid}`)),account=proof(()=>readAccount(marker.data()));
   if(account.state!=='ACTIVE'||account.generation!==i.accountGeneration||(await tx.get(this.db.doc(`accountDeletions/${uid}`))).exists)invalid();
   const source=await tx.get(this.db.doc(`households/${i.householdId}`)),target=await tx.get(this.db.doc(`households/${i.privateHouseholdId}`)),user=await tx.get(this.db.doc(`users/${uid}`));
   proof(()=>validatePrivateRoot(target.data()!,uid));
   const owner=o.participants.find(p=>p.role==='owner')!,privateMember=await tx.get(target.ref.collection('members').doc(uid));
   if(!owner.privateCreatedAt.isEqual(target.get('createdAt'))||privateMember.get('role')!=='owner')invalid();
   if(source.get('state')!=='DISSOLVED'||source.get('kind')!=='family'||source.get('ownerUid')!==uid||source.get('operationId')!==null||!i.householdCreatedAt.isEqual(source.get('createdAt'))||source.get('shoppingEpoch')!==r.sourceEpoch||!epochPattern.test(target.get('shoppingEpoch'))||target.get('shoppingEpoch')===o.targetFence.epoch||user.get('activeHouseholdId')!==i.privateHouseholdId||user.get('privateHouseholdId')!==i.privateHouseholdId||user.get('familyHouseholdId')!==null)invalid();
   const capDoc=await tx.get(this.db.doc(`familyJoinCapacity/${i.householdId}`)),cap=proof(()=>readJoinCapacity(capDoc.data()));
   const slotDoc=await tx.get(this.db.doc(`familyInviteSlots/${i.householdId}`)),slots=proof(()=>readInviteSlots(slotDoc.data()));
   const members=await tx.get(source.ref.collection('members').limit(1)),indexes=await tx.get(this.db.collection('familyMemberships').where('householdId','==',i.householdId).limit(1)),ownerIndex=await tx.get(this.db.doc(`familyMemberships/${uid}`)),items=await tx.get(source.ref.collection('shoppingItems').limit(1));
   const reserved=await tx.get(this.db.collection('familyInvites').where('householdId','==',i.householdId).where('status','==','RESERVED').limit(1));
   const usable=await tx.get(this.db.collection('familyInvites').where('householdId','==',i.householdId).where('status','==','PENDING').where('expiresAt','>',this.clock()).limit(1));
   if(cap.structuralOperationId!==null||cap.operationIds.length||slots.length||!members.empty||!indexes.empty||ownerIndex.exists||!items.empty||!reserved.empty||!usable.empty)invalid();
   tx.update(ref,{phase:'WAITING_HISTORICAL_AUDIT',completionEvidence:receiptRef.path,updatedAt:this.clock(),lastOutcome:'historicalAuditBarrier',nextAt:FieldValue.delete()});return 'WAITING_HISTORICAL_AUDIT' as const;
  });
 }
 async step(uid:string):Promise<Phase>{
  this.local();authenticatedUid({uid});
  const i=readOwnerDeletionIntent((await this.db.doc(`familyOwnerDeletions/${uid}`).get()).data(),uid);if(terminal(i.phase))return i.phase;
  const ref=this.db.doc(`familyOperations/${i.operationId}`),driver=new DissolutionLifecycleDriver(this.db,this.clock);
  try{
   if(!(await ref.get()).exists){
    const conflict=await driver.beforeAdmission(uid,i.householdId);
    if(conflict!=='AVAILABLE')return this.record(uid,conflict==='OPERATOR'?'OPERATOR':'WAITING_DISSOLUTION',conflict);
    try{await new DissolutionPreparationStore(this.db,this.clock).prepareForAccountDeletion(uid,i.householdId);}
    catch(e){if((await ref.get()).exists)return this.record(uid,'DISSOLUTION_IN_PROGRESS','concurrentAdmission');throw e;}
    return this.record(uid,'DISSOLUTION_IN_PROGRESS','admitted');
   }
   const result=await driver.step(uid,i.householdId);
   if(result==='DONE')return await this.handoff(uid);
   return this.record(uid,result==='OPERATOR'?'OPERATOR':'DISSOLUTION_IN_PROGRESS',result);
  }catch(e){
   if(e instanceof Error&&e.message==='IN_PROGRESS')return this.record(uid,'WAITING_DISSOLUTION','structuralConflict');
   if(e instanceof Error&&['ownerDeletionIntegrity','INTEGRITY_REQUIRES_OPERATOR','NOT_OWNER','WRONG_FAMILY','ACCOUNT_UNAVAILABLE'].includes(e.message)){
    // No account, household, lock or shopping repair. Preserve durable intent for operator action.
    return this.db.runTransaction(async tx=>{const r=this.db.doc(`familyOwnerDeletions/${uid}`),current=readOwnerDeletionIntent((await tx.get(r)).data(),uid);if(terminal(current.phase))return current.phase;tx.update(r,{phase:'OPERATOR',updatedAt:this.clock(),nextAt:FieldValue.delete(),lastOutcome:e.message});return 'OPERATOR';});
   }
   throw e;
  }
 }
 /** null means use the unchanged 6B1/private classification path. */
 async begin(uid:string){
  const i=await this.admit(uid);if(!i)return null;
  const phase=await this.step(uid);
  return {outcome:phase==='HISTORICAL_AUDIT_READY'?'historicalAuditReady' as const:phase==='DETACHING_HISTORICAL_AUDIT'?'historicalAuditPending' as const:phase==='WAITING_HISTORICAL_AUDIT'?'waitingHistoricalAudit' as const:phase==='OPERATOR'?'supportRequired' as const:'familyDissolutionPending' as const,operationId:i.operationId,phase};
 }
 async sweep(){
  this.local();const due=await this.db.collection('familyOwnerDeletions').where('nextAt','<=',this.clock()).orderBy('nextAt').limit(20).get();let failed=false;
  for(const d of due.docs){try{await this.step(d.id);}catch{failed=true;}
   await this.db.runTransaction(async tx=>{const current=await tx.get(d.ref);if(current.get('nextAt') instanceof Timestamp)tx.update(d.ref,{nextAt:Timestamp.fromMillis(this.clock().toMillis()+60000)});});
  }
  if(failed)throw new Error('ownerDeletionRetryRequired');return due.size;
 }
}
