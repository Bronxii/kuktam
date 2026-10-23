import { after, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeApp, deleteApp } from 'firebase-admin/app';
import { getFirestore, Timestamp, Firestore } from 'firebase-admin/firestore';
import { requireLocalEmulator } from './emulator-guard';
import { grant, now } from './fixtures';
import { HouseholdStore, privateHouseholdId } from '../src/households/household-store';
import { FamilyInviteStore } from '../src/households/family-invites';
import { FamilyJoinStore, readJoinOperation } from '../src/households/family-join';
import { JoinTransferStore } from '../src/households/join-transfer';
import { transferChildId } from '../src/households/join-transfer-execution';
import { TransferOperation } from '../src/households/join-transfer-contract';
import { ShoppingMutationStore, advanceShoppingEpoch } from '../src/shopping/mutation-store';
import { newMutationId } from '../src/shopping/mutation-contract';
import { LifecycleStore } from '../src/billing/lifecycle-store';
import { FirestoreMeter } from './firestore-meter';
requireLocalEmulator(process.env);
const app=initializeApp({projectId:'demo-kuktam-local'},'family-join-transfer'),db=getFirestore(app);
beforeEach(async()=>{assert.ok((await fetch('http://127.0.0.1:8088/emulator/v1/projects/demo-kuktam-local/databases/(default)/documents',{method:'DELETE'})).ok);});
after(()=>deleteApp(app));
type Item={name:string;quantity:number;unit:string};
const milk=(quantity=300,unit='ml'):Item=>({name:'Milk',quantity,unit});
const unique=(n:number)=>Array.from({length:n},(_,i)=>({name:`product${i}`,quantity:i+1,unit:'db'}));
async function fixture(items:Item[],mode:'ADD'|'DELETE'='ADD'){
  await new HouseholdStore(db).ensure({uid:'owner'});await new HouseholdStore(db).ensure({uid:'guest'});
  await db.doc('users/owner/entitlementGrants/pro').set(grant());
  await db.doc('familyRuntime/config').set({inviteCreationEnabled:true,joinReservationEnabled:true});
  await db.doc('shoppingRuntime/config').set({enabled:true});
  const home=db.doc('households/family-test');
  await home.set({schemaVersion:2,kind:'family',state:'ACTIVE',operationId:null,ownerUid:'owner',createdAt:now});
  await home.collection('members').doc('owner').set({role:'owner'});
  await db.doc('users/owner').update({activeHouseholdId:'family-test',familyHouseholdId:'family-test'});
  await db.doc('familyMemberships/owner').set({householdId:'family-test',role:'owner',state:'ACTIVE',operationId:null});
  let time=now.toMillis()+1000;const clock=()=>Timestamp.fromMillis(time),advance=(ms=300001)=>{time+=ms;};
  const shopping=new ShoppingMutationStore(db,clock),context=await shopping.ensureContext({uid:'owner'});
  const p=privateHouseholdId('guest'),source=db.collection(`households/${p}/shoppingItems`);
  const batch=db.batch();items.forEach((item,i)=>batch.create(source.doc(`i${String(i).padStart(4,'0')}`),{...item,isChecked:true,createdAt:now}));if(items.length)await batch.commit();
  const invites=new FamilyInviteStore(db,{resolve:async()=>new Map()},clock),invite=await invites.create({uid:'owner'});
  const join=new FamilyJoinStore(db,clock,1000),id=await join.reserve({uid:'guest'},invite.token,mode),ref=db.doc(`familyOperations/${id}`);
  const op=async()=>readJoinOperation((await ref.get()).data(),id) as TransferOperation;
  await join.resume(id);const engine=new JoinTransferStore(db,clock);await engine.prepare({uid:'guest'},id,invite.inviteId);
  const tick=async()=>{advance();return new FamilyJoinStore(db,clock,1000).resume(id);};
  for(let i=0;i<30&&(await op()).phase==='SNAPSHOT_SOURCE';i++)await tick();
  if(mode==='ADD')await tick();else{
    const v=await engine.state({uid:'guest'},id,invite.inviteId);
    await engine.confirm({uid:'guest'},{operationId:id,inviteId:invite.inviteId,sourceEpoch:v.sourceEpoch!,snapshotHash:v.snapshotHash!,sourceItemCount:v.sourceItemCount!,consentVersion:1});
  }
  assert.equal((await op()).phase,'COMMITTED_TRANSFER');
  const frozen=(await source.get()).docs.map(d=>[d.id,d.data(),d.updateTime]);
  const epoch=(await source.parent!.get()).get('shoppingEpoch');
  const pages=async()=>(await ref.collection('transferJournal').get()).docs.sort((a,b)=>a.get('pageIndex')-b.get('pageIndex'));
  const finish=async()=>{for(let i=0;i<40&&(await op()).phase==='COMMITTED_TRANSFER'&&(await op()).status==='READY';i++)await tick();assert.equal((await op()).phase,'CLEAN_SOURCE');assert.equal((await op()).status,'READY');};
  const boundary=async()=>{
    assert.deepEqual((await source.get()).docs.map(d=>[d.id,d.data(),d.updateTime]),frozen);
    const root=await source.parent!.get();assert.equal(root.get('operationId'),id);assert.equal(root.get('shoppingEpoch'),epoch);
    assert.equal((await db.doc('familyMemberships/guest').get()).get('state'),'RESERVED');
    assert.equal((await db.doc('users/guest').get()).get('activeHouseholdId'),p);
    assert.equal((await home.collection('members').doc('guest').get()).exists,false);
    assert.equal((await db.doc('familyJoinCapacity/family-test').get()).get('structuralOperationId'),id);
    assert.equal((await db.doc(`familyInvites/${invite.inviteId}`).get()).get('status'),'RESERVED');
  };
  const external=async(quantity:number)=>{
    const c=await shopping.ensureContext({uid:'owner'}),mutationId=newMutationId(c.epoch);
    await shopping.submit({uid:'owner'},{schemaVersion:1,actorUid:'owner',...c,mutationId,kind:'ADD',payloadJson:JSON.stringify({type:'ADD',...milk(quantity)}),submittedAt:clock()});
    return ()=>shopping.process('owner',mutationId);
  };
  return {join,id,ref,op,engine,invite,invites,clock,advance,tick,finish,boundary,source,home,pages,shopping,context,external};
}
for(const n of [0,1,11,25,201])test(`ADD ${n}: exact snapshot, receipts, sequence, CLEAN_SOURCE and no cleanup`,async()=>{
 const f=await fixture(unique(n));await f.finish();await f.boundary();
 const rows=await f.home.collection('shoppingItems').get();assert.equal(rows.size,n);
 for(const row of rows.docs){const i=Number(row.get('name').slice(7));assert.equal(row.get('quantity'),i+1);assert.equal(row.get('isChecked'),false);}
 const pages=await f.pages(),o=await f.op();const results=pages.flatMap(d=>d.get('results'));
 assert.equal(results.length,n);assert.deepEqual(results.map(r=>r.revision),Array.from({length:n},(_,i)=>i+1));
 assert.equal((await f.home.get()).get('shoppingRevision'),n);
 for(const p of pages)for(const r of p.get('results')){assert.equal(r.code,'APPLIED');assert.equal(r.created,true);assert.equal(r.transferId,transferChildId(f.id,o,p.get('pageIndex'),r.childIndex));}
 const before=rows.docs.map(d=>[d.id,d.data(),d.updateTime]);await f.tick();assert.deepEqual((await f.home.collection('shoppingItems').get()).docs.map(d=>[d.id,d.data(),d.updateTime]),before);
});
for(const n of [0,11])test(`DELETE ${n}: disposition only, source intact and no ADD receipt`,async()=>{
 const f=await fixture(unique(n),'DELETE');await f.home.collection('shoppingItems').doc('existing').set({name:'milk',quantity:1000,unit:'ml',revision:1});
 const before=(await f.home.collection('shoppingItems').get()).docs.map(d=>[d.id,d.data(),d.updateTime]);
 await f.finish();await f.boundary();assert.deepEqual((await f.home.collection('shoppingItems').get()).docs.map(d=>[d.id,d.data(),d.updateTime]),before);
 const results=(await f.pages()).flatMap(p=>p.get('results'));assert.equal(results.length,n);assert.ok(results.every(r=>r.code==='NO_TRANSFER'&&!('itemId'in r)));
});
for(const initial of [0,1000])test(`same block create/merge against ${initial}`,async()=>{
 const f=await fixture([milk(300),milk(2,'l'),...(initial?[]:[milk(500)])]);
 if(initial)await f.home.collection('shoppingItems').doc('seed').set({name:'milk',quantity:initial,unit:'ml',revision:8,isChecked:true});
 await f.finish();const rows=await f.home.collection('shoppingItems').get();assert.equal(rows.size,1);assert.equal(rows.docs[0]!.get('quantity'),initial?3300:2800);
 const r=(await f.pages())[0]!.get('results');assert.equal(r[0].created,!initial);assert.ok(r.slice(1).every((v:any)=>!v.created));await f.boundary();
});
test('same product across blocks and incompatible unit separation',async()=>{
 const f=await fixture([...Array.from({length:24},()=>milk(100)),milk(1,'db')]);await f.finish();
 assert.deepEqual((await f.home.collection('shoppingItems').get()).docs.map(d=>[d.get('unit'),d.get('quantity')]).sort(),[['db',1],['ml',2400]]);await f.boundary();
});
test('interruption resumes durable 10/10/5, same receipts and no prefix replay',async()=>{
 const f=await fixture(Array.from({length:25},()=>milk(100)));await f.tick();const prefix=(await f.pages())[0]!.data();
 assert.deepEqual((await f.op()).cursor,{pageIndex:1,childOffset:0});assert.equal((await f.home.collection('shoppingItems').get()).docs[0]!.get('quantity'),1000);
 await f.tick();assert.deepEqual((await f.op()).cursor,{pageIndex:2,childOffset:0});await f.finish();
 assert.deepEqual((await f.pages())[0]!.data(),prefix);assert.equal((await f.home.collection('shoppingItems').get()).docs[0]!.get('quantity'),2500);await f.boundary();
});
test('lost block acknowledgement resumes without duplicate effects',async()=>{
 const f=await fixture(Array.from({length:11},()=>milk(100)));f.advance();const lease=(await f.join.claim(f.id))!;
 const original=db.runTransaction.bind(db);let lost=true;
 const wrapped=new Proxy(db,{get(target,key){if(key==='runTransaction')return async(...args:any[])=>{const v=await (original as any)(...args);if(lost){lost=false;throw new Error('lostAck');}return v;};const v=(target as any)[key];return typeof v==='function'?v.bind(target):v;}}) as Firestore;
 await assert.rejects(new FamilyJoinStore(wrapped,f.clock).step(f.id,lease),/lostAck/);assert.equal((await f.op()).cursor!.pageIndex,1);
 await f.finish();assert.equal((await f.home.collection('shoppingItems').get()).docs[0]!.get('quantity'),1100);await f.boundary();
});
test('competing workers and expired lease never release structural lock',async()=>{
 const f=await fixture(unique(25));f.advance();const claims=await Promise.all([f.join.claim(f.id),new FamilyJoinStore(db,f.clock,1000).claim(f.id)]);assert.equal(claims.filter(Boolean).length,1);
 const old=claims.find(Boolean)!;f.advance();const next=(await f.join.claim(f.id))!;assert.notEqual(next,old);
 assert.equal(await f.join.step(f.id,old),'BUSY');await Promise.all([f.join.step(f.id,next),f.join.step(f.id,next)]);await f.finish();await f.boundary();assert.equal((await f.home.get()).get('shoppingRevision'),25);
});
test('forced transaction retry revalidates and commits effects once',async()=>{
 const f=await fixture(Array.from({length:11},()=>milk(100)));f.advance();const lease=(await f.join.claim(f.id))!;let attempts=0;
 const original=db.runTransaction.bind(db);
 const wrapped=new Proxy(db,{get(target,key){if(key==='runTransaction')return (cb:any)=>original(async tx=>{attempts++;const v=await cb(tx);if(attempts===1)throw Object.assign(new Error('forcedAbort'),{code:10});return v;});const v=(target as any)[key];return typeof v==='function'?v.bind(target):v;}}) as Firestore;
 await new FamilyJoinStore(wrapped,f.clock).step(f.id,lease);assert.ok(attempts>=2);await f.finish();assert.equal((await f.home.collection('shoppingItems').get()).docs[0]!.get('quantity'),1100);
});
test('external semantic ADD concurrent with block: deterministic start barrier',async()=>{
 const f=await fixture(Array.from({length:25},()=>milk(100))),external=await f.external(500);
 f.advance();const lease=(await f.join.claim(f.id))!;let release!:()=>void;const barrier=new Promise<void>(r=>{release=r;});
 const a=(async()=>{await barrier;return f.join.step(f.id,lease);})(),b=(async()=>{await barrier;return external();})();release();
 const outcomes=await Promise.all([a,b]);assert.equal(outcomes[1],'APPLIED');await f.finish();
 const rows=await f.home.collection('shoppingItems').get();assert.equal(rows.size,1);assert.equal(rows.docs[0]!.get('quantity'),3000);assert.equal((await f.home.get()).get('shoppingRevision'),26);await f.boundary();
});
test('postcommit revoke/cancel/expiry/Pro loss and disabled admission do not abort',async()=>{
 const f=await fixture(unique(25));await f.tick();assert.equal((await f.invites.revoke({uid:'owner'},f.invite.inviteId)).code,'IN_PROGRESS');assert.equal(await f.engine.cancel({uid:'guest'},f.id,f.invite.inviteId),'IN_PROGRESS');
 f.advance(8*86400000);await db.doc('users/owner/entitlementGrants/pro').delete();await db.doc('familyRuntime/config').update({joinReservationEnabled:false});
 for(const uid of ['guest','owner'])await assert.rejects(new LifecycleStore(db,f.clock).beginDeletion(uid),/JOIN_COMMITTED_IN_PROGRESS/);
 await f.finish();await f.boundary();await assert.rejects(new LifecycleStore(db,f.clock).beginDeletion('guest'),/JOIN_COMMITTED_IN_PROGRESS/);
 await assert.rejects(f.shopping.ensureContext({uid:'guest'}));
});
for(const corruption of ['source','hash','result','nullResult','cursor','extraSource','targetEpoch','ownership'])test(`corrupt ${corruption} parks OPERATOR without cleanup`,async()=>{
 const f=await fixture(unique(11));
 if(corruption==='source')await f.source.doc('i0000').update({quantity:999});
 if(corruption==='hash')await (await f.pages())[0]!.ref.update({chainHash:'0'.repeat(64)});
 if(corruption==='result')await (await f.pages())[0]!.ref.update({results:[{code:'APPLIED'}]});
 if(corruption==='nullResult')await (await f.pages())[0]!.ref.update({results:[null]});
 if(corruption==='cursor')await f.ref.update({cursor:{pageIndex:1,childOffset:0}});
 if(corruption==='extraSource')await f.source.doc('extra').set(milk());
 if(corruption==='targetEpoch'){await f.tick();await f.home.update(advanceShoppingEpoch(f.clock()));}
 if(corruption==='ownership')await db.doc('familyJoinCapacity/family-test').update({structuralOperationId:null});
 for(let i=0;i<3&&(await f.op()).status==='READY';i++)await f.tick();
 assert.equal((await f.op()).status,'OPERATOR');assert.equal((await f.op()).nextAt,null);assert.equal((await f.source.parent!.get()).get('operationId'),f.id);assert.equal((await f.source.get()).size,corruption==='extraSource'?12:11);
});
test('natural destination epoch renewal preserves committed identity and expired source fence',async()=>{
 const f=await fixture(Array.from({length:11},()=>milk(100)));await f.tick();const prefix=(await f.pages())[0]!.data();
 f.advance(31*86400000);await f.finish();assert.deepEqual((await f.pages())[0]!.data(),prefix);
 assert.equal((await f.home.collection('shoppingItems').get()).docs[0]!.get('quantity'),1100);await f.boundary();
});
test('semantic duplicate destination preserves applied prefix and parks, never compensates',async()=>{
 const f=await fixture([milk(),{name:'duplicate',quantity:1,unit:'db'}]);for(const id of ['a','b'])await f.home.collection('shoppingItems').doc(id).set({name:'duplicate',quantity:1,unit:'db',revision:0});
 await f.tick();assert.equal((await f.op()).status,'OPERATOR');const results=(await f.pages())[0]!.get('results');assert.deepEqual(results.map((r:any)=>r.code),['APPLIED','FAILED_TERMINAL']);
 assert.equal((await f.home.collection('shoppingItems').where('name','==','milk').get()).docs[0]!.get('quantity'),300);await f.boundary();
});
test('legacy target uses accepted conservative single-child fallback',async()=>{
 const f=await fixture(Array.from({length:11},()=>milk(100)));await f.home.collection('shoppingItems').doc('legacy').set({name:'milk',quantity:1000,unit:'ml',revision:1,custom:'preserved'});
 await f.tick();assert.deepEqual((await f.op()).cursor,{pageIndex:0,childOffset:1});await f.finish();assert.equal((await f.home.collection('shoppingItems').doc('legacy').get()).get('quantity'),2100);await f.boundary();
});
test('25 item operation meter: three blocks and fresh authority per block',async()=>{
 const f=await fixture(unique(25));f.advance();const lease=(await f.join.claim(f.id))!,meter=new FirestoreMeter(db,'family-test'),join=new FamilyJoinStore(meter.db,f.clock);
 const m=await meter.measure(async()=>{for(let i=0;i<3;i++)await join.step(f.id,lease);});
 assert.equal((await f.op()).phase,'CLEAN_SOURCE');assert.equal(m.counts.transactionAttempts,3);assert.equal(m.counts.transactionRetries,0);
 assert.equal(m.counts.readCategories.lifecycle,6);assert.equal(m.counts.writeCategories.item,25);assert.equal(m.counts.writeCategories.household,3);
 assert.equal(m.counts.committedWrites,34);assert.equal(m.counts.aggregateCalls,1);
 console.log('FAMILY_4B1B1_COST '+JSON.stringify({n:25,R:m.readEquivalent,W:m.counts.committedWrites,counts:m.counts}));await f.boundary();
});
