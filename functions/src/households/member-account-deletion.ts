import {FieldValue,Firestore,Timestamp,Transaction} from 'firebase-admin/firestore';
import {authenticatedUid} from '../billing/account-binding';
import {LifecycleStore} from '../billing/lifecycle-store';
import {readAccount} from '../accounts/account-lifecycle';
import {readDeletion} from '../accounts/deletion-contract';
import {familyLifecycleEnabled} from './owner-pro-loss';
import {readFamilyMembership,validatePrivateRoot} from './household-contract';
import {privateHouseholdId} from './household-store';
import {readJoinOperation,currentJoinId,isJoinIdentity} from './family-join';
import {readJoinCapacity} from './join-capacity';
import {MemberLeaveStore,memberLeaveId,ownerRemoveId,readMemberExitCompletion,FamilyLeaveError} from './member-leave';
import {dissolutionId} from './dissolution-preparation';
import {readPreservation} from './dissolution-preservation';
import {readParticipantReleaseProgress,participantReleaseId} from './dissolution-member-release';

type Phase='WAITING_EXIT'|'EXIT_COMPLETE'|'HANDED_OFF'|'OPERATOR';
type Intent={version:1;uid:string;accountGeneration:number;householdId:string;ownerUid:string;privateHouseholdId:string;joinOperationId:string;inviteId:string;membershipUpdateTime:Timestamp;reason:'ACCOUNT_DELETION_MEMBER_EXIT';phase:Phase;exitEvidence:string|null;deletionOperationId:string|null;createdAt:Timestamp;updatedAt:Timestamp;nextAt?:Timestamp;lastOutcome:string};
const invalid=():never=>{throw new Error('memberDeletionIntegrity');};
const proof=<T>(fn:()=>T):T=>{try{return fn();}catch{return invalid();}};
function read(v:any,uid:string):Intent {
 if(!v||v.version!==1||v.uid!==uid||v.reason!=='ACCOUNT_DELETION_MEMBER_EXIT'||!Number.isSafeInteger(v.accountGeneration)||v.accountGeneration<1||v.privateHouseholdId!==privateHouseholdId(uid)||!isJoinIdentity(v.joinOperationId,uid,v.inviteId)||typeof v.ownerUid!=='string'||v.ownerUid===uid||typeof v.householdId!=='string'||!/^[A-Za-z0-9_-]{1,128}$/.test(v.householdId)||!/^[a-f0-9]{64}$/.test(v.inviteId)||!(v.membershipUpdateTime instanceof Timestamp)||!(v.createdAt instanceof Timestamp)||!(v.updatedAt instanceof Timestamp)||!['WAITING_EXIT','EXIT_COMPLETE','HANDED_OFF','OPERATOR'].includes(v.phase)||!(v.exitEvidence===null||typeof v.exitEvidence==='string')||!(v.deletionOperationId===null||typeof v.deletionOperationId==='string')||['EXIT_COMPLETE','HANDED_OFF'].includes(v.phase)&&typeof v.exitEvidence!=='string'||v.phase==='HANDED_OFF'&&typeof v.deletionOperationId!=='string'||['WAITING_EXIT','EXIT_COMPLETE'].includes(v.phase)&&!(v.nextAt instanceof Timestamp))invalid();
 return v;
}
/** Recent authentication is enforced by the existing DeletionGateway before begin. */
export class MemberAccountDeletionStore {
 constructor(private readonly db:Firestore,private readonly clock=Timestamp.now,private readonly deletion=new LifecycleStore(db,clock)){}
 private local(){if(!familyLifecycleEnabled())throw new Error('FEATURE_DISABLED');}
 async admit(uid:string){
  this.local();authenticatedUid({uid});
  return this.db.runTransaction(async tx=>{
   const ref=this.db.doc(`familyMemberDeletions/${uid}`),old=await tx.get(ref);
   if(old.exists)return read(old.data(),uid);
   const index=await tx.get(this.db.doc(`familyMemberships/${uid}`));if(!index.exists)return null;
   const m=proof(()=>readFamilyMembership(index.data()));
   if(m.role==='owner')throw new Error('FAMILY_LIFECYCLE_NOT_READY');
   if(m.state!=='ACTIVE')throw new Error('JOIN_COMMITTED_IN_PROGRESS');
   const historical=await tx.get(this.db.collection('households').where('ownerUid','==',uid).where('kind','==','family').where('state','==','DISSOLVED').limit(1));
   if(!historical.empty)throw new Error('FAMILY_LIFECYCLE_NOT_READY');
   const marker=await tx.get(this.db.doc(`accountLifecycle/${uid}`)),account=proof(()=>readAccount(marker.data()));
   if(account.state!=='ACTIVE'||(await tx.get(this.db.doc(`accountDeletions/${uid}`))).exists)invalid();
   const user=await tx.get(this.db.doc(`users/${uid}`)),home=await tx.get(this.db.doc(`households/${m.householdId}`));
   const joinId=proof(()=>currentJoinId(uid,user.get('familyJoinBinding')));
   const joinDoc=await tx.get(this.db.doc(`familyOperations/${joinId}`)),join=proof(()=>readJoinOperation(joinDoc.data(),joinId));
   if(join.actorUid!==uid||user.get('familyJoinBinding')!==undefined&&user.get('familyJoinBinding.inviteId')!==join.inviteId||join.phase!=='ACTIVE'||join.status!=='DONE'||join.householdId!==m.householdId||home.get('kind')!=='family'||home.get('state')!=='ACTIVE'||home.get('ownerUid')!==join.ownerUid||user.get('activeHouseholdId')!==m.householdId||user.get('privateHouseholdId')!==privateHouseholdId(uid)||user.get('familyHouseholdId')!==m.householdId)invalid();
   const now=this.clock(),i:Intent={version:1,uid,accountGeneration:account.generation,householdId:m.householdId,ownerUid:join.ownerUid,privateHouseholdId:privateHouseholdId(uid),joinOperationId:joinId,inviteId:join.inviteId,membershipUpdateTime:index.updateTime!,reason:'ACCOUNT_DELETION_MEMBER_EXIT',phase:'WAITING_EXIT',exitEvidence:null,deletionOperationId:null,createdAt:now,updatedAt:now,nextAt:now,lastOutcome:'admitted'};
   tx.create(ref,i);return i;
  });
 }
 /** Proof of another winning exit, never absence alone. Reuses original validators. */
 private async evidence(tx:Transaction,i:Intent){
  for(const removal of [false,true]){
   const actor=removal?i.ownerUid:i.uid,id=removal?ownerRemoveId(actor,i.uid,i.inviteId):memberLeaveId(i.uid,i.inviteId),doc=await tx.get(this.db.doc(`familyOperations/${id}`));
   if(doc.exists){const r=proof(()=>readMemberExitCompletion(doc.data(),actor,i.uid,i.inviteId,removal));if(r.householdId!==i.householdId)invalid();return doc.ref.path;}
  }
  const id=dissolutionId(i.ownerUid,i.householdId),ref=this.db.doc(`familyOperations/${id}`),doc=await tx.get(ref);
  if(!doc.exists)invalid();const o=proof(()=>readPreservation(doc.data(),id));
  const p=o.participants.find(p=>p.uid===i.uid&&p.role==='member');if(!p||!p.reverseUpdateTime.isEqual(i.membershipUpdateTime)||p.privateHouseholdId!==i.privateHouseholdId)invalid();
  const stored=await tx.get(ref.collection('participantRelease').doc('state')),records=await tx.get(ref.collection('participantReleaseJournal').limit(8));
  const result=proof(()=>readParticipantReleaseProgress(o,stored,records));if(!result.released.has(i.uid))invalid();
  return ref.collection('participantReleaseJournal').doc(participantReleaseId(o,p!)).path;
 }
 private async reconcile(uid:string){
  return this.db.runTransaction(async tx=>{
   const ref=this.db.doc(`familyMemberDeletions/${uid}`),i=read((await tx.get(ref)).data(),uid);
   if(i.phase==='OPERATOR'||i.phase==='HANDED_OFF')return i.phase;
   const index=await tx.get(this.db.doc(`familyMemberships/${uid}`)),marker=await tx.get(this.db.doc(`accountLifecycle/${uid}`)),account=proof(()=>readAccount(marker.data())),job=await tx.get(this.db.doc(`accountDeletions/${uid}`));
   if(index.exists){
    if(job.exists||account.state!=='ACTIVE'||account.generation!==i.accountGeneration||i.phase!=='WAITING_EXIT')invalid();
    const m=proof(()=>readFamilyMembership(index.data()));if(m.state!=='ACTIVE'||m.role!=='member'||m.householdId!==i.householdId||!index.updateTime!.isEqual(i.membershipUpdateTime))invalid();
    const capDoc=await tx.get(this.db.doc(`familyJoinCapacity/${i.householdId}`)),cap=proof(()=>readJoinCapacity(capDoc.data()));
    if(cap.structuralOperationId){tx.update(ref,{nextAt:Timestamp.fromMillis(this.clock().toMillis()+60000),lastOutcome:'structuralConflict'});return 'WAITING_EXIT';}
    return 'EXIT_ALLOWED';
   }
   const exitEvidence=await this.evidence(tx,i);
   if(i.exitEvidence!==null&&i.exitEvidence!==exitEvidence)invalid();
   if((await tx.get(this.db.doc(`households/${i.householdId}/members/${uid}`))).exists)invalid();
   if(job.exists){
    const j=proof(()=>readDeletion(job.data()));
    if(account.state==='ACTIVE'||j.generation!==account.generation||account.generation!==i.accountGeneration+(account.state==='DELETED'?2:1)||account.state==='DELETED'&&j.stage!=='DONE')invalid();
    tx.update(ref,{phase:'HANDED_OFF',exitEvidence,deletionOperationId:j.operationId,updatedAt:this.clock(),nextAt:FieldValue.delete(),lastOutcome:'privateDeletionAdmitted'});return 'HANDED_OFF';
   }
   if(account.state!=='ACTIVE'||account.generation!==i.accountGeneration)invalid();
   const user=await tx.get(this.db.doc(`users/${uid}`)),home=await tx.get(this.db.doc(`households/${i.privateHouseholdId}`)),member=await tx.get(home.ref.collection('members').doc(uid));
   if(user.get('activeHouseholdId')!==i.privateHouseholdId||user.get('familyHouseholdId')!==null||user.get('privateHouseholdId')!==i.privateHouseholdId||!home.exists||home.get('schemaVersion')!==2||member.get('role')!=='owner')invalid();
   proof(()=>validatePrivateRoot(home.data()!,uid));
   tx.update(ref,{phase:'EXIT_COMPLETE',exitEvidence,updatedAt:this.clock(),lastOutcome:'familyExitProven'});return 'EXIT_COMPLETE';
  });
 }
 async step(uid:string){
  this.local();authenticatedUid({uid});const i=read((await this.db.doc(`familyMemberDeletions/${uid}`).get()).data(),uid);
  if(i.phase==='OPERATOR'||i.phase==='HANDED_OFF')return i.phase;
  try{
   const state=await this.reconcile(uid);
   if(state==='EXIT_ALLOWED'){
    await new MemberLeaveStore(this.db,this.clock).leaveForAccountDeletion(uid,i.inviteId);
    return this.reconcile(uid);
   }
   if(state==='EXIT_COMPLETE'&&i.phase==='EXIT_COMPLETE'){
    // Existing admission rechecks membership/structural guards in its own transaction.
    await this.deletion.beginDeletion(uid);
    return this.reconcile(uid);
   }
   return state;
  }catch(e){
   if(e instanceof FamilyLeaveError&&['IN_PROGRESS','NOT_ACTIVE_MEMBER'].includes(e.code))return 'WAITING_EXIT';
   if(e instanceof Error&&['JOIN_COMMITTED_IN_PROGRESS','FAMILY_LIFECYCLE_NOT_READY'].includes(e.message))return 'WAITING_EXIT';
   if(e instanceof FamilyLeaveError||e instanceof Error&&e.message==='memberDeletionIntegrity'){
    return this.db.runTransaction(async tx=>{const ref=this.db.doc(`familyMemberDeletions/${uid}`),current=read((await tx.get(ref)).data(),uid);if(current.phase==='HANDED_OFF')return current.phase;tx.update(ref,{phase:'OPERATOR',nextAt:FieldValue.delete(),updatedAt:this.clock(),lastOutcome:'memberDeletionIntegrity'});return 'OPERATOR';});
   }
   throw e;
  }
 }
 async begin(uid:string){
  const intent=await this.admit(uid);if(!intent)return this.deletion.beginDeletion(uid);
  let state=await this.step(uid);if(state==='EXIT_COMPLETE')state=await this.step(uid);
  if(state==='HANDED_OFF')return this.deletion.beginDeletion(uid);
  return {outcome:state==='OPERATOR'?'supportRequired' as const:'familyExitPending' as const,operationId:undefined};
 }
 async sweep(){
  this.local();const due=await this.db.collection('familyMemberDeletions').where('nextAt','<=',this.clock()).orderBy('nextAt').limit(20).get();let failed=false;
  for(const d of due.docs){try{await this.step(d.id);}catch{failed=true;}
   await this.db.runTransaction(async tx=>{const current=await tx.get(d.ref);if(current.get('nextAt') instanceof Timestamp)tx.update(d.ref,{nextAt:Timestamp.fromMillis(this.clock().toMillis()+60000)});});
  }
  if(failed)throw new Error('memberDeletionRetryRequired');return due.size;
 }
}
