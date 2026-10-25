import {Firestore,Timestamp} from 'firebase-admin/firestore';
import {authenticatedUid,AuthContext} from '../billing/account-binding';
import {readAccount} from '../accounts/account-lifecycle';
import {MutationError,epochPattern,revision} from '../shopping/mutation-contract';
import {dissolutionId,Participant} from './dissolution-preparation';
import {DissolutionPreservationStore,readPreservation,Preservation} from './dissolution-preservation';
import {progress as readMergeProgress} from './dissolution-merge';
import {readState as readCleanupState} from './dissolution-source-disposition';
import {commitMemberExit} from './member-leave';
import {validatePrivateRoot} from './household-contract';
import {digest} from './join-snapshot';

const invalid=():never=>{throw new Error('participantReleaseIntegrity');};
const accountState=(v:unknown)=>{try{return readAccount(v).state;}catch{return invalid();}};
const exact=(v:any,keys:string)=>v&&typeof v==='object'&&!Array.isArray(v)&&Object.keys(v).sort().join(',')===keys;
export const participantReleaseId=(o:Preservation,p:Participant)=>digest(JSON.stringify(['dissolution-member-release-v1',o.structuralOperationId,o.snapshotHash,p.uid]));
const seed=(o:Preservation)=>digest(JSON.stringify(['dissolution-release-progress-v1',o.structuralOperationId,o.snapshotHash]));
const append=(h:string,r:any)=>digest(JSON.stringify([h,r.releaseId,r.uid,r.householdId,r.privateHouseholdId,r.epoch,r.completedAt.seconds,r.completedAt.nanoseconds,r.result]));

/** Local explicit continuation. At most one member exits per atomic transaction.
 * The immutable participant set remains the only authority for release. */
