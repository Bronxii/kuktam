import {before,after,test} from 'node:test';
import assert from 'node:assert/strict';
import {initializeApp,deleteApp} from 'firebase-admin/app';
import {getFirestore,Timestamp as AdminTimestamp} from 'firebase-admin/firestore';
import {HouseholdStore} from '../src/households/household-store';
import {ShoppingMutationStore,advanceShoppingEpoch} from '../src/shopping/mutation-store';
import {Child,newMutationId} from '../src/shopping/mutation-contract';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {initializeTestEnvironment,assertFails,assertSucceeds,RulesTestEnvironment} from '@firebase/rules-unit-testing';
import {doc,setDoc,getDoc,getDocs,collection,onSnapshot,writeBatch,updateDoc,deleteDoc,Timestamp,serverTimestamp} from 'firebase/firestore';
import {requireLocalEmulator} from './emulator-guard';
requireLocalEmulator(process.env);
const adminApp=initializeApp({projectId:'demo-kuktam-local'},'s1c-rules');
const admin=getFirestore(adminApp),processor=new ShoppingMutationStore(admin);
let env:RulesTestEnvironment,n=0;
const expiry=Date.now()+86400000,epoch=`${expiry}-${'a'.repeat(32)}`;
const request=()=>{const mutationId=`${epoch}_${(++n).toString(16).padStart(64,'0')}`;return {schemaVersion:1,mutationId,actorUid:'u',householdId:'home',epoch,kind:'ADD',payloadJson:JSON.stringify({type:'ADD',name:'x',quantity:1,unit:'g'}),submittedAt:serverTimestamp()};};
before(async()=>{
 env=await initializeTestEnvironment({projectId:'demo-kuktam-local',firestore:{host:'127.0.0.1',port:8088,rules:readFileSync(resolve(__dirname,'../../../firestore.rules'),'utf8')}});await env.clearFirestore();
 await env.withSecurityRulesDisabled(async ctx=>{const db=ctx.firestore();
 for(const [path,data] of Object.entries({'shoppingRuntime/config':{enabled:true},'accountLifecycle/u':{state:'ACTIVE'},'users/u':{activeHouseholdId:'home',privateHouseholdId:'home',familyHouseholdId:null,shoppingMigrationVersion:1},'households/home':{schemaVersion:2,kind:'private',state:'ACTIVE',operationId:null,ownerUid:'u',shoppingEpoch:epoch,shoppingEpochExpiresAt:Timestamp.fromMillis(expiry)},'households/home/members/u':{role:'owner'},'households/home/shoppingItems/a':{name:'x',revision:1}}))await setDoc(doc(db,path),data);
 });
});
after(async()=>{await env.cleanup();await deleteApp(adminApp);});
test('immutable owner command create/read; no update/delete or other user read',async()=>{
 const db=env.authenticatedContext('u').firestore(),r=request(),path=`users/u/shoppingMutations/${r.mutationId}`;await assertSucceeds(setDoc(doc(db,path),r));await assertSucceeds(getDoc(doc(db,path)));
 await assertFails(updateDoc(doc(db,path),{payloadJson:'{}'}));await assertFails(deleteDoc(doc(db,path)));await assertFails(getDoc(doc(env.authenticatedContext('b').firestore(),path)));
});
for(const patch of [{actorUid:'b'},{householdId:'other'},{schemaVersion:2},{kind:'PATCH'},{status:'APPLIED'},{cursor:1},{result:{}},{submittedAt:Timestamp.fromMillis(1)},{epoch:`${expiry}-${'b'.repeat(32)}`},{payloadJson:'a'.repeat(262145)}])test(`reject envelope ${Object.keys(patch)}`,async()=>{
 const r=request();await assertFails(setDoc(doc(env.authenticatedContext('u').firestore(),`users/u/shoppingMutations/${r.mutationId}`),{...r,...patch}));
});
test('actor cannot impersonate path UID, unauthenticated denied',async()=>{
 const r=request();for(const db of [env.unauthenticatedContext().firestore(),env.authenticatedContext('b').firestore()])await assertFails(setDoc(doc(db,`users/u/shoppingMutations/${r.mutationId}`),r));
});
test('technical work/gate and epoch/revision are server owned; canonical CRUD is denied',async()=>{
 const db=env.authenticatedContext('u').firestore();
 for(const path of ['shoppingMutationWork/x','shoppingRuntime/config']){await assertFails(getDoc(doc(db,path)));await assertFails(setDoc(doc(db,path),{enabled:true}));}
 await assertFails(updateDoc(doc(db,'households/home'),{shoppingEpoch:'fake'}));await assertFails(updateDoc(doc(db,'households/home/shoppingItems/a'),{revision:2}));
 await assertFails(setDoc(doc(db,'households/home/shoppingItems/forged'),{revision:1}));
 await assertFails(updateDoc(doc(db,'households/home/shoppingItems/a'),{quantity:2}));await assertFails(setDoc(doc(db,'households/home/shoppingItems/legacy'),{name:'legacy'}));await assertFails(deleteDoc(doc(db,'households/home/shoppingItems/a')));
});
for(const state of ['DELETING','DELETED'])test(`${state} blocks command creation`,async()=>{
 await env.withSecurityRulesDisabled(ctx=>updateDoc(doc(ctx.firestore(),'accountLifecycle/u'),{state}));const r=request();await assertFails(setDoc(doc(env.authenticatedContext('u').firestore(),`users/u/shoppingMutations/${r.mutationId}`),r));await env.withSecurityRulesDisabled(ctx=>updateDoc(doc(ctx.firestore(),'accountLifecycle/u'),{state:'ACTIVE'}));
});
test('default/missing gate and expired context denied',async()=>{
 await env.withSecurityRulesDisabled(ctx=>deleteDoc(doc(ctx.firestore(),'shoppingRuntime/config')));const r=request();await assertFails(setDoc(doc(env.authenticatedContext('u').firestore(),`users/u/shoppingMutations/${r.mutationId}`),r));
 await env.withSecurityRulesDisabled(async ctx=>{await setDoc(doc(ctx.firestore(),'shoppingRuntime/config'),{enabled:true});await updateDoc(doc(ctx.firestore(),'households/home'),{shoppingEpochExpiresAt:Timestamp.fromMillis(1)});});
 await assertFails(setDoc(doc(env.authenticatedContext('u').firestore(),`users/u/shoppingMutations/${r.mutationId}`),r));
});
test('family owner/member requests fit rules access budget and RESERVED private remains authorized',async()=>{
 await env.withSecurityRulesDisabled(async ctx=>{const db=ctx.firestore();
  await setDoc(doc(db,'households/family'),{schemaVersion:2,kind:'family',state:'ACTIVE',operationId:null,ownerUid:'owner',shoppingEpoch:epoch,shoppingEpochExpiresAt:Timestamp.fromMillis(expiry)});
  for(const uid of ['owner','member','joining']){
   const role=uid==='owner'?'owner':'member',hid=uid==='joining'?'p-joining':'family';
   await setDoc(doc(db,`accountLifecycle/${uid}`),{state:'ACTIVE'});
   await setDoc(doc(db,`users/${uid}`),{activeHouseholdId:hid,privateHouseholdId:`p-${uid}`,familyHouseholdId:uid==='joining'?null:'family',shoppingMigrationVersion:1});
   await setDoc(doc(db,`households/p-${uid}`),{schemaVersion:2,kind:'private',state:'ACTIVE',operationId:null,ownerUid:uid,shoppingEpoch:epoch,shoppingEpochExpiresAt:Timestamp.fromMillis(expiry)});
   await setDoc(doc(db,`households/p-${uid}/members/${uid}`),{role:'owner'});
   await setDoc(doc(db,`familyMemberships/${uid}`),{householdId:'family',role,state:uid==='joining'?'RESERVED':'ACTIVE',operationId:uid==='joining'?'join':null});
   if(uid!=='joining')await setDoc(doc(db,`households/family/members/${uid}`),{role});
  }
  await setDoc(doc(db,'familyOperations/join'),{kind:'JOIN',status:'READY',phase:'READY_FOR_TRANSFER',actorUid:'joining',sourceHouseholdId:'p-joining',householdId:'family'});
 });
 for(const uid of ['owner','member','joining']){
  const r={...request(),actorUid:uid,householdId:uid==='joining'?'p-joining':'family'};
  await assertSucceeds(setDoc(doc(env.authenticatedContext(uid).firestore(),`users/${uid}/shoppingMutations/${r.mutationId}`),r));
 }
});

