import {Firestore,Timestamp,DocumentReference} from 'firebase-admin/firestore';
import {authenticatedUid,AuthContext} from '../billing/account-binding';
import {ShoppingMutationStore} from '../shopping/mutation-store';
import {MutationError,revision,safeId} from '../shopping/mutation-contract';
import {dissolutionId} from './dissolution-preparation';
import {DissolutionPreservationStore,Preservation,readPreservation,readPreservationPage,preservationPageId,preservationSeed} from './dissolution-preservation';
import {digest,sourceFingerprint} from './join-snapshot';

const fail=():never=>{throw new Error('preservationMergeIntegrity');};
const exact=(v:any,keys:string)=>v&&typeof v==='object'&&!Array.isArray(v)&&Object.keys(v).sort().join(',')===keys;
const nat=(v:any)=>Number.isSafeInteger(v)&&v>=0;
const hash=(v:any)=>typeof v==='string'&&/^[a-f0-9]{64}$/.test(v);
export const receiptSeed=(o:Preservation)=>digest(JSON.stringify(['preservation-merge-v1',preservationSeed(o.structuralOperationId,o),o.shoppingSnapshot!.version,o.shoppingSnapshot!.count,o.shoppingSnapshot!.pages,o.shoppingSnapshot!.hash]));
const append=(h:string,r:any)=>digest(JSON.stringify([h,r.transferId,r.childIndex,r.code,r.itemId,r.revision,r.created,r.epoch]));
type Progress={version:1;stage:'APPLY'|'VERIFY'|'COMPLETE';pageIndex:number;offset:number;count:number;sourceHash:string;lastId:string|null;receiptHash:string;finalReceiptHash:string|null;sequence:number;baseSequence:number;blocks:number};
export function progress(raw:any,o:Preservation):Progress {
 if(!exact(raw,'baseSequence,blocks,count,finalReceiptHash,lastId,offset,pageIndex,receiptHash,sequence,sourceHash,stage,version')||raw.version!==1||!['APPLY','VERIFY','COMPLETE'].includes(raw.stage)||
  !['pageIndex','offset','count','sequence','baseSequence','blocks'].every(k=>nat(raw[k]))||raw.offset>=10||raw.pageIndex>o.shoppingSnapshot!.pages||raw.count>o.shoppingSnapshot!.count||raw.count!==raw.pageIndex*10+raw.offset&&raw.count!==o.shoppingSnapshot!.count||
  raw.sequence<raw.baseSequence||!hash(raw.sourceHash)||!hash(raw.receiptHash)||!(raw.lastId===null||typeof raw.lastId==='string'&&raw.lastId.length>0&&!raw.lastId.includes('/'))||!(raw.finalReceiptHash===null||hash(raw.finalReceiptHash))||
  raw.stage==='APPLY'&&(raw.finalReceiptHash!==null||raw.sequence!==raw.baseSequence+raw.count)||raw.stage!=='APPLY'&&(raw.offset!==0||!hash(raw.finalReceiptHash)||raw.sequence!==raw.baseSequence+o.shoppingSnapshot!.count))fail();
 return raw;
}
export function journal(raw:any,o:Preservation,n:number,entries:any[],priorHash:string,base:number){
 if(!exact(raw,'hash,pageId,pageIndex,previousHash,results,version')||raw.version!==1||raw.previousHash!==priorHash||!hash(priorHash)||raw.pageIndex!==n||raw.pageId!==preservationPageId(o,n)||!Array.isArray(raw.results)||raw.results.length>entries.length)fail();
 let h=priorHash;
 for(let i=0;i<raw.results.length;i++){
  const r=raw.results[i];if(!exact(r,'childIndex,code,created,epoch,itemId,revision,transferId')||r.childIndex!==i||r.transferId!==entries[i]?.transferId||r.code!=='APPLIED'||!safeId(r.itemId)||typeof r.created!=='boolean'||r.epoch!==o.targetFence.epoch||r.revision!==base+n*10+i+1)fail();h=append(h,r);
 }
 if(h!==raw.hash)fail();return raw;
}
/** Explicit local continuation. Authority, S1D effects, receipts and cursor share
 * one transaction. Durable structural ownership never expires with a worker. */