export class DissolutionMemberReleaseStore {
 constructor(private readonly db:Firestore,private readonly clock=Timestamp.now){}
 async step(auth:AuthContext,householdId:string){
  const uid=authenticatedUid(auth);
  if(typeof householdId!=='string'||!/^[A-Za-z0-9_-]{1,128}$/.test(householdId))throw new Error('INVALID_ARGUMENT');
  if(process.env.K_SERVICE||process.env.FUNCTION_NAME||process.env.GCLOUD_PROJECT!=='demo-kuktam-local'||!/^(127\.0\.0\.1|localhost):[0-9]{1,5}$/.test(process.env.FIRESTORE_EMULATOR_HOST??''))throw new Error('FEATURE_DISABLED');
  const id=dissolutionId(uid,householdId),ref=this.db.doc(`familyOperations/${id}`),state=ref.collection('participantRelease').doc('state'),journal=ref.collection('participantReleaseJournal');
  return this.db.runTransaction(async tx=>{
   const raw=(await tx.get(ref)).data();
   if(!raw||raw.kind!=='FAMILY_DISSOLUTION'||raw.actorUid!==uid||raw.householdId!==householdId)throw new Error('NOT_FOUND');
   if(raw.status==='OPERATOR')return 'OPERATOR';
   if(!['PRESERVATION_SOURCE_CLEANED','RELEASING_NON_OWNERS','NON_OWNER_RELEASE_COMPLETE'].includes(raw.phase))throw new Error('INVALID_ARGUMENT');
   try{
    const o=readPreservation(raw,id),participants=o.participants.filter(p=>p.role==='member'),stored=await tx.get(state),records=await tx.get(journal.limit(8));
    const progress=stored.exists?stored.data()!:{version:1,snapshotHash:o.snapshotHash,cursor:0,hash:seed(o)};
    if(!exact(progress,'cursor,hash,snapshotHash,version')||progress.version!==1||progress.snapshotHash!==o.snapshotHash||!Number.isSafeInteger(progress.cursor)||progress.cursor<0||progress.cursor>participants.length||records.size!==progress.cursor||!stored.exists&&o.phase!=='PRESERVATION_SOURCE_CLEANED'||o.phase==='PRESERVATION_SOURCE_CLEANED'&&progress.cursor!==0)invalid();
    let chain=seed(o);const released=new Set<string>();
    for(let i=0;i<progress.cursor;i++){
     const p=participants[i]!,rid=participantReleaseId(o,p),record=records.docs.find(d=>d.id===rid),r=record?.data();
     if(!exact(r,'completedAt,epoch,householdId,privateHouseholdId,releaseId,result,snapshotHash,uid,version')||r!.version!==1||r!.snapshotHash!==o.snapshotHash||r!.releaseId!==rid||r!.uid!==p.uid||r!.householdId!==o.householdId||r!.privateHouseholdId!==p.privateHouseholdId||r!.result!=='PRIVATE'||typeof r!.epoch!=='string'||!epochPattern.test(r!.epoch)||!(r!.completedAt instanceof Timestamp))invalid();
     chain=append(chain,r);released.add(p.uid);
     // Completed receipts are historical evidence. Fresh private writes/epoch
     // refresh and private-account deletion must not stall later participants.
     const user=await tx.get(this.db.doc(`users/${p.uid}`)),deletion=await tx.get(this.db.doc(`accountDeletions/${p.uid}`)),index=await tx.get(this.db.doc(`familyMemberships/${p.uid}`));
     if(index.exists)invalid();
     if(deletion.exists){if(accountState((await tx.get(this.db.doc(`accountLifecycle/${p.uid}`))).data())==='ACTIVE')invalid();}
     else {
      if(user.get('activeHouseholdId')!==p.privateHouseholdId||user.get('familyHouseholdId')!==null||user.get('privateHouseholdId')!==p.privateHouseholdId)invalid();
      const home=await tx.get(this.db.doc(`households/${p.privateHouseholdId}`)),member=await tx.get(home.ref.collection('members').doc(p.uid));
      if(!home.exists||home.get('schemaVersion')!==2||!home.get('createdAt')?.isEqual(p.privateCreatedAt)||member.get('role')!=='owner')invalid();
      try{validatePrivateRoot(home.data()!,p.uid);}catch{invalid();}
     }
    }
    if(chain!==progress.hash)invalid();
    const homes=await new DissolutionPreservationStore(this.db,this.clock).validate(tx,id,o,released);
    const merge=readMergeProgress((await tx.get(ref.collection('preservationMerge').doc('state'))).data(),o),clean=readCleanupState((await tx.get(ref.collection('preservationSourceCleanup').doc('state'))).data(),o),snapshot=o.shoppingSnapshot!;
    if(merge.stage!=='COMPLETE'||merge.count!==snapshot.count||merge.pageIndex!==snapshot.pages||merge.sourceHash!==snapshot.hash||merge.receiptHash!==merge.finalReceiptHash||snapshot.count&&revision(homes.target.get('shoppingRevision'))!==merge.sequence||clean.stage!=='COMPLETE'||clean.pageIndex!==snapshot.pages||clean.count!==snapshot.count||clean.sourceHash!==snapshot.hash||clean.mergeHash!==merge.receiptHash||clean.cleanupHash!==clean.finalCleanupHash||(await tx.get(homes.source.ref.collection('shoppingItems').limit(1))).size)invalid();
    if(o.phase==='NON_OWNER_RELEASE_COMPLETE'){if(progress.cursor!==participants.length)invalid();return o.phase;}
    const now=this.clock();
    if(progress.cursor===participants.length){
     if(!stored.exists)tx.create(state,progress);
     tx.update(ref,{phase:'NON_OWNER_RELEASE_COMPLETE',updatedAt:now,lastOutcome:'nonOwnerReleaseComplete'});return 'NON_OWNER_RELEASE_COMPLETE';
    }
    const p=participants[progress.cursor]!,account=await tx.get(this.db.doc(`accountLifecycle/${p.uid}`)),deletion=await tx.get(this.db.doc(`accountDeletions/${p.uid}`));
    // No admission/Pro/revoke revalidation: committed operation owns completion.
    // A structurally impossible prior deletion is operator repair, not rollback.
    if(!account.exists||accountState(account.data())!=='ACTIVE'||deletion.exists)invalid();
    const rid=participantReleaseId(o,p);
    const epoch=commitMemberExit(tx,{member:homes.source.ref.collection('members').doc(p.uid),index:this.db.doc(`familyMemberships/${p.uid}`),user:this.db.doc(`users/${p.uid}`),fallback:this.db.doc(`households/${p.privateHouseholdId}`)},now);
    const result={version:1,snapshotHash:o.snapshotHash,releaseId:rid,uid:p.uid,householdId:o.householdId,privateHouseholdId:p.privateHouseholdId,epoch:epoch.shoppingEpoch,completedAt:now,result:'PRIVATE'};
    tx.create(journal.doc(rid),result);tx.set(state,{...progress,cursor:progress.cursor+1,hash:append(chain,result)});
    tx.update(ref,{phase:'RELEASING_NON_OWNERS',updatedAt:now,lastOutcome:'participantReleased'});return 'RELEASING_NON_OWNERS';
   }catch(e){if(e instanceof MutationError||e instanceof Error&&['participantReleaseIntegrity','preservationIntegrity','preservationMergeIntegrity','sourceDispositionIntegrity','invalidAccountLifecycle'].includes(e.message)){
    tx.update(ref,{status:'OPERATOR',updatedAt:this.clock(),lastOutcome:'participantReleaseIntegrity'});return 'OPERATOR';}throw e;}
  });
 }
}
