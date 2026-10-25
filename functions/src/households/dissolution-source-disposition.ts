import {Firestore,Timestamp,DocumentReference} from 'firebase-admin/firestore';
import {authenticatedUid,AuthContext} from '../billing/account-binding';
import {MutationError,revision} from '../shopping/mutation-contract';
import {dissolutionId} from './dissolution-preparation';
import {DissolutionPreservationStore,Preservation,readPreservation,readPreservationPage,preservationPageId,preservationSeed} from './dissolution-preservation';
import {progress as readMergeProgress,journal as readMergeJournal,receiptSeed} from './dissolution-merge';
import {digest,sourceFingerprint} from './join-snapshot';

export const SOURCE_CLEANUP_BLOCK_SIZE=10;
export const preservationCleanupId=(transferId:string)=>digest(JSON.stringify(['preservation-source-cleanup-v1',transferId]));
const invalid=():never=>{throw new Error('sourceDispositionIntegrity');};
const exact=(v:any,keys:string)=>v&&typeof v==='object'&&!Array.isArray(v)&&Object.keys(v).sort().join(',')===keys;
const hash=(v:any)=>typeof v==='string'&&/^[a-f0-9]{64}$/.test(v);
const nat=(v:any)=>Number.isSafeInteger(v)&&v>=0;
const seed=(o:Preservation,mergeHash:string)=>digest(JSON.stringify(['source-disposition-v1',preservationSeed(o.structuralOperationId,o),o.shoppingSnapshot!.hash,mergeHash]));
const append=(h:string,r:any)=>digest(JSON.stringify([h,r.cleanupId,r.transferId,r.sourceId,r.code]));
type State={version:1;stage:'CHECK'|'DELETE'|'VERIFY'|'COMPLETE';pageIndex:number;count:number;lastId:string|null;sourceHash:string;mergeHash:string;cleanupHash:string;finalCleanupHash:string|null};
export function readState(raw:any,o:Preservation):State {
 const s=o.shoppingSnapshot!;
 if(!exact(raw,'cleanupHash,count,finalCleanupHash,lastId,mergeHash,pageIndex,sourceHash,stage,version')||raw.version!==1||!['CHECK','DELETE','VERIFY','COMPLETE'].includes(raw.stage)||!nat(raw.pageIndex)||raw.pageIndex>s.pages||raw.count!==Math.min(raw.pageIndex*SOURCE_CLEANUP_BLOCK_SIZE,s.count)||!hash(raw.sourceHash)||!hash(raw.mergeHash)||!hash(raw.cleanupHash)||!(raw.lastId===null||typeof raw.lastId==='string'&&raw.lastId.length>0&&!raw.lastId.includes('/'))||
  (raw.pageIndex===0)!==(raw.lastId===null)||(['CHECK','DELETE'].includes(raw.stage)?raw.finalCleanupHash!==null:!hash(raw.finalCleanupHash)))invalid();
 return raw;
}
function readCleanup(raw:any,o:Preservation,n:number,entries:any[],prior:string){
 if(!exact(raw,'hash,pageId,pageIndex,previousHash,results,version')||raw.version!==1||raw.pageIndex!==n||raw.pageId!==preservationPageId(o,n)||!hash(raw.previousHash)||raw.previousHash!==prior||!Array.isArray(raw.results)||raw.results.length!==entries.length)invalid();
 let h=prior;
 for(let i=0;i<entries.length;i++){
  const r=raw.results[i],e=entries[i];if(!exact(r,'cleanupId,code,sourceId,transferId')||r.transferId!==e?.transferId||r.sourceId!==e?.sourceId||r.cleanupId!==preservationCleanupId(e.transferId)||r.code!=='DELETED')invalid();h=append(h,r);
 }
 if(h!==raw.hash)invalid();return raw;
}
/** A bounded explicit server continuation. No worker lease can release the
 * structural lock. All deletes are selected from immutable proven snapshot IDs. */
