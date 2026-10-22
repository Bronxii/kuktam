import {beforeEach,after,test} from 'node:test';
import assert from 'node:assert/strict';
import {writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {initializeApp,deleteApp} from 'firebase-admin/app';
import {getFirestore,Timestamp,FieldValue} from 'firebase-admin/firestore';
import {requireLocalEmulator} from './emulator-guard';
import {FirestoreMeter,Counts} from './firestore-meter';
import {HouseholdStore} from '../src/households/household-store';
import {ShoppingMutationStore} from '../src/shopping/mutation-store';
import {Child,newMutationId,epochExpiry,RETENTION_MS} from '../src/shopping/mutation-contract';
import {Maintenance} from '../src/jobs/maintenance';
import {AccountBinding} from '../src/billing/account-binding';
requireLocalEmulator(process.env);
const app=initializeApp({projectId:'demo-kuktam-local'},'s1d1-cost'),raw=getFirestore(app);
let now=Timestamp.fromMillis(1800000000000);
const reports:Record<string,unknown>[]=[];
beforeEach(async()=>{
 assert.equal((await fetch('http://127.0.0.1:8088/emulator/v1/projects/demo-kuktam-local/databases/(default)/documents',{method:'DELETE'})).ok,true);
 now=Timestamp.fromMillis(1800000000000);await raw.doc('shoppingRuntime/config').set({enabled:true});
});
after(async()=>{
 writeFileSync(resolve(__dirname,'../../../S1D1_COST_BASELINE.json'),JSON.stringify({baseline:'6891ceabeef90d8dd4efc34bcbcb5b18d9bbfa8d',project:'demo-kuktam-local',method:'Actual SDK operations/results, not billing counters. readEquivalent = documentGets + queryDocuments + emptyQueries. Submission separate; client/rules reads excluded.',reports},null,2)+'\n');
 await deleteApp(app);
});
const add=(name:string,quantity=1,unit='g'):Child=>({type:'ADD',name,quantity,unit});
async function fixture(family:boolean){
 const uid='member',households=new HouseholdStore(raw);await households.ensure({uid});
 if(family){
  await households.ensure({uid:'owner'});
  await raw.doc('households/family').set({schemaVersion:2,kind:'family',state:'ACTIVE',operationId:null,ownerUid:'owner',createdAt:now});
  for(const [actor,role] of [['owner','owner'],[uid,'member']]){
   await raw.doc(`users/${actor}`).update({activeHouseholdId:'family',familyHouseholdId:'family'});
   await raw.doc(`households/family/members/${actor}`).set({role});
   await raw.doc(`familyMemberships/${actor}`).set({householdId:'family',role,state:'ACTIVE',operationId:null});
  }
 }
 const context=await new ShoppingMutationStore(raw,()=>now).ensureContext({uid});
 const meter=new FirestoreMeter(raw,context.householdId),store=new ShoppingMutationStore(meter.db,()=>now);
 const never=async()=>{throw new Error('Unrelated external API forbidden in cost measurement');};
 const maintenance=new Maintenance(meter.db,{play:{lookup:never},voided:{lookup:never},ack:{acknowledge:never},feed:{list:never},binding:new AccountBinding(Buffer.alloc(32,1))},()=>now);
 return {uid,...context,meter,store,maintenance,items:raw.collection(`households/${context.householdId}/shoppingItems`)};
}
type Fixture=Awaited<ReturnType<typeof fixture>>;
async function seed(f:Fixture,id:string,name=id){await f.items.doc(id).set({name,quantity:1000,unit:'g',revision:0,isChecked:false,createdAt:now});}
function envelope(f:Fixture,payload:Child|Child[]){return {schemaVersion:1,mutationId:newMutationId(f.epoch),actorUid:f.uid,householdId:f.householdId,epoch:f.epoch,kind:Array.isArray(payload)?'BULK':payload.type,payloadJson:JSON.stringify(Array.isArray(payload)?{items:payload}:payload),submittedAt:now};}
function report(name:string,result:{counts:Counts;readEquivalent:number},extra:Record<string,unknown>={}){
 const entry={name,...extra,counts:result.counts,readEquivalent:result.readEquivalent};reports.push(entry);console.log('COST '+JSON.stringify(entry));
}
async function run(f:Fixture,name:string,payload:Child|Child[],expected='APPLIED'){
 const request=envelope(f,payload),ref=f.meter.db.doc(`users/${f.uid}/shoppingMutations/${request.mutationId}`);
 // Admission write measured independently; no fixture or client/rules reads.
 const submission=await f.meter.measure(()=>ref.create(request));assert.equal(submission.counts.committedWrites,1);assert.equal(submission.readEquivalent,0);
 let rounds=0;
 const processing=await f.meter.measure(async()=>{
  let status=await f.store.process(f.uid,request.mutationId);
  while(status==='PROCESSING'){
   assert.ok(++rounds<=19,'Bounded 200-child recovery');
   const result=await f.maintenance.run({now,only:['shopping']});assert.equal(result.items.length,1);status=result.items[0]!.outcome;
  }return status;
 });
 assert.equal(processing.value,expected);assert.equal(processing.counts.transactionRetries,0,'Baseline must not hide retries');
 assert.equal(processing.counts.attemptedWrites,processing.counts.committedWrites);
 const receipt=await raw.doc(ref.path).get();assert.equal(receipt.get('status'),expected);
 report(name,processing,{submission:submission.counts,continuationRounds:rounds,totalWritesIncludingSubmission:processing.counts.committedWrites+1});
 return {processing,request,receipt};
}
for(const family of [false,true]){
 const scope=family?'family':'private',base=family?9:7;
 for(const operation of ['ADD_NEW','ADD_MERGE','EDIT','CHECK','DELETE'] as const)test(`cost ${scope} ${operation}`,async()=>{
  const f=await fixture(family);if(operation!=='ADD_NEW')await seed(f,'target');
  const child:Child=operation==='ADD_NEW'?add('new'):operation==='ADD_MERGE'?add(' TARGET ',2,'kg'):operation==='EDIT'?{type:'EDIT',itemId:'target',expectedRevision:0,name:'renamed',quantity:2,unit:'kg'}:operation==='CHECK'?{type:'SET_CHECKED',itemId:'target',expectedRevision:0,isChecked:true}:{type:'DELETE',itemId:'target',expectedRevision:0};
  const {processing}=await run(f,`${scope}/${operation}`,child);assert.equal(processing.readEquivalent,base+Number(operation==='EDIT'));assert.equal(processing.counts.committedWrites,4);
  if(operation==='ADD_MERGE')assert.equal((await f.items.doc('target').get()).get('quantity'),3000);
 });
 for(const size of [1,10,50,200])test(`cost ${scope} distinct bulk ${size}`,async()=>{
  const f=await fixture(family),{processing}=await run(f,`${scope}/BULK_${size}`,Array.from({length:size},(_,i)=>add(`product-${i}`)));
  const continuations=Math.ceil(size/10)-1;
  assert.equal(processing.readEquivalent,base*size+2*continuations);assert.equal(processing.counts.documentGets,(base-1)*size+continuations);
  assert.equal(processing.counts.queryCategories.itemCandidates,size);assert.equal(processing.counts.queryCategories.dueWork??0,continuations);
  assert.equal(processing.counts.emptyQueries,size);assert.equal(processing.counts.transactionCalls,size+continuations);assert.equal(processing.counts.committedWrites,4*size);
  assert.equal((await f.items.get()).size,size);
 });
 test(`cost ${scope} 50 merge-heavy bulk`,async()=>{
  const f=await fixture(family);const {processing}=await run(f,`${scope}/MERGE_BULK_50`,Array.from({length:50},(_,i)=>add(`product-${i%5}`)));
  assert.equal(processing.counts.emptyQueries,5);assert.equal(processing.counts.queryDocuments,49);assert.equal(processing.readEquivalent,base*50+8);
  for(const d of (await f.items.get()).docs)assert.equal(d.get('quantity'),10);
 });
 test(`cost ${scope} mixed five-child bulk`,async()=>{
  const f=await fixture(family);for(const id of ['merge','edit','check','delete'])await seed(f,id);
  const {processing}=await run(f,`${scope}/MIXED_5`,[add('new'),add('merge'),{type:'EDIT',itemId:'edit',expectedRevision:0,name:'renamed',quantity:2,unit:'g'},{type:'SET_CHECKED',itemId:'check',expectedRevision:0,isChecked:true},{type:'DELETE',itemId:'delete',expectedRevision:0}]);
  assert.equal(processing.readEquivalent,base*5+1);assert.equal(processing.counts.committedWrites,20);assert.equal((await f.items.get()).size,4);
 });
 for(const merge of [false,true])test(`cost ${scope} EDIT ${merge?'merge':'same identity'}`,async()=>{
  const f=await fixture(family);await seed(f,'source');if(merge)await seed(f,'target');
  const {processing}=await run(f,`${scope}/${merge?'EDIT_MERGE':'EDIT_SAME_IDENTITY'}`,{type:'EDIT',itemId:'source',expectedRevision:0,name:merge?'target':'source',quantity:2,unit:'g'});
  assert.equal(processing.readEquivalent,base+1);assert.equal(processing.counts.queryDocuments,1);
  assert.equal(processing.counts.committedWrites,merge?5:4);
 });
 test(`cost ${scope} cold context separately`,async()=>{
  const f=await fixture(family);
  await raw.doc(`households/${f.householdId}`).update({shoppingEpoch:FieldValue.delete(),shoppingEpochExpiresAt:FieldValue.delete(),shoppingRevision:FieldValue.delete()});
  const context=await f.meter.measure(()=>f.store.ensureContext({uid:f.uid}));report(`${scope}/COLD_CONTEXT`,context);
  assert.equal(context.readEquivalent,family?10:8);assert.equal(context.counts.committedWrites,1);
 });
 test(`cost ${scope} warm context and authenticated submit helper separate`,async()=>{
  const f=await fixture(family),context=await f.meter.measure(()=>f.store.ensureContext({uid:f.uid}));report(`${scope}/WARM_CONTEXT`,context);
  assert.equal(context.counts.documentGets,family?9:7);assert.equal(context.counts.committedWrites,0);
  const submission=await f.meter.measure(()=>f.store.submit({uid:f.uid},envelope(f,add('helper'))));report(`${scope}/SUBMIT_HELPER`,submission);
  assert.equal(submission.counts.documentGets,family?9:7);assert.equal(submission.counts.committedWrites,1);
 });
}
for(const candidates of [2,3,4])test(`cost duplicate ADD candidates ${candidates}, actual query bound`,async()=>{
 const f=await fixture(false);for(let i=0;i<candidates;i++)await seed(f,`duplicate-${i}`,'same');
 const {processing}=await run(f,`private/DUPLICATE_CANDIDATES_${candidates}`,add('same'),'FAILED_TERMINAL');
 assert.equal(processing.counts.queryDocuments,Math.min(candidates,3));assert.equal(processing.counts.maxQueryDocuments,Math.min(candidates,3));
 assert.equal(processing.readEquivalent,6+Math.min(candidates,3));assert.equal(processing.counts.committedWrites,2);assert.equal((await f.items.get()).size,candidates);
});
test('cost duplicate delivery and expiry cleanup measured separately',async()=>{
 const f=await fixture(false),{request}=await run(f,'private/REPLAY_SEED',add('new'));
 const replay=await f.meter.measure(()=>f.store.process(f.uid,request.mutationId));report('private/TERMINAL_REPLAY',replay);assert.equal(replay.readEquivalent,1);assert.equal(replay.counts.committedWrites,0);
 now=Timestamp.fromMillis(epochExpiry(f.epoch)+RETENTION_MS+1);
 const cleanup=await f.meter.measure(()=>f.maintenance.run({now,only:['shopping']}));report('private/EXPIRY_CLEANUP',cleanup);assert.equal(cleanup.readEquivalent,2);assert.equal(cleanup.counts.committedWrites,2);
 const idle=await f.meter.measure(()=>f.maintenance.run({now,only:['shopping']}));report('private/EMPTY_DUE_QUERY',idle);assert.equal(idle.counts.queryDocuments,0);assert.equal(idle.readEquivalent,1);
});
test('meter calibration: real reads, missing documents, queries, getAll, reset and aborted attempt',async()=>{
 const f=await fixture(false);await seed(f,'calibration');
 const counts=await f.meter.measure(async()=>{
  await f.meter.db.getAll(f.meter.db.doc(f.items.doc('calibration').path),f.meter.db.doc(f.items.doc('missing').path));
  await f.meter.db.collection(f.items.path).get();await f.meter.db.collection(f.items.path).where('name','==','missing').get();
 });
 assert.equal(counts.counts.documentGets,2);assert.equal(counts.counts.missingDocuments,1);assert.equal(counts.counts.queryCalls,2);assert.equal(counts.counts.queryDocuments,1);assert.equal(counts.readEquivalent,4);
 let attempts=0;
 const retry=await f.meter.measure(()=>f.meter.db.runTransaction(async tx=>{
  const ref=f.meter.db.doc(f.items.doc('calibration').path);await tx.get(ref);tx.update(ref,{quantity:1001});
  if(++attempts===1)throw Object.assign(new Error('deterministic calibration abort'),{code:10});
 }));
 assert.equal(retry.counts.transactionAttempts,2);assert.equal(retry.counts.transactionRetries,1);assert.equal(retry.counts.attemptedWrites,2);assert.equal(retry.counts.committedWrites,1);assert.equal(retry.counts.documentGets,2);
 report('calibration/FORCED_ABORT_RETRY',retry);assert.equal((await f.items.doc('calibration').get()).get('quantity'),1001);
 const empty=await f.meter.measure(async()=>{});assert.equal(empty.readEquivalent,0);assert.equal(empty.counts.committedWrites,0);
});
