import {Firestore,Timestamp} from 'firebase-admin/firestore';
import {DissolutionPreservationStore} from './dissolution-preservation';
import {DissolutionMergeStore} from './dissolution-merge';
import {DissolutionSourceDispositionStore} from './dissolution-source-disposition';
import {DissolutionMemberReleaseStore} from './dissolution-member-release';
import {DissolutionFinalizationStore} from './dissolution-finalization';
import {FamilyJoinStore,readJoinOperation} from './family-join';
import {readJoinCapacity} from './join-capacity';
import {dissolutionId} from './dissolution-preparation';
/** Shared bounded forward driver. Admission policy belongs to the calling lifecycle. */
export class DissolutionLifecycleDriver {
 constructor(private readonly db:Firestore,private readonly clock=Timestamp.now){}
 async beforeAdmission(ownerUid:string,householdId:string){
  const id=dissolutionId(ownerUid,householdId),i={ownerUid,householdId};
   // A committed JOIN owns forward completion. Never steal its structural lock.
   const capDoc=await this.db.doc(`familyJoinCapacity/${i.householdId}`).get();
   let cap;try{cap=readJoinCapacity(capDoc.data());}catch{return 'OPERATOR';}
   if(cap.structuralOperationId&&cap.structuralOperationId!==id){
    const lock=await this.db.doc(`familyOperations/${cap.structuralOperationId}`).get();
    if(lock.get('kind')!=='JOIN'||lock.get('householdId')!==i.householdId||lock.get('ownerUid')!==i.ownerUid)return 'OPERATOR';
    let join;try{join=readJoinOperation(lock.data(),lock.id);}catch{return 'OPERATOR';}
    if(join.status==='OPERATOR')return 'OPERATOR';
    if(lock.get('committedAt')==null)return 'structuralConflict';
    await new FamilyJoinStore(this.db,this.clock).resume(lock.id);
    return 'committedJoinForwardCompletion';
   }
  return 'AVAILABLE';
 }
 async step(ownerUid:string,householdId:string){
  const id=dissolutionId(ownerUid,householdId),i={ownerUid,householdId},auth={uid:ownerUid},ref=this.db.doc(`familyOperations/${id}`),op=await ref.get();
  if(op.get('kind')!=='FAMILY_DISSOLUTION'||op.get('ownerUid')!==i.ownerUid||op.get('householdId')!==i.householdId)return 'OPERATOR';
  if(op.get('status')==='OPERATOR')return 'OPERATOR';
  const phase=op.get('phase');
  const engine=['PREPARED','SNAPSHOT_SHOPPING','VERIFY_SHOPPING'].includes(phase)?new DissolutionPreservationStore(this.db,this.clock):phase==='PRESERVATION_COMMITTED'?new DissolutionMergeStore(this.db,this.clock):phase==='PRESERVATION_MERGE_COMPLETE'?new DissolutionSourceDispositionStore(this.db,this.clock):['PRESERVATION_SOURCE_CLEANED','RELEASING_NON_OWNERS'].includes(phase)?new DissolutionMemberReleaseStore(this.db,this.clock):['NON_OWNER_RELEASE_COMPLETE','DONE'].includes(phase)?new DissolutionFinalizationStore(this.db,this.clock):null;
  if(!engine)return 'OPERATOR';
  try{const result=await engine.step(auth,i.householdId);return result;}
  catch(e){if(e instanceof Error&&e.message==='INVALID_ARGUMENT'&&(await ref.get()).get('phase')!==phase)return 'concurrentPhaseAdvance';throw e;}
 }
}
