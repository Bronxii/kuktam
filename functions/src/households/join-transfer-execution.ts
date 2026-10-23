import { Firestore, Timestamp, Transaction, DocumentSnapshot, DocumentReference } from 'firebase-admin/firestore';
import { ShoppingMutationStore, advanceShoppingEpoch } from '../shopping/mutation-store';
import { Child, epochExpiry, MutationError, parseRequest, revision, safeId } from '../shopping/mutation-contract';
import { TransferOperation, hashValue } from './join-transfer-contract';
import { digest, sourceFingerprint } from './join-snapshot';

export const transferSeed=(id:string,o:TransferOperation)=>digest(JSON.stringify(['join-source-v1',id,o.inviteId,o.actorUid,o.sourceHouseholdId,o.householdId,o.mode,o.sourceFence!.epoch]));
export const transferPageId=(o:TransferOperation,n:number)=>digest(`${o.inviteId}:${o.sourceFence!.epoch}:${n}`);
export const transferChildId=(id:string,o:TransferOperation,page:number,child:number)=>digest(JSON.stringify([id,o.inviteId,o.sourceFence!.epoch,page,child]));
const invariant=():never=>{throw new Error('transferIntegrity');};
const exact=(v:any,keys:string)=>!!v&&typeof v==='object'&&Object.keys(v).sort().join(',')===keys;

/** Validate a bounded manifest page and its append-only terminal prefix. */
function page(raw:any,id:string,o:TransferOperation,n:number){
  const length=Math.min(10,o.snapshot!.count-n*10);
  if(!exact(raw,'chainHash,entries,fenceEpoch,inviteId,pageIndex,results,version')||raw.version!==1||raw.inviteId!==o.inviteId||
    raw.fenceEpoch!==o.sourceFence!.epoch||raw.pageIndex!==n||!hashValue(raw.chainHash)||!Array.isArray(raw.entries)||
    length<1||raw.entries.length!==length||!Array.isArray(raw.results)||raw.results.length>length)invariant();
  for(let i=0;i<length;i++){
    const e=raw.entries[i];
    if(!exact(e,'addPayloadHash,dataHash,sourceId,updateTime')||typeof e.sourceId!=='string'||!e.sourceId||e.sourceId.includes('/')||
      !(e.updateTime instanceof Timestamp)||!hashValue(e.dataHash)||(o.mode==='ADD'?!hashValue(e.addPayloadHash):e.addPayloadHash!==null)||
      i>0&&Buffer.compare(Buffer.from(raw.entries[i-1].sourceId),Buffer.from(e.sourceId))>=0)invariant();
  }
  for(let i=0;i<raw.results.length;i++){
    const r=raw.results[i];
    if(!r||typeof r!=='object'||r.childIndex!==i||r.transferId!==transferChildId(id,o,n,i))invariant();
    if(o.mode==='DELETE'){
      if(!exact(r,'childIndex,code,transferId')||r.code!=='NO_TRANSFER')invariant();
    }else if(!exact(r,'childIndex,code,created,epoch,itemId,revision,transferId')||r.code!=='APPLIED'||!safeId(r.itemId)||
      !Number.isSafeInteger(r.revision)||r.revision<1||typeof r.created!=='boolean'||typeof r.epoch!=='string'||
      !Number.isFinite(epochExpiry(r.epoch))||i>0&&r.revision<=raw.results[i-1].revision)invariant();
  }
  return raw;
}

/** Called only after the JOIN's committed authority/lease has been read in this
 * same transaction. Never submits an ordinary command as the invitee or owner.
 * Reads frozen payloads solely to verify/recover the exact manifest content. */
