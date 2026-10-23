import { Firestore, Timestamp, Transaction } from 'firebase-admin/firestore';
import { TransferOperation } from './join-transfer-contract';
import { cleanupPage } from './join-source-disposition';
import { transferPageId, transferSeed } from './join-transfer-execution';
import { digest } from './join-snapshot';

/** Read-only proof in the activation transaction, before ANY activation writes.
 * Pages stay bounded at ten children; only a digest/order/revision accumulator
 * is kept across pages. No source reconstruction or shopping effect is allowed. */
export async function verifyActivationEvidence(db:Firestore,tx:Transaction,id:string,o:TransferOperation,now:Timestamp){
  const invalid=():never=>{throw new Error('transferIntegrity');};
  if(o.phase!=='TRANSFER_COMPLETE'||!o.committedAt||!o.snapshot||!o.sourceFence||o.cursor!==null)invalid();
  let chain=transferSeed(id,o),previousId:string|null=null,previousRevision=0;
  for(let n=0;n<Math.ceil(o.snapshot!.count/10);n++){
    const p=cleanupPage((await tx.get(db.doc(`familyOperations/${id}/transferJournal/${transferPageId(o,n)}`))).data(),id,o,n);
    if(p.cleanup.length!==p.entries.length)invalid();
    for(let i=0;i<p.entries.length;i++){
      const e=p.entries[i],r=p.results[i];
      if(previousId!==null&&Buffer.compare(Buffer.from(previousId),Buffer.from(e.sourceId))>=0||p.cleanup[i].completedAt.toMillis()>now.toMillis())invalid();
      previousId=e.sourceId;chain=digest(JSON.stringify([chain,e.dataHash,e.addPayloadHash]));
      if(o.mode==='ADD'){if(r.revision<=previousRevision)invalid();previousRevision=r.revision;}
    }
    if(chain!==p.chainHash)invalid();
  }
  if(chain!==o.snapshot!.hash||(await tx.get(db.collection(`households/${o.sourceHouseholdId}/shoppingItems`).limit(1))).size)invalid();
  return previousRevision;
}
