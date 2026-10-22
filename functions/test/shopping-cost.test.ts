import {beforeEach,after,test} from 'node:test';
import assert from 'node:assert/strict';
import {writeFileSync,readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {initializeApp,deleteApp} from 'firebase-admin/app';
import {getFirestore,Timestamp,FieldValue,Transaction} from 'firebase-admin/firestore';
import {requireLocalEmulator} from './emulator-guard';
import {FirestoreMeter,Counts} from './firestore-meter';
import {HouseholdStore} from '../src/households/household-store';
import {ShoppingMutationStore,advanceShoppingEpoch} from '../src/shopping/mutation-store';
import {Child,newMutationId,epochExpiry,RETENTION_MS,parseRequest} from '../src/shopping/mutation-contract';
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
 writeFileSync(resolve(__dirname,process.env.S1D_COST_SMALL_ONLY==='1'?'../../../S1D_CURRENT_SMALL_COST_MEASUREMENT.json':'../../../S1D2B_COST_MEASUREMENT.json'),JSON.stringify({measurementVersion:1,baseline:'7719da0cdc78dfb565d509305fcdb624722df60a',comparisonBaseline:'S1D1_COST_BASELINE.json',historicalBaselines:process.env.S1D_COST_SMALL_ONLY==='1'?undefined:{S1D1:JSON.parse(readFileSync(resolve(__dirname,'../../../S1D1_COST_BASELINE.json'),'utf8')).reports.filter((r:any)=>/\/BULK_(1|10|50|200)$/.test(r.name)),S1D2A:JSON.parse(readFileSync(resolve(__dirname,'../../../S1D2A_COST_MEASUREMENT.json'),'utf8')).reports.filter((r:any)=>/\/BULK_(1|10)$/.test(r.name))},executor:'current checkout',project:'demo-kuktam-local',method:'Actual SDK operations/results, not billing counters. readEquivalent = documentGets + queryDocuments + emptyQueries. Submission separate; client/rules reads excluded.',reports},null,2)+'\n');
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
 const initial=(await f.items.get()).docs;
 const request=envelope(f,payload),ref=f.meter.db.doc(`users/${f.uid}/shoppingMutations/${request.mutationId}`);
 // Admission write measured independently; no fixture or client/rules reads.
 const submission=await f.meter.measure(()=>ref.create(request));assert.equal(submission.counts.committedWrites,1);assert.equal(submission.readEquivalent,0);
 const children=parseRequest(request,f.uid,request.mutationId).children;
 const allAdds=children.every((c):c is Extract<Child,{type:'ADD'}>=>c.type==='ADD');
 const progress:number[]=[];
 const checkProgress=async(status:string)=>{
  const d=await raw.doc(ref.path).get(),cursor=d.get('cursor');progress.push(cursor);
  assert.equal(d.get('results').length,cursor);assert.equal(cursor,Math.min(children.length,10*(rounds+1)));
  assert.equal(status==='PROCESSING',cursor<children.length);
 };
 let rounds=0;
 const processing=await f.meter.measure(async()=>{
  let status=await f.store.process(f.uid,request.mutationId);if(allAdds&&expected==='APPLIED')await checkProgress(status);
  while(status==='PROCESSING'){
   assert.ok(++rounds<=19,'Bounded 200-child recovery');
   const result=await f.maintenance.run({now,only:['shopping']});assert.equal(result.items.length,1);status=result.items[0]!.outcome;if(allAdds&&expected==='APPLIED')await checkProgress(status);
  }return status;
 });
 assert.equal(processing.value,expected);assert.equal(processing.counts.transactionRetries,0,'Baseline must not hide retries');
 assert.equal(processing.counts.attemptedWrites,processing.counts.committedWrites);
 const receipt=await raw.doc(ref.path).get();assert.equal(receipt.get('status'),expected);
 if(allAdds&&expected==='APPLIED'){
  const results=receipt.get('results');assert.equal(results.length,children.length);
  assert.deepEqual(results.map((r:any)=>r.revision),children.map((_,i)=>i+1));
  assert.equal((await raw.doc(`households/${f.householdId}`).get()).get('shoppingRevision'),children.length);
  const totals=new Map<string,number>(),targets=new Map<string,string>();
  const key=(name:string,unit:string)=>JSON.stringify([name,unit]);
  for(const d of initial){totals.set(key(d.get('name'),d.get('unit')),d.get('quantity'));targets.set(key(d.get('name'),d.get('unit')),d.id);}
  for(const [i,c] of children.entries()){
   const k=key(c.name,c.unit),r=results[i];assert.equal(r.code,'APPLIED');assert.equal(r.created,!targets.has(k));
   if(targets.has(k))assert.equal(r.itemId,targets.get(k));else targets.set(k,r.itemId);
   totals.set(k,(totals.get(k)??0)+c.quantity);
  }
  const final=await f.items.get();assert.equal(final.size,totals.size);
  for(const d of final.docs)assert.equal(d.get('quantity'),totals.get(key(d.get('name'),d.get('unit'))));
 }
 report(name,processing,{childCount:children.length,blockCount:allAdds?processing.counts.readCategories.lifecycle:undefined,progress,finalParentState:receipt.get('status'),submission:submission.counts,continuationRounds:rounds,totalWritesIncludingSubmission:processing.counts.committedWrites+1});
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
 for(const size of (process.env.S1D_COST_SMALL_ONLY==='1'?[1,10]:[1,10,50,200]))test(`cost ${scope} distinct bulk ${size}`,async()=>{
  const f=await fixture(family),{processing}=await run(f,`${scope}/BULK_${size}`,Array.from({length:size},(_,i)=>add(`product-${i}`)));
  const blocks=Math.ceil(size/10),continuations=blocks-1;
  assert.equal(processing.readEquivalent,size+(base-1)*blocks+2*continuations);assert.equal(processing.counts.documentGets,(base-1)*blocks+continuations);
  for(const category of ['lifecycle','user','household','membership','reverseMembership'])assert.equal(processing.counts.readCategories[category],blocks);
  assert.equal(processing.counts.readCategories.commandReceipt,blocks+continuations);
  if(family)for(const category of ['fallbackHousehold','fallbackMembership'])assert.equal(processing.counts.readCategories[category],blocks);
  assert.equal(processing.counts.queryCategories.itemCandidates,size);assert.equal(processing.counts.queryCategories.dueWork??0,continuations);
  assert.equal(processing.counts.emptyQueries,size);assert.equal(processing.counts.transactionCalls,blocks+continuations);assert.equal(processing.counts.committedWrites,size+3*blocks);
  assert.equal((await f.items.get()).size,size);
 });
 if(process.env.S1D_COST_SMALL_ONLY!=='1')test(`cost ${scope} 50 merge-heavy bulk`,async()=>{
  const f=await fixture(family);const {processing}=await run(f,`${scope}/MERGE_BULK_50`,Array.from({length:50},(_,i)=>add(`product-${i%5}`)));
  assert.equal(processing.counts.emptyQueries,5);assert.equal(processing.counts.queryDocuments,24);assert.equal(processing.counts.committedWrites,40);assert.equal(processing.readEquivalent,(base-1)*5+25+8);
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

if(process.env.S1D_COST_SMALL_ONLY!=='1'){
 for(const family of [false,true])for(const size of [25,50,200])test(`scale semantic units ${family?'family':'private'} ${size}`,async()=>{
  const f=await fixture(family);
  const pattern=[add(' Milk ',300,'ml'),add('milk',2,'l'),add('milk',500,'ml'),add('milk',1,'db'),add('flour',2,'kg')];
  const {processing}=await run(f,`${family?'family':'private'}/SEMANTIC_${size}`,Array.from({length:size},(_,i)=>pattern[i%5]!));
  const blocks=Math.ceil(size/10),continuations=blocks-1;
  assert.equal(processing.readEquivalent,(family?11:9)*blocks+2*continuations);
  assert.equal(processing.counts.committedWrites,6*blocks);assert.equal((await f.items.get()).size,3);
 });
 test('measured 25 distinct final partial block',async()=>{
  const f=await fixture(false),{processing}=await run(f,'private/PARTIAL_25',Array.from({length:25},(_,i)=>add(`p${i}`)));
  assert.equal(processing.readEquivalent,47);assert.equal(processing.counts.committedWrites,34);
 });
 test('meter real ten-child transaction abort: attempts and committed effects separate',async()=>{
  const f=await fixture(false),request=envelope(f,Array.from({length:10},(_,i)=>add(`p${i}`)));
  await raw.doc(`users/${f.uid}/shoppingMutations/${request.mutationId}`).create(request);
  let attempts=0;
  const wrapped=new Proxy(raw,{get(target,key){
   if(key==='runTransaction')return (callback:(tx:Transaction)=>Promise<any>)=>target.runTransaction(async tx=>{
    const result=await callback(tx);if(++attempts===1)throw Object.assign(new Error('test abort'),{code:10});return result;
   });
   const value=(target as any)[key];return typeof value==='function'?value.bind(target):value;
  }});
  const meter=new FirestoreMeter(wrapped,f.householdId),store=new ShoppingMutationStore(meter.db,()=>now);
  const m=await meter.measure(()=>store.process(f.uid,request.mutationId));
  assert.equal(m.value,'APPLIED');assert.equal(m.readEquivalent,32);assert.equal(m.counts.transactionAttempts,2);
  assert.equal(m.counts.transactionRetries,1);assert.equal(m.counts.attemptedWrites,26);assert.equal(m.counts.committedWrites,13);
  assert.equal(m.counts.readCategories.lifecycle,2);const rows=await f.items.get();assert.equal(rows.size,10);for(const d of rows.docs)assert.equal(d.get('quantity'),1);
  assert.deepEqual((await raw.doc(`users/${f.uid}/shoppingMutations/${request.mutationId}`).get()).get('results').map((r:any)=>r.revision),Array.from({length:10},(_,i)=>i+1));
  report('private/RETRY_10',m,{normalR:16,normalCommittedW:13,submissionWrites:1,totalCommittedW:14});
 });
 test('50 parent: measured interruption after 30 and fresh-worker resume remaining 20',async()=>{
  const f=await fixture(false),request=envelope(f,Array.from({length:50},(_,i)=>add(`p${i}`))),ref=raw.doc(`users/${f.uid}/shoppingMutations/${request.mutationId}`);
  await ref.create(request);
  const prefix=await f.meter.measure(async()=>{for(let i=0;i<3;i++)assert.equal(await f.store.process(f.uid,request.mutationId),'PROCESSING');});
  const durable=await ref.get();assert.equal(durable.get('cursor'),30);assert.equal(durable.get('payloadJson'),request.payloadJson);
  const restored=new ShoppingMutationStore(f.meter.db,()=>now);
  const suffix=await f.meter.measure(async()=>{assert.equal(await restored.continueWork(f.uid,request.mutationId),'PROCESSING');assert.equal(await restored.continueWork(f.uid,request.mutationId),'APPLIED');});
  assert.equal(prefix.readEquivalent,48);assert.equal(prefix.counts.committedWrites,39);
  assert.equal(suffix.readEquivalent,34);assert.equal(suffix.counts.committedWrites,26);
  const result=await ref.get();assert.deepEqual(result.get('results').slice(0,30),durable.get('results'));
  assert.deepEqual(result.get('results').map((r:any)=>r.revision),Array.from({length:50},(_,i)=>i+1));
  const rows=await f.items.get();assert.equal(rows.size,50);for(const d of rows.docs)assert.equal(d.get('quantity'),1);
  const replay=await f.meter.measure(()=>restored.process(f.uid,request.mutationId));assert.equal(replay.readEquivalent,1);assert.equal(replay.counts.committedWrites,0);
  report('private/INTERRUPT_PREFIX_30',prefix);report('private/RESUME_SUFFIX_20',suffix);report('private/RESUME_TERMINAL_REPLAY',replay);
 });
 for(const change of ['epoch','membership','lifecycle'] as const)test(`50 parent authority invalidation after 30: ${change}`,async()=>{
  const f=await fixture(change==='membership'),request=envelope(f,Array.from({length:50},(_,i)=>add(`p${i}`))),ref=raw.doc(`users/${f.uid}/shoppingMutations/${request.mutationId}`);
  await ref.create(request);for(let i=0;i<3;i++)assert.equal(await f.store.process(f.uid,request.mutationId),'PROCESSING');
  const prefix=(await ref.get()).get('results');
  if(change==='epoch')await raw.doc(`households/${f.householdId}`).update(advanceShoppingEpoch(now));
  if(change==='membership')await raw.doc(`households/${f.householdId}/members/${f.uid}`).delete();
  if(change==='lifecycle')await raw.doc(`accountLifecycle/${f.uid}`).update({state:'DELETING'});
  const m=await f.meter.measure(()=>f.store.process(f.uid,request.mutationId));assert.equal(m.value,'PARTIAL');
  const result=await ref.get();assert.equal(result.get('cursor'),50);assert.equal(result.get('appliedCount'),30);
  assert.deepEqual(result.get('results').slice(0,30),prefix);assert.equal((await f.items.get()).size,30);
  assert.ok(result.get('results').slice(30).every((r:any)=>r.code===(change==='epoch'?'REJECTED_CONTEXT_CHANGED':'REJECTED_UNAUTHORIZED')));
  report(`privateOrFamily/INVALIDATED_${change}`,m,{committedChildren:30,terminalChildren:50});
 });
 test('multi-block parent and external ADD overlap through transaction barrier',async()=>{
  const f=await fixture(false),request=envelope(f,Array.from({length:50},()=>add('milk',300,'ml'))),ref=raw.doc(`users/${f.uid}/shoppingMutations/${request.mutationId}`);
  await ref.create(request);await f.store.process(f.uid,request.mutationId);
  const ext=envelope(f,add('milk',2,'l'));await raw.doc(`users/${f.uid}/shoppingMutations/${ext.mutationId}`).create(ext);
  let arrived=0,release!:()=>void;const barrier=new Promise<void>(r=>release=r);
  const wrapped=new Proxy(raw,{get(target,key){
   if(key==='runTransaction')return (callback:(tx:Transaction)=>Promise<any>)=>target.runTransaction(async tx=>{if(++arrived===2)release();await barrier;return callback(tx);});
   const value=(target as any)[key];return typeof value==='function'?value.bind(target):value;
  }});
  const store=new ShoppingMutationStore(wrapped,()=>now);
  assert.deepEqual(await Promise.all([store.process(f.uid,request.mutationId),store.process(f.uid,ext.mutationId)]),['PROCESSING','APPLIED']);
  for(let i=0;i<3;i++)await f.store.process(f.uid,request.mutationId);
  const rows=await f.items.get();assert.equal(rows.size,1);assert.equal(rows.docs[0]!.get('quantity'),17000);assert.equal(rows.docs[0]!.get('revision'),51);
  const results=(await ref.get()).get('results');assert.equal(results.length,50);
  const externalResult=(await raw.doc(`users/${f.uid}/shoppingMutations/${ext.mutationId}`).get()).get('results')[0];
  assert.deepEqual([...results.map((r:any)=>r.revision),externalResult.revision].sort((a,b)=>a-b),Array.from({length:51},(_,i)=>i+1));
 });
}