export async function executeTransfer(db:Firestore,tx:Transaction,id:string,o:TransferOperation,now:Timestamp,home:DocumentSnapshot){
  const ref=db.doc(`familyOperations/${id}`),n=o.cursor?.pageIndex??0,offset=o.cursor?.childOffset??0;
  const finish=()=>{tx.update(ref,{phase:'CLEAN_SOURCE',cursor:null,updatedAt:now,lastOutcome:'transferComplete'});return 'CLEAN_SOURCE';};
  if(!o.snapshot||!o.sourceFence||o.phase!=='COMMITTED_TRANSFER')invariant();
  if(o.snapshot!.count===0){
    if(o.cursor!==null||o.snapshot!.hash!==transferSeed(id,o)||(await tx.get(db.collection(`households/${o.sourceHouseholdId}/shoppingItems`).limit(1))).size)invariant();
    return finish();
  }
  if(n>=Math.ceil(o.snapshot!.count/10))invariant();
  const currentRef=ref.collection('transferJournal').doc(transferPageId(o,n));
  const current=page((await tx.get(currentRef)).data(),id,o,n);
  const previous=n?page((await tx.get(ref.collection('transferJournal').doc(transferPageId(o,n-1)))).data(),id,o,n-1):null;
  if(current.results.length!==offset||offset>=current.entries.length||previous&&previous.results.length!==previous.entries.length)invariant();
  if(previous&&Buffer.compare(Buffer.from(previous.entries.at(-1).sourceId),Buffer.from(current.entries[0].sourceId))>=0)invariant();
  let chain=previous?.chainHash??transferSeed(id,o);
  for(const e of current.entries)chain=digest(JSON.stringify([chain,e.dataHash,e.addPayloadHash]));
  const lastPage=(n+1)*10>=o.snapshot!.count;
  if(chain!==current.chainHash||lastPage&&chain!==o.snapshot!.hash)invariant();
  const sourceRefs:DocumentReference[]=current.entries.map((e:any)=>db.doc(`households/${o.sourceHouseholdId}/shoppingItems/${e.sourceId}`));
  const sources=await tx.getAll(...sourceRefs);
  const children:Extract<Child,{type:'ADD'}>[]=[];
  for(let i=0;i<sources.length;i++){
    const d=sources[i]!,e=current.entries[i];
    if(!d.exists||!d.updateTime?.isEqual(e.updateTime)||sourceFingerprint(d)!==e.dataHash)invariant();
    if(o.mode==='ADD'){
      const mutationId=o.sourceFence!.epoch+'_'+'0'.repeat(64);
      const parsed=parseRequest({schemaVersion:1,mutationId,actorUid:o.actorUid,householdId:o.sourceHouseholdId,epoch:o.sourceFence!.epoch,kind:'ADD',
        payloadJson:JSON.stringify({type:'ADD',name:d.get('name'),quantity:d.get('quantity'),unit:d.get('unit')}),submittedAt:now},o.actorUid,mutationId);
      if(digest(JSON.stringify(parsed.children[0]))!==e.addPayloadHash)invariant();
      children.push(parsed.children[0] as Extract<Child,{type:'ADD'}>);
    }
  }
  if(lastPage&&(await tx.get(db.collection(`households/${o.sourceHouseholdId}/shoppingItems`).count())).data().count!==o.snapshot!.count)invariant();
  let results:any[];
  if(o.mode==='DELETE')results=current.entries.slice(offset).map((_:unknown,i:number)=>({childIndex:offset+i,transferId:transferChildId(id,o,n,offset+i),code:'NO_TRANSFER'}));
  else{
    const epoch=home.get('shoppingEpoch'),expires=home.get('shoppingEpochExpiresAt');
    const prior=current.results.at(-1)??previous?.results.at(-1);
    // Structural changes may not replace a live epoch while this lock is held.
    // Natural expiry is safe: every block still reads the live root transactionally.
    if(prior&&prior.epoch!==epoch&&epochExpiry(prior.epoch)>now.toMillis())invariant();
    if(epoch!==undefined&&(!(expires instanceof Timestamp)||expires.toMillis()!==epochExpiry(epoch)))invariant();
    if(epoch===undefined||epochExpiry(epoch)<=now.toMillis()||home.get('shoppingRevision')===undefined){
      const max=await tx.get(home.ref.collection('shoppingItems').orderBy('revision','desc').limit(1));
      const seq=Math.max(revision(home.get('shoppingRevision')),max.empty?0:revision(max.docs[0]!.get('revision')));
      tx.update(home.ref,{...(epoch===undefined||epochExpiry(epoch)<=now.toMillis()?advanceShoppingEpoch(now):{}),shoppingRevision:seq});
      return 'COMMITTED_TRANSFER';
    }
    if(prior&&revision(home.get('shoppingRevision'))<prior.revision)invariant();
    const applied=await new ShoppingMutationStore(db).applyAddBlock(tx,home,children.slice(offset),now);
    results=applied.map((r,i)=>({...r,childIndex:offset+i,transferId:transferChildId(id,o,n,offset+i),epoch}));
    // The existing primitive commits a valid prefix on semantic failure. Retain
    // every outcome atomically and park for repair; never compensate that prefix.
    if(applied.some(r=>r.code!=='APPLIED')){
      tx.update(currentRef,{results:[...current.results,...results]});
      tx.update(ref,{status:'OPERATOR',nextAt:null,leaseId:null,leaseUntil:null,updatedAt:now,lastOutcome:'transferSemanticFailure'});
      return 'OPERATOR';
    }
  }
  const all=[...current.results,...results];
  tx.update(currentRef,{results:all});
  if(lastPage&&all.length===current.entries.length)return finish();
  tx.update(ref,{cursor:all.length===current.entries.length?{pageIndex:n+1,childOffset:0}:{pageIndex:n,childOffset:all.length},updatedAt:now,lastOutcome:'transferProgress'});
  return 'COMMITTED_TRANSFER';
}

export function transferIntegrityError(e:unknown){
  return e instanceof MutationError||e instanceof Error&&['transferIntegrity','invalidSnapshotValue','unsupportedSnapshotValue','snapshotUnavailable'].includes(e.message);
}
