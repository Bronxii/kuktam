import {FieldPath,FieldValue,Firestore,Timestamp,Transaction,DocumentSnapshot} from 'firebase-admin/firestore';
import {authenticatedUid,AuthContext} from '../billing/account-binding';
import {readAccount} from '../accounts/account-lifecycle';
import {familyLifecycleEnabled,readOwnerProLossIntent} from './owner-pro-loss';
import {readOwnerDeletionIntent} from './owner-account-deletion';
import {privateHouseholdId} from './household-store';
import {validatePrivateRoot} from './household-contract';
import {dissolutionId} from './dissolution-preparation';
import {readPreservation} from './dissolution-preservation';
import {readDissolutionFinalizationReceipt} from './dissolution-finalization';
import {readJoinCapacity,assertNoLiveFamilyDependency} from './join-capacity';
import {readInvite,readInviteSlots} from './invite-contract';
import {readJoinOperation} from './family-join';
import {readCreateOperation,isCreateIdentity} from './family-create';
import {readMemberExitCompletion,memberLeaveId,ownerRemoveId} from './member-leave';
import {readParticipantReleaseProgress} from './dissolution-member-release';
import {digest,sourceFingerprint} from './join-snapshot';

const invalid=():never=>{throw new Error('historicalAuditIntegrity');};
const proof=<T>(fn:()=>T):T=>{try{return fn();}catch{return invalid();}};
const hex=(v:any)=>typeof v==='string'&&/^[a-f0-9]{64}$/.test(v);
const nat=(v:any)=>Number.isSafeInteger(v)&&v>=0;
const seed=(uid:string,g:number)=>digest(JSON.stringify(['historical-family-audit-v1',uid,g]));
const stamp=(t:Timestamp)=>[t.seconds,t.nanoseconds];
type Current={householdId:string;updateTime:Timestamp;stage:'INVITES'|'OPERATIONS'|'DETACH';after:string|null;auditHash:string};
type Progress={version:1;uid:string;accountGeneration:number;stage:'SCAN'|'VERIFY'|'COMPLETE';count:number;hash:string;current:Current|null;verified:number;after:string|null;verifyHash:string};
const receiptHash=(r:any)=>digest(JSON.stringify([r.version,r.uid,r.accountGeneration,r.householdId,r.operationId,stamp(r.householdCreatedAt),stamp(r.priorUpdateTime),r.finalizationHash,r.auditHash,stamp(r.detachedAt),r.previousHash]));
function progress(v:any,uid:string,g:number):Progress {
 if(!v||Object.keys(v).sort().join(',')!=='accountGeneration,after,count,current,hash,stage,uid,verified,verifyHash,version'||v.version!==1||v.uid!==uid||v.accountGeneration!==g||!['SCAN','VERIFY','COMPLETE'].includes(v.stage)||!nat(v.count)||!nat(v.verified)||v.verified>v.count||!hex(v.hash)||!hex(v.verifyHash)||!(v.after===null||typeof v.after==='string')||v.stage!=='SCAN'&&v.current!==null)invalid();
 if(v.current!==null){const c=v.current;if(!c||Object.keys(c).sort().join(',')!=='after,auditHash,householdId,stage,updateTime'||typeof c.householdId!=='string'||!/^[A-Za-z0-9_-]{1,128}$/.test(c.householdId)||!(c.updateTime instanceof Timestamp)||!['INVITES','OPERATIONS','DETACH'].includes(c.stage)||!(c.after===null||typeof c.after==='string')||!hex(c.auditHash))invalid();}
 return v;
}
/** Explicit trusted local preparation. Never dispatches private deletion or Auth. */
export class HistoricalFamilyAuditStore {
 constructor(private readonly db:Firestore,private readonly clock=Timestamp.now){}
 private local(uid:string){if(!familyLifecycleEnabled())throw new Error('FEATURE_DISABLED');authenticatedUid({uid});}
 private async privateAccount(tx:Transaction,uid:string,g?:number){
  const marker=await tx.get(this.db.doc(`accountLifecycle/${uid}`)),a=proof(()=>readAccount(marker.data()));
  const job=await tx.get(this.db.doc(`accountDeletions/${uid}`)),index=await tx.get(this.db.doc(`familyMemberships/${uid}`)),user=await tx.get(this.db.doc(`users/${uid}`)),p=privateHouseholdId(uid);
  if(a.state!=='ACTIVE'||g!==undefined&&a.generation!==g||job.exists||index.exists||user.get('activeHouseholdId')!==p||user.get('privateHouseholdId')!==p||user.get('familyHouseholdId')!==null)invalid();
  const home=await tx.get(this.db.doc(`households/${p}`)),member=await tx.get(home.ref.collection('members').doc(uid));proof(()=>validatePrivateRoot(home.data()!,uid));if(member.get('role')!=='owner')invalid();
  const ownedWork=await tx.get(this.db.collection('familyOperations').where('ownerUid','==',uid).where('status','in',['READY','OPERATOR']).limit(1));
  const actorWork=await tx.get(this.db.collection('familyOperations').where('actorUid','==',uid).where('status','in',['READY','OPERATOR']).limit(1));
  const live=await tx.get(this.db.collection('households').where('ownerUid','==',uid).where('kind','==','family').where('state','in',['ACTIVE','PREPARING','DISSOLVING']).limit(1));
  if(!ownedWork.empty||!actorWork.empty||!live.empty)invalid();
  return a;
 }
 /** Shared for freshly dissolved 6B2 owners and later private historical owners. */
 async admitHistorical(context:AuthContext){
  const uid=authenticatedUid(context);this.local(uid);
  return this.db.runTransaction(async tx=>{
   const ref=this.db.doc(`familyOwnerDeletions/${uid}`),old=await tx.get(ref);
   if(old.exists)return proof(()=>readOwnerDeletionIntent(old.data(),uid));
   const a=await this.privateAccount(tx,uid),homes=await tx.get(this.db.collection('households').where('ownerUid','==',uid).where('kind','==','family').orderBy(FieldPath.documentId()).limit(1));
   if(homes.empty)throw new Error('NO_HISTORICAL_FAMILY');
   const home=homes.docs[0]!,{o}=await this.audit(tx,uid,home,false),now=this.clock();
   const i={version:1,uid,role:'owner',reason:'OWNER_ACCOUNT_DELETION',accountGeneration:a.generation,householdId:home.id,privateHouseholdId:privateHouseholdId(uid),householdCreatedAt:home.get('createdAt'),operationId:o.structuralOperationId,phase:'WAITING_HISTORICAL_AUDIT',createdAt:now,updatedAt:now,lastOutcome:'historicalOwnerRequest',completionEvidence:`familyOperations/${o.structuralOperationId}/finalization/state`};
   proof(()=>readOwnerDeletionIntent(i,uid));tx.create(ref,i);return i;
  });
 }
 private async audit(tx:Transaction,uid:string,home:DocumentSnapshot,detached:boolean){
  const id=dissolutionId(uid,home.id),op=await tx.get(this.db.doc(`familyOperations/${id}`)),o=proof(()=>readPreservation(op.data(),id));
  if(o.phase!=='DONE'||o.status!=='DONE'||o.ownerUid!==uid||o.householdId!==home.id||home.get('schemaVersion')!==2||home.get('kind')!=='family'||home.get('state')!=='DISSOLVED'||home.get('operationId')!==null||!o.householdCreatedAt.isEqual(home.get('createdAt'))||home.get('ownerUid')!==(detached?null:uid))invalid();
  const receipt=await tx.get(op.ref.collection('finalization').doc('state')),r=proof(()=>readDissolutionFinalizationReceipt(receipt.data(),o));
  if(home.get('shoppingEpoch')!==r.sourceEpoch)invalid();
  const capDoc=await tx.get(this.db.doc(`familyJoinCapacity/${home.id}`)),slotsDoc=await tx.get(this.db.doc(`familyInviteSlots/${home.id}`));
  const cap=proof(()=>readJoinCapacity(capDoc.data())),slots=proof(()=>readInviteSlots(slotsDoc.data()));
  const members=await tx.get(home.ref.collection('members').limit(1)),indexes=await tx.get(this.db.collection('familyMemberships').where('householdId','==',home.id).limit(1)),items=await tx.get(home.ref.collection('shoppingItems').limit(1));
  const reservations=await tx.get(this.db.collection('familyInvites').where('householdId','==',home.id).where('status','==','RESERVED').limit(1));
  const usable=await tx.get(this.db.collection('familyInvites').where('householdId','==',home.id).where('status','==','PENDING').where('expiresAt','>',this.clock()).limit(1));
  const work=await tx.get(this.db.collection('familyOperations').where('householdId','==',home.id).where('status','in',['READY','OPERATOR']).limit(1));
  const lossDoc=await tx.get(this.db.doc(`familyProLoss/${id}`)),loss=lossDoc.exists?proof(()=>readOwnerProLossIntent(lossDoc.data(),id)):null;
  if(cap.schemaVersion!==2||cap.structuralOperationId!==null||cap.operationIds.length||slots.length||!members.empty||!indexes.empty||!items.empty||!reservations.empty||!usable.empty||!work.empty||loss!==null&&(!['DONE','SUPERSEDED'].includes(loss.status)||loss.status==='DONE'&&loss.operationId!==id||loss.status==='SUPERSEDED'&&loss.operationId!==null))invalid();
  const released=await tx.get(op.ref.collection('participantRelease').doc('state')),journal=await tx.get(op.ref.collection('participantReleaseJournal').limit(8));
  const release=proof(()=>readParticipantReleaseProgress(o,released,journal));if(release.progress.cursor!==release.participants.length)invalid();
  return {o,r};
 }
 /** 6C2: fresh, read-only proof in the SAME transaction as private deletion admission.
  * Pages bound query payloads; the transaction reads all historical roots so no
  * earlier page can change between validation and the account barrier commit. */
 async verifyDeletionHandoff(tx:Transaction,uid:string){
  this.local(uid);
  const ref=this.db.doc(`familyOwnerDeletions/${uid}`),intentDoc=await tx.get(ref),i=proof(()=>readOwnerDeletionIntent(intentDoc.data(),uid));
  if(i.phase!=='HISTORICAL_AUDIT_READY')invalid();
  await this.privateAccount(tx,uid,i.accountGeneration);
  const stateDoc=await tx.get(ref.collection('historicalAudit').doc('state')),p=proof(()=>progress(stateDoc.data(),uid,i.accountGeneration));
  if(p.stage!=='COMPLETE'||p.count<1||p.verified!==p.count||p.verifyHash!==p.hash)invalid();
  let hash=seed(uid,i.accountGeneration),after:string|null=null,count=0,primary=false;
  const receipts=ref.collection('historicalFamilies');
  for(;;){
   let query=receipts.orderBy(FieldPath.documentId()).limit(10);if(after)query=query.startAfter(after);
   const page=await tx.get(query);
   for(const d of page.docs){
    const r=d.data();
    if(r.version!==1||r.uid!==uid||r.accountGeneration!==i.accountGeneration||r.householdId!==d.id||!(r.detachedAt instanceof Timestamp)||!(r.priorUpdateTime instanceof Timestamp)||!(r.householdCreatedAt instanceof Timestamp)||!hex(r.auditHash)||r.previousHash!==hash||r.hash!==proof(()=>receiptHash(r)))invalid();
    const home=await tx.get(this.db.doc(`households/${d.id}`)),a=await this.audit(tx,uid,home,true);
    if(home.get('auditOwnerUid')!==uid||home.get('auditDetachmentPath')!==d.ref.path||a.o.structuralOperationId!==r.operationId||a.r.hash!==r.finalizationHash||!a.o.householdCreatedAt.isEqual(r.householdCreatedAt))invalid();
    if(d.id===i.householdId){if(r.operationId!==i.operationId||!i.householdCreatedAt.isEqual(r.householdCreatedAt))invalid();primary=true;}
    hash=r.hash;count++;after=d.id;
   }
   if(page.size<10)break;
  }
  const roots=await tx.get(this.db.collection('households').where('auditOwnerUid','==',uid).count());
  if(!primary||count!==p.count||hash!==p.hash||roots.data().count!==count)invalid();
  await assertNoLiveFamilyDependency(this.db,tx,uid);
  return i;
 }
 private operation(d:DocumentSnapshot,uid:string,hid:string){
  const v=d.data()!;if(v.householdId!==hid||!['DONE','ABORTED'].includes(v.status))invalid();
  switch(v.kind){
   case 'FAMILY_DISSOLUTION':{const o=readPreservation(v,d.id);if(o.ownerUid!==uid||o.phase!=='DONE'||o.status!=='DONE')invalid();break;}
   case 'JOIN':{const o=readJoinOperation(v,d.id);if(o.ownerUid!==uid||o.status==='DONE'&&o.phase!=='ACTIVE')invalid();break;}
   case 'CREATE':{const o=readCreateOperation(v);if(o.actorUid!==uid||!isCreateIdentity(d.id,o))invalid();break;}
   case 'MEMBER_LEAVE':readMemberExitCompletion(v,v.actorUid,v.actorUid,v.inviteId,false);if(d.id!==memberLeaveId(v.actorUid,v.inviteId))invalid();break;
   case 'OWNER_REMOVE_MEMBER':readMemberExitCompletion(v,uid,v.targetUid,v.inviteId,true);if(d.id!==ownerRemoveId(uid,v.targetUid,v.inviteId))invalid();break;
   default:invalid();
  }
 }
 async step(uid:string){
  this.local(uid);
  try{return await this.db.runTransaction(async tx=>{
   const ref=this.db.doc(`familyOwnerDeletions/${uid}`),intentDoc=await tx.get(ref),i=proof(()=>readOwnerDeletionIntent(intentDoc.data(),uid));
   if(i.phase==='OPERATOR')return 'OPERATOR';
   if(!['WAITING_HISTORICAL_AUDIT','DETACHING_HISTORICAL_AUDIT','HISTORICAL_AUDIT_READY'].includes(i.phase))throw new Error('HISTORICAL_AUDIT_NOT_READY');
   await this.privateAccount(tx,uid,i.accountGeneration);
   const state=ref.collection('historicalAudit').doc('state'),stored=await tx.get(state),receipts=ref.collection('historicalFamilies'),initial=seed(uid,i.accountGeneration);
   if(!stored.exists){
    if(i.phase!=='WAITING_HISTORICAL_AUDIT'||!(await tx.get(receipts.limit(1))).empty)invalid();
    const p:Progress={version:1,uid,accountGeneration:i.accountGeneration,stage:'SCAN',count:0,hash:initial,current:null,verified:0,after:null,verifyHash:initial};
    tx.create(state,p);tx.update(ref,{phase:'DETACHING_HISTORICAL_AUDIT',nextAt:FieldValue.delete(),updatedAt:this.clock(),lastOutcome:'historicalAuditStarted'});return 'DETACHING_HISTORICAL_AUDIT';
   }
   const p=proof(()=>progress(stored.data(),uid,i.accountGeneration));
   if(p.stage==='COMPLETE'){
    if(i.phase!=='HISTORICAL_AUDIT_READY'||p.count<1||p.verified!==p.count||p.verifyHash!==p.hash)invalid();
    await assertNoLiveFamilyDependency(this.db,tx,uid);return 'HISTORICAL_AUDIT_READY';
   }
   if(i.phase!=='DETACHING_HISTORICAL_AUDIT')invalid();
   if(p.stage==='SCAN'){
    if(!p.current){
     const page=await tx.get(this.db.collection('households').where('ownerUid','==',uid).where('kind','==','family').orderBy(FieldPath.documentId()).limit(1));
     if(page.empty){tx.update(state,{stage:'VERIFY'});return 'DETACHING_HISTORICAL_AUDIT';}
     const home=page.docs[0]!;await this.audit(tx,uid,home,false);
     if(home.get('auditOwnerUid')!==undefined||home.get('auditDetachmentPath')!==undefined||(await tx.get(receipts.doc(home.id))).exists)invalid();
     tx.update(state,{current:{householdId:home.id,updateTime:home.updateTime!,stage:'INVITES',after:null,auditHash:seed(home.id,i.accountGeneration)}});return 'DETACHING_HISTORICAL_AUDIT';
    }
    const c=p.current,home=await tx.get(this.db.doc(`households/${c.householdId}`));
    if(!home.exists||!home.updateTime!.isEqual(c.updateTime))invalid();const {o,r}=await this.audit(tx,uid,home,false);
    if(c.stage!=='DETACH'){
     let q=this.db.collection(c.stage==='INVITES'?'familyInvites':'familyOperations').where('householdId','==',home.id).orderBy(FieldPath.documentId()).limit(10);if(c.after)q=q.startAfter(c.after);
     const page=await tx.get(q);let hash=c.auditHash;
     for(const d of page.docs){proof(()=>{if(c.stage==='INVITES'){const v=readInvite(d.data());if(v.createdByUid!==uid||v.status==='RESERVED'||v.status==='PENDING'&&v.expiresAt.toMillis()>this.clock().toMillis())invalid();}else this.operation(d,uid,home.id);});hash=digest(JSON.stringify([hash,d.id,proof(()=>sourceFingerprint(d))]));}
     tx.update(state,{current:{...c,auditHash:hash,after:page.size===10?page.docs.at(-1)!.id:null,stage:page.size===10?c.stage:c.stage==='INVITES'?'OPERATIONS':'DETACH'}});return 'DETACHING_HISTORICAL_AUDIT';
    }
    const rr=receipts.doc(home.id);if((await tx.get(rr)).exists)invalid();
    const record={version:1,uid,accountGeneration:i.accountGeneration,householdId:home.id,operationId:o.structuralOperationId,householdCreatedAt:o.householdCreatedAt,priorUpdateTime:home.updateTime!,finalizationHash:r.hash,auditHash:c.auditHash,detachedAt:this.clock(),previousHash:p.hash};
    const hash=receiptHash(record);
    tx.create(rr,{...record,hash});tx.update(home.ref,{ownerUid:null,auditOwnerUid:uid,auditDetachmentPath:rr.path});tx.update(state,{count:p.count+1,hash,current:null});return 'DETACHING_HISTORICAL_AUDIT';
   }
   let q=receipts.orderBy(FieldPath.documentId()).limit(1);if(p.after)q=q.startAfter(p.after);const page=await tx.get(q);
   if(!page.empty){
    const d=page.docs[0]!,r=d.data();
    if(r.version!==1||r.uid!==uid||r.accountGeneration!==i.accountGeneration||r.householdId!==d.id||!(r.detachedAt instanceof Timestamp)||!(r.priorUpdateTime instanceof Timestamp)||!(r.householdCreatedAt instanceof Timestamp)||!hex(r.auditHash)||r.previousHash!==p.verifyHash||r.hash!==proof(()=>receiptHash(r)))invalid();
    const home=await tx.get(this.db.doc(`households/${d.id}`)),a=await this.audit(tx,uid,home,true);
    if(home.get('auditOwnerUid')!==uid||home.get('auditDetachmentPath')!==d.ref.path||a.o.structuralOperationId!==r.operationId||a.r.hash!==r.finalizationHash||!a.o.householdCreatedAt.isEqual(r.householdCreatedAt))invalid();
    tx.update(state,{after:d.id,verified:p.verified+1,verifyHash:r.hash});return 'DETACHING_HISTORICAL_AUDIT';
   }
   if(p.count<1||p.count!==p.verified||p.hash!==p.verifyHash||(await tx.get(receipts.count())).data().count!==p.count)invalid();
   const primary=await tx.get(receipts.doc(i.householdId));if(primary.get('operationId')!==i.operationId||!i.householdCreatedAt.isEqual(primary.get('householdCreatedAt')))invalid();
   await assertNoLiveFamilyDependency(this.db,tx,uid);
   tx.update(state,{stage:'COMPLETE'});tx.update(ref,{phase:'HISTORICAL_AUDIT_READY',updatedAt:this.clock(),lastOutcome:'historicalAuditReady'});return 'HISTORICAL_AUDIT_READY';
  });}catch(e){
   if(e instanceof Error&&['historicalAuditIntegrity','FAMILY_LIFECYCLE_NOT_READY'].includes(e.message))return this.db.runTransaction(async tx=>{
    const ref=this.db.doc(`familyOwnerDeletions/${uid}`),doc=await tx.get(ref);if(!doc.exists)throw e;
    // Do not rewrite historical data, or roll back already-detached audit roots.
    tx.update(ref,{phase:'OPERATOR',nextAt:FieldValue.delete(),updatedAt:this.clock(),lastOutcome:'historicalAuditIntegrity'});return 'OPERATOR';
   });throw e;
  }
 }
}
