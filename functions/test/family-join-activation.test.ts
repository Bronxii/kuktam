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
requireLocalEmulator(process.env);
const app=initializeApp({projectId:'demo-kuktam-local'},'family-join-activation'),db=getFirestore(app);
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

async function ready(n=1,mode:'ADD'|'DELETE'='ADD',pending=false){
 const f=await fixture(unique(n),mode,pending);await f.finish();
 for(let i=0;i<40&&(await f.op()).phase==='CLEAN_SOURCE';i++)await f.tick();
 assert.equal((await f.op()).phase,'TRANSFER_COMPLETE');assert.equal((await f.source.get()).size,0);
 const journal=(await f.pages()).map(p=>[p.id,p.data(),p.updateTime]);
 const familyItems=(await f.home.collection('shoppingItems').get()).docs.map(d=>[d.id,d.data(),d.updateTime]);
 const oldRoot=(await f.source.parent!.get()).data()!;
 const unchangedShopping=async()=>{
  assert.equal((await f.source.get()).size,0);
  assert.deepEqual((await f.home.collection('shoppingItems').get()).docs.map(d=>[d.id,d.data(),d.updateTime]),familyItems);
  assert.deepEqual((await f.pages()).map(p=>[p.id,p.data(),p.updateTime]),journal);
 };
 const stable=async()=>{
  const op=await f.op();assert.equal(op.phase,'ACTIVE');assert.equal(op.status,'DONE');assert.equal(op.nextAt,null);assert.equal(op.leaseId,null);assert.equal(op.lastOutcome,'joinActivated');
  assert.deepEqual((await db.doc('familyMemberships/guest').get()).data(),{householdId:'family-test',role:'member',state:'ACTIVE',operationId:null});
  assert.deepEqual((await f.home.collection('members').doc('guest').get()).data(),{role:'member'});
  const u=await db.doc('users/guest').get();assert.equal(u.get('activeHouseholdId'),'family-test');assert.equal(u.get('familyHouseholdId'),'family-test');assert.equal(u.get('privateHouseholdId'),privateHouseholdId('guest'));
  const root=await f.source.parent!.get();assert.ok(root.exists);assert.equal(root.get('operationId'),null);assert.notEqual(root.get('shoppingEpoch'),oldRoot.shoppingEpoch);
  const {shoppingEpoch,shoppingEpochExpiresAt,operationId,...rest}=root.data()!;
  const {shoppingEpoch:oldEpoch,shoppingEpochExpiresAt:oldExpires,operationId:oldId,...oldRest}=oldRoot;assert.deepEqual(rest,oldRest);
  assert.equal((await db.doc(`households/${privateHouseholdId('guest')}/members/guest`).get()).get('role'),'owner');
  const inv=await db.doc(`familyInvites/${f.invite.inviteId}`).get();assert.equal(inv.get('status'),'USED');assert.equal(inv.get('usedByUid'),'guest');assert.equal(inv.get('operationId'),f.id);assert.ok(inv.get('usedAt') instanceof Timestamp);
  assert.equal((await db.doc('familyJoinCapacity/family-test').get()).get('structuralOperationId'),null);
  assert.ok(!(await db.doc('familyJoinCapacity/family-test').get()).get('operationIds').includes(f.id));
  assert.ok(!(await db.doc('familyInviteSlots/family-test').get()).get('inviteIds').includes(f.invite.inviteId));
  await unchangedShopping();
 };
 return {...f,stable,unchangedShopping,oldRoot};
}
for(const mode of ['ADD','DELETE'] as const)for(const n of [0,1,11,201])test(`${mode} ${n}: atomic ACTIVE/DONE, preserved empty fallback and immutable journal`,async()=>{
 const f=await ready(n,mode);const home=(await f.home.get()).data();assert.equal(await f.tick(),'DONE');await f.stable();assert.deepEqual((await f.home.get()).data(),home);
 const rows=await f.home.collection('members').get(),cap=(await db.doc('familyJoinCapacity/family-test').get()).data()!;assert.equal(rows.size+cap.operationIds.length,2);
});
test('activation reentry returns DONE without epoch, capacity, invite or shopping rewrites',async()=>{
 const f=await ready(11);await f.tick();await f.stable();
 const refs=[f.ref,f.source.parent!,f.home,db.doc('users/guest'),db.doc('familyMemberships/guest'),db.doc('familyJoinCapacity/family-test'),db.doc(`familyInvites/${f.invite.inviteId}`)];
 const before=(await db.getAll(...refs)).map(d=>[d.data(),d.updateTime]);
 for(let i=0;i<3;i++)assert.equal(await f.tick(),'DONE');
 assert.deepEqual((await db.getAll(...refs)).map(d=>[d.data(),d.updateTime]),before);await f.stable();
});
test('lost activation acknowledgement recovers existing DONE without replay',async()=>{
 const f=await ready();f.advance();const lease=(await f.join.claim(f.id))!,original=db.runTransaction.bind(db);
 const wrapped=new Proxy(db,{get(t,k){if(k==='runTransaction')return async(...args:any[])=>{await (original as any)(...args);throw new Error('lostAck');};const v=(t as any)[k];return typeof v==='function'?v.bind(t):v;}}) as Firestore;
 await assert.rejects(new FamilyJoinStore(wrapped,f.clock).step(f.id,lease),/lostAck/);await f.stable();
 const root=await f.source.parent!.get();assert.equal(await f.tick(),'DONE');assert.ok((await f.source.parent!.get()).updateTime!.isEqual(root.updateTime!));await f.stable();
});
test('competing claims and same-lease transaction workers activate once',async()=>{
 const f=await ready(11);f.advance();const leases=await Promise.all([f.join.claim(f.id),f.join.claim(f.id)]);assert.equal(leases.filter(Boolean).length,1);
 const results=await Promise.all([f.join.step(f.id,leases.find(Boolean)!),f.join.step(f.id,leases.find(Boolean)!)]);assert.deepEqual(results,['DONE','DONE']);await f.stable();
});
test('aborted activation transaction exposes neither half of pointer/member transition',async()=>{
 const f=await ready();f.advance();const lease=(await f.join.claim(f.id))!,original=db.runTransaction.bind(db);
 const wrapped=new Proxy(db,{get(t,k){if(k==='runTransaction')return (cb:any)=>original(async tx=>{await cb(tx);throw Object.assign(new Error('forcedAbort'),{code:10});},{maxAttempts:1});const v=(t as any)[k];return typeof v==='function'?v.bind(t):v;}}) as Firestore;
 await assert.rejects(new FamilyJoinStore(wrapped,f.clock).step(f.id,lease),/forcedAbort/);
 assert.equal((await f.op()).phase,'TRANSFER_COMPLETE');assert.equal((await db.doc('familyMemberships/guest').get()).get('state'),'RESERVED');assert.equal((await db.doc('users/guest').get()).get('activeHouseholdId'),privateHouseholdId('guest'));
 assert.equal((await f.home.collection('members').doc('guest').get()).exists,false);assert.deepEqual((await f.source.parent!.get()).data(),f.oldRoot);await f.unchangedShopping();
 await f.tick();await f.stable();
});
for(const event of ['expiry','proLoss','revoke','cancel','gateDisabled','epochExpired'])test(`postcommit ${event} cannot roll back mandatory activation`,async()=>{
 const f=await ready();
 if(event==='expiry')f.advance(8*86400000);
 if(event==='epochExpired')f.advance(40*86400000);
 if(event==='proLoss')await db.doc('users/owner/entitlementGrants/pro').delete();
 if(event==='revoke')assert.equal((await f.invites.revoke({uid:'owner'},f.invite.inviteId)).code,'IN_PROGRESS');
 if(event==='cancel')assert.equal(await f.engine.cancel({uid:'guest'},f.id,f.invite.inviteId),'IN_PROGRESS');
 if(event==='gateDisabled')await db.doc('familyRuntime/config').set({inviteCreationEnabled:false,joinReservationEnabled:false});
 assert.equal(await f.tick(),'DONE');await f.stable();assert.equal((await f.shopping.ensureContext({uid:'guest'})).householdId,'family-test');
 assert.equal((await f.invites.revoke({uid:'owner'},f.invite.inviteId)).code,'USED');
});
test('old private request stays rejected; fresh normal context and ADD route to family',async()=>{
 const f=await ready(1,'ADD',true);await f.tick();await f.stable();
 assert.notEqual(await f.shopping.process('guest',f.oldMutationId!),'APPLIED');assert.equal((await f.source.get()).size,0);
 const c=await f.shopping.ensureContext({uid:'guest'});assert.equal(c.householdId,'family-test');const mutationId=newMutationId(c.epoch);
 await f.shopping.submit({uid:'guest'},{schemaVersion:1,actorUid:'guest',...c,mutationId,kind:'ADD',payloadJson:JSON.stringify({type:'ADD',...milk()}),submittedAt:f.clock()});
 assert.equal(await f.shopping.process('guest',mutationId),'APPLIED');assert.equal((await f.source.get()).size,0);assert.equal((await f.home.collection('shoppingItems').get()).size,2);
});
test('ACTIVE admission remains safely blocked for guest and owner until Family lifecycle implementation',async()=>{
 const f=await ready();await f.tick();
 for(const uid of ['guest','owner']){
  const marker=await db.doc(`accountLifecycle/${uid}`).get(),store=new LifecycleStore(db,f.clock);
  await assert.rejects(store.beginDeletion(uid),/FAMILY_LIFECYCLE_NOT_READY/);
  await assert.rejects(store.advanceAccountMarker({uid},marker.get('generation'),'DELETING'),/FAMILY_LIFECYCLE_NOT_READY/);
  assert.deepEqual((await marker.ref.get()).data(),marker.data());assert.equal((await db.doc(`accountDeletions/${uid}`).get()).exists,false);
 }
 await f.stable();
});
for(const corruption of ['lock','reservation','digest','cleanup','receipt','missingPage','cursor','extraSource','target','sequence','familyEpoch','sourceEpoch'])test(`${corruption} integrity failure parks OPERATOR without partial activation`,async()=>{
 const f=await ready(11),page=(await f.pages())[0]!;
 if(corruption==='lock')await db.doc('familyJoinCapacity/family-test').update({structuralOperationId:'join_'+'a'.repeat(64),operationIds:[f.id,'join_'+'a'.repeat(64)]});
 if(corruption==='reservation')await db.doc('familyMemberships/guest').update({operationId:'other'});
 if(corruption==='digest')await f.ref.update({'snapshot.hash':'0'.repeat(64)});
 if(corruption==='cleanup'){const cleanup=page.get('cleanup');cleanup[0].cleanupId='0'.repeat(64);await page.ref.update({cleanup});}
 if(corruption==='receipt'){const results=page.get('results');results[0].revision=999;await page.ref.update({results});}
 if(corruption==='missingPage')await page.ref.delete();
 if(corruption==='cursor')await f.ref.update({cursor:{pageIndex:0,childOffset:0}});
 if(corruption==='extraSource')await f.source.doc('unrelated').set(milk());
 if(corruption==='target')await f.home.update({ownerUid:'other'});
 if(corruption==='sequence')await f.home.update({shoppingRevision:0});
 if(corruption==='familyEpoch')await f.home.update({shoppingEpoch:'corrupt'});
 if(corruption==='sourceEpoch')await f.source.parent!.update({shoppingEpochExpiresAt:Timestamp.fromMillis(1)});
 const sourceBefore=(await f.source.parent!.get()).data();
 await f.tick();assert.equal((await f.op()).status,'OPERATOR');assert.equal((await f.op()).phase,'TRANSFER_COMPLETE');assert.equal((await f.op()).nextAt,null);
 assert.equal((await db.doc('familyMemberships/guest').get()).get('state'),'RESERVED');assert.equal((await db.doc('users/guest').get()).get('activeHouseholdId'),privateHouseholdId('guest'));
 assert.equal((await f.home.collection('members').doc('guest').get()).exists,false);assert.deepEqual((await f.source.parent!.get()).data(),sourceBefore);
 assert.equal((await db.doc(`familyInvites/${f.invite.inviteId}`).get()).get('status'),'RESERVED');
 assert.equal((await f.home.collection('shoppingItems').get()).size,11);if(corruption==='extraSource')assert.ok((await f.source.doc('unrelated').get()).exists);
});
test('activation removes only its own reserved capacity and invite entries',async()=>{
 const f=await ready();await new HouseholdStore(db).ensure({uid:'other'});const invite=await f.invites.create({uid:'owner'});
 const other=await f.join.reserve({uid:'other'},invite.token,'ADD');await f.tick();await f.stable();
 assert.deepEqual((await db.doc('familyJoinCapacity/family-test').get()).get('operationIds'),[other]);
 assert.deepEqual((await db.doc('familyInviteSlots/family-test').get()).get('inviteIds'),[invite.inviteId]);
 assert.equal((await f.home.collection('members').get()).size+1,3);
});
