import { before, beforeEach, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeApp, deleteApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { requireLocalEmulator } from './emulator-guard';
import { HouseholdStore, privateHouseholdId } from '../src/households/household-store';
import { AccountDeletionService } from '../src/accounts/account-deletion';
import { FakeAuthDeletionApi } from './fake-auth-deletion-api';
requireLocalEmulator(process.env);
const app=initializeApp({projectId:'demo-kuktam-local'},'households'), db=getFirestore(app), store=new HouseholdStore(db);
beforeEach(async()=>{assert.ok((await fetch('http://127.0.0.1:8088/emulator/v1/projects/demo-kuktam-local/databases/(default)/documents',{method:'DELETE'})).ok);});
after(()=>deleteApp(app));
for(const provider of ['email','google'])test(`fresh ${provider} account provisions without recipes or billing`,async()=>{
 const r=await store.ensure({uid:provider});assert.equal(r.ready,true);
 assert.equal((await db.collection('households').get()).size,1);
 assert.equal((await db.doc(`users/${provider}`).get()).get('activeHouseholdId'),privateHouseholdId(provider));
 assert.equal((await db.doc(`households/${privateHouseholdId(provider)}/members/${provider}`).get()).get('role'),'owner');
 assert.equal((await db.doc(`accountLifecycle/${provider}`).get()).get('state'),'ACTIVE');
 assert.equal((await db.collection('billingPurchases').get()).size,0);
});
test('concurrent initialization and repeated startup reuse one household',async()=>{
 const results=await Promise.all(Array.from({length:5},()=>store.ensure({uid:'u'})));
 assert.ok(results.every(r=>r.ready));assert.equal((await db.collection('households').get()).size,1);
 await store.ensure({uid:'u'});assert.equal((await db.collection('households').get()).size,1);
});
for(const count of [0,1,7,103])test(`migration ${count} preserves IDs and every field without root document`,async()=>{
 for(let i=0;i<count;i++)await db.doc(`users/u/shopping/i${i}`).set({name:`item${i}`,quantity:i+1,unit:'g',isChecked:i%2===0,custom:'preserved'});
 const first=await store.page('u',2);
 if(count>2)assert.equal(first.ready,false);
 await store.ensure({uid:'u'});await store.ensure({uid:'u'});
 const items=await db.collection(`households/${privateHouseholdId('u')}/shoppingItems`).get();
 assert.equal(items.size,count);assert.equal((await db.collection('users/u/shopping').get()).size,0);
 for(const d of items.docs)assert.equal(d.get('custom'),'preserved');
 assert.equal((await db.doc('users/u').get()).get('shoppingMigrationVersion'),1);
});
test('interrupted migration resumes; other user untouched; migrated edits not overwritten',async()=>{
 await db.doc('users/u/shopping/a').set({name:'a'});await db.doc('users/u/shopping/b').set({name:'b'});
 await db.doc('users/other/shopping/a').set({name:'other'});
 await store.page('u',1);
 assert.equal((await db.collection('users/u/shopping').get()).size,1);
 assert.equal((await db.collection(`households/${privateHouseholdId('u')}/shoppingItems`).get()).size,1);
 await store.ensure({uid:'u'});
 const a=db.doc(`households/${privateHouseholdId('u')}/shoppingItems/a`);await a.update({name:'edited'});
 await store.ensure({uid:'u'});assert.equal((await a.get()).get('name'),'edited');
 assert.equal((await db.doc('users/other/shopping/a').get()).get('name'),'other');
});
test('collision fails atomically without deleting legacy data',async()=>{
 await store.page('u');await db.doc('users/u/shopping/a').set({name:'old'});
 await db.doc(`households/${privateHouseholdId('u')}/shoppingItems/a`).set({name:'new'});
 await assert.rejects(store.ensure({uid:'u'}),/migrationCollision/);
 assert.equal((await db.doc('users/u/shopping/a').get()).get('name'),'old');
});
test('existing valid active membership resolves existing household, never injects a membership',async()=>{
 await store.ensure({uid:'u'});await db.doc('households/shared').set({ownerUid:'other'});
 await db.doc('households/shared/members/u').set({role:'member'});await db.doc('users/u').update({activeHouseholdId:'shared'});
 const r=await store.ensure({uid:'u'});assert.equal('householdId' in r && r.householdId,'shared');
 await db.doc('households/shared/members/u').delete();await assert.rejects(store.ensure({uid:'u'}),/membershipMissing/);
});
test('private household cleanup is bounded; DONE includes items and membership; other household untouched',async()=>{
 await store.ensure({uid:'u'});await store.ensure({uid:'other'});
 for(let i=0;i<7;i++)await db.doc(`households/${privateHouseholdId('u')}/shoppingItems/${i}`).set({name:'x'});
 const deletion=new AccountDeletionService(db,new FakeAuthDeletionApi());await deletion.beginAccountDeletion({uid:'u'});
 await deletion.resume('u',1,2);assert.equal((await db.collection(`households/${privateHouseholdId('u')}/shoppingItems`).get()).size,5);
 assert.notEqual((await db.doc('accountDeletions/u').get()).get('stage'),'DONE');
 assert.equal(await deletion.resume('u',50,2),'deletionCompleted');
 assert.equal((await db.doc(`households/${privateHouseholdId('u')}`).get()).exists,false);
 assert.equal((await db.collection(`households/${privateHouseholdId('u')}/members`).get()).size,0);
 assert.equal((await db.doc(`households/${privateHouseholdId('other')}`).get()).exists,true);
 await assert.rejects(store.ensure({uid:'u'}),/accountUnavailable/);
 assert.equal((await store.ensure({uid:'new-u'})).ready,true);
});
test('external Auth deletion converges household cleanup',async()=>{
 await store.ensure({uid:'u'});await db.doc(`households/${privateHouseholdId('u')}/shoppingItems/a`).set({name:'x'});
 const deletion=new AccountDeletionService(db,new FakeAuthDeletionApi());
 await deletion.handleAuthUserDeleted('u',50);
 assert.equal((await db.doc('accountDeletions/u').get()).get('stage'),'DONE');
 assert.equal((await db.doc(`households/${privateHouseholdId('u')}`).get()).exists,false);
});
test('shared data fails closed until explicit shared deletion policy is introduced',async()=>{
 await store.ensure({uid:'u'});const home=db.doc(`households/${privateHouseholdId('u')}`);
 await home.collection('members').doc('other').set({role:'member'});await home.collection('shoppingItems').doc('a').set({name:'shared'});
 const deletion=new AccountDeletionService(db,new FakeAuthDeletionApi());await deletion.beginAccountDeletion({uid:'u'});
 assert.equal(await deletion.resume('u'),'cleanupRetryRequired');assert.equal((await home.collection('shoppingItems').get()).size,1);
 assert.notEqual((await db.doc('accountDeletions/u').get()).get('stage'),'DONE');
});
