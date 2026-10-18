import { before, after, test } from 'node:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { initializeTestEnvironment, assertFails, assertSucceeds, RulesTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, setDoc, getDoc, getDocs, updateDoc, deleteDoc, collection } from 'firebase/firestore';
import { requireLocalEmulator } from './emulator-guard';
requireLocalEmulator(process.env);
let env:RulesTestEnvironment;
before(async()=>{
 env=await initializeTestEnvironment({projectId:'demo-kuktam-local',firestore:{host:'127.0.0.1',port:8088,rules:readFileSync(resolve(__dirname,'../../../firestore.rules'),'utf8')}});
 await env.clearFirestore();
 await env.withSecurityRulesDisabled(async ctx=>{const db=ctx.firestore();
  for(const uid of ['owner','member','deleting','deleted','migrating']){
   await setDoc(doc(db,`users/${uid}`),{privateHouseholdId:`private-${uid}`,familyHouseholdId:'home',activeHouseholdId:'home',shoppingMigrationVersion:uid==='migrating'?0:1});
   await setDoc(doc(db,`households/private-${uid}`),{schemaVersion:2,kind:'private',state:'ACTIVE',operationId:null,ownerUid:uid});
   await setDoc(doc(db,`households/private-${uid}/members/${uid}`),{role:'owner'});
   await setDoc(doc(db,`familyMemberships/${uid}`),{householdId:'home',role:uid==='owner'?'owner':'member',state:'ACTIVE',operationId:null});
   await setDoc(doc(db,`accountLifecycle/${uid}`),{state:uid==='deleting'?'DELETING':uid==='deleted'?'DELETED':'ACTIVE'});
   await setDoc(doc(db,`households/home/members/${uid}`),{role:uid==='owner'?'owner':'member'});
  }
  await setDoc(doc(db,'households/home'),{schemaVersion:2,kind:'family',state:'ACTIVE',operationId:null,ownerUid:'owner'});
  await setDoc(doc(db,'households/home/shoppingItems/a'),{name:'milk'});
 });
});
after(()=>env.cleanup());
test('JOIN reservation keeps private CRUD usable, grants no family access and cannot be forged',async()=>{
 const uid='joining',p='joining-private';
 await env.withSecurityRulesDisabled(async ctx=>{const db=ctx.firestore();
  await setDoc(doc(db,`accountLifecycle/${uid}`),{state:'ACTIVE'});
  await setDoc(doc(db,`users/${uid}`),{privateHouseholdId:p,activeHouseholdId:p,familyHouseholdId:null,shoppingMigrationVersion:1});
  await setDoc(doc(db,`households/${p}`),{schemaVersion:2,kind:'private',state:'ACTIVE',operationId:null,ownerUid:uid});
  await setDoc(doc(db,`households/${p}/members/${uid}`),{role:'owner'});
  await setDoc(doc(db,`familyMemberships/${uid}`),{state:'RESERVED',role:'member',householdId:'home',operationId:'join-op'});
  await setDoc(doc(db,'familyOperations/join-op'),{kind:'JOIN',status:'READY',phase:'READY_FOR_TRANSFER',actorUid:uid,sourceHouseholdId:p,householdId:'home'});
 });
 const db=env.authenticatedContext(uid).firestore(),item=doc(db,`households/${p}/shoppingItems/a`);
 await assertSucceeds(setDoc(item,{name:'milk'}));await assertSucceeds(getDoc(item));
 await assertSucceeds(updateDoc(item,{quantity:2}));await assertSucceeds(deleteDoc(item));
 await assertFails(getDoc(doc(db,'households/home/shoppingItems/a')));
 await assertFails(setDoc(doc(db,'households/home/shoppingItems/forged'),{name:'x'}));
 for(const path of ['familyOperations/join-op','familyJoinCapacity/home',`familyMemberships/${uid}`,'familyInvites/hash']) {
  await assertFails(getDoc(doc(db,path)));await assertFails(setDoc(doc(db,path),{state:'ACTIVE'}));
 }
 for(const state of ['DELETING','DELETED']) {
  await env.withSecurityRulesDisabled(ctx=>setDoc(doc(ctx.firestore(),`accountLifecycle/${uid}`),{state}));
  await assertFails(setDoc(item,{name:'blocked'}));
 }
});
test('reserved private exception fails closed without matching JOIN operation',async()=>{
 const uid='joining';
 await env.withSecurityRulesDisabled(async ctx=>{
  await setDoc(doc(ctx.firestore(),`accountLifecycle/${uid}`),{state:'ACTIVE'});
  await updateDoc(doc(ctx.firestore(),'familyOperations/join-op'),{actorUid:'other'});
 });
 await assertFails(setDoc(doc(env.authenticatedContext(uid).firestore(),'households/joining-private/shoppingItems/a'),{name:'blocked'}));
});
for(const uid of ['owner','member','outsider'])test(`${uid} cannot read/forge invites, slot inventory or member email`,async()=>{
 const db=env.authenticatedContext(uid).firestore();
 for(const path of ['familyInvites/hash','familyInviteSlots/home']){
  await assertFails(getDoc(doc(db,path)));await assertFails(setDoc(doc(db,path),{status:'PENDING',email:'forged@example.test'}));
  await assertFails(deleteDoc(doc(db,path)));
 }
 await assertFails(getDocs(collection(db,'familyInvites')));
 await assertFails(updateDoc(doc(db,`households/home/members/${uid}`),{email:'forged@example.test'}));
});
test('CREATE reservation fences source and PREPARING destination; operation state is backend-only',async()=>{
 const uid='creator',p='creator-private',f='creator-family';
 await env.withSecurityRulesDisabled(async ctx=>{const db=ctx.firestore();
  await setDoc(doc(db,`accountLifecycle/${uid}`),{state:'ACTIVE'});
  await setDoc(doc(db,`users/${uid}`),{privateHouseholdId:p,activeHouseholdId:p,familyHouseholdId:null,shoppingMigrationVersion:1});
  await setDoc(doc(db,`households/${p}`),{schemaVersion:2,kind:'private',state:'ACTIVE',operationId:'create-op',ownerUid:uid});
  await setDoc(doc(db,`households/${p}/members/${uid}`),{role:'owner'});
  await setDoc(doc(db,`households/${f}`),{schemaVersion:2,kind:'family',state:'PREPARING',operationId:'create-op',ownerUid:uid});
  await setDoc(doc(db,`familyMemberships/${uid}`),{householdId:f,role:'owner',state:'RESERVED',operationId:'create-op'});
 });
 const db=env.authenticatedContext(uid).firestore();
 for(const path of [`households/${p}/shoppingItems/a`,`households/${f}/shoppingItems/a`]){
  await assertFails(setDoc(doc(db,path),{name:'forged'}));await assertFails(getDoc(doc(db,path)));
 }
 for(const path of ['familyOperations/create-op','familyOperations/create-op/items/a','familyRuntime/config']){
  await assertFails(setDoc(doc(db,path),{creationEnabled:true,status:'DONE'}));await assertFails(getDoc(doc(db,path)));
 }
 await assertFails(updateDoc(doc(db,`households/${p}`),{operationId:null}));
 await assertFails(updateDoc(doc(db,`households/${f}`),{state:'ACTIVE',operationId:null}));
 await assertSucceeds(setDoc(doc(db,`users/${uid}/recipes/own`),{name:'private recipe'}));
});
for(const uid of ['owner','member'])test(`${uid} reads and CRUDs household shopping with zero recipes`,async()=>{
 const db=env.authenticatedContext(uid).firestore(),ref=doc(db,`households/home/shoppingItems/${uid}`);
 await assertSucceeds(getDocs(collection(db,'households/home/shoppingItems')));
 await assertSucceeds(setDoc(ref,{name:'bread'}));await assertSucceeds(updateDoc(ref,{isChecked:true}));await assertSucceeds(deleteDoc(ref));
 await assertSucceeds(setDoc(doc(db,`users/${uid}/recipes/first`),{name:'private recipe'}));
});
for(const uid of ['outsider',null])test(`${uid} cannot read or mutate household`,async()=>{
 const db=uid?env.authenticatedContext(uid).firestore():env.unauthenticatedContext().firestore();
 const ref=doc(db,'households/home/shoppingItems/a');await assertFails(getDoc(ref));await assertFails(getDocs(collection(db,'households/home/shoppingItems')));
 await assertFails(setDoc(ref,{name:'bad'}));await assertFails(updateDoc(ref,{isChecked:true}));await assertFails(deleteDoc(ref));
});
for(const uid of ['owner','outsider'])test(`${uid} cannot forge household/membership or migration state`,async()=>{
 const db=env.authenticatedContext(uid).firestore();
 await assertFails(setDoc(doc(db,'households/forged'),{ownerUid:uid}));
 await assertFails(setDoc(doc(db,`households/home/members/${uid}`),{role:'owner'}));
 await assertFails(updateDoc(doc(db,`users/${uid}`),{shoppingMigrationVersion:99}));
 await assertFails(updateDoc(doc(db,`users/${uid}`),{activeHouseholdId:'forged'}));
});
for(const uid of ['deleting','deleted','migrating'])test(`${uid} cannot write household items`,async()=>{
 const db=env.authenticatedContext(uid).firestore(),ref=doc(db,'households/home/shoppingItems/a');
 await assertFails(setDoc(ref,{name:'bad'}));await assertFails(updateDoc(ref,{isChecked:true}));await assertFails(deleteDoc(ref));
});
test('migration barrier cannot be erased by ACTIVE client; legacy cannot be reopened',async()=>{
 const db=env.authenticatedContext('owner').firestore();await assertFails(deleteDoc(doc(db,'users/owner')));
 await assertFails(setDoc(doc(db,'users/owner/shopping/new'),{name:'old'}));
});
test('even valid membership cannot authorize client pointer updates',async()=>{
 const db=env.authenticatedContext('owner').firestore();
 await assertFails(updateDoc(doc(db,'users/owner'),{activeHouseholdId:'private-owner'}));
 await assertFails(updateDoc(doc(db,'users/owner'),{activeHouseholdId:'home',shoppingMigrationVersion:0}));
});