// S1C: ordinary SDK requests cross the real rules boundary. Only fixtures,
// context provisioning and the actual production processor use the Admin SDK.
async function s1cFixture(mode:'private'|'family-owner'|'family-member') {
 const uid=`s1c-${mode}-${++n}`;
 await new HouseholdStore(admin).ensure({uid});
 if(mode!=='private') {
  const owner=mode==='family-owner'?uid:`${uid}-owner`,hid=`${uid}-family`;
  if(owner!==uid)await new HouseholdStore(admin).ensure({uid:owner});
  await admin.doc(`households/${hid}`).set({schemaVersion:2,kind:'family',state:'ACTIVE',operationId:null,ownerUid:owner,createdAt:AdminTimestamp.now()});
  for(const actor of new Set([owner,uid])) {
   const role=actor===owner?'owner':'member';
   await admin.doc(`users/${actor}`).update({activeHouseholdId:hid,familyHouseholdId:hid});
   await admin.doc(`households/${hid}/members/${actor}`).set({role});
   await admin.doc(`familyMemberships/${actor}`).set({householdId:hid,role,state:'ACTIVE',operationId:null});
  }
 }
 const context=await processor.ensureContext({uid}),db=env.authenticatedContext(uid).firestore();
 return {uid,db,...context};
}
type S1cFixture=Awaited<ReturnType<typeof s1cFixture>>;
async function enqueue(f:S1cFixture,payload:Child|Child[]) {
 const r={schemaVersion:1,mutationId:newMutationId(f.epoch),actorUid:f.uid,householdId:f.householdId,epoch:f.epoch,kind:Array.isArray(payload)?'BULK':payload.type,payloadJson:JSON.stringify(Array.isArray(payload)?{items:payload}:payload),submittedAt:serverTimestamp()};
 await assertSucceeds(setDoc(doc(f.db,`users/${f.uid}/shoppingMutations/${r.mutationId}`),r));
 return r;
}
async function execute(f:S1cFixture,payload:Child|Child[],expected='APPLIED') {
 const r=await enqueue(f,payload);
 assert.equal(await processor.process(f.uid,r.mutationId),expected);
 const receipt=await assertSucceeds(getDoc(doc(f.db,`users/${f.uid}/shoppingMutations/${r.mutationId}`)));
 assert.equal(receipt.get('status'),expected);
 return receipt;
}
async function denied(operation:Promise<unknown>) {
 const error=await assertFails(operation);
 assert.equal(error.code,'permission-denied');
}
const milk=(quantity:number,unit='ml'):Child=>({type:'ADD',name:'Milk',quantity,unit});

