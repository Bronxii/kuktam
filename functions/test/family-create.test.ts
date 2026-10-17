import { after, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeApp, deleteApp } from 'firebase-admin/app';
import { getFirestore, Timestamp, GeoPoint } from 'firebase-admin/firestore';
import { requireLocalEmulator } from './emulator-guard';
import { HouseholdStore, privateHouseholdId } from '../src/households/household-store';
import { FamilyCreateStore, CreatePhase, readCreateOperation } from '../src/households/family-create';
import { AccountDeletionService } from '../src/accounts/account-deletion';
import { FakeAuthDeletionApi } from './fake-auth-deletion-api';
import { grant, now } from './fixtures';
import { Maintenance } from '../src/jobs/maintenance';
import { FakePlayApi } from './fake-play-api';
import { FakeVoidedApi } from './fake-voided-api';
import { FakeAcknowledgmentApi } from './fake-acknowledgment-api';
import { FakeVoidedFeed } from './fake-voided-feed';
import { AccountBinding } from '../src/billing/account-binding';
requireLocalEmulator(process.env);
const app=initializeApp({projectId:'demo-kuktam-local'},'family-create'), db=getFirestore(app);
beforeEach(async()=>{assert.ok((await fetch('http://127.0.0.1:8088/emulator/v1/projects/demo-kuktam-local/databases/(default)/documents',{method:'DELETE'})).ok);});
after(()=>deleteApp(app));
async function setup(count=0,pro=true,uid='owner') {
  await new HouseholdStore(db).ensure({uid});
  await db.doc('familyRuntime/config').set({creationEnabled:true});
  if(pro)await db.doc(`users/${uid}/entitlementGrants/pro`).set(grant());
  let time=now.toMillis()+1000;
  const clock=()=>Timestamp.fromMillis(time), service=new FamilyCreateStore(db,clock,3,10000);
  const p=privateHouseholdId(uid), source=db.collection(`households/${p}/shoppingItems`);
  for(let i=0;i<count;i++)await source.doc(`item-${String(i).padStart(4,'0')}`).set({name:`item ${i}`,quantity:i%2?1.5:2,unit:'g',isChecked:i%2===0,
    createdAt:now,forward:{array:[null,true,3]},point:new GeoPoint(47,19),reference:db.doc('ingredients/test'),bytes:Buffer.from('fixture')});
  const snapshot=await source.get();
  const expected=new Map(snapshot.docs.map(d=>[d.id,d.data()]));
  return {uid,p,source,service,clock,expected,advance:()=>{time+=10001;}};
}
async function finish(s:Awaited<ReturnType<typeof setup>>,id:string) {
  for(let i=0;i<100;i++){
    const status=(await db.doc(`familyOperations/${id}`).get()).get('status');
    if(status!=='READY')return status;
    await s.service.resume(id,2);
  }
  throw new Error('didNotConverge');
}
async function assertDone(s:Awaited<ReturnType<typeof setup>>,id:string,expectedOperations=1) {
  const op=readCreateOperation((await db.doc(`familyOperations/${id}`).get()).data());
  assert.equal(op.status,'DONE');assert.equal(op.leaseId,null);assert.equal(op.nextAt,null);
  const user=await db.doc(`users/${s.uid}`).get(), home=await db.doc(`households/${op.householdId}`).get();
  assert.equal(user.get('privateHouseholdId'),s.p);assert.equal(user.get('activeHouseholdId'),op.householdId);assert.equal(user.get('familyHouseholdId'),op.householdId);
  assert.equal(home.get('state'),'ACTIVE');assert.equal(home.get('operationId'),null);
  assert.deepEqual((await db.doc(`familyMemberships/${s.uid}`).get()).data(),{householdId:op.householdId,role:'owner',state:'ACTIVE',operationId:null});
  assert.deepEqual((await home.ref.collection('members').doc(s.uid).get()).data(),{role:'owner'});
  const privateHome=await db.doc(`households/${s.p}`).get();assert.ok(privateHome.exists);assert.equal(privateHome.get('operationId'),null);
  assert.equal((await s.source.get()).size,0);
  const items=await home.ref.collection('shoppingItems').get();assert.equal(items.size,s.expected.size);
  for(const d of items.docs)assert.deepEqual(d.data(),s.expected.get(d.id));
  assert.equal((await db.collection('familyOperations').get()).size,expectedOperations);
  assert.equal((await db.collection('households').where('kind','==','family').get()).size,1);
  assert.equal((await db.collection(`familyOperations/${id}/items`).get()).size,0);
}
test('default-off server gate denies before allocating anything',async()=>{
 const s=await setup();await db.doc('familyRuntime/config').delete();
 await assert.rejects(s.service.reserve({uid:s.uid}),/featureDisabled/);
 assert.equal((await db.collection('familyOperations').get()).size,0);
});
for(const reason of ['free','expired','revoked','DELETING','DELETED','invalidLifecycle','migration','private','alreadyFamily'])test(`validation rejects ${reason} before reservation`,async()=>{
 const s=await setup(0,reason!=='free');
 if(reason==='expired')await db.doc(`users/${s.uid}/entitlementGrants/pro`).update({expiresAt:now});
 if(reason==='revoked')await db.doc(`users/${s.uid}/entitlementGrants/pro`).update({status:'REVOKED',revokedAt:now});
 if(['DELETING','DELETED','invalidLifecycle'].includes(reason))await db.doc(`accountLifecycle/${s.uid}`).set({schemaVersion:1,state:reason,generation:2,updatedAt:now,deletionStartedAt:now,deletedAt:reason==='DELETED'?now:null});
 if(reason==='migration')await db.doc(`users/${s.uid}`).update({shoppingMigrationVersion:0});
 if(reason==='private')await db.doc(`households/${s.p}`).update({ownerUid:'other'});
 if(reason==='alreadyFamily')await db.doc(`familyMemberships/${s.uid}`).set({householdId:'f',role:'member',state:'ACTIVE',operationId:null});
 await assert.rejects(s.service.reserve({uid:s.uid}));
 assert.equal((await db.collection('familyOperations').get()).size,0);
 assert.equal((await db.collection('households').where('kind','==','family').get()).size,0);
});
test('canonical aggregation ignores stale effective cache and keeps another valid grant',async()=>{
 const s=await setup();await db.doc(`users/${s.uid}/entitlements/pro`).set({active:false});
 await db.doc(`users/${s.uid}/entitlementGrants/revoked`).set(grant({source:'ADMIN',status:'REVOKED',revokedAt:now}));
 const id=await s.service.reserve({uid:s.uid});assert.equal(await finish(s,id),'DONE');
 assert.deepEqual((await db.doc(`users/${s.uid}/entitlements/pro`).get()).data(),{active:false});
});
test('historical effective active without valid grants does not authorize',async()=>{
 const s=await setup(0,false);await db.doc(`users/${s.uid}/entitlements/pro`).set({active:true});
 await assert.rejects(s.service.reserve({uid:s.uid}),/proRequired/);
});
for(const count of [0,1,7,67])test(`lossless CREATE ${count} items with bounded restart and idempotency`,async()=>{
 const s=await setup(count);const id=await s.service.reserve({uid:s.uid});
 const op=readCreateOperation((await db.doc(`familyOperations/${id}`).get()).data());
 assert.equal((await db.doc(`users/${s.uid}`).get()).get('activeHouseholdId'),s.p);
 await s.service.resume(id,1);
 assert.equal((await s.source.get()).size,count);
 assert.ok((await db.collection(`households/${op.householdId}/shoppingItems`).get()).size<=3);
 assert.equal(await s.service.reserve({uid:s.uid}),id);
 assert.equal(await finish(s,id),'DONE');await assertDone(s,id);
 assert.equal(await s.service.reserve({uid:s.uid}),id);assert.equal(await s.service.resume(id),'DONE');await assertDone(s,id);
});
for(const stop of ['COPY','VERIFY','ACTIVATE','CLEAN_SOURCE','FINALIZE'] as CreatePhase[])test(`crash at ${stop} safely resumes after lease expiry`,async()=>{
 const s=await setup(5),id=await s.service.reserve({uid:s.uid}),lease=await s.service.claim(id);assert.ok(lease);
 for(let i=0;i<30;i++){
  const op=readCreateOperation((await db.doc(`familyOperations/${id}`).get()).data());if(op.phase===stop)break;
  await s.service.step(id,lease);
 }
 assert.equal((await db.doc(`familyOperations/${id}`).get()).get('phase'),stop);
 assert.equal(await s.service.claim(id),null);s.advance();
 const fresh=new FamilyCreateStore(db,s.clock,3,10000);
 assert.equal(await s.service.step(id,lease),'BUSY');
 await fresh.resume(id,1);assert.equal(await finish(s,id),'DONE');await assertDone(s,id);
});
test('simultaneous reservations and workers create exactly one family',async()=>{
 const s=await setup(7),ids=await Promise.all([s.service.reserve({uid:s.uid}),s.service.reserve({uid:s.uid})]);assert.equal(ids[0],ids[1]);
 await Promise.all([s.service.resume(ids[0]!,3),s.service.resume(ids[0]!,3)]);
 assert.equal(await finish(s,ids[0]!),'DONE');await assertDone(s,ids[0]!);
});
test('partial cleanup crash preserves authoritative family edits and never recopies',async()=>{
 const s=await setup(7),id=await s.service.reserve({uid:s.uid});let op;
 do {await s.service.resume(id,1);op=readCreateOperation((await db.doc(`familyOperations/${id}`).get()).data());}while(op.phase!=='CLEAN_SOURCE');
 await db.doc(`households/${op.householdId}/shoppingItems/item-0000`).update({name:'edited after activation'});
 await s.service.resume(id,1);assert.equal((await s.source.get()).size,4);
 assert.equal(await finish(s,id),'DONE');
 assert.equal((await db.doc(`households/${op.householdId}/shoppingItems/item-0000`).get()).get('name'),'edited after activation');
});
test('Pro loss immediately before activation aborts; explicit retry can allocate after eligibility returns',async()=>{
 const s=await setup(5),id=await s.service.reserve({uid:s.uid});
 while((await db.doc(`familyOperations/${id}`).get()).get('phase')!=='ACTIVATE')await s.service.resume(id,1);
 const oldHome=(await db.doc(`familyOperations/${id}`).get()).get('householdId');
 await db.doc(`users/${s.uid}/entitlementGrants/pro`).delete();
 assert.equal(await finish(s,id),'ABORTED');assert.equal((await s.source.get()).size,5);
 await db.doc(`users/${s.uid}/entitlementGrants/pro`).set(grant());
 assert.equal(await s.service.reserve({uid:s.uid}),id);assert.equal(await finish(s,id),'DONE');await assertDone(s,id);
 assert.equal((await db.doc(`households/${oldHome}`).get()).exists,false);
});
test('worker failure leaves durable retry and a new instance resumes without duplicate copy',async()=>{
 const s=await setup(5),id=await s.service.reserve({uid:s.uid});await s.service.resume(id,1);
 const failing=new FamilyCreateStore(db,s.clock,3,10000);
 failing.step=async()=>{throw new Error('simulated transport failure');};
 assert.equal(await failing.resume(id),'retry');
 const op=readCreateOperation((await db.doc(`familyOperations/${id}`).get()).data());
 assert.equal(op.leaseId,null);assert.equal(op.lastOutcome,'retry');assert.equal(op.phase,'COPY');
 assert.equal(await s.service.claim(id),null);s.advance();s.advance();s.advance();
 assert.equal(await finish(s,id),'DONE');await assertDone(s,id);
});
for(const reason of ['proLost','collision','corruptCopy','deletion','missingRoot'])test(`pre-activation abort ${reason} preserves private data`,async()=>{
 const s=await setup(5),id=await s.service.reserve({uid:s.uid});await s.service.resume(id,1);
 const op=readCreateOperation((await db.doc(`familyOperations/${id}`).get()).data());
 if(reason==='proLost')await db.doc(`users/${s.uid}/entitlementGrants/pro`).delete();
 if(reason==='collision')await db.doc(`households/${op.householdId}/shoppingItems/item-0004`).set({name:'collision'});
 if(reason==='corruptCopy')await db.doc(`households/${op.householdId}/shoppingItems/item-0000`).update({name:'corrupt'});
 if(reason==='deletion'||reason==='missingRoot'){
  const deletion=new AccountDeletionService(db,new FakeAuthDeletionApi());await deletion.beginAccountDeletion({uid:s.uid});
  assert.equal(await deletion.resume(s.uid,1),'cleanupRetryRequired');
  if(reason==='missingRoot')await db.doc(`users/${s.uid}`).delete();
 }
 assert.equal(await finish(s,id),'ABORTED');
 assert.equal((await db.doc(`households/${op.householdId}`).get()).exists,false);
 assert.equal((await db.doc(`familyMemberships/${s.uid}`).get()).exists,false);
 assert.equal((await db.doc(`households/${s.p}`).get()).get('operationId'),null);
 const source=await s.source.get();assert.equal(source.size,5);for(const d of source.docs)assert.deepEqual(d.data(),s.expected.get(d.id));
 if(reason==='missingRoot')assert.equal((await db.doc(`users/${s.uid}`).get()).exists,false);
 else assert.equal((await db.doc(`users/${s.uid}`).get()).get('activeHouseholdId'),s.p);
});
test('deletion after activation remains fail-closed, while CREATE finishes cleanup',async()=>{
 const s=await setup(5),id=await s.service.reserve({uid:s.uid});
 while((await db.doc(`familyOperations/${id}`).get()).get('phase')!=='CLEAN_SOURCE')await s.service.resume(id,1);
 const deletion=new AccountDeletionService(db,new FakeAuthDeletionApi());await deletion.beginAccountDeletion({uid:s.uid});
 assert.equal(await finish(s,id),'DONE');
 assert.equal(await deletion.resume(s.uid,2),'cleanupRetryRequired');
 assert.notEqual((await db.doc(`accountDeletions/${s.uid}`).get()).get('stage'),'DONE');
});
test('disabling gate does not strand maintenance continuation or touch billing',async()=>{
 const s=await setup(7),id=await s.service.reserve({uid:s.uid});await db.doc('familyRuntime/config').set({creationEnabled:false});
 const binding=new AccountBinding({currentVersion:'v1',material:()=>Buffer.alloc(32,1)});
 const play=new FakePlayApi(),ack=new FakeAcknowledgmentApi();
 const maintenance=new Maintenance(db,{play,ack,voided:new FakeVoidedApi(),feed:new FakeVoidedFeed(),binding},s.clock);
 await db.doc('familyOperations/malformed').set({nextAt:s.clock()});
 for(let i=0;i<30&&(await db.doc(`familyOperations/${id}`).get()).get('status')==='READY';i++){
  await Promise.all([maintenance.run({now:s.clock(),only:['family']}),s.service.resume(id,1)]);
 }
 await assertDone(s,id,2);assert.equal(play.calls,0);assert.equal(ack.calls,0);
 const after=await maintenance.run({now:s.clock(),only:['family']});assert.ok(after.items.every(i=>i.key!==id));
});
