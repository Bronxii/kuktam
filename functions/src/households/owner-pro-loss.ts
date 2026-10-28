import {FamilyInviteStore} from './family-invites';
import {DissolutionLifecycleDriver} from './dissolution-lifecycle-driver';
import {FieldPath,FieldValue,Firestore,Timestamp} from 'firebase-admin/firestore';
import {hasPro} from './family-create';
import {authenticatedUid} from '../billing/account-binding';
import {readFamilyMembership} from './household-contract';
import {DissolutionPreparationStore,dissolutionId} from './dissolution-preparation';

/** Keep the accepted local-only Family gate. No deployed billing side effects. */
export function familyLifecycleEnabled(){return !process.env.K_SERVICE&&!process.env.FUNCTION_NAME&&process.env.GCLOUD_PROJECT==='demo-kuktam-local'&&/^(127\.0\.0\.1|localhost):[0-9]{1,5}$/.test(process.env.FIRESTORE_EMULATOR_HOST??'');}
type Intent={version:1;ownerUid:string;householdId:string;reason:'OWNER_PRO_LOSS'|'OWNER_REQUEST';status:'PENDING'|'IN_PROGRESS'|'DONE'|'SUPERSEDED'|'OPERATOR';operationId:string|null;createdAt:Timestamp;updatedAt:Timestamp;nextAt?:Timestamp;lastOutcome:string;ownerRequestedAt?:Timestamp};
export function readOwnerProLossIntent(raw:any,id:string):Intent {
 if(!raw||raw.ownerRequestedAt!==undefined&&!(raw.ownerRequestedAt instanceof Timestamp)||raw.version!==1||typeof raw.ownerUid!=='string'||authenticatedUid({uid:raw.ownerUid})!==raw.ownerUid||typeof raw.householdId!=='string'||!/^[A-Za-z0-9_-]{1,128}$/.test(raw.householdId)||dissolutionId(raw.ownerUid,raw.householdId)!==id||!['OWNER_PRO_LOSS','OWNER_REQUEST'].includes(raw.reason)||!['PENDING','IN_PROGRESS','DONE','SUPERSEDED','OPERATOR'].includes(raw.status)||!(raw.createdAt instanceof Timestamp)||!(raw.updatedAt instanceof Timestamp)||!([null,id].includes(raw.operationId))||typeof raw.lastOutcome!=='string'||(['PENDING','IN_PROGRESS'].includes(raw.status)&&!(raw.nextAt instanceof Timestamp)))throw new Error('proLossIntegrity');
 return raw;
}
export class OwnerProLossStore {
 constructor(private readonly db:Firestore,private readonly clock=Timestamp.now){}
 private local(){if(!familyLifecycleEnabled())throw new Error('FEATURE_DISABLED');}
 /** Auth-derived manual admission into the existing durable maintenance queue.
  * The historical collection name stays unchanged; reason preserves provenance. */
 async startOwner(uid:string){
  this.local();authenticatedUid({uid});
  const id=await this.db.runTransaction(async tx=>{
   const validation=new FamilyInviteStore(this.db,{resolve:async()=>new Map()},this.clock);
   await validation.active(tx,uid);
   const index=await tx.get(this.db.doc(`familyMemberships/${uid}`));
   if(!index.exists)throw new Error('NOT_OWNER');
   const membership=readFamilyMembership(index.data());
   if(membership.state!=='ACTIVE'||membership.role!=='owner')throw new Error('NOT_OWNER');
   const family={householdId:membership.householdId},id=dissolutionId(uid,family.householdId),ref=this.db.doc(`familyProLoss/${id}`);
   const home=await tx.get(this.db.doc(`households/${family.householdId}`)),member=await tx.get(home.ref.collection('members').doc(uid)),user=await tx.get(this.db.doc(`users/${uid}`));
   if(home.get('kind')!=='family'||home.get('state')!=='ACTIVE'||home.get('ownerUid')!==uid||member.get('role')!=='owner'||user.get('activeHouseholdId')!==family.householdId||user.get('familyHouseholdId')!==family.householdId||![null,id].includes(home.get('operationId')))throw new Error('NOT_OWNER');
   const {privateHouseholdId}=await import('./household-store');
   if(user.get('privateHouseholdId')!==privateHouseholdId(uid)||user.get('shoppingMigrationVersion')!==1)throw new Error('INTEGRITY_REQUIRES_OPERATOR');
   const prior=await tx.get(ref),op=await tx.get(this.db.doc(`familyOperations/${id}`));
   if(!op.exists)await validation.privateHome(tx,uid,privateHouseholdId(uid));
   if(op.exists&&(op.get('kind')!=='FAMILY_DISSOLUTION'||op.get('ownerUid')!==uid||op.get('householdId')!==family.householdId))throw new Error('INTEGRITY_REQUIRES_OPERATOR');
   if(prior.exists){const old=readOwnerProLossIntent(prior.data(),id);if(old.status!=='SUPERSEDED'){if(old.status==='PENDING'&&!op.exists&&old.reason==='OWNER_PRO_LOSS'&&!old.ownerRequestedAt)tx.update(ref,{ownerRequestedAt:this.clock()});return id;}}
   const now=this.clock();
   tx.set(ref,{version:1,ownerUid:uid,householdId:family.householdId,reason:'OWNER_REQUEST',status:op.exists?'IN_PROGRESS':'PENDING',operationId:op.exists?id:null,createdAt:now,updatedAt:now,nextAt:now,lastOutcome:'ownerRequested'} satisfies Intent);
   return id;
  });
  // Acceptance is durable before execution. Maintenance owns all subsequent steps.
  await this.step(id);
  return {schemaVersion:1,operationId:id,outcome:'IN_PROGRESS' as const};
 }
 /** Event payloads are hints only: recompute the complete current grant set. */
 async observe(uid:string){
  this.local();authenticatedUid({uid});
  return this.db.runTransaction(async tx=>{
   const index=await tx.get(this.db.doc(`familyMemberships/${uid}`));
   if(!index.exists)return 'NO_ACTIVE_FAMILY';
   const m=readFamilyMembership(index.data());if(m.state!=='ACTIVE'||m.role!=='owner')return 'NOT_ACTIVE_OWNER';
   const hid=m.householdId,id=dissolutionId(uid,hid),ref=this.db.doc(`familyProLoss/${id}`),op=await tx.get(this.db.doc(`familyOperations/${id}`)),prior=await tx.get(ref),home=await tx.get(this.db.doc(`households/${hid}`));
   if(home.get('kind')!=='family'||home.get('state')!=='ACTIVE'||home.get('ownerUid')!==uid)throw new Error('proLossIntegrity');
   if(prior.exists){const old=readOwnerProLossIntent(prior.data(),id);if(['IN_PROGRESS','DONE','OPERATOR'].includes(old.status)||(old.reason==='OWNER_REQUEST'||old.ownerRequestedAt)&&old.status==='PENDING')return id;}
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
   const ref=this.db.doc(`familyProLoss/${id}`),op=await tx.get(this.db.doc(`familyOperations/${id}`)),i=readOwnerProLossIntent((await tx.get(ref)).data(),id);
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
  const i=readOwnerProLossIntent((await this.db.doc(`familyProLoss/${id}`).get()).data(),id);
  if(['DONE','SUPERSEDED','OPERATOR'].includes(i.status))return i.status;
  const ref=this.db.doc(`familyOperations/${id}`),op=await ref.get();
  if(!op.exists){
   const conflict=await new DissolutionLifecycleDriver(this.db,this.clock).beforeAdmission(i.ownerUid,i.householdId);
   if(conflict!=='AVAILABLE')return this.record(id,conflict==='OPERATOR'?'OPERATOR':'PENDING',conflict);
   try{
    const preparation=new DissolutionPreparationStore(this.db,this.clock);
    const result=(i.reason==='OWNER_REQUEST'||i.ownerRequestedAt)?await preparation.prepare({uid:i.ownerUid},i.householdId):await preparation.prepareForProLoss(i.ownerUid,i.householdId);
    if(result===null)return this.record(id,'SUPERSEDED','currentProRestored');
    return this.record(id,'IN_PROGRESS','admitted');
   }catch(e){
    if((await ref.get()).exists)return this.record(id,'IN_PROGRESS','concurrentAdmission');
    if(e instanceof Error&&e.message==='IN_PROGRESS')return this.record(id,'PENDING','structuralConflict');
    if(e instanceof Error&&['INTEGRITY_REQUIRES_OPERATOR','NOT_OWNER','WRONG_FAMILY','ACCOUNT_UNAVAILABLE'].includes(e.message))return this.record(id,'OPERATOR',e.message);
    throw e;
   }
  }
  const result=await new DissolutionLifecycleDriver(this.db,this.clock).step(i.ownerUid,i.householdId);
  return this.record(id,result==='DONE'?'DONE':result==='OPERATOR'?'OPERATOR':'IN_PROGRESS',result);
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