test('S1C production and emulator configurations use the tested root rules file',()=>{
 for(const file of ['firebase.json','firebase.emulators.json']) {
  const config=JSON.parse(readFileSync(resolve(__dirname,`../../../${file}`),'utf8'));
  assert.equal(config.firestore.rules,'firestore.rules');
 }
});

for(const mode of ['private','family-owner','family-member'] as const) {
 test(`S1C ${mode}: authorized read/listen; every direct write class denied atomically`,async()=>{
  const f=await s1cFixture(mode),path=`households/${f.householdId}/shoppingItems`;
  const original={name:'milk',quantity:1000,unit:'ml',revision:1,isChecked:false};
  // Deliberately omit revision: these creates would pass the PRE-S1C rules.
  const legacyCreate={name:'milk',quantity:1000,unit:'ml',isChecked:false};
  await admin.doc(`${path}/a`).set(original);await admin.doc(`${path}/b`).set({...original,name:'flour',unit:'g'});
  const a=doc(f.db,`${path}/a`),b=doc(f.db,`${path}/b`);
  assert.equal((await assertSucceeds(getDocs(collection(f.db,path)))).size,2);
  await assertSucceeds(getDoc(a));
  // Server-backed realtime read, no sleeps or fabricated canonical snapshot.
  await new Promise<void>((resolve,reject)=>{
   const stop=onSnapshot(collection(f.db,path),{includeMetadataChanges:true},snapshot=>{
    if(snapshot.metadata.fromCache)return;
    try{assert.equal(snapshot.size,2);stop();resolve();}catch(error){stop();reject(error);}
   },reject);
  });
  await denied(setDoc(doc(f.db,`${path}/new`),legacyCreate));
  await denied(setDoc(a,{name:'overwrite'}));
  await denied(setDoc(a,{quantity:0},{merge:true}));
  for(const patch of [{quantity:0},{name:'renamed'},{unit:'db'},{isChecked:true},{isChecked:false},{revision:99},{createdAt:serverTimestamp()},{custom:'forged'}])await denied(updateDoc(a,patch));
  for(const flag of ['source','mutationProtocol','trusted','server','internal','role'])await denied(setDoc(doc(f.db,`${path}/escape`),{...legacyCreate,[flag]:true}));
  await denied(deleteDoc(a));
  const clear=writeBatch(f.db);clear.delete(a);clear.delete(b);await denied(clear.commit());
  const mixed=writeBatch(f.db);mixed.update(a,{quantity:0});mixed.set(doc(f.db,`${path}/batch-new`),legacyCreate);await denied(mixed.commit());
  assert.deepEqual((await admin.doc(`${path}/a`).get()).data(),original);
  assert.equal((await admin.collection(path).get()).size,2);
  for(const outsider of [env.authenticatedContext('s1c-outsider').firestore(),env.unauthenticatedContext().firestore()]) {
   await denied(getDoc(doc(outsider,`${path}/a`)));await denied(getDocs(collection(outsider,path)));
  }
 });
 test(`S1C ${mode}: client commands -> actual Admin processor -> reads/receipts, CRUD/clear/stale`,async()=>{
  const f=await s1cFixture(mode),path=`households/${f.householdId}/shoppingItems`;
  const first=await execute(f,milk(300)),target=first.get('results')[0];
  assert.equal(target.created,true);
  const merged=await execute(f,milk(2,'l'));assert.equal(merged.get('results')[0].created,false);
  assert.equal(merged.get('results')[0].itemId,target.itemId);
  let item=await getDoc(doc(f.db,`${path}/${target.itemId}`));assert.equal(item.get('quantity'),2300);
  assert.equal((await getDocs(collection(f.db,path))).size,1);
  // No second semantic effect on duplicate processor delivery.
  await processor.process(f.uid,merged.id);assert.equal((await admin.doc(`${path}/${target.itemId}`).get()).get('quantity'),2300);
  await execute(f,{type:'EDIT',itemId:item.id,expectedRevision:item.get('revision'),name:'Milk',quantity:3,unit:'l'});
  for(const isChecked of [true,false]) {
   item=await getDoc(doc(f.db,`${path}/${target.itemId}`));
   await execute(f,{type:'SET_CHECKED',itemId:item.id,expectedRevision:item.get('revision'),isChecked});
   assert.equal((await getDoc(item.ref)).get('isChecked'),isChecked);
  }
  for(const type of ['EDIT','DELETE','SET_CHECKED'] as const) {
   const stale:Child=type==='EDIT'?{type,itemId:target.itemId,expectedRevision:target.revision,name:'old',quantity:1,unit:'ml'}:type==='SET_CHECKED'?{type,itemId:target.itemId,expectedRevision:target.revision,isChecked:true}:{type,itemId:target.itemId,expectedRevision:target.revision};
   await execute(f,stale,'REJECTED_STALE');
  }
  item=await getDoc(doc(f.db,`${path}/${target.itemId}`));assert.equal(item.get('quantity'),3000);assert.equal(item.get('isChecked'),false);
  await execute(f,{type:'DELETE',itemId:item.id,expectedRevision:item.get('revision')});assert.equal((await getDoc(item.ref)).exists(),false);
  await execute(f,[milk(1),{type:'ADD',name:'Flour',quantity:2,unit:'g'},{type:'ADD',name:'Egg',quantity:3,unit:'db'}]);
  const rows=await getDocs(collection(f.db,path));assert.equal(rows.size,3);
  const clear=await execute(f,rows.docs.map(d=>({type:'DELETE',itemId:d.id,expectedRevision:d.get('revision')})));
  assert.equal(clear.get('results').length,3);assert.equal((await getDocs(collection(f.db,path))).size,0);
  const receiptRef=doc(f.db,`users/${f.uid}/shoppingMutations/${clear.id}`);
  for(const patch of [{status:'PENDING'},{results:[]},{actorUid:'other'},{payloadJson:'{}'},{cursor:0}])await denied(updateDoc(receiptRef,patch));
  await denied(deleteDoc(receiptRef));
 });
}

