import { FieldPath, Firestore, Timestamp, Transaction, DocumentSnapshot } from 'firebase-admin/firestore';
import { authenticatedUid, AuthContext } from '../billing/account-binding';
import { readAccount } from '../accounts/account-lifecycle';
import { advanceShoppingEpoch } from '../shopping/mutation-store';
import { Child, epochExpiry, epochPattern, parseRequest } from '../shopping/mutation-contract';
import { dissolutionId, DissolutionPreparation, readDissolutionPreparation } from './dissolution-preparation';
import { readFamilyMembership, validatePrivateRoot } from './household-contract';
import { readJoinCapacity } from './join-capacity';
import { readJoinOperation } from './family-join';
import { readInvite, readInviteSlots } from './invite-contract';
import { digest, sourceFingerprint } from './join-snapshot';

export const PRESERVATION_PAGE_SIZE=10;
export const PRESERVATION_MERGE_CONTRACT='S1D_APPLY_ADD_BLOCK_V1';
type Add=Extract<Child,{type:'ADD'}>;
type Fence={householdId:string;operationId:string;epoch:string;at:Timestamp};
type Cursor={pageIndex:number;count:number;hash:string;lastId:string|null};
export type Preservation=Omit<DissolutionPreparation,'schemaVersion'|'phase'|'status'|'cursor'>&{
 schemaVersion:2;phase:'SNAPSHOT_SHOPPING'|'VERIFY_SHOPPING'|'PRESERVATION_COMMITTED'|'PRESERVATION_MERGE_COMPLETE'|'PRESERVATION_SOURCE_CLEANED'|'RELEASING_NON_OWNERS'|'NON_OWNER_RELEASE_COMPLETE'|'DONE';status:'READY'|'OPERATOR'|'DONE';
 cursor:Cursor|null;sourceFence:Fence;targetFence:Fence;shoppingSnapshot:{version:1;count:number;pages:number;hash:string}|null;
 preservationCommittedAt:Timestamp|null;mergeContract:typeof PRESERVATION_MERGE_CONTRACT;lastOutcome:string|null;
};
const extra=['sourceFence','targetFence','shoppingSnapshot','preservationCommittedAt','mergeContract','lastOutcome'];
const exact=(v:any,keys:string)=>v&&typeof v==='object'&&!Array.isArray(v)&&Object.keys(v).sort().join(',')===keys;
const nonnegative=(v:any)=>Number.isSafeInteger(v)&&v>=0;
const hashValue=(v:any)=>typeof v==='string'&&/^[a-f0-9]{64}$/.test(v);
const invalid=():never=>{throw new Error('preservationIntegrity');};
const proof=<T>(fn:()=>T):T=>{try{return fn();}catch{return invalid();}};
const compare=(a:string,b:string)=>Buffer.compare(Buffer.from(a),Buffer.from(b));
export const preservationSeed=(id:string,o:Preservation)=>digest(JSON.stringify(['dissolution-shopping-v1',id,o.snapshotHash,o.householdId,o.sourceFence.epoch,o.targetFence.householdId,o.targetFence.epoch,o.mergeContract]));
export const preservationPageId=(o:Preservation,n:number)=>digest(JSON.stringify([o.structuralOperationId,o.sourceFence.epoch,o.targetFence.epoch,n]));
export const preservationChildId=(o:Preservation,n:number,i:number,sourceId:string)=>digest(JSON.stringify([o.structuralOperationId,o.sourceFence.epoch,o.targetFence.epoch,n,i,sourceId]));
function base(o:Preservation,id:string){return readDissolutionPreparation({...Object.fromEntries(Object.entries(o).filter(([k])=>!extra.includes(k))),schemaVersion:1,phase:'PREPARED',status:'READY',cursor:null,updatedAt:o.createdAt},id);}
export function readPreservation(raw:any,id:string):Preservation {
 const o=raw as Preservation;proof(()=>base(o,id));
 const owner=o.participants.find(p=>p.role==='owner')!;
 const fence=(f:any,hid:string)=>exact(f,'at,epoch,householdId,operationId')&&f.householdId===hid&&f.operationId===id&&typeof f.epoch==='string'&&epochPattern.test(f.epoch)&&f.at instanceof Timestamp;
 if(o.schemaVersion!==2||!['SNAPSHOT_SHOPPING','VERIFY_SHOPPING','PRESERVATION_COMMITTED','PRESERVATION_MERGE_COMPLETE','PRESERVATION_SOURCE_CLEANED','RELEASING_NON_OWNERS','NON_OWNER_RELEASE_COMPLETE','DONE'].includes(o.phase)||!['READY','OPERATOR','DONE'].includes(o.status)||o.status==='DONE'&&o.phase!=='DONE'||o.phase==='DONE'&&!['DONE','OPERATOR'].includes(o.status)||
  !fence(o.sourceFence,o.householdId)||!fence(o.targetFence,owner.privateHouseholdId)||o.sourceFence.epoch===o.targetFence.epoch||!o.sourceFence.at.isEqual(o.targetFence.at)||
  !(o.updatedAt instanceof Timestamp)||o.mergeContract!==PRESERVATION_MERGE_CONTRACT||!(o.lastOutcome===null||typeof o.lastOutcome==='string')||
  !(o.preservationCommittedAt===null||o.preservationCommittedAt instanceof Timestamp)||
  !(o.shoppingSnapshot===null||exact(o.shoppingSnapshot,'count,hash,pages,version')&&o.shoppingSnapshot.version===1&&nonnegative(o.shoppingSnapshot.count)&&nonnegative(o.shoppingSnapshot.pages)&&o.shoppingSnapshot.pages===Math.ceil(o.shoppingSnapshot.count/10)&&hashValue(o.shoppingSnapshot.hash))||
  !(o.cursor===null||exact(o.cursor,'count,hash,lastId,pageIndex')&&nonnegative(o.cursor.pageIndex)&&nonnegative(o.cursor.count)&&hashValue(o.cursor.hash)&&(o.cursor.lastId===null||typeof o.cursor.lastId==='string'&&o.cursor.lastId.length>0&&!o.cursor.lastId.includes('/'))))invalid();
 if(o.phase==='SNAPSHOT_SHOPPING'&&(!o.cursor||o.shoppingSnapshot!==null||o.preservationCommittedAt!==null)||
   o.phase==='VERIFY_SHOPPING'&&(!o.cursor||!o.shoppingSnapshot||o.preservationCommittedAt!==null)||
   ['PRESERVATION_COMMITTED','PRESERVATION_MERGE_COMPLETE','PRESERVATION_SOURCE_CLEANED','RELEASING_NON_OWNERS','NON_OWNER_RELEASE_COMPLETE','DONE'].includes(o.phase)&&(o.cursor!==null||!o.shoppingSnapshot||!o.preservationCommittedAt))invalid();
 if(o.cursor&&(o.cursor.count>o.cursor.pageIndex*10||o.cursor.pageIndex!==Math.ceil(o.cursor.count/10)||(o.cursor.count===0)!==(o.cursor.lastId===null)))invalid();
 return o;
}
function addPayload(data:any,o:Preservation):Add {
 const mutationId=o.sourceFence.epoch+'_'+'0'.repeat(64);
 return proof(()=>parseRequest({schemaVersion:1,mutationId,actorUid:o.ownerUid,householdId:o.householdId,epoch:o.sourceFence.epoch,kind:'ADD',payloadJson:JSON.stringify({type:'ADD',name:data.name,quantity:data.quantity,unit:data.unit}),submittedAt:o.sourceFence.at},o.ownerUid,mutationId).children[0] as Add);
}
export function readPreservationPage(raw:any,o:Preservation,n:number,previousHash:string,lastId:string|null){
 if(!exact(raw,'chainHash,entries,operationId,pageIndex,results,sourceEpoch,targetEpoch,version')||raw.version!==1||raw.operationId!==o.structuralOperationId||raw.pageIndex!==n||raw.sourceEpoch!==o.sourceFence.epoch||raw.targetEpoch!==o.targetFence.epoch||!Array.isArray(raw.entries)||raw.entries.length<1||raw.entries.length>10||!Array.isArray(raw.results)||raw.results.length!==0)invalid();
 let chain=previousHash,prior=lastId;
 for(let i=0;i<raw.entries.length;i++){
  const e=raw.entries[i];
  if(!exact(e,'addPayload,addPayloadHash,dataHash,sourceId,transferId,updateTime')||typeof e.sourceId!=='string'||!e.sourceId||e.sourceId.includes('/')||prior!==null&&compare(prior,e.sourceId)>=0||!(e.updateTime instanceof Timestamp)||!hashValue(e.dataHash)||!hashValue(e.addPayloadHash)||
   !exact(e.addPayload,'name,quantity,type,unit')||e.addPayload.type!=='ADD'||e.transferId!==preservationChildId(o,n,i,e.sourceId)||Object.entries(addPayload(e.addPayload,o)).some(([key,value])=>e.addPayload[key]!==value)||digest(JSON.stringify(addPayload(e.addPayload,o)))!==e.addPayloadHash)invalid();
  chain=digest(JSON.stringify([chain,e.dataHash,e.addPayloadHash,e.transferId]));prior=e.sourceId;
 }
 if(raw.chainHash!==chain)invalid();return raw;
}
/** One bounded transaction per call. No timer, no merge, no automatic 5C2B dispatch. */
export class DissolutionPreservationStore {
 constructor(private readonly db:Firestore,private readonly clock=Timestamp.now){}
 async validate(tx:Transaction,id:string,o:DissolutionPreparation|Preservation,released:ReadonlySet<string>=new Set()){
  const fenced=o.schemaVersion===2,p=fenced?o as Preservation:null;
  const capDoc=await tx.get(this.db.doc(`familyJoinCapacity/${o.householdId}`)),cap=proof(()=>readJoinCapacity(capDoc.data()));
  if(cap.schemaVersion!==3||cap.structuralOperationId!==id)invalid();
  const source=await tx.get(this.db.doc(`households/${o.householdId}`));
  if(source.get('schemaVersion')!==2||source.get('kind')!=='family'||source.get('state')!=='ACTIVE'||source.get('ownerUid')!==o.ownerUid||!source.get('createdAt')?.isEqual(o.householdCreatedAt)||source.get('operationId')!==(fenced?id:null))invalid();
  const members=await tx.get(source.ref.collection('members').limit(9)),indexes=await tx.get(this.db.collection('familyMemberships').where('householdId','==',o.householdId).limit(9));
  if(members.size!==o.participantCount-released.size||indexes.size!==o.participantCount-released.size+cap.operationIds.length||indexes.size>8)invalid();
  const reverse=new Map(indexes.docs.map(d=>[d.id,{doc:d,value:proof(()=>readFamilyMembership(d.data()))}]));
  let target:DocumentSnapshot|undefined;
  for(const participant of o.participants){
   if(released.has(participant.uid)){if(participant.role!=='member'||members.docs.some(d=>d.id===participant.uid)||reverse.has(participant.uid))invalid();continue;}
   const u=participant.uid,r=reverse.get(u),m=members.docs.find(d=>d.id===u),user=await tx.get(this.db.doc(`users/${u}`));
   if(!r||r.value.state!=='ACTIVE'||r.value.role!==participant.role||!r.doc.updateTime!.isEqual(participant.reverseUpdateTime)||!m||m.get('role')!==participant.role||!m.updateTime!.isEqual(participant.memberUpdateTime)||user.get('activeHouseholdId')!==o.householdId||user.get('familyHouseholdId')!==o.householdId||user.get('privateHouseholdId')!==participant.privateHouseholdId||user.get('shoppingMigrationVersion')!==1)invalid();
   // After the point of no return lifecycle changes never reopen/abort the fences.
   if(!p||!['PRESERVATION_COMMITTED','PRESERVATION_MERGE_COMPLETE','PRESERVATION_SOURCE_CLEANED','RELEASING_NON_OWNERS','NON_OWNER_RELEASE_COMPLETE','DONE'].includes(p.phase)){
    const account=await tx.get(this.db.doc(`accountLifecycle/${u}`)),deletion=await tx.get(this.db.doc(`accountDeletions/${u}`));
    if(!account.exists||proof(()=>readAccount(account.data())).state!=='ACTIVE'||deletion.exists)invalid();
   }
   const home=await tx.get(this.db.doc(`households/${participant.privateHouseholdId}`)),member=await tx.get(home.ref.collection('members').doc(u));
   if(!home.exists||home.get('schemaVersion')!==2||member.get('role')!=='owner'||!home.get('createdAt')?.isEqual(participant.privateCreatedAt)||home.get('operationId')!==(fenced&&u===o.ownerUid?id:null))invalid();
   proof(()=>validatePrivateRoot({...home.data(),operationId:null},u));if(u===o.ownerUid)target=home;
  }
  if(!target||target.id===source.id)invalid();
  if(p)for(const [home,f] of [[source,p.sourceFence],[target!,p.targetFence]] as [DocumentSnapshot,Fence][]){
   if(home.id!==f.householdId||home.get('operationId')!==id||home.get('shoppingEpoch')!==f.epoch||!(home.get('shoppingEpochExpiresAt') instanceof Timestamp)||home.get('shoppingEpochExpiresAt').toMillis()!==epochExpiry(f.epoch))invalid();
  }
  const slots=await tx.get(this.db.doc(`familyInviteSlots/${o.householdId}`)),ids=slots.exists?proof(()=>readInviteSlots(slots.data())):[];
  const invites=new Map<string,ReturnType<typeof readInvite>>();
  for(const invId of ids){const doc=await tx.get(this.db.doc(`familyInvites/${invId}`)),inv=proof(()=>readInvite(doc.data()));if(inv.householdId!==o.householdId||inv.createdByUid!==o.ownerUid)invalid();invites.set(invId,inv);}
  for(const joinId of cap.operationIds){const doc=await tx.get(this.db.doc(`familyOperations/${joinId}`)),j=proof(()=>readJoinOperation(doc.data(),joinId)),r=reverse.get(j.actorUid),inv=invites.get(j.inviteId);
   if(j.status!=='READY'||j.householdId!==o.householdId||j.ownerUid!==o.ownerUid||doc.get('committedAt')!=null||!r||r.value.state!=='RESERVED'||r.value.role!=='member'||r.value.operationId!==joinId||!inv||inv.status!=='RESERVED'||inv.operationId!==joinId)invalid();}
  if([...invites.values()].some(inv=>inv.status==='RESERVED'&&!cap.operationIds.includes(inv.operationId!)))invalid();
  return {source,target:target!};
 }
 async step(context:AuthContext,householdId:string){
  const owner=authenticatedUid(context);if(typeof householdId!=='string'||!/^[A-Za-z0-9_-]{1,128}$/.test(householdId))throw new Error('INVALID_ARGUMENT');
  if(process.env.K_SERVICE||process.env.FUNCTION_NAME||process.env.GCLOUD_PROJECT!=='demo-kuktam-local'||!/^(127\.0\.0\.1|localhost):[0-9]{1,5}$/.test(process.env.FIRESTORE_EMULATOR_HOST??''))throw new Error('FEATURE_DISABLED');
  const id=dissolutionId(owner,householdId),ref=this.db.doc(`familyOperations/${id}`);
  return this.db.runTransaction(async tx=>{
   const d=await tx.get(ref),raw=d.data();if(!d.exists||raw?.kind!=='FAMILY_DISSOLUTION'||raw.actorUid!==owner||raw.householdId!==householdId)throw new Error('NOT_FOUND');
   if(raw.status==='OPERATOR')return 'OPERATOR';
   try{
    const o=raw.schemaVersion===1?proof(()=>readDissolutionPreparation(raw,id)):readPreservation(raw,id);
    // Later participant exits deliberately change the immutable snapshot's live
    // topology. Earlier preparation must never revalidate it as still ACTIVE.
    if(['RELEASING_NON_OWNERS','NON_OWNER_RELEASE_COMPLETE','DONE'].includes(o.phase))return o.phase;
    const c=await this.validate(tx,id,o),now=this.clock();
    if(o.schemaVersion===1){
     if((await tx.get(ref.collection('shoppingPreservation').limit(1))).size)invalid();
     const sourceEpoch=advanceShoppingEpoch(now),targetEpoch=advanceShoppingEpoch(now);
     const next:Preservation={...o,schemaVersion:2,phase:'SNAPSHOT_SHOPPING',sourceFence:{householdId:o.householdId,operationId:id,epoch:sourceEpoch.shoppingEpoch,at:now},targetFence:{householdId:c.target.id,operationId:id,epoch:targetEpoch.shoppingEpoch,at:now},shoppingSnapshot:null,preservationCommittedAt:null,mergeContract:PRESERVATION_MERGE_CONTRACT,lastOutcome:null,cursor:null,updatedAt:now};
     next.cursor={pageIndex:0,count:0,hash:preservationSeed(id,next),lastId:null};readPreservation(next,id);
     tx.update(c.source.ref,{operationId:id,...sourceEpoch});tx.update(c.target.ref,{operationId:id,...targetEpoch});tx.set(ref,next);return next.phase;
    }
    if(['PRESERVATION_COMMITTED','PRESERVATION_MERGE_COMPLETE','PRESERVATION_SOURCE_CLEANED','RELEASING_NON_OWNERS','NON_OWNER_RELEASE_COMPLETE','DONE'].includes(o.phase))return o.phase;
    const cursor=o.cursor!,n=cursor.pageIndex,seed=preservationSeed(id,o),pages=ref.collection('shoppingPreservation');
    if(n===0&&(cursor.count!==0||cursor.hash!==seed||cursor.lastId!==null))invalid();
    // Prior immutable page ties the durable cursor to its committed append.
    if(n){const prev=(await tx.get(pages.doc(preservationPageId(o,n-1)))).data();if(!prev||prev.chainHash!==cursor.hash||prev.entries?.at(-1)?.sourceId!==cursor.lastId||cursor.count!==(n-1)*10+prev.entries.length)invalid();}
    let q=c.source.ref.collection('shoppingItems').orderBy(FieldPath.documentId()).limit(10);if(cursor.lastId!==null)q=q.startAfter(cursor.lastId);
    const docs=await tx.get(q),pageRef=pages.doc(preservationPageId(o,n)),page=await tx.get(pageRef);
    if(o.phase==='SNAPSHOT_SHOPPING'){
     if(page.exists)invalid();
     if(docs.empty){const snapshot={version:1 as const,count:cursor.count,pages:n,hash:cursor.hash};tx.update(ref,{phase:'VERIFY_SHOPPING',shoppingSnapshot:snapshot,cursor:{pageIndex:0,count:0,hash:seed,lastId:null},updatedAt:now});return 'VERIFY_SHOPPING';}
     if(n&&cursor.count!==n*10)invalid();
     let chain=cursor.hash;const entries=docs.docs.map((doc,i)=>{const payload=addPayload(doc.data(),o),e={sourceId:doc.id,updateTime:doc.updateTime!,dataHash:sourceFingerprint(doc),addPayload:payload,addPayloadHash:digest(JSON.stringify(payload)),transferId:preservationChildId(o,n,i,doc.id)};chain=digest(JSON.stringify([chain,e.dataHash,e.addPayloadHash,e.transferId]));return e;});
     const value={version:1,operationId:id,pageIndex:n,sourceEpoch:o.sourceFence.epoch,targetEpoch:o.targetFence.epoch,entries,chainHash:chain,results:[]};readPreservationPage(value,o,n,cursor.hash,cursor.lastId);
     tx.create(pageRef,value);tx.update(ref,{cursor:{pageIndex:n+1,count:cursor.count+entries.length,hash:chain,lastId:entries.at(-1)!.sourceId},updatedAt:now});return 'SNAPSHOT_SHOPPING';
    }
    const snapshot=o.shoppingSnapshot!;
    if(n===snapshot.pages){
     if(!docs.empty||page.exists||cursor.count!==snapshot.count||cursor.hash!==snapshot.hash||(await tx.get(pages.count())).data().count!==snapshot.pages)invalid();
     tx.update(ref,{phase:'PRESERVATION_COMMITTED',cursor:null,preservationCommittedAt:now,updatedAt:now,lastOutcome:'forwardOnlyPreservation'});return 'PRESERVATION_COMMITTED';
    }
    if(n>snapshot.pages)invalid();const v=readPreservationPage(page.data(),o,n,cursor.hash,cursor.lastId);
    if(v.entries.length!==docs.size||docs.size!==Math.min(10,snapshot.count-cursor.count))invalid();
    for(let i=0;i<docs.size;i++){const doc=docs.docs[i]!,e=v.entries[i];if(doc.id!==e.sourceId||!doc.updateTime!.isEqual(e.updateTime)||sourceFingerprint(doc)!==e.dataHash||digest(JSON.stringify(addPayload(doc.data(),o)))!==e.addPayloadHash)invalid();}
    tx.update(ref,{cursor:{pageIndex:n+1,count:cursor.count+docs.size,hash:v.chainHash,lastId:v.entries.at(-1).sourceId},updatedAt:now});return 'VERIFY_SHOPPING';
   }catch(e){if(e instanceof Error&&['preservationIntegrity','snapshotUnavailable','invalidSnapshotValue','unsupportedSnapshotValue'].includes(e.message)){tx.update(ref,{status:'OPERATOR',nextAt:null,leaseId:null,leaseUntil:null,lastOutcome:'preservationIntegrity',updatedAt:this.clock()});return 'OPERATOR';}throw e;}
  });
 }
}
