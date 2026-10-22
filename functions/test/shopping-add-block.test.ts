import {beforeEach,after,test} from 'node:test';
import assert from 'node:assert/strict';
import {initializeApp,deleteApp} from 'firebase-admin/app';
import {getFirestore,Timestamp,Firestore,Transaction} from 'firebase-admin/firestore';
import {requireLocalEmulator} from './emulator-guard';
import {HouseholdStore} from '../src/households/household-store';
import {ShoppingMutationStore,MAX_ADD_BLOCK_SIZE,advanceShoppingEpoch,workId} from '../src/shopping/mutation-store';
import {Child,newMutationId} from '../src/shopping/mutation-contract';
import {FirestoreMeter} from './firestore-meter';
requireLocalEmulator(process.env);
const app=initializeApp({projectId:'demo-kuktam-local'},'s1d2a'),db=getFirestore(app);
const now=Timestamp.fromMillis(1800000000000);
const add=(name='milk',quantity=1,unit='ml'):Child=>({type:'ADD',name,quantity,unit});
beforeEach(async()=>{assert.ok((await fetch('http://127.0.0.1:8088/emulator/v1/projects/demo-kuktam-local/databases/(default)/documents',{method:'DELETE'})).ok);await db.doc('shoppingRuntime/config').set({enabled:true});});
after(()=>deleteApp(app));
async function fixture(family=false){
 const uid='u';await new HouseholdStore(db).ensure({uid});
 if(family){
  await new HouseholdStore(db).ensure({uid:'owner'});
  await db.doc('households/family').set({schemaVersion:2,kind:'family',state:'ACTIVE',operationId:null,ownerUid:'owner',createdAt:now});
  for(const [actor,role] of [[uid,'member'],['owner','owner']]){
   await db.doc(`users/${actor}`).update({activeHouseholdId:'family',familyHouseholdId:'family'});
   await db.doc(`households/family/members/${actor}`).set({role});
   await db.doc(`familyMemberships/${actor}`).set({householdId:'family',role,state:'ACTIVE',operationId:null});
  }
 }
 const store=new ShoppingMutationStore(db,()=>now),context=await store.ensureContext({uid});
 const items=db.collection(`households/${context.householdId}/shoppingItems`),home=items.parent!;
 const command=async(payload:Child|Child[])=>{
  const r={schemaVersion:1,mutationId:newMutationId(context.epoch),actorUid:uid,...context,kind:Array.isArray(payload)?'BULK':payload.type,payloadJson:JSON.stringify(Array.isArray(payload)?{items:payload}:payload),submittedAt:now};
  const ref=db.doc(`users/${uid}/shoppingMutations/${r.mutationId}`);await store.submit({uid},r);return {r,ref};
 };
 return {uid,store,context,items,home,command};
}
for(const family of [false,true])for(const n of [1,10])test(`measured ${family?'family':'private'} ADD block ${n}`,async()=>{
 const f=await fixture(family),c=await f.command(Array.from({length:n},(_,i)=>add(`p${i}`)));
 const meter=new FirestoreMeter(db,f.context.householdId),store=new ShoppingMutationStore(meter.db,()=>now);
 const m=await meter.measure(()=>store.process(f.uid,c.r.mutationId));
 assert.equal(m.value,'APPLIED');assert.equal(m.readEquivalent,n+(family?8:6));assert.equal(m.counts.committedWrites,n+3);
 assert.equal(m.counts.transactionCalls,1);assert.equal(m.counts.transactionRetries,0);
 assert.equal(m.counts.readCategories.lifecycle,1);assert.equal(m.counts.readCategories.commandReceipt,1);
 assert.equal((await f.items.get()).size,n);
 const d=await c.ref.get();assert.equal(d.get('cursor'),n);assert.equal(d.get('appliedCount'),n);
 assert.deepEqual(d.get('results').map((r:any)=>r.revision),Array.from({length:n},(_,i)=>i+1));
 assert.equal((await f.home.get()).get('shoppingRevision'),n);
 assert.ok((await db.doc(`shoppingMutationWork/${workId(c.ref.path)}`).get()).get('nextAt').isEqual(d.get('purgeAfter')));
 console.log('S1D2A_COST '+JSON.stringify({family,n,R:m.readEquivalent,W:m.counts.committedWrites+1,counts:m.counts}));
});
for(const initial of [0,1000])test(`same-block normalized create/merge, initial ${initial}`,async()=>{
 const f=await fixture();if(initial)await f.items.doc('seed').set({name:'milk',quantity:initial,unit:'ml',revision:9,isChecked:true,createdAt:now});
 const c=await f.command([add(' Milk ',300),add('milk',2,'l'),add('milk',500)]);
 assert.equal(await f.store.process(f.uid,c.r.mutationId),'APPLIED');
 const rows=await f.items.get();assert.equal(rows.size,1);assert.equal(rows.docs[0]!.get('quantity'),initial+2800);
 const results=(await c.ref.get()).get('results');assert.deepEqual(results.map((r:any)=>r.created),[!initial,false,false]);
 assert.equal(new Set(results.map((r:any)=>r.itemId)).size,1);assert.deepEqual(results.map((r:any)=>r.revision),initial?[10,11,12]:[1,2,3]);
 if(initial){assert.ok(rows.docs[0]!.get('createdAt').isEqual(now));assert.equal(rows.docs[0]!.get('isChecked'),true);}
 await f.store.process(f.uid,c.r.mutationId);assert.equal((await rows.docs[0]!.ref.get()).get('quantity'),initial+2800);
});
test('incompatible units stay separate',async()=>{
 const f=await fixture(),c=await f.command([add('milk',2,'l'),add('milk',1,'db')]);await f.store.process(f.uid,c.r.mutationId);
 assert.deepEqual((await f.items.get()).docs.map(d=>[d.get('unit'),d.get('quantity')]).sort(),[['db',1],['ml',2000]]);
});
for(const duplicates of [2,3,4])test(`ambiguous candidates ${duplicates}: valid prefix only, bound three`,async()=>{
 const f=await fixture();for(let i=0;i<duplicates;i++)await f.items.doc(`d${i}`).set({name:'duplicate',quantity:1,unit:'ml',revision:0});
 const c=await f.command([add('valid'),add('duplicate'),add('never')]),meter=new FirestoreMeter(db,f.context.householdId);
 const m=await meter.measure(()=>new ShoppingMutationStore(meter.db,()=>now).process(f.uid,c.r.mutationId));
 assert.equal(m.value,'PARTIAL');assert.equal(m.counts.maxQueryDocuments,Math.min(3,duplicates));
 assert.deepEqual((await c.ref.get()).get('results').map((r:any)=>r.code),['APPLIED','FAILED_TERMINAL','FAILED_TERMINAL']);
 assert.equal((await f.items.where('name','==','never').get()).size,0);assert.equal((await f.home.get()).get('shoppingRevision'),1);
});
test('overflow in later child retains exact valid prefix and no invalid delta',async()=>{
 const f=await fixture(),c=await f.command([add('milk',Number.MAX_SAFE_INTEGER),add('milk',1),add('other')]);
 assert.equal(await f.store.process(f.uid,c.r.mutationId),'PARTIAL');assert.equal((await f.items.get()).docs[0]!.get('quantity'),Number.MAX_SAFE_INTEGER);
 assert.equal((await c.ref.get()).get('appliedCount'),1);
});
test('25 children resume 10/10/5 in fresh workers; terminal replay is read-only',async()=>{
 assert.equal(MAX_ADD_BLOCK_SIZE,10);const f=await fixture(),c=await f.command(Array.from({length:25},(_,i)=>add(`p${i}`)));
 for(const [cursor,status] of [[10,'PROCESSING'],[20,'PROCESSING'],[25,'APPLIED']] as const){
  assert.equal(await new ShoppingMutationStore(db,()=>now).process(f.uid,c.r.mutationId),status);
  const d=await c.ref.get();assert.equal(d.get('cursor'),cursor);assert.equal(d.get('results').length,cursor);assert.equal((await f.items.get()).size,cursor);
 }
 const before=(await c.ref.get()).data();await f.store.process(f.uid,c.r.mutationId);assert.deepEqual((await c.ref.get()).data(),before);
});
for(const change of ['epoch','lifecycle','membership','household'] as const)test(`${change} changes between blocks: fresh authority`,async()=>{
 const f=await fixture(change==='membership'),c=await f.command(Array.from({length:11},(_,i)=>add(`p${i}`)));
 assert.equal(await f.store.process(f.uid,c.r.mutationId),'PROCESSING');
 if(change==='epoch')await f.home.update(advanceShoppingEpoch(now));
 if(change==='membership')await f.home.collection('members').doc(f.uid).delete();
 if(change==='lifecycle')await db.doc(`accountLifecycle/${f.uid}`).update({state:'DELETING'});
 if(change==='household')await db.doc(`users/${f.uid}`).update({activeHouseholdId:'other'});
 assert.equal(await f.store.process(f.uid,c.r.mutationId),'PARTIAL');assert.equal((await f.items.get()).size,10);
 assert.equal((await c.ref.get()).get('results')[10].code,['epoch','household'].includes(change)?'REJECTED_CONTEXT_CHANGED':'REJECTED_UNAUTHORIZED');
});
// Test-only SDK wrapper: retry uses the real Firestore runTransaction implementation.
function intercept(db:Firestore,hook:(run:()=>Promise<any>,attempt:number)=>Promise<any>){
 let attempts=0;
 return new Proxy(db,{get(target,key){
  if(key==='runTransaction')return (callback:(tx:Transaction)=>Promise<any>)=>target.runTransaction(tx=>hook(()=>callback(tx),++attempts));
  const value=(target as any)[key];return typeof value==='function'?value.bind(target):value;
 }});
}
for(const invalidate of [false,true])test(`real transaction retry is atomic and rereads authority, invalidate=${invalidate}`,async()=>{
 const f=await fixture(),c=await f.command([add('milk',300),add('milk',2,'l')]);
 let attempts=0;
 const wrapped=intercept(db,async(run,attempt)=>{
  attempts=attempt;
  if(attempt===2){
   assert.equal((await f.items.get()).size,0);assert.equal((await c.ref.get()).get('cursor'),undefined);
   if(invalidate)await db.doc(`accountLifecycle/${f.uid}`).update({state:'DELETING'});
  }
  const result=await run();if(attempt===1)throw Object.assign(new Error('forced real SDK retry'),{code:10});return result;
 });
 const meter=new FirestoreMeter(wrapped,f.context.householdId),store=new ShoppingMutationStore(meter.db,()=>now);
 const m=await meter.measure(()=>store.process(f.uid,c.r.mutationId));assert.equal(attempts,2);assert.equal(m.counts.transactionRetries,1);
 assert.equal(m.counts.readCategories.lifecycle,2);assert.equal(m.counts.readCategories.commandReceipt,2);
 assert.equal(m.value,invalidate?'REJECTED_UNAUTHORIZED':'APPLIED');
 assert.equal((await f.items.get()).size,invalidate?0:1);if(!invalidate)assert.equal((await f.items.get()).docs[0]!.get('quantity'),2300);
});
test('deterministic concurrent external ADD reaches transaction barrier; all deltas once',async()=>{
 const f=await fixture(),block=await f.command([add('milk',300),add('milk',2,'l')]),external=await f.command(add('milk',500));
 let arrived=0,release!:()=>void;const barrier=new Promise<void>(r=>release=r);
 const wrapped=intercept(db,async(run)=>{if(++arrived===2)release();await barrier;return run();});
 const store=new ShoppingMutationStore(wrapped,()=>now);
 assert.deepEqual(await Promise.all([store.process(f.uid,block.r.mutationId),store.process(f.uid,external.r.mutationId)]),['APPLIED','APPLIED']);
 const rows=await f.items.get();assert.equal(rows.size,1);assert.equal(rows.docs[0]!.get('quantity'),2800);assert.equal(rows.docs[0]!.get('revision'),3);
 await store.process(f.uid,block.r.mutationId);assert.equal((await rows.docs[0]!.ref.get()).get('quantity'),2800);
});
test('mixed parent stays one child per transaction and preserves ordering',async()=>{
 const f=await fixture();await f.items.doc('target').set({name:'old',quantity:1,unit:'ml',revision:0});
 const c=await f.command([add('milk'),add('milk'),{type:'EDIT',itemId:'target',expectedRevision:0,name:'new',quantity:7,unit:'ml'},add('new'),{type:'SET_CHECKED',itemId:'target',expectedRevision:4,isChecked:true}]);
 const meter=new FirestoreMeter(db,f.context.householdId),m=await meter.measure(()=>new ShoppingMutationStore(meter.db,()=>now).process(f.uid,c.r.mutationId));
 assert.equal(m.value,'APPLIED');assert.equal(m.counts.transactionCalls,5);assert.equal((await f.items.doc('target').get()).get('quantity'),8);assert.equal((await f.items.doc('target').get()).get('isChecked'),true);
});
for(const type of ['EDIT','DELETE','SET_CHECKED'] as const)test(`receipt-bound dependent ${type} uses actual child revision, no guessed rebase`,async()=>{
 const f=await fixture(),c=await f.command([add('milk'),add('other')]);await f.store.process(f.uid,c.r.mutationId);
 const result=(await c.ref.get()).get('results')[0];assert.equal(result.created,true);
 const child:Child=type==='EDIT'?{type,itemId:result.itemId,expectedRevision:result.revision,name:'milk',quantity:9,unit:'ml'}:type==='SET_CHECKED'?{type,itemId:result.itemId,expectedRevision:result.revision,isChecked:true}:{type,itemId:result.itemId,expectedRevision:result.revision};
 const dependent=await f.command(child);assert.equal(await f.store.process(f.uid,dependent.r.mutationId),'APPLIED');
});
test('earlier in-block revision cannot authorize a destructive dependency after later merge',async()=>{
 const f=await fixture(),c=await f.command([add('milk'),add('milk')]);await f.store.process(f.uid,c.r.mutationId);
 const results=(await c.ref.get()).get('results');assert.deepEqual(results.map((r:any)=>r.created),[true,false]);
 const dependent=await f.command({type:'DELETE',itemId:results[0].itemId,expectedRevision:results[0].revision});
 assert.equal(await f.store.process(f.uid,dependent.r.mutationId),'REJECTED_STALE');assert.equal((await f.items.get()).docs[0]!.get('quantity'),2);
});