test('S1C original stale direct ADD and +500 edit/delete attacks; protocol epoch fence',async()=>{
 const f=await s1cFixture('private'),path=`households/${f.householdId}/shoppingItems`;
 const receipt=await execute(f,milk(1000)),target=receipt.get('results')[0];
 const staleItem=await getDoc(doc(f.db,`${path}/${target.itemId}`));
 await execute(f,milk(500));
 const newer=(await admin.doc(staleItem.ref.path).get()).data();assert.equal(newer?.quantity,1500);
 await denied(updateDoc(staleItem.ref,{quantity:staleItem.get('quantity')}));await denied(deleteDoc(staleItem.ref));
 assert.deepEqual((await admin.doc(staleItem.ref.path).get()).data(),newer);
 const delayed=await enqueue(f,milk(300));
 await admin.doc(`households/${f.householdId}`).update(advanceShoppingEpoch(AdminTimestamp.now()));
 await denied(setDoc(doc(f.db,`${path}/delayed-duplicate`),{name:'milk',quantity:300,unit:'ml'}));
 assert.equal(await processor.process(f.uid,delayed.mutationId),'REJECTED_CONTEXT_CHANGED');
 // An old envelope arriving only after the fence is rejected at command CREATE.
 const late={...delayed,mutationId:newMutationId(f.epoch)};
 await denied(setDoc(doc(f.db,`users/${f.uid}/shoppingMutations/${late.mutationId}`),late));
 assert.equal((await admin.collection(path).get()).size,1);
 assert.deepEqual((await admin.doc(staleItem.ref.path).get()).data(),newer);
});

