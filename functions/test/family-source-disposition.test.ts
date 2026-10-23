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
import { cleanupChildId } from '../src/households/join-source-disposition';
requireLocalEmulator(process.env);
const app=initializeApp({projectId:'demo-kuktam-local'},'family-source-disposition'),db=getFirestore(app);
beforeEach(async()=>{assert.ok((await fetch('http://127.0.0.1:8088/emulator/v1/projects/demo-kuktam-local/databases/(default)/documents',{method:'DELETE'})).ok);});
after(()=>deleteApp(app));
type Item={name:string;quantity:number;unit:string};
const milk=(quantity=300,unit='ml'):Item=>({name:'Milk',quantity,unit});
const unique=(n:number)=>Array.from({length:n},(_,i)=>({name:`product${i}`,quantity:i+1,unit:'db'}));
async function fixture(items:Item[],mode:'ADD'|'DELETE'='ADD',pending=false){
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
  let oldMutationId:string|null=null;
  if(pending){const old=await shopping.ensureContext({uid:'guest'});oldMutationId=newMutationId(old.epoch);
    await shopping.submit({uid:'guest'},{schemaVersion:1,actorUid:'guest',...old,mutationId:oldMutationId,kind:'ADD',payloadJson:JSON.stringify({type:'ADD',...milk()}),submittedAt:clock()});}
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
  return {join,id,ref,op,engine,invite,invites,clock,advance,tick,finish,boundary,source,home,pages,shopping,context,external,oldMutationId};
}