export class DissolutionMergeStore {
 constructor(private readonly db:Firestore,private readonly clock=Timestamp.now){}
 async step(auth:AuthContext,householdId:string){
  const uid=authenticatedUid(auth);
  if(typeof householdId!=='string'||!/^[A-Za-z0-9_-]{1,128}$/.test(householdId))throw new Error('INVALID_ARGUMENT');
  if(process.env.K_SERVICE||process.env.FUNCTION_NAME||process.env.GCLOUD_PROJECT!=='demo-kuktam-local'||!/^(127\.0\.0\.1|localhost):[0-9]{1,5}$/.test(process.env.FIRESTORE_EMULATOR_HOST??''))throw new Error('FEATURE_DISABLED');
  const id=dissolutionId(uid,householdId),ref=this.db.doc(`familyOperations/${id}`),state=ref.collection('preservationMerge').doc('state'),journals=ref.collection('preservationMergeJournal');
  return this.db.runTransaction(async tx=>{
   const raw=(await tx.get(ref)).data();if(!raw||raw.actorUid!==uid||raw.householdId!==householdId||raw.kind!=='FAMILY_DISSOLUTION')throw new Error('NOT_FOUND');
   if(raw.status==='OPERATOR')return 'OPERATOR';
   // A premature call must not park a valid 5C2A operation.
   if(!['PRESERVATION_COMMITTED','PRESERVATION_MERGE_COMPLETE','PRESERVATION_SOURCE_CLEANED'].includes(raw.phase))throw new Error('INVALID_ARGUMENT');
   try{
    const o=readPreservation(raw,id),homes=await new DissolutionPreservationStore(this.db,this.clock).validate(tx,id,o),now=this.clock(),stored=await tx.get(state),seed=receiptSeed(o),sourceSeed=preservationSeed(id,o),snapshot=o.shoppingSnapshot!;
    if(!stored.exists){
     if(o.phase!=='PRESERVATION_COMMITTED'||(await tx.get(journals.limit(1))).size)fail();
     const max=await tx.get(homes.target.ref.collection('shoppingItems').orderBy('revision','desc').limit(1));
     const seq=Math.max(revision(homes.target.get('shoppingRevision')),max.empty?0:revision(max.docs[0]!.get('revision')));
     const p:Progress={version:1,stage:'APPLY',pageIndex:0,offset:0,count:0,sourceHash:sourceSeed,lastId:null,receiptHash:seed,finalReceiptHash:null,sequence:seq,baseSequence:seq,blocks:0};
     if(snapshot.count&&homes.target.get('shoppingRevision')!==seq)tx.update(homes.target.ref,{shoppingRevision:seq});
     tx.create(state,p);return 'PRESERVATION_COMMITTED';
    }
    const p=progress(stored.data(),o);
    if(snapshot.count&&revision(homes.target.get('shoppingRevision'))!==p.sequence)fail();
    if(['PRESERVATION_MERGE_COMPLETE','PRESERVATION_SOURCE_CLEANED'].includes(o.phase)){
     if(p.stage!=='COMPLETE'||p.count!==snapshot.count||p.pageIndex!==snapshot.pages||p.sourceHash!==snapshot.hash||p.receiptHash!==p.finalReceiptHash)fail();return o.phase;
    }
    if(p.stage==='COMPLETE')fail();
    const n=p.pageIndex;
    if(n===snapshot.pages){
     if(p.offset!==0||p.count!==snapshot.count||p.sourceHash!==snapshot.hash||(await tx.get(journals.count())).data().count!==snapshot.pages||(await tx.get(ref.collection('shoppingPreservation').count())).data().count!==snapshot.pages)fail();
     if(p.stage==='APPLY'){
      tx.update(state,{stage:'VERIFY',pageIndex:0,offset:0,count:0,sourceHash:sourceSeed,lastId:null,finalReceiptHash:p.receiptHash,receiptHash:seed});return 'PRESERVATION_COMMITTED';
     }
     if(p.receiptHash!==p.finalReceiptHash||(await tx.get(homes.source.ref.collection('shoppingItems').count())).data().count!==snapshot.count)fail();
     tx.update(state,{stage:'COMPLETE'});tx.update(ref,{phase:'PRESERVATION_MERGE_COMPLETE',updatedAt:now,lastOutcome:'preservationMergeComplete'});return 'PRESERVATION_MERGE_COMPLETE';
    }
    if(n===0&&(p.sourceHash!==sourceSeed||p.lastId!==null)||p.count!==n*10+p.offset)fail();
    const pageId=preservationPageId(o,n),page=readPreservationPage((await tx.get(ref.collection('shoppingPreservation').doc(pageId))).data(),o,n,p.sourceHash,p.lastId);
    if(page.entries.length!==Math.min(10,snapshot.count-n*10)||n===snapshot.pages-1&&page.chainHash!==snapshot.hash)fail();
    let prior=seed;
    if(n){
     const previous=(await tx.get(journals.doc(preservationPageId(o,n-1)))).data();
          if(!previous||previous.results?.length!==10||!hash(previous.hash))fail();
     const previousPage=(await tx.get(ref.collection('shoppingPreservation').doc(preservationPageId(o,n-1)))).data();
          if(!previousPage||!Array.isArray(previousPage.entries)||previousPage.entries.length!==10||previousPage.chainHash!==p.sourceHash||previousPage.entries.at(-1)?.sourceId!==p.lastId)fail();
     journal(previous,o,n-1,previousPage!.entries,previous!.previousHash,p.baseSequence);
     prior=previous!.hash;
    }
    const jr=journals.doc(pageId),jd=await tx.get(jr);
    const j=jd.exists?journal(jd.data(),o,n,page.entries,prior,p.baseSequence):{version:1,pageId,pageIndex:n,previousHash:prior,results:[],hash:prior};
    if(p.stage==='APPLY'&&(j.results.length!==p.offset||j.hash!==p.receiptHash)||p.stage==='VERIFY'&&(j.results.length!==page.entries.length||prior!==p.receiptHash))fail();
    // The immutable snapshot supplies deltas; live source reads are proof checks
    // only, never payload reconstruction or automatic snapshot repair.
    const sourceRefs:DocumentReference[]=page.entries.map((e:any)=>homes.source.ref.collection('shoppingItems').doc(e.sourceId));
    const sources=await tx.getAll(...sourceRefs);
    for(let i=0;i<sources.length;i++)if(!sources[i]!.exists||sourceFingerprint(sources[i]!)!==page.entries[i].dataHash||!sources[i]!.updateTime!.isEqual(page.entries[i].updateTime))fail();
    if(p.stage==='VERIFY'){
     for(const r of j.results){const target=await tx.get(homes.target.ref.collection('shoppingItems').doc(r.itemId)),e=page.entries[r.childIndex];if(!target.exists||target.get('name')!==e.addPayload.name||target.get('unit')!==e.addPayload.unit||revision(target.get('revision'))<r.revision)fail();}
     tx.update(state,{pageIndex:n+1,count:p.count+page.entries.length,sourceHash:page.chainHash,lastId:page.entries.at(-1).sourceId,receiptHash:j.hash});return 'PRESERVATION_COMMITTED';
    }
    // All reads above precede the primitive's writes. Preserve its bounded legacy
    // single-child fallback and valid-prefix terminal-error semantics.
    const applied=await new ShoppingMutationStore(this.db).applyAddBlock(tx,homes.target,page.entries.slice(p.offset).map((e:any)=>e.addPayload),now);
    const results=applied.map((r,i)=>({...r,childIndex:p.offset+i,transferId:page.entries[p.offset+i].transferId,epoch:o.targetFence.epoch}));
    let h=j.hash;for(const r of results)h=append(h,r);
    tx.set(jr,{...j,results:[...j.results,...results],hash:h});
    if(applied.some(r=>r.code!=='APPLIED')){tx.update(ref,{status:'OPERATOR',lastOutcome:'preservationMergeSemanticFailure',updatedAt:now});return 'OPERATOR';}
    const offset=p.offset+results.length,done=offset===page.entries.length;
    tx.update(state,{pageIndex:done?n+1:n,offset:done?0:offset,count:p.count+results.length,sourceHash:done?page.chainHash:p.sourceHash,lastId:done?page.entries.at(-1).sourceId:p.lastId,receiptHash:h,sequence:p.sequence+results.length,blocks:p.blocks+1});
    return 'PRESERVATION_COMMITTED';
   }catch(e){if(e instanceof MutationError||e instanceof Error&&['preservationMergeIntegrity','preservationIntegrity','snapshotUnavailable','invalidSnapshotValue','unsupportedSnapshotValue'].includes(e.message)){
    tx.update(ref,{status:'OPERATOR',lastOutcome:'preservationMergeIntegrity',updatedAt:this.clock()});return 'OPERATOR';}throw e;}
  });
 }
}
