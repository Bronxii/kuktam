import {FieldPath,FieldValue,Firestore,Timestamp} from 'firebase-admin/firestore';
import {hasPro} from './family-create';
import {authenticatedUid} from '../billing/account-binding';
import {readFamilyMembership} from './household-contract';
import {DissolutionPreparationStore,dissolutionId} from './dissolution-preparation';
import {DissolutionPreservationStore} from './dissolution-preservation';
import {DissolutionMergeStore} from './dissolution-merge';
import {DissolutionSourceDispositionStore} from './dissolution-source-disposition';
import {DissolutionMemberReleaseStore} from './dissolution-member-release';
import {DissolutionFinalizationStore} from './dissolution-finalization';
import {FamilyJoinStore,readJoinOperation} from './family-join';
import {readJoinCapacity} from './join-capacity';

/** Keep the accepted local-only Family gate. No deployed billing side effects. */
export function familyLifecycleEnabled(){return !process.env.K_SERVICE&&!process.env.FUNCTION_NAME&&process.env.GCLOUD_PROJECT==='demo-kuktam-local'&&/^(127\.0\.0\.1|localhost):[0-9]{1,5}$/.test(process.env.FIRESTORE_EMULATOR_HOST??'');}
type Intent={version:1;ownerUid:string;householdId:string;reason:'OWNER_PRO_LOSS';status:'PENDING'|'IN_PROGRESS'|'DONE'|'SUPERSEDED'|'OPERATOR';operationId:string|null;createdAt:Timestamp;updatedAt:Timestamp;nextAt?:Timestamp;lastOutcome:string};
function read(raw:any,id:string):Intent {
 if(!raw||raw.version!==1||typeof raw.ownerUid!=='string'||authenticatedUid({uid:raw.ownerUid})!==raw.ownerUid||typeof raw.householdId!=='string'||!/^[A-Za-z0-9_-]{1,128}$/.test(raw.householdId)||dissolutionId(raw.ownerUid,raw.householdId)!==id||raw.reason!=='OWNER_PRO_LOSS'||!['PENDING','IN_PROGRESS','DONE','SUPERSEDED','OPERATOR'].includes(raw.status)||!(raw.createdAt instanceof Timestamp)||!(raw.updatedAt instanceof Timestamp)||!([null,id].includes(raw.operationId))||typeof raw.lastOutcome!=='string'||(['PENDING','IN_PROGRESS'].includes(raw.status)&&!(raw.nextAt instanceof Timestamp)))throw new Error('proLossIntegrity');
 return raw;
}
export class OwnerProLossStore {
 constructor(private readonly db:Firestore,private readonly clock=Timestamp.now){}
 private local(){if(!familyLifecycleEnabled())throw new Error('FEATURE_DISABLED');}
 /** Event payloads are hints only: recompute the complete current grant set. */
 async observe(uid:string){
  this.local();authenticatedUid({uid});
  return this.db.runTransaction(async tx=>{
   const index=await tx.get(this.db.doc(`familyMemberships/${uid}`));
   if(!index.exists)return 'NO_ACTIVE_FAMILY';
   const m=readFamilyMembership(index.data());if(m.state!=='ACTIVE'||m.role!=='owner')return 'NOT_ACTIVE_OWNER';
   const hid=m.householdId,id=dissolutionId(uid,hid),ref=this.db.doc(`familyProLoss/${id}`),op=await tx.get(this.db.doc(`familyOperations/${id}`)),prior=await tx.get(ref),home=await tx.get(this.db.doc(`households/${hid}`));
   if(home.get('kind')!=='family'||home.get('state')!=='ACTIVE'||home.get('ownerUid')!==uid)throw new Error('proLossIntegrity');
   if(prior.exists){const old=read(prior.data(),id);if(['IN_PROGRESS','DONE','OPERATOR'].includes(old.status))return id;}
   if(!op.exists&&await hasPro(this.db,tx,uid,this.clock()))return 'ENTITLED';
   if(op.exists&&(op.get('kind')!=='FAMILY_DISSOLUTION'||op.get('ownerUid')!==uid||op.get('householdId')!==hid))throw new Error('proLossIntegrity');
   if(prior.exists&&prior.get('status')==='PENDING')return id;
   const now=this.clock();
   tx.set(ref,{version:1,ownerUid:uid,householdId:hid,reason:'OWNER_PRO_LOSS',status:op.exists?'IN_PROGRESS':'PENDING',operationId:op.exists?id:null,createdAt:prior.exists?prior.get('createdAt'):now,updatedAt:now,nextAt:now,lastOutcome:'observedCurrentGrants'} satisfies Intent);
   return id;
  });
 }
 private async record(id:string,status:Intent['status'],outcome:string){
  return this.db.runTransaction(async tx=>{
   const ref=this.db.doc(`familyProLoss/${id}`),op=await tx.get(this.db.doc(`familyOperations/${id}`)),i=read((await tx.get(ref)).data(),id);
   if(['DONE','OPERATOR'].includes(i.status))return i.status;
   // A concurrent admission wins over stale restoration/no-family observations.
   if(status==='SUPERSEDED'&&op.exists)return i.status;
   if(status==='DONE'&&(op.get('status')!=='DONE'||op.get('phase')!=='DONE'))throw new Error('proLossIntegrity');
   if(status==='PENDING'&&op.exists)status='IN_PROGRESS';
   const terminal=['DONE','SUPERSEDED','OPERATOR'].includes(status),now=this.clock();
   tx.update(ref,{status,lastOutcome:outcome,updatedAt:now,operationId:op.exists?id:null,nextAt:terminal?FieldValue.delete():Timestamp.fromMillis(now.toMillis()+60000)});
   return status;
  });
 }
 /** One existing engine transaction per invocation; scheduler supplies durable continuation. */
 async step(id:string){
  this.local();if(!/^dissolve_[a-f0-9]{64}$/.test(id))throw new Error('proLossIntegrity');
  const i=read((await this.db.doc(`familyProLoss/${id}`).get()).data(),id);
  if(['DONE','SUPERSEDED','OPERATOR'].includes(i.status))return i.status;
  const ref=this.db.doc(`familyOperations/${id}`),op=await ref.get(),auth={uid:i.ownerUid};
  if(!op.exists){
   // A committed JOIN owns forward completion. Never steal its structural lock.
   const capDoc=await this.db.doc(`familyJoinCapacity/${i.householdId}`).get();
   let cap;try{cap=readJoinCapacity(capDoc.data());}catch{return this.record(id,'OPERATOR','invalidCapacity');}
   if(cap.structuralOperationId&&cap.structuralOperationId!==id){
    const lock=await this.db.doc(`familyOperations/${cap.structuralOperationId}`).get();
    if(lock.get('kind')!=='JOIN'||lock.get('householdId')!==i.householdId||lock.get('ownerUid')!==i.ownerUid)return this.record(id,'OPERATOR','unknownStructuralOwner');
    let join;try{join=readJoinOperation(lock.data(),lock.id);}catch{return this.record(id,'OPERATOR','invalidJoin');}
    if(join.status==='OPERATOR')return this.record(id,'OPERATOR','joinRequiresOperator');
    if(lock.get('committedAt')==null)return this.record(id,'PENDING','structuralConflict');
    await new FamilyJoinStore(this.db,this.clock).resume(lock.id);
    return this.record(id,'PENDING','committedJoinForwardCompletion');
   }
   try{
    const result=await new DissolutionPreparationStore(this.db,this.clock).prepareForProLoss(i.ownerUid,i.householdId);
    if(result===null)return this.record(id,'SUPERSEDED','currentProRestored');
    return this.record(id,'IN_PROGRESS','admitted');
   }catch(e){
    if((await ref.get()).exists)return this.record(id,'IN_PROGRESS','concurrentAdmission');
    if(e instanceof Error&&e.message==='IN_PROGRESS')return this.record(id,'PENDING','structuralConflict');
    if(e instanceof Error&&['INTEGRITY_REQUIRES_OPERATOR','NOT_OWNER','WRONG_FAMILY','ACCOUNT_UNAVAILABLE'].includes(e.message))return this.record(id,'OPERATOR',e.message);
    throw e;
   }
  }
  if(op.get('kind')!=='FAMILY_DISSOLUTION'||op.get('ownerUid')!==i.ownerUid||op.get('householdId')!==i.householdId)return this.record(id,'OPERATOR','operationIdentity');
  if(op.get('status')==='OPERATOR')return this.record(id,'OPERATOR','dissolutionRequiresOperator');
  const phase=op.get('phase');
  const engine=['PREPARED','SNAPSHOT_SHOPPING','VERIFY_SHOPPING'].includes(phase)?new DissolutionPreservationStore(this.db,this.clock):phase==='PRESERVATION_COMMITTED'?new DissolutionMergeStore(this.db,this.clock):phase==='PRESERVATION_MERGE_COMPLETE'?new DissolutionSourceDispositionStore(this.db,this.clock):['PRESERVATION_SOURCE_CLEANED','RELEASING_NON_OWNERS'].includes(phase)?new DissolutionMemberReleaseStore(this.db,this.clock):['NON_OWNER_RELEASE_COMPLETE','DONE'].includes(phase)?new DissolutionFinalizationStore(this.db,this.clock):null;
  if(!engine)return this.record(id,'OPERATOR','unknownDissolutionPhase');
  try{const result=await engine.step(auth,i.householdId);return this.record(id,result==='DONE'?'DONE':result==='OPERATOR'?'OPERATOR':'IN_PROGRESS',result);}
  catch(e){if(e instanceof Error&&e.message==='INVALID_ARGUMENT'&&(await ref.get()).get('phase')!==phase)return this.record(id,'IN_PROGRESS','concurrentPhaseAdvance');throw e;}
 }
 /** Bounded rotating owner scan catches timed grant expiry without a write event. */
 async sweep(){
  this.local();const cursorRef=this.db.doc('familyLifecycleMaintenance/ownerScan'),cursor=await cursorRef.get();
  let query=this.db.collection('familyMemberships').orderBy(FieldPath.documentId()).limit(20);
  if(typeof cursor.get('after')==='string')query=query.startAfter(cursor.get('after'));
  const page=await query.get();
  const failures:string[]=[];
  for(const d of page.docs)if(d.get('state')==='ACTIVE'&&d.get('role')==='owner'){try{await this.observe(d.id);}catch{failures.push('ownerObservation');}}
  await cursorRef.set({after:page.size===20?page.docs[page.size-1]!.id:null});
  const due=await this.db.collection('familyProLoss').where('nextAt','<=',this.clock()).orderBy('nextAt').limit(20).get();
  for(const d of due.docs){try{await this.step(d.id);}catch{
   // Rotate transient failures so one unavailable operation cannot starve others.
   await this.db.runTransaction(async tx=>{const v=await tx.get(d.ref);if(v.get('nextAt') instanceof Timestamp)tx.update(d.ref,{nextAt:Timestamp.fromMillis(this.clock().toMillis()+60000)});});
   failures.push('lifecycleStep');
  }}
  if(failures.length)throw new Error('familyLifecycleRetryRequired');
  return {scanned:page.size,processed:due.size};
 }
}