async function cleanupFixture(n:number,mode:'ADD'|'DELETE'='ADD',pending=false){
 const f=await fixture(unique(n),mode,pending);await f.finish();await f.boundary();
 const familyBefore=(await f.home.collection('shoppingItems').get()).docs.map(d=>[d.id,d.data(),d.updateTime]);
 const familyRoot=(await f.home.get()).data(),privateRoot=(await f.source.parent!.get()).data();
 const transferBefore=(await f.pages()).map(p=>[p.id,p.data()]);
 const guards=async()=>{
  assert.deepEqual((await f.source.parent!.get()).data(),privateRoot);
  assert.deepEqual((await f.home.get()).data(),familyRoot);
  assert.deepEqual((await f.home.collection('shoppingItems').get()).docs.map(d=>[d.id,d.data(),d.updateTime]),familyBefore);
  assert.equal((await db.doc('familyMemberships/guest').get()).get('state'),'RESERVED');
  assert.equal((await db.doc('users/guest').get()).get('activeHouseholdId'),privateHouseholdId('guest'));
  assert.equal((await f.home.collection('members').doc('guest').get()).exists,false);
  assert.equal((await db.doc('familyJoinCapacity/family-test').get()).get('structuralOperationId'),f.id);
  const invite=await db.doc(`familyInvites/${f.invite.inviteId}`).get();assert.equal(invite.get('status'),'RESERVED');assert.equal(invite.get('usedAt'),null);
  assert.deepEqual((await f.pages()).map(p=>{const {cleanup,...original}=p.data();return [p.id,original];}),transferBefore);
 };
 const complete=async()=>{for(let i=0;i<40&&(await f.op()).phase==='CLEAN_SOURCE'&&(await f.op()).status==='READY';i++)await f.tick();assert.equal((await f.op()).phase,'TRANSFER_COMPLETE');assert.equal((await f.op()).status,'READY');};
 return {...f,guards,complete};
}
for(const mode of ['ADD','DELETE'] as const)for(const n of mode==='ADD'?[0,1,11,25,201]:[0,1,25])test(`${mode} cleanup ${n}: exact evidence, empty fenced fallback, no activation`,async()=>{
 const f=await cleanupFixture(n,mode);await f.complete();await f.guards();assert.equal((await f.source.get()).size,0);
 const pages=await f.pages(),o=await f.op();assert.equal(pages.flatMap(p=>p.get('cleanup')).length,n);
 for(const p of pages){assert.ok(p.get('cleanup').length<=10);for(const c of p.get('cleanup')){
  assert.equal(c.code,'DELETED');assert.equal(c.cleanupId,cleanupChildId(f.id,o,p.get('pageIndex'),c.childIndex));
  assert.equal(c.transferId,transferChildId(f.id,o,p.get('pageIndex'),c.childIndex));
  assert.equal(c.dataHash,p.get('entries')[c.childIndex].dataHash);
 }}
 assert.equal(o.cursor,null);await assert.rejects(f.shopping.ensureContext({uid:'guest'}));
 for(const uid of ['guest','owner'])await assert.rejects(new LifecycleStore(db,f.clock).beginDeletion(uid),/JOIN_COMMITTED_IN_PROGRESS/);
 const proof=pages.map(p=>[p.id,p.data(),p.updateTime]);await f.tick();await f.tick();
 assert.equal((await f.op()).phase,'TRANSFER_COMPLETE');assert.deepEqual((await f.pages()).map(p=>[p.id,p.data(),p.updateTime]),proof);await f.guards();
});
for(const mode of ['ADD','DELETE'] as const)test(`${mode} interruption resumes 10/10/5 without replay`,async()=>{
 const f=await cleanupFixture(25,mode);await f.tick();assert.equal((await f.source.get()).size,15);assert.deepEqual((await f.op()).cursor,{pageIndex:1,childOffset:0});
 const first=(await f.pages())[0]!.data();await f.tick();assert.equal((await f.source.get()).size,5);assert.deepEqual((await f.op()).cursor,{pageIndex:2,childOffset:0});
 await f.tick();assert.equal((await f.source.get()).size,0);assert.equal((await f.op()).phase,'CLEAN_SOURCE');
 await f.complete();assert.deepEqual((await f.pages())[0]!.data(),first);await f.guards();
});
test('lost cleanup acknowledgement recovers from atomic deletion evidence',async()=>{
 const f=await cleanupFixture(11);f.advance();const lease=(await f.join.claim(f.id))!;const original=db.runTransaction.bind(db);
 const wrapped=new Proxy(db,{get(t,k){if(k==='runTransaction')return async(...args:any[])=>{await (original as any)(...args);throw new Error('lostAck');};const v=(t as any)[k];return typeof v==='function'?v.bind(t):v;}}) as Firestore;
 await assert.rejects(new FamilyJoinStore(wrapped,f.clock).step(f.id,lease),/lostAck/);
 assert.equal((await f.source.get()).size,1);assert.equal((await f.pages())[0]!.get('cleanup').length,10);
 await f.complete();await f.guards();
});
test('competing cleanup workers and expired lease retain structural ownership',async()=>{
 const f=await cleanupFixture(25);f.advance();const claims=await Promise.all([f.join.claim(f.id),new FamilyJoinStore(db,f.clock,1000).claim(f.id)]);assert.equal(claims.filter(Boolean).length,1);
 const old=claims.find(Boolean)!;f.advance();const lease=(await f.join.claim(f.id))!;assert.equal(await f.join.step(f.id,old),'BUSY');
 await Promise.all([f.join.step(f.id,lease),f.join.step(f.id,lease)]);await f.complete();await f.guards();
});
test('aborted cleanup transaction leaves all source documents and no receipts',async()=>{
 const f=await cleanupFixture(11);f.advance();const lease=(await f.join.claim(f.id))!;const original=db.runTransaction.bind(db);
 const wrapped=new Proxy(db,{get(t,k){if(k==='runTransaction')return (cb:any)=>original(async tx=>{await cb(tx);throw Object.assign(new Error('forcedAbort'),{code:10});},{maxAttempts:1});const v=(t as any)[k];return typeof v==='function'?v.bind(t):v;}}) as Firestore;
 await assert.rejects(new FamilyJoinStore(wrapped,f.clock).step(f.id,lease),/forcedAbort/);
 assert.equal((await f.source.get()).size,11);assert.equal((await f.pages())[0]!.get('cleanup'),undefined);assert.equal((await f.op()).cursor,null);
 await f.complete();await f.guards();
});
test('recorded cleanup can be safely reobserved without new delete identity',async()=>{
 const f=await cleanupFixture(11);await f.tick();const first=(await f.pages())[0]!.data();
 // Simulate a lagging progress checkpoint, never missing effect evidence.
 await f.ref.update({cursor:null});await f.tick();assert.deepEqual((await f.pages())[0]!.data(),first);assert.equal((await f.source.get()).size,1);
 await f.complete();await f.guards();
});
for(const corruption of ['missing','content','updateTime','journalHash','transferResult','cleanupId','partialCleanup','recreated','cursorSkip','extraSource'])test(`${corruption} integrity parks OPERATOR; unrelated/mismatched documents never deleted`,async()=>{
 const f=await cleanupFixture(11),first=(await f.pages())[0]!;
 if(corruption==='missing')await f.source.doc('i0009').delete();
 if(corruption==='content')await f.source.doc('i0009').update({quantity:999});
 if(corruption==='updateTime'){
  const d=await f.source.doc('i0009').get();
  // An identical set can be a Firestore no-op. Make a real change, restore the
  // original payload, then prove only the document version has changed.
  await d.ref.update({quantity:999});await d.ref.set(d.data()!);
  const restored=await d.ref.get();assert.deepEqual(restored.data(),d.data());assert.equal(restored.updateTime!.isEqual(d.updateTime!),false);
 }
 if(corruption==='journalHash')await first.ref.update({chainHash:'0'.repeat(64)});
 if(corruption==='transferResult'){const results=first.get('results');results[0].code='FAILED_TERMINAL';await first.ref.update({results});}
 if(corruption==='cursorSkip')await f.ref.update({cursor:{pageIndex:1,childOffset:0}});
 if(corruption==='extraSource')await f.source.doc('unrelated').set({name:'do not delete',quantity:1,unit:'db'});
 if(['cleanupId','partialCleanup','recreated'].includes(corruption)){
  await f.tick();const cleaned=(await first.ref.get()).get('cleanup');
  if(corruption==='cleanupId'){cleaned[0].cleanupId='0'.repeat(64);await first.ref.update({cleanup:cleaned});}
  if(corruption==='partialCleanup')await first.ref.update({cleanup:cleaned.slice(0,1)});
  if(corruption==='recreated')await f.source.doc('i0000').set({name:'replacement',quantity:5,unit:'db'});
 }
 for(let i=0;i<4&&(await f.op()).status==='READY';i++)await f.tick();assert.equal((await f.op()).status,'OPERATOR');assert.equal((await f.op()).nextAt,null);
 if(corruption==='extraSource')assert.equal((await f.source.doc('unrelated').get()).exists,true);
 else if(corruption==='recreated')assert.equal((await f.source.doc('i0000').get()).get('name'),'replacement');
 else if(['cleanupId','partialCleanup'].includes(corruption))assert.equal((await f.source.get()).size,1);
 else assert.equal((await f.source.get()).size,corruption==='missing'?10:11);
 assert.equal((await f.source.parent!.get()).get('operationId'),f.id);assert.equal((await db.doc('familyJoinCapacity/family-test').get()).get('structuralOperationId'),f.id);
 assert.equal((await f.home.collection('shoppingItems').get()).size,11);
});
test('postcommit cancellation, expiry and Pro loss cannot abort cleanup; deletion remains deferred',async()=>{
 const f=await cleanupFixture(25);await f.tick();assert.equal((await f.invites.revoke({uid:'owner'},f.invite.inviteId)).code,'IN_PROGRESS');assert.equal(await f.engine.cancel({uid:'guest'},f.id,f.invite.inviteId),'IN_PROGRESS');
 f.advance(8*86400000);await db.doc('users/owner/entitlementGrants/pro').delete();await db.doc('familyRuntime/config').update({joinReservationEnabled:false});
 await assert.rejects(new LifecycleStore(db,f.clock).beginDeletion('guest'),/JOIN_COMMITTED_IN_PROGRESS/);await f.complete();await f.guards();
 await assert.rejects(new LifecycleStore(db,f.clock).beginDeletion('guest'),/JOIN_COMMITTED_IN_PROGRESS/);await assert.rejects(f.shopping.ensureContext({uid:'guest'}));
});
test('empty source is proven after final deletion, never predicted from the cursor',async()=>{
 const f=await cleanupFixture(1,'DELETE');await f.tick();assert.equal((await f.op()).phase,'CLEAN_SOURCE');
 await f.source.doc('late-unrelated').set(milk());await f.tick();assert.equal((await f.op()).status,'OPERATOR');assert.equal((await f.source.doc('late-unrelated').get()).exists,true);
});
test('old accepted private command remains rejected during cleanup and after completion',async()=>{
 const f=await cleanupFixture(11,'ADD',true);await f.tick();
 assert.notEqual(await f.shopping.process('guest',f.oldMutationId!),'APPLIED');assert.equal((await f.source.get()).size,1);
 await assert.rejects(f.shopping.ensureContext({uid:'guest'}));await f.complete();
 assert.notEqual(await f.shopping.process('guest',f.oldMutationId!),'APPLIED');assert.equal((await f.source.get()).size,0);await f.guards();
});