for(const field of ['privateHouseholdId','activeHouseholdId','familyHouseholdId'])test(`client cannot change ${field}`,async()=>{
 await assertFails(updateDoc(doc(env.authenticatedContext('owner').firestore(),'users/owner'),{[field]:'private-owner'}));
});
test('client cannot read/write reverse index or change any structural household field',async()=>{
 const db=env.authenticatedContext('owner').firestore(), ref=doc(db,'familyMemberships/owner');
 await assertFails(getDoc(ref));await assertFails(setDoc(ref,{householdId:'home',role:'owner',state:'ACTIVE',operationId:null}));
 await assertFails(updateDoc(ref,{role:'member'}));await assertFails(deleteDoc(ref));
 await assertFails(setDoc(doc(db,'familyMemberships/new'),{householdId:'home'}));
 for(const field of ['ownerUid','kind','state','operationId'])await assertFails(updateDoc(doc(db,'households/home'),{[field]:'forged'}));
});
test('family member cannot read or write hidden private list',async()=>{
 const db=env.authenticatedContext('member').firestore(), ref=doc(db,'households/private-member/shoppingItems/a');
 await assertFails(getDoc(ref));await assertFails(setDoc(ref,{name:'hidden'}));await assertFails(deleteDoc(ref));
});
for(const variation of ['RESERVED','PREPARING','DISSOLVING','activeMismatch','familyMismatch','indexMismatch','missingIndex','wrongPrivateKind'])test(`family ${variation} fails closed`,async()=>{
 const uid=`case-${variation}`, hid=`family-${variation}`, p=`private-${variation}`;
 await env.withSecurityRulesDisabled(async ctx=>{const db=ctx.firestore();
  await setDoc(doc(db,`users/${uid}`),{activeHouseholdId:variation==='activeMismatch'?p:hid,privateHouseholdId:p,familyHouseholdId:variation==='familyMismatch'?null:hid,shoppingMigrationVersion:1});
  await setDoc(doc(db,`accountLifecycle/${uid}`),{state:'ACTIVE'});
  await setDoc(doc(db,`households/${p}`),{schemaVersion:2,state:'ACTIVE',operationId:null,kind:variation==='wrongPrivateKind'?'family':'private',ownerUid:uid});
  await setDoc(doc(db,`households/${p}/members/${uid}`),{role:'owner'});
  await setDoc(doc(db,`households/${hid}`),{schemaVersion:2,kind:'family',ownerUid:'owner',state:['PREPARING','DISSOLVING'].includes(variation)?variation:'ACTIVE',operationId:null});
  await setDoc(doc(db,`households/${hid}/members/${uid}`),{role:'member'});
  if(variation!=='missingIndex')await setDoc(doc(db,`familyMemberships/${uid}`),{householdId:variation==='indexMismatch'?'other':hid,role:'member',state:variation==='RESERVED'?'RESERVED':'ACTIVE',operationId:variation==='RESERVED'?'op':null});
 });
 const db=env.authenticatedContext(uid).firestore(),ref=doc(db,`households/${hid}/shoppingItems/a`);
 await assertFails(getDoc(ref));await assertFails(setDoc(ref,{name:'bad'}));await assertFails(deleteDoc(ref));
});
for(const legacy of [false,true])test(`standalone ${legacy?'v1 compatibility':'v2'} active list CRUD works`,async()=>{
 const uid=legacy?'legacy':'standalone',hid=`p-${uid}`;
 await env.withSecurityRulesDisabled(async ctx=>{const db=ctx.firestore();
  await setDoc(doc(db,`users/${uid}`),{activeHouseholdId:hid,shoppingMigrationVersion:1,...(legacy?{}:{privateHouseholdId:hid,familyHouseholdId:null})});
  await setDoc(doc(db,`accountLifecycle/${uid}`),{state:'ACTIVE'});
  await setDoc(doc(db,`households/${hid}`),{schemaVersion:legacy?1:2,ownerUid:uid,...(legacy?{}:{kind:'private',state:'ACTIVE',operationId:null})});
  await setDoc(doc(db,`households/${hid}/members/${uid}`),{role:'owner'});
 });
 const db=env.authenticatedContext(uid).firestore(),ref=doc(db,`households/${hid}/shoppingItems/a`);
 await assertSucceeds(setDoc(ref,{name:'ok'}));await assertSucceeds(getDoc(ref));await assertSucceeds(updateDoc(ref,{isChecked:true}));await assertSucceeds(deleteDoc(ref));
 await assertFails(setDoc(doc(db,'households/private-owner/shoppingItems/x'),{name:'bad'}));
 await assertFails(setDoc(doc(db,`users/${uid}/shopping/x`),{name:'legacy'}));
});
test('household membership does not grant access to another members private recipes',async()=>{
 const db=env.authenticatedContext('member').firestore();await assertFails(getDoc(doc(db,'users/owner/recipes/first')));
 await assertFails(setDoc(doc(db,'users/owner/recipes/injected'),{name:'bad'}));
});