test('S1C trusted legacy migration remains functional, lifecycle still fences reads and commands',async()=>{
 const uid=`s1c-legacy-${++n}`;
 await admin.doc(`users/${uid}/shopping/legacy`).set({name:'milk',quantity:2,unit:'ml'});
 await new HouseholdStore(admin).ensure({uid});
 const f={uid,db:env.authenticatedContext(uid).firestore(),...await processor.ensureContext({uid})};
 const ref=doc(f.db,`households/${f.householdId}/shoppingItems/legacy`);
 assert.equal((await getDoc(ref)).get('quantity'),2);
 assert.equal((await admin.doc(`users/${uid}/shopping/legacy`).get()).exists,false);
 await denied(updateDoc(ref,{quantity:3}));
 await execute(f,{type:'SET_CHECKED',itemId:'legacy',expectedRevision:0,isChecked:true});
 for(const state of ['DELETING','DELETED']) {
  await admin.doc(`accountLifecycle/${uid}`).update({state});
  await denied(getDoc(ref));await denied(getDocs(collection(f.db,`households/${f.householdId}/shoppingItems`)));
  const r={schemaVersion:1,mutationId:newMutationId(f.epoch),actorUid:uid,householdId:f.householdId,epoch:f.epoch,kind:'ADD',payloadJson:JSON.stringify(milk(1)),submittedAt:serverTimestamp()};
  await denied(setDoc(doc(f.db,`users/${uid}/shoppingMutations/${r.mutationId}`),r));
 }
});