export class DissolutionSourceDispositionStore {
 constructor(private readonly db:Firestore,private readonly clock=Timestamp.now){}
 async step(auth:AuthContext,householdId:string){
  const uid=authenticatedUid(auth);if(typeof householdId!=='string'||!/^[A-Za-z0-9_-]{1,128}$/.test(householdId))throw new Error('INVALID_ARGUMENT');
  if(process.env.K_SERVICE||process.env.FUNCTION_NAME||process.env.GCLOUD_PROJECT!=='demo-kuktam-local'||!/^(127\.0\.0\.1|localhost):[0-9]{1,5}$/.test(process.env.FIRESTORE_EMULATOR_HOST??''))throw new Error('FEATURE_DISABLED');
  const id=dissolutionId(uid,householdId),ref=this.db.doc(`familyOperations/${id}`),stateRef=ref.collection('preservationSourceCleanup').doc('state'),cleanup=ref.collection('preservationSourceCleanupJournal');
  return this.db.runTransaction(async tx=>{
   const raw=(await tx.get(ref)).data();if(!raw||raw.kind!=='FAMILY_DISSOLUTION'||raw.actorUid!==uid||raw.householdId!==householdId)throw new Error('NOT_FOUND');
   if(raw.status==='OPERATOR')return 'OPERATOR';
   if(!['PRESERVATION_MERGE_COMPLETE','PRESERVATION_SOURCE_CLEANED'].includes(raw.phase))throw new Error('INVALID_ARGUMENT');
   try{
    const o=readPreservation(raw,id),homes=await new DissolutionPreservationStore(this.db,this.clock).validate(tx,id,o),snapshot=o.shoppingSnapshot!,now=this.clock();
    const m=readMergeProgress((await tx.get(ref.collection('preservationMerge').doc('state'))).data(),o);
    if(m.stage!=='COMPLETE'||m.pageIndex!==snapshot.pages||m.count!==snapshot.count||m.sourceHash!==snapshot.hash||m.receiptHash!==m.finalReceiptHash||snapshot.count&&revision(homes.target.get('shoppingRevision'))!==m.sequence)invalid();
    const start={sourceHash:preservationSeed(id,o),mergeHash:receiptSeed(o),cleanupHash:seed(o,m.receiptHash),pageIndex:0,count:0,lastId:null};
    const stored=await tx.get(stateRef);
    if(!stored.exists){
     if(o.phase!=='PRESERVATION_MERGE_COMPLETE'||(await tx.get(cleanup.limit(1))).size)invalid();
          if(snapshot.count===0){
      if(snapshot.hash!==start.sourceHash||m.receiptHash!==start.mergeHash||(await tx.get(ref.collection('shoppingPreservation').limit(1))).size||(await tx.get(ref.collection('preservationMergeJournal').limit(1))).size||(await tx.get(homes.source.ref.collection('shoppingItems').limit(1))).size)invalid();
      tx.create(stateRef,{version:1,stage:'COMPLETE',...start,finalCleanupHash:start.cleanupHash});tx.update(ref,{phase:'PRESERVATION_SOURCE_CLEANED',updatedAt:now,lastOutcome:'preservationSourceCleaned'});return 'PRESERVATION_SOURCE_CLEANED';
     }
     tx.create(stateRef,{version:1,stage:'CHECK',...start,finalCleanupHash:null});return o.phase;
    }
    const p=readState(stored.data(),o),n=p.pageIndex;
    if(n===0&&(p.sourceHash!==start.sourceHash||p.mergeHash!==start.mergeHash||p.cleanupHash!==start.cleanupHash))invalid();
    if(o.phase==='PRESERVATION_SOURCE_CLEANED'){
     if(p.stage!=='COMPLETE'||n!==snapshot.pages||p.count!==snapshot.count||p.sourceHash!==snapshot.hash||p.mergeHash!==m.receiptHash||p.cleanupHash!==p.finalCleanupHash||(await tx.get(homes.source.ref.collection('shoppingItems').limit(1))).size)invalid();return o.phase;
    }
    if(p.stage==='COMPLETE')invalid();
    if(n===snapshot.pages){
     if(p.sourceHash!==snapshot.hash||p.mergeHash!==m.receiptHash||(await tx.get(ref.collection('shoppingPreservation').count())).data().count!==snapshot.pages||(await tx.get(ref.collection('preservationMergeJournal').count())).data().count!==snapshot.pages)invalid();
     if(p.stage==='CHECK'){
      if((await tx.get(cleanup.limit(1))).size||(await tx.get(homes.source.ref.collection('shoppingItems').count())).data().count!==snapshot.count)invalid();
      tx.update(stateRef,{stage:'DELETE',...start});return o.phase;
     }
     if((await tx.get(cleanup.count())).data().count!==snapshot.pages)invalid();
     if(p.stage==='DELETE'){tx.update(stateRef,{stage:'VERIFY',...start,finalCleanupHash:p.cleanupHash});return o.phase;}
     if(p.cleanupHash!==p.finalCleanupHash||(await tx.get(homes.source.ref.collection('shoppingItems').limit(1))).size)invalid();
     tx.update(stateRef,{stage:'COMPLETE'});tx.update(ref,{phase:'PRESERVATION_SOURCE_CLEANED',updatedAt:now,lastOutcome:'preservationSourceCleaned'});return 'PRESERVATION_SOURCE_CLEANED';
    }
    const pageId=preservationPageId(o,n),page=readPreservationPage((await tx.get(ref.collection('shoppingPreservation').doc(pageId))).data(),o,n,p.sourceHash,p.lastId);
    if(page.entries.length!==Math.min(SOURCE_CLEANUP_BLOCK_SIZE,snapshot.count-n*SOURCE_CLEANUP_BLOCK_SIZE)||n===snapshot.pages-1&&page.chainHash!==snapshot.hash)invalid();
    const merge=readMergeJournal((await tx.get(ref.collection('preservationMergeJournal').doc(pageId))).data(),o,n,page.entries,p.mergeHash,m.baseSequence);
    if(merge.results.length!==page.entries.length)invalid();
    const cr=cleanup.doc(pageId),record=await tx.get(cr);
    const refs:DocumentReference[]=page.entries.map((e:any)=>homes.source.ref.collection('shoppingItems').doc(e.sourceId));
    const docs=await tx.getAll(...refs);
    // Receipt destination verification never modifies the preserved target.
    for(const r of merge.results){const target=await tx.get(homes.target.ref.collection('shoppingItems').doc(r.itemId)),e=page.entries[r.childIndex];if(!target.exists||target.get('name')!==e.addPayload.name||target.get('unit')!==e.addPayload.unit||revision(target.get('revision'))<r.revision)invalid();}
    const next={pageIndex:n+1,count:p.count+page.entries.length,lastId:page.entries.at(-1).sourceId,sourceHash:page.chainHash,mergeHash:merge.hash};
    if(p.stage==='VERIFY'){
     const c=readCleanup(record.data(),o,n,page.entries,p.cleanupHash);if(docs.some(d=>d.exists))invalid();tx.update(stateRef,{...next,cleanupHash:c.hash});return o.phase;
    }
    if(record.exists)invalid();
    // Validate the WHOLE block before scheduling ANY delete or journal write.
    for(let i=0;i<docs.length;i++)if(!docs[i]!.exists||!docs[i]!.updateTime!.isEqual(page.entries[i].updateTime)||sourceFingerprint(docs[i]!)!==page.entries[i].dataHash)invalid();
    if(p.stage==='CHECK'){tx.update(stateRef,next);return o.phase;}
    if(n){
     const prev=(await tx.get(cleanup.doc(preservationPageId(o,n-1)))).data(),prevPage=(await tx.get(ref.collection('shoppingPreservation').doc(preservationPageId(o,n-1)))).data();
     if(!prev||!prevPage||!Array.isArray(prevPage.entries)||prevPage.entries.length!==SOURCE_CLEANUP_BLOCK_SIZE||prevPage.chainHash!==p.sourceHash||prevPage.entries.at(-1)?.sourceId!==p.lastId)invalid();
     const c=readCleanup(prev,o,n-1,prevPage!.entries,prev!.previousHash);if(c.hash!==p.cleanupHash)invalid();
    }
    let h=p.cleanupHash;const results=page.entries.map((e:any)=>{const r={cleanupId:preservationCleanupId(e.transferId),transferId:e.transferId,sourceId:e.sourceId,code:'DELETED'};h=append(h,r);return r;});
    for(const doc of docs)tx.delete(doc.ref,{lastUpdateTime:doc.updateTime!});
    tx.create(cr,{version:1,pageId,pageIndex:n,previousHash:p.cleanupHash,hash:h,results});tx.update(stateRef,{...next,cleanupHash:h});return o.phase;
   }catch(e){if(e instanceof MutationError||e instanceof Error&&['sourceDispositionIntegrity','preservationMergeIntegrity','preservationIntegrity','snapshotUnavailable','invalidSnapshotValue','unsupportedSnapshotValue'].includes(e.message)){
    tx.update(ref,{status:'OPERATOR',updatedAt:this.clock(),lastOutcome:'preservationSourceIntegrity'});return 'OPERATOR';}throw e;}
  });
 }
}
