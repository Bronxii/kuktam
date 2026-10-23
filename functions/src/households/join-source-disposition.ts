import { DocumentReference, Firestore, Timestamp, Transaction } from 'firebase-admin/firestore';
import { TransferOperation } from './join-transfer-contract';
import { digest, sourceFingerprint } from './join-snapshot';
import { readTransferPage, transferChildId, transferPageId, transferSeed } from './join-transfer-execution';

export const MAX_SOURCE_DISPOSITION_BLOCK=10;
export const cleanupChildId=(id:string,o:TransferOperation,n:number,i:number)=>digest(JSON.stringify(['join-source-disposition-v1',transferChildId(id,o,n,i)]));
const invalid=():never=>{throw new Error('transferIntegrity');};

/** Original manifest/results stay immutable. Only this bounded cleanup evidence
 * is appended by source disposition. A full page is one atomic deletion unit. */
function cleanupPage(raw:any,id:string,o:TransferOperation,n:number){
  if(!raw||typeof raw!=='object')invalid();
  const {cleanup,...manifest}=raw;
  const p=readTransferPage(manifest,id,o,n);
  if(p.results.length!==p.entries.length)invalid();
  if(cleanup!==undefined&&(!Array.isArray(cleanup)||cleanup.length!==p.entries.length))invalid();
  const evidence=cleanup??[];
  for(let i=0;i<evidence.length;i++){
    const c=evidence[i],e=p.entries[i];
    if(!c||Object.keys(c).sort().join(',')!=='childIndex,cleanupId,code,completedAt,dataHash,sourceId,transferId'||
      c.childIndex!==i||c.cleanupId!==cleanupChildId(id,o,n,i)||c.transferId!==transferChildId(id,o,n,i)||
      c.code!=='DELETED'||c.sourceId!==e.sourceId||c.dataHash!==e.dataHash||!(c.completedAt instanceof Timestamp)||
      c.completedAt.toMillis()<o.committedAt!.toMillis())invalid();
  }
  return {...p,cleanup:evidence};
}

/** Caller has freshly read committed JOIN authority, source fence and lease in
 * this same transaction. No family canonical writes and no fence/lock release. */
export async function disposeSource(db:Firestore,tx:Transaction,id:string,o:TransferOperation,now:Timestamp){
  if(o.phase!=='CLEAN_SOURCE'||!o.snapshot||!o.sourceFence||!o.committedAt)invalid();
  const snapshot=o.snapshot!,ref=db.doc(`familyOperations/${id}`),source=db.collection(`households/${o.sourceHouseholdId}/shoppingItems`);
  const n=o.cursor?.pageIndex??0,pages=Math.ceil(snapshot.count/MAX_SOURCE_DISPOSITION_BLOCK);
  if((o.cursor?.childOffset??0)!==0||n>pages)invalid();
  const prior=n?cleanupPage((await tx.get(ref.collection('transferJournal').doc(transferPageId(o,n-1)))).data(),id,o,n-1):null;
  if(prior&&prior.cleanup.length!==prior.entries.length)invalid();
  // A recreated already-disposed source document is corruption, never fresh work.
  if(prior){
    const refs:DocumentReference[]=prior.entries.map((e:any)=>source.doc(e.sourceId));
    if((await tx.getAll(...refs)).some(d=>d.exists))invalid();
  }
  if(n===pages){
    if((pages===0?transferSeed(id,o):prior.chainHash)!==snapshot.hash||(await tx.get(source.limit(1))).size!==0)invalid();
    tx.update(ref,{phase:'TRANSFER_COMPLETE',cursor:null,updatedAt:now,lastOutcome:'sourceDispositionComplete'});
    return 'TRANSFER_COMPLETE';
  }
  const pageRef=ref.collection('transferJournal').doc(transferPageId(o,n));
  const current=cleanupPage((await tx.get(pageRef)).data(),id,o,n);
  if(prior&&Buffer.compare(Buffer.from(prior.entries.at(-1).sourceId),Buffer.from(current.entries[0].sourceId))>=0)invalid();
  if(o.mode==='ADD'&&prior&&current.results[0].revision<=prior.results.at(-1).revision)invalid();
  let chain=prior?.chainHash??transferSeed(id,o);
  for(const e of current.entries)chain=digest(JSON.stringify([chain,e.dataHash,e.addPayloadHash]));
  if(chain!==current.chainHash||n===pages-1&&chain!==snapshot.hash)invalid();
  const refs:DocumentReference[]=current.entries.map((e:any)=>source.doc(e.sourceId));
  const documents=await tx.getAll(...refs);
  if(current.cleanup.length){
    // Durable recorded deletion is safe to reobserve. Never delete a replacement.
    if(documents.some(d=>d.exists))invalid();
  }else{
    // Validate the ENTIRE block before scheduling its first deletion.
    for(let i=0;i<documents.length;i++){
      const d=documents[i]!,e=current.entries[i];
      if(!d.exists||!d.updateTime?.isEqual(e.updateTime)||sourceFingerprint(d)!==e.dataHash)invalid();
    }
    const cleanup=current.entries.map((e:any,i:number)=>({childIndex:i,cleanupId:cleanupChildId(id,o,n,i),
      transferId:transferChildId(id,o,n,i),sourceId:e.sourceId,dataHash:e.dataHash,code:'DELETED',completedAt:now}));
    for(const d of documents)tx.delete(d.ref,{lastUpdateTime:d.updateTime!});
    tx.update(pageRef,{cleanup});
  }
  tx.update(ref,{cursor:{pageIndex:n+1,childOffset:0},updatedAt:now,lastOutcome:'sourceDispositionProgress'});
  // Completion is a separate bounded transaction proving the collection empty
  // after the final deletion commit. No read-after-write or speculative emptiness.
  return 'CLEAN_SOURCE';
}
