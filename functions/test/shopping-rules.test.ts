import {before,after,test} from 'node:test';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {initializeTestEnvironment,assertFails,assertSucceeds,RulesTestEnvironment} from '@firebase/rules-unit-testing';
import {doc,setDoc,getDoc,updateDoc,deleteDoc,Timestamp,serverTimestamp} from 'firebase/firestore';
import {requireLocalEmulator} from './emulator-guard';
requireLocalEmulator(process.env);
let env:RulesTestEnvironment,n=0;
const expiry=Date.now()+86400000,epoch=`${expiry}-${'a'.repeat(32)}`;
const request=()=>{const mutationId=`${epoch}_${(++n).toString(16).padStart(64,'0')}`;return {schemaVersion:1,mutationId,actorUid:'u',householdId:'home',epoch,kind:'ADD',payloadJson:JSON.stringify({type:'ADD',name:'x',quantity:1,unit:'g'}),submittedAt:serverTimestamp()};};
before(async()=>{
 env=await initializeTestEnvironment({projectId:'demo-kuktam-local',firestore:{host:'127.0.0.1',port:8088,rules:readFileSync(resolve(__dirname,'../../../firestore.rules'),'utf8')}});await env.clearFirestore();
 await env.withSecurityRulesDisabled(async ctx=>{const db=ctx.firestore();
 for(const [path,data] of Object.entries({'shoppingRuntime/config':{enabled:true},'accountLifecycle/u':{state:'ACTIVE'},'users/u':{activeHouseholdId:'home',privateHouseholdId:'home',familyHouseholdId:null,shoppingMigrationVersion:1},'households/home':{schemaVersion:2,kind:'private',state:'ACTIVE',operationId:null,ownerUid:'u',shoppingEpoch:epoch,shoppingEpochExpiresAt:Timestamp.fromMillis(expiry)},'households/home/members/u':{role:'owner'},'households/home/shoppingItems/a':{name:'x',revision:1}}))await setDoc(doc(db,path),data);
 });
});
after(()=>env.cleanup());
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
test('technical work/gate and epoch/revision are server owned; legacy CRUD stays enabled',async()=>{
 const db=env.authenticatedContext('u').firestore();
 for(const path of ['shoppingMutationWork/x','shoppingRuntime/config']){await assertFails(getDoc(doc(db,path)));await assertFails(setDoc(doc(db,path),{enabled:true}));}
 await assertFails(updateDoc(doc(db,'households/home'),{shoppingEpoch:'fake'}));await assertFails(updateDoc(doc(db,'households/home/shoppingItems/a'),{revision:2}));
 await assertFails(setDoc(doc(db,'households/home/shoppingItems/forged'),{revision:1}));
 await assertSucceeds(updateDoc(doc(db,'households/home/shoppingItems/a'),{quantity:2}));await assertSucceeds(setDoc(doc(db,'households/home/shoppingItems/legacy'),{name:'legacy'}));await assertSucceeds(deleteDoc(doc(db,'households/home/shoppingItems/legacy')));
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
