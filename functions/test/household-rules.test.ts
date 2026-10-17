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
   await setDoc(doc(db,`users/${uid}`),{activeHouseholdId:'home',shoppingMigrationVersion:uid==='migrating'?0:1});
   await setDoc(doc(db,`accountLifecycle/${uid}`),{state:uid==='deleting'?'DELETING':uid==='deleted'?'DELETED':'ACTIVE'});
   await setDoc(doc(db,`households/home/members/${uid}`),{role:uid==='owner'?'owner':'member'});
  }
  await setDoc(doc(db,'households/home'),{ownerUid:'owner'});
  await setDoc(doc(db,'households/home/shoppingItems/a'),{name:'milk'});
 });
});
after(()=>env.cleanup());
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
test('active household switching requires membership and preserves other root fields',async()=>{
 const db=env.authenticatedContext('owner').firestore();
 await assertSucceeds(updateDoc(doc(db,'users/owner'),{activeHouseholdId:'home'}));
 await assertFails(updateDoc(doc(db,'users/owner'),{activeHouseholdId:'home',shoppingMigrationVersion:0}));
});
test('household membership does not grant access to another members private recipes',async()=>{
 const db=env.authenticatedContext('member').firestore();await assertFails(getDoc(doc(db,'users/owner/recipes/first')));
 await assertFails(setDoc(doc(db,'users/owner/recipes/injected'),{name:'bad'}));
});
