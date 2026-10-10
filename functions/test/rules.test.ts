import { after, before, test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { initializeTestEnvironment, assertFails, assertSucceeds, RulesTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, getDoc, getDocs, setDoc, updateDoc, deleteDoc, collection, query, orderBy, limit, writeBatch } from 'firebase/firestore';
import { initializeApp, deleteApp, App } from 'firebase-admin/app';
import { getFirestore, Firestore } from 'firebase-admin/firestore';
import { requireLocalEmulator } from './emulator-guard';
import { aggregateGrants } from '../src/aggregate';
import { parseEntitlement, parseGrant, parsePurchase } from '../src/models';
import { grant, now, purchase } from './fixtures';

// Must run BEFORE creating either SDK client. Direct invocation cannot fall back.
requireLocalEmulator(process.env);
let env: RulesTestEnvironment;
let app: App;
let admin: Firestore;
before(async () => {
  env = await initializeTestEnvironment({ projectId: 'demo-kuktam-local', firestore: {
    host: '127.0.0.1', port: 8088, rules: readFileSync(resolve(__dirname, '../../../firestore.rules'), 'utf8'),
  } });
  app = initializeApp({ projectId: 'demo-kuktam-local' }, 'n2-admin');
  admin = getFirestore(app);
  await env.clearFirestore();
  await Promise.all([
    admin.doc('users/alice').set({ legacy: true }),
    admin.doc('users/alice/recipes/existing').set({ name: 'Recipe' }),
    admin.doc('users/alice/shopping/existing').set({ name: 'milk', quantity: 1, unit: 'l', isChecked: false, createdAt: now }),
    admin.doc('users/alice/entitlements/pro').set(aggregateGrants([grant()], now, 1)),
    admin.doc('users/alice/entitlementGrants/promo').set(parseGrant(grant())),
    admin.doc('billingPurchases/synthetic-hash').set(parsePurchase(purchase())),
    admin.doc('ingredients/milk').set({ name: 'milk' }),
  ]);
});
after(async () => { await env?.cleanup(); if (app) await deleteApp(app); });
const client = (uid?: string) => uid ? env.authenticatedContext(uid).firestore() : env.unauthenticatedContext().firestore();

for (const category of ['recipes', 'shopping']) {
  test(`owner ${category}: get/list/create/update/delete`, async () => {
    const db = client('alice');
    await assertSucceeds(getDoc(doc(db, `users/alice/${category}/existing`)));
    await assertSucceeds(getDocs(collection(db, `users/alice/${category}`)));
    const ref = doc(db, `users/alice/${category}/owned-new`);
    await assertSucceeds(setDoc(ref, { name: 'new' }));
    await assertSucceeds(updateDoc(ref, { name: 'edited' }));
    await assertSucceeds(deleteDoc(ref));
  });
  for (const identity of ['bob', undefined]) {
    test(`${identity ?? 'anonymous'} ${category}: reads and every write denied`, async () => {
      const db = client(identity);
      const ref = doc(db, `users/alice/${category}/existing`);
      await assertFails(getDoc(ref));
      await assertFails(getDocs(collection(db, `users/alice/${category}`)));
      await assertFails(setDoc(doc(db, `users/alice/${category}/attack`), { name: 'bad' }));
      await assertFails(updateDoc(ref, { name: 'bad' }));
      await assertFails(deleteDoc(ref));
    });
  }
}
test('owner can read effective entitlement', async () => {
  assert.equal((await assertSucceeds(getDoc(doc(client('alice'), 'users/alice/entitlements/pro')))).data()?.active, true);
});
for (const identity of ['alice', 'bob', undefined]) {
  test(`${identity ?? 'anonymous'} cannot write entitlement, grants or ledger`, async () => {
    const db = client(identity);
    for (const path of ['users/alice/entitlements/pro', 'users/alice/entitlementGrants/promo', 'billingPurchases/synthetic-hash']) {
      const ref = doc(db, path);
      await assertFails(setDoc(ref, { active: true }));
      await assertFails(updateDoc(ref, { active: true }));
      await assertFails(deleteDoc(ref));
    }
    await assertFails(setDoc(doc(db, 'users/alice/entitlementGrants/new'), { source: 'ADMIN' }));
    await assertFails(setDoc(doc(db, 'billingPurchases/new'), { boundUid: 'alice' }));
    await assertFails(getDoc(doc(db, 'users/alice/entitlementGrants/promo')));
    await assertFails(getDocs(collection(db, 'users/alice/entitlementGrants')));
    await assertFails(getDoc(doc(db, 'billingPurchases/synthetic-hash')));
    await assertFails(getDocs(collection(db, 'billingPurchases')));
    if (identity !== 'alice') await assertFails(getDoc(doc(db, 'users/alice/entitlements/pro')));
  });
}
test('cannot self-create missing pro entitlement', async () => {
  await assertFails(setDoc(doc(client('bob'), 'users/bob/entitlements/pro'), { active: true }));
});
test('ingredients authenticated read/list only', async () => {
  for (const uid of ['alice', 'bob']) {
    const db = client(uid);
    await assertSucceeds(getDoc(doc(db, 'ingredients/milk')));
    await assertSucceeds(getDocs(query(collection(db, 'ingredients'), orderBy('name'))));
  }
  for (const uid of ['alice', undefined]) {
    const db = client(uid);
    await assertFails(setDoc(doc(db, 'ingredients/new'), { name: 'new' }));
    await assertFails(updateDoc(doc(db, 'ingredients/milk'), { name: 'bad' }));
    await assertFails(deleteDoc(doc(db, 'ingredients/milk')));
  }
  await assertFails(getDoc(doc(client(), 'ingredients/milk')));
  await assertFails(getDocs(collection(client(), 'ingredients')));
});
test('unlisted root, user, entitlement and nested paths denied', async () => {
  const db = client('alice');
  for (const path of ['unknown/doc', 'users/alice/private/doc', 'users/alice/entitlements/other',
    'users/alice/recipes/existing/entitlements/pro', 'users/alice/shopping/existing/nested/doc']) {
    await assertFails(getDoc(doc(db, path)));
    await assertFails(setDoc(doc(db, path), { active: true }));
  }
});
test('root only supports own get/delete; no profile escalation or user listing', async () => {
  const db = client('alice');
  await assertSucceeds(getDoc(doc(db, 'users/alice')));
  await assertFails(updateDoc(doc(db, 'users/alice'), { pro: true }));
  await assertFails(setDoc(doc(client('bob'), 'users/bob'), { pro: true }));
  await assertFails(getDocs(collection(db, 'users')));
  await assertFails(getDoc(doc(client('bob'), 'users/alice')));
  await assertFails(deleteDoc(doc(client('bob'), 'users/alice')));
  await assertFails(getDoc(doc(client(), 'users/alice')));
});
test('existing owner queries/batches and root deletion remain compatible', async () => {
  const db = client('legacy');
  await admin.doc('users/legacy').set({ legacy: true });
  const batch = writeBatch(db);
  batch.set(doc(db, 'users/legacy/recipes/r'), { name: 'Recipe' });
  batch.set(doc(db, 'users/legacy/shopping/s'), { name: 'milk', quantity: 1, createdAt: now.toDate(), isChecked: false });
  await assertSucceeds(batch.commit());
  await assertSucceeds(getDocs(query(collection(db, 'users/legacy/shopping'), orderBy('createdAt'))));
  for (const name of ['recipes', 'shopping']) {
    const page = await assertSucceeds(getDocs(query(collection(db, `users/legacy/${name}`), limit(200))));
    const remove = writeBatch(db);
    page.docs.forEach(d => remove.delete(d.ref));
    await assertSucceeds(remove.commit());
  }
  await assertSucceeds(deleteDoc(doc(db, 'users/legacy')));
});
test('mixed legal recipe and illegal entitlement batch fails atomically', async () => {
  const db = client('alice');
  const batch = writeBatch(db);
  batch.set(doc(db, 'users/alice/recipes/atomic'), { name: 'not persisted' });
  batch.set(doc(db, 'users/alice/entitlements/pro'), { active: true });
  await assertFails(batch.commit());
  assert.equal((await admin.doc('users/alice/recipes/atomic').get()).exists, false);
});
test('real Admin SDK bypass writes and schema round-trips all three backend documents', async () => {
  const e = aggregateGrants([grant()], now, 2);
  const g = parseGrant(grant());
  const p = parsePurchase(purchase());
  await admin.doc('users/admin-test/entitlements/pro').set(e);
  await admin.doc('users/admin-test/entitlementGrants/g').set(g);
  await admin.doc('billingPurchases/admin-test').set(p);
  assert.deepEqual(parseEntitlement((await admin.doc('users/admin-test/entitlements/pro').get()).data()), e);
  assert.deepEqual(parseGrant((await admin.doc('users/admin-test/entitlementGrants/g').get()).data()), g);
  assert.deepEqual(parsePurchase((await admin.doc('billingPurchases/admin-test').get()).data()), p);
});

test('acknowledgment delivery state is backend-only including nested collection queries', async () => {
  const path = 'billingPurchases/synthetic-hash/acknowledgment/state';
  await admin.doc(path).set({ status: 'acknowledgmentPending' });
  for (const uid of ['alice', 'bob', undefined]) {
    const db = client(uid), ref = doc(db, path);
    await assertFails(getDoc(ref));
    await assertFails(getDocs(collection(db, 'billingPurchases/synthetic-hash/acknowledgment')));
    await assertFails(setDoc(ref, { status: 'acknowledged' }));
    await assertFails(updateDoc(ref, { status: 'acknowledged' }));
    await assertFails(deleteDoc(ref));
  }
  assert.equal((await admin.doc(path).get()).data()!.status, 'acknowledgmentPending');
});

test('N4B account lifecycle and binding registry deny every client read/write', async () => {
  const paths = ['accountLifecycle/alice', 'billingAccountBindings/synthetic-binding'];
  for (const path of paths) await admin.doc(path).set({ state: 'ACTIVE' });
  for (const uid of ['alice', 'bob', undefined]) {
    const db = client(uid);
    for (const path of paths) {
      const ref = doc(db, path);
      await assertFails(getDoc(ref)); await assertFails(getDocs(collection(db, path.split('/')[0]!)));
      await assertFails(setDoc(ref, { state: 'ACTIVE' })); await assertFails(updateDoc(ref, { state: 'ACTIVE' })); await assertFails(deleteDoc(ref));
      await assertFails(setDoc(doc(db, `${path}/nested/attack`), { state: 'ACTIVE' }));
    }
  }
  for (const path of paths) assert.equal((await admin.doc(path).get()).data()!.state, 'ACTIVE');
});

test('RTDN inbox: Admin can write; owner, unrelated and unauthenticated clients denied', async () => {
  const path = 'rtdnInbox/synthetic-event'; await admin.doc(path).set({ status: 'RECEIVED' });
  for (const uid of ['alice', 'bob', undefined]) {
    const db = client(uid), ref = doc(db, path);
    await assertFails(getDoc(ref)); await assertFails(getDocs(collection(db, 'rtdnInbox')));
    await assertFails(setDoc(ref, { status: 'PROCESSED' })); await assertFails(updateDoc(ref, { status: 'PROCESSED' }));
    await assertFails(deleteDoc(ref)); await assertFails(setDoc(doc(db, path + '/nested/attack'), { active: true }));
  }
  assert.equal((await admin.doc(path).get()).data()!.status, 'RECEIVED');
});

test('maintenance metadata is backend-only for all clients', async () => {
 const path='billingMaintenance/synthetic';await admin.doc(path).set({status:'READY'});
 for(const uid of ['alice','bob',undefined]) {const db=client(uid),ref=doc(db,path);await assertFails(getDoc(ref));await assertFails(setDoc(ref,{status:'CLOSED'}));await assertFails(deleteDoc(ref));await assertFails(getDocs(collection(db,'billingMaintenance')));}
 assert.equal((await admin.doc(path).get()).data()!.status,'READY');
});

test('account deletion coordination is backend-only',async()=>{
 const path='accountDeletions/alice';await admin.doc(path).set({stage:'GRANTS'});
 for(const uid of ['alice','bob',undefined]){const db=client(uid),ref=doc(db,path);await assertFails(getDoc(ref));await assertFails(getDocs(collection(db,'accountDeletions')));await assertFails(setDoc(ref,{stage:'DONE'}));await assertFails(deleteDoc(ref));}
 assert.equal((await admin.doc(path).get()).data()!.stage,'GRANTS');
});

for(const state of ['ACTIVE','DELETING','DELETED'])test(`closure: ${state} content permissions`,async()=>{
 const uid=`closure-${state}`,db=client(uid);
 await admin.doc(`accountLifecycle/${uid}`).set({state});
 for(const c of ['recipes','shopping']){
  const path=`users/${uid}/${c}/existing`;await admin.doc(path).set({name:'existing'});
  await assertSucceeds(getDoc(doc(db,path)));
  if(state==='ACTIVE')await assertSucceeds(updateDoc(doc(db,path),{name:'edit'}));
  else{
   await assertFails(updateDoc(doc(db,path),{name:'edit'}));
   await assertFails(setDoc(doc(db,`users/${uid}/${c}/new`),{name:'new'}));
  }
  await assertSucceeds(deleteDoc(doc(db,path)));
 }
});
for (const uid of ['alice','bob',undefined]) test(`runtime dispatcher metadata denies ${uid ?? 'anonymous'}`,async()=>{
 const ref=doc(client(uid),'billingRuntime/maintenance');await assertFails(getDoc(ref));await assertFails(setDoc(ref,{nextCategory:'ack'}));
});