test('large custom legacy targets retain single-child granularity and unknown fields',async()=>{
 const f=await fixture();await f.items.doc('legacy').set({name:'milk',quantity:1000,unit:'ml',revision:0,custom:'x'.repeat(300000)});
 const c=await f.command([add('milk',300),add('milk',2,'l'),add('milk',500)]),meter=new FirestoreMeter(db,f.context.householdId);
 const m=await meter.measure(()=>new ShoppingMutationStore(meter.db,()=>now).process(f.uid,c.r.mutationId));
 assert.equal(m.value,'APPLIED');assert.equal(m.counts.transactionCalls,3);
 const item=await f.items.doc('legacy').get();assert.equal(item.get('quantity'),3800);assert.equal(item.get('custom').length,300000);
});
test('lost ACK after block commit resumes from durable cursor without reapplying prefix',async()=>{
 const f=await fixture(),c=await f.command(Array.from({length:11},()=>add('milk')));
 let lost=false;
 const wrapped=new Proxy(db,{get(target,key){
  if(key==='runTransaction')return async(callback:(tx:Transaction)=>Promise<any>)=>{
   const result=await target.runTransaction(callback);if(!lost){lost=true;throw new Error('lost commit ACK');}return result;
  };
  const value=(target as any)[key];return typeof value==='function'?value.bind(target):value;
 }});
 await assert.rejects(new ShoppingMutationStore(wrapped,()=>now).process(f.uid,c.r.mutationId),/lost commit ACK/);
 const partial=await c.ref.get();assert.equal(partial.get('cursor'),10);assert.equal(partial.get('status'),'FAILED_RETRYABLE');
 assert.equal((await f.items.get()).docs[0]!.get('quantity'),10);
 assert.equal(await new ShoppingMutationStore(db,()=>Timestamp.fromMillis(now.toMillis()+300001)).process(f.uid,c.r.mutationId),'APPLIED');
 assert.equal((await f.items.get()).docs[0]!.get('quantity'),11);assert.equal((await c.ref.get()).get('results').length,11);
});

test('maxSteps 20 means two bounded ten-child transactions, never a twenty-child block',async()=>{
 const f=await fixture(),c=await f.command(Array.from({length:21},(_,i)=>add(`p${i}`))),meter=new FirestoreMeter(db,f.context.householdId);
 const m=await meter.measure(()=>new ShoppingMutationStore(meter.db,()=>now).process(f.uid,c.r.mutationId,20));
 assert.equal(m.value,'PROCESSING');assert.equal(m.counts.transactionCalls,2);assert.equal(m.counts.readCategories.lifecycle,2);
 assert.equal((await c.ref.get()).get('cursor'),20);assert.equal((await f.items.get()).size,20);
 assert.equal(await f.store.process(f.uid,c.r.mutationId),'APPLIED');
});
