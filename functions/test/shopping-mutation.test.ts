import {beforeEach,after,test} from 'node:test';
import assert from 'node:assert/strict';
import {initializeApp,deleteApp} from 'firebase-admin/app';
import {getFirestore,Timestamp} from 'firebase-admin/firestore';
import {requireLocalEmulator} from './emulator-guard';
import {HouseholdStore,privateHouseholdId} from '../src/households/household-store';
import {ShoppingMutationStore,advanceShoppingEpoch,workId} from '../src/shopping/mutation-store';
import {Child,newMutationId,epochExpiry,RETENTION_MS} from '../src/shopping/mutation-contract';
import {AccountDeletionService} from '../src/accounts/account-deletion';
import {FakeAuthDeletionApi} from './fake-auth-deletion-api';
import {Maintenance} from '../src/jobs/maintenance';
import {AccountBinding} from '../src/billing/account-binding';
requireLocalEmulator(process.env);
const app=initializeApp({projectId:'demo-kuktam-local'},'shopping'),db=getFirestore(app);
let time:number,store:ShoppingMutationStore;
beforeEach(async()=>{await fetch('http://127.0.0.1:8088/emulator/v1/projects/demo-kuktam-local/databases/(default)/documents',{method:'DELETE'});time=Date.now();store=new ShoppingMutationStore(db,()=>Timestamp.fromMillis(time));await db.doc('shoppingRuntime/config').set({enabled:true});});
after(()=>deleteApp(app));
async function setup(uid='u'){await new HouseholdStore(db).ensure({uid});return store.ensureContext({uid});}
const add=(quantity=1,name='alma'):Child=>({type:'ADD',name,quantity,unit:'g'});
async function command(payload:Child|Child[],uid='u'){
 const context=await store.ensureContext({uid}),r={schemaVersion:1,mutationId:newMutationId(context.epoch),actorUid:uid,...context,kind:Array.isArray(payload)?'BULK':payload.type,payloadJson:JSON.stringify(Array.isArray(payload)?{items:payload}:payload),submittedAt:Timestamp.fromMillis(time)};
 await store.submit({uid},r);return r;
}
const receipt=(id:string,uid='u')=>db.doc(`users/${uid}/shoppingMutations/${id}`).get();
const rows=(hid=privateHouseholdId('u'))=>db.collection(`households/${hid}/shoppingItems`).get();
test('ADD receipt proves creation versus merge for dependent destructive intents',async()=>{
 await setup();const a=await command(add(2)),b=await command(add(500));
 await store.process('u',a.mutationId);await store.process('u',b.mutationId);
 const first=(await receipt(a.mutationId)).get('results')[0],second=(await receipt(b.mutationId)).get('results')[0];
 assert.equal(first.created,true);assert.equal(second.created,false);
 assert.equal(first.itemId,second.itemId);assert.equal((await rows()).docs[0]!.get('quantity'),502);
 await store.process('u',a.mutationId);assert.deepEqual((await receipt(a.mutationId)).get('results')[0],first);
});
test('concurrent ADD receipts identify exactly one newly created target',async()=>{
 await setup();const a=await command(add(2)),b=await command(add(3));
 await Promise.all([store.process('u',a.mutationId),store.process('u',b.mutationId)]);
 const results=[(await receipt(a.mutationId)).get('results')[0],(await receipt(b.mutationId)).get('results')[0]];
 assert.equal(results.filter(r=>r.created===true).length,1);assert.equal(results.filter(r=>r.created===false).length,1);
 assert.equal(results[0].itemId,results[1].itemId);assert.equal((await rows()).docs[0]!.get('quantity'),5);
});
async function seed(){await setup();const r=await command(add(1000));await store.process('u',r.mutationId);return (await rows()).docs[0]!;}
test('default gate OFF; authenticated context only; initialize legacy lazily',async()=>{
 await db.doc('shoppingRuntime/config').delete();await new HouseholdStore(db).ensure({uid:'u'});await assert.rejects(store.ensureContext({uid:'u'}),/FEATURE_DISABLED/);
 await assert.rejects(store.ensureContext({uid:''}));
 await db.doc('shoppingRuntime/config').set({enabled:true});const a=await store.ensureContext({uid:'u'}),b=await store.ensureContext({uid:'u'});assert.deepEqual(a,b);
});
test('concurrent distinct ADD and duplicate delivery create exactly one logical row',async()=>{
 await setup();const a=await command(add(500,' ALMA ')),b=await command(add(1000));
 await Promise.all([store.process('u',a.mutationId),store.process('u',b.mutationId),store.process('u',a.mutationId)]);
 const all=await rows();assert.equal(all.size,1);assert.equal(all.docs[0]!.get('quantity'),1500);assert.equal(all.docs[0]!.get('revision'),2);
 await store.submit({uid:'u'},a);assert.equal(await store.process('u',a.mutationId),'APPLIED');
 await assert.rejects(store.submit({uid:'u'},{...a,payloadJson:JSON.stringify(add(999))}),/ID_CONFLICT/);
});
test('old-context ADD after fence/release is rejected, no second row',async()=>{
 const item=await seed(),r=await command(add(500));await item.ref.parent.parent!.update(advanceShoppingEpoch(Timestamp.fromMillis(time)));
 assert.equal(await store.process('u',r.mutationId),'REJECTED_CONTEXT_CHANGED');assert.equal((await rows()).size,1);assert.equal((await item.ref.get()).get('quantity'),1000);
});
for(const type of ['EDIT','DELETE','SET_CHECKED'] as const)test(`new +500 survives stale ${type}`,async()=>{
 const i=await seed(),c:Child=type==='EDIT'?{type,itemId:i.id,expectedRevision:1,name:'renamed',quantity:1000,unit:'g'}:type==='SET_CHECKED'?{type,itemId:i.id,expectedRevision:1,isChecked:true}:{type,itemId:i.id,expectedRevision:1};
 const old=await command(c),a=await command(add(500));await store.process('u',a.mutationId);
 assert.equal(await store.process('u',old.mutationId),'REJECTED_STALE');assert.equal((await i.ref.get()).get('quantity'),1500);
});
for(const type of ['EDIT','DELETE','SET_CHECKED'] as const)test(`${type} exact once concurrent/retry and explicit fields`,async()=>{
 const i=await seed(),c:Child=type==='EDIT'?{type,itemId:i.id,expectedRevision:1,name:' NEW ',quantity:2,unit:'kg'}:type==='SET_CHECKED'?{type,itemId:i.id,expectedRevision:1,isChecked:true}:{type,itemId:i.id,expectedRevision:1};
 const r=await command(c);assert.deepEqual(await Promise.all([store.process('u',r.mutationId),store.process('u',r.mutationId)]),['APPLIED','APPLIED']);
 const d=await i.ref.get();if(type==='DELETE')assert.equal(d.exists,false);else{assert.equal(d.get('revision'),2);if(type==='EDIT'){assert.equal(d.get('name'),'new');assert.equal(d.get('quantity'),2000);}else assert.equal(d.get('isChecked'),true);}
});
for(const pair of [['EDIT','ADD'],['DELETE','ADD'],['EDIT','EDIT'],['DELETE','EDIT'],['SET_CHECKED','EDIT'],['SET_CHECKED','ADD']] as const)test(`concurrency ${pair.join(' vs ')}`,async()=>{
 const i=await seed();const c=(type:string):Child=>type==='ADD'?add(500):type==='EDIT'?{type:'EDIT',itemId:i.id,expectedRevision:1,name:'alma',quantity:2000,unit:'g'}:type==='DELETE'?{type:'DELETE',itemId:i.id,expectedRevision:1}:{type:'SET_CHECKED',itemId:i.id,expectedRevision:1,isChecked:true};
 const a=await command(c(pair[0])),b=await command(c(pair[1]));const out=await Promise.all([store.process('u',a.mutationId),store.process('u',b.mutationId)]);
 assert.ok(out.includes('APPLIED'));const data=(await rows()).docs;
 if(pair[1]==='ADD'){assert.equal(data.length,1);const q=data[0]!.get('quantity');assert.ok(pair[0]==='EDIT'?[1500,2500].includes(q):pair[0]==='DELETE'?[500,1500].includes(q):q===1500);}
 else assert.equal(out.filter(x=>x==='APPLIED').length,1);
});
test('merge edit preserves target checked/created/custom, deletes source atomically',async()=>{
 const source=await seed(),r=await command(add(1,'target'));await store.process('u',r.mutationId);const target=(await rows()).docs.find(d=>d.id!==source.id)!;await target.ref.update({isChecked:true,custom:'keep'});
 const created=target.get('createdAt');const e=await command({type:'EDIT',itemId:source.id,expectedRevision:1,name:'target',quantity:1000,unit:'g'});await store.process('u',e.mutationId);
 const d=await target.ref.get();assert.equal(d.get('quantity'),1001);assert.equal(d.get('isChecked'),true);assert.equal(d.get('custom'),'keep');assert.ok(d.get('createdAt').isEqual(created));assert.equal((await source.ref.get()).exists,false);
});
for(const n of [10,50,200])test(`bulk ${n}, interruption/new worker, duplicate replay`,async()=>{
 await setup();const r=await command(Array.from({length:n},(_,i)=>add(1,`item${i%10}`)));
 assert.equal(await store.process('u',r.mutationId,3),'PROCESSING');assert.equal((await receipt(r.mutationId)).get('cursor'),3);
 store=new ShoppingMutationStore(db,()=>Timestamp.fromMillis(time));let status='PROCESSING';while(status==='PROCESSING')status=await store.continueWork('u',r.mutationId);
 assert.equal(status,'APPLIED');await store.process('u',r.mutationId);const list=await rows();assert.equal(list.size,10);for(const d of list.docs)assert.equal(d.get('quantity'),n/10);
 assert.equal((await receipt(r.mutationId)).get('payloadJson'),undefined);
});
test('bulk context changes: partial result never repeats committed child',async()=>{
 await setup();const r=await command([add(1,'a'),add(1,'b')]);await store.process('u',r.mutationId,1);await db.doc(`households/${r.householdId}`).update(advanceShoppingEpoch(Timestamp.fromMillis(time)));
 assert.equal(await store.process('u',r.mutationId),'PARTIAL');assert.equal((await rows()).size,1);assert.equal((await receipt(r.mutationId)).get('appliedCount'),1);
});
test('retention cleans compact receipt; expired replay never reapplies even before rotation',async()=>{
 await setup();const r=await command(add());await store.process('u',r.mutationId);assert.equal(await store.continueWork('u',r.mutationId),'APPLIED');
 time=epochExpiry(r.epoch)+RETENTION_MS+1;assert.equal(await store.continueWork('u',r.mutationId),'CLEANED');assert.equal((await receipt(r.mutationId)).exists,false);
 await assert.rejects(store.submit({uid:'u'},r),/REJECTED_CONTEXT_CHANGED/);
 // Simulate an extremely delayed duplicate event/admin transport insertion too.
 await db.doc(`users/u/shoppingMutations/${r.mutationId}`).set(r);assert.equal(await store.process('u',r.mutationId),'REJECTED_CONTEXT_CHANGED');assert.equal((await rows()).docs[0]!.get('quantity'),1);
});
test('legacy item revision zero lazily normalizes, keeps unknown fields',async()=>{
 await setup();const ref=db.doc(`households/${privateHouseholdId('u')}/shoppingItems/legacy`);await ref.set({name:'alma',quantity:2,unit:'g',isChecked:true,createdAt:Timestamp.fromMillis(1),unknown:{a:1}});
 const r=await command({type:'SET_CHECKED',itemId:'legacy',expectedRevision:0,isChecked:false});assert.equal(await store.process('u',r.mutationId),'APPLIED');const d=await ref.get();assert.equal(d.get('revision'),1);assert.deepEqual(d.get('unknown'),{a:1});
});
test('existing logical duplicates fail closed',async()=>{
 await setup();for(const id of ['a','b'])await db.doc(`households/${privateHouseholdId('u')}/shoppingItems/${id}`).set({name:'alma',quantity:1,unit:'g'});
 const r=await command(add());assert.equal(await store.process('u',r.mutationId),'FAILED_TERMINAL');for(const d of (await rows()).docs)assert.equal(d.get('quantity'),1);
});
for(const state of ['DELETING','DELETED'])test(`lifecycle ${state} denies pending command`,async()=>{
 await setup();const r=await command(add());await db.doc('accountLifecycle/u').update({state});assert.equal(await store.process('u',r.mutationId),'REJECTED_UNAUTHORIZED');assert.equal((await rows()).size,0);
});
test('authorized family member and owner concurrent adds; stranger denied',async()=>{
 await setup('owner');await setup('member');await setup('stranger');const h='family';
 await db.doc(`households/${h}`).set({schemaVersion:2,kind:'family',state:'ACTIVE',operationId:null,ownerUid:'owner',createdAt:Timestamp.now()});
 for(const [uid,role] of [['owner','owner'],['member','member']]){await db.doc(`users/${uid}`).update({activeHouseholdId:h,familyHouseholdId:h});await db.doc(`households/${h}/members/${uid}`).set({role});await db.doc(`familyMemberships/${uid}`).set({householdId:h,role,state:'ACTIVE',operationId:null});}
 const a=await command(add(2),'owner'),b=await command(add(3),'member');await Promise.all([store.process('owner',a.mutationId),store.process('member',b.mutationId)]);const list=await rows(h);assert.equal(list.size,1);assert.equal(list.docs[0]!.get('quantity'),5);
 await assert.rejects(store.submit({uid:'stranger'},{...a,actorUid:'stranger',mutationId:newMutationId(a.epoch)}),/REJECTED_CONTEXT_CHANGED/);
});
test('deletion removes command/work payloads, late trigger cannot recreate user',async()=>{
 await setup();const r=await command([add(),add(1,'b')]);await store.process('u',r.mutationId,1);
 const deletion=new AccountDeletionService(db,new FakeAuthDeletionApi());await deletion.beginAccountDeletion({uid:'u'});assert.equal(await deletion.resume('u',50,2),'deletionCompleted');
 assert.equal((await receipt(r.mutationId)).exists,false);assert.equal((await db.doc(`shoppingMutationWork/${workId(`users/u/shoppingMutations/${r.mutationId}`)}`).get()).exists,false);
 assert.equal(await store.process('u',r.mutationId),'ABSENT');assert.equal((await db.doc('users/u').get()).exists,false);
});
for(const field of ['state','operationId'])test(`structural ${field} barrier rejects without effects`,async()=>{
 await setup();const r=await command(add());await db.doc(`households/${r.householdId}`).update({[field]:field==='state'?'DISSOLVING':'operation'});
 assert.equal(await store.process('u',r.mutationId),'REJECTED_CONTEXT_CHANGED');assert.equal((await rows()).size,0);
});
test('ABA delete/recreate cannot satisfy the original revision',async()=>{
 const i=await seed();const stale=await command({type:'DELETE',itemId:i.id,expectedRevision:1});const d=await command({type:'DELETE',itemId:i.id,expectedRevision:1});await store.process('u',d.mutationId);
 const a=await command(add());await store.process('u',a.mutationId);const newer=(await rows()).docs[0]!;assert.equal(newer.get('revision'),3);
 assert.equal(await store.process('u',stale.mutationId),'REJECTED_NOT_FOUND');assert.equal((await rows()).size,1);
});
test('invalid bulk child is rejected before first mutation',async()=>{
 await setup();await assert.rejects(command([add(),{type:'ADD',name:'',quantity:1,unit:'g'}]));assert.equal((await rows()).size,0);
});
test('rules-mediated malformed JSON becomes sanitized compact terminal receipt',async()=>{
 await setup();const r=await command(add());await db.doc(`users/u/shoppingMutations/${r.mutationId}`).update({payloadJson:'{bad'});
 assert.equal(await store.process('u',r.mutationId),'FAILED_TERMINAL');assert.equal((await receipt(r.mutationId)).get('payloadJson'),undefined);assert.equal((await rows()).size,0);
});
test('v1 private root and existing copied revision initialize safely',async()=>{
 await new HouseholdStore(db).ensure({uid:'u'});const home=db.doc(`households/${privateHouseholdId('u')}`);
 await home.set({schemaVersion:1,ownerUid:'u',createdAt:Timestamp.now()});await home.collection('shoppingItems').doc('copied').set({name:'alma',quantity:2,unit:'g',revision:80});
 await store.ensureContext({uid:'u'});const r=await command(add());await store.process('u',r.mutationId);assert.equal((await home.collection('shoppingItems').doc('copied').get()).get('revision'),81);
});
test('transient pre-commit failure persists bounded retry work, same ID resumes',async()=>{
 await setup();const r=await command(add()),original=db.runTransaction.bind(db);let once=true;
 (db as any).runTransaction=async(...args:any[])=>{if(once){once=false;throw new Error('temporary');}return (original as any)(...args);};
 try{await assert.rejects(store.process('u',r.mutationId),/temporary/);}finally{(db as any).runTransaction=original;}
 assert.equal((await receipt(r.mutationId)).get('status'),'FAILED_RETRYABLE');assert.equal(await store.process('u',r.mutationId),'FAILED_RETRYABLE');assert.equal((await rows()).size,0);
 time+=300001;assert.equal(await store.continueWork('u',r.mutationId),'APPLIED');assert.equal((await rows()).docs[0]!.get('quantity'),1);
});
test('crash after atomic canonical+receipt commit cannot reapply',async()=>{
 await setup();const r=await command(add()),original=db.runTransaction.bind(db);let once=true;
 (db as any).runTransaction=async(...args:any[])=>{const result=await (original as any)(...args);if(once){once=false;throw new Error('lostAck');}return result;};
 try{await assert.rejects(store.process('u',r.mutationId),/lostAck/);}finally{(db as any).runTransaction=original;}
 assert.equal(await store.process('u',r.mutationId),'APPLIED');assert.equal((await rows()).docs[0]!.get('quantity'),1);
});
test('maintenance continues bounded pending work and isolates poisoned job',async()=>{
 await setup();const r=await command(Array.from({length:12},()=>add()));await store.process('u',r.mutationId,1);
 await db.doc('shoppingMutationWork/bad').set({uid:'../bad',mutationId:'bad',nextAt:Timestamp.fromMillis(time)});
 const never=async()=>{throw new Error('unrelated API must not be called');};
 const maintenance=new Maintenance(db,{play:{lookup:never},voided:{lookup:never},ack:{acknowledge:never},feed:{list:never},binding:new AccountBinding(Buffer.alloc(32,1))},()=>Timestamp.fromMillis(time));
 const report=await maintenance.run({now:Timestamp.fromMillis(time),only:['shopping']});assert.ok(report.items.some(x=>x.outcome==='retryable'));assert.equal((await receipt(r.mutationId)).get('cursor'),11);
 await maintenance.run({now:Timestamp.fromMillis(time),only:['shopping']});assert.equal((await receipt(r.mutationId)).get('status'),'APPLIED');assert.equal((await rows()).docs[0]!.get('quantity'),12);
});
test('Phase 4A RESERVED member can mutate only unchanged private context',async()=>{
 await setup();const p=privateHouseholdId('u');
 await db.doc('familyMemberships/u').set({state:'RESERVED',role:'member',householdId:'family',operationId:'join'});
 await db.doc('familyOperations/join').set({kind:'JOIN',status:'READY',phase:'READY_FOR_TRANSFER',actorUid:'u',sourceHouseholdId:p,householdId:'family'});
 const r=await command(add());assert.equal(await store.process('u',r.mutationId),'APPLIED');
 const user=await db.doc('users/u').get();assert.equal(user.get('activeHouseholdId'),p);assert.equal(user.get('familyHouseholdId'),null);assert.equal((await db.doc('familyOperations/join').get()).get('phase'),'READY_FOR_TRANSFER');
});
test('persistent infrastructure failure stops after eight attempts without repeating effects',async()=>{
 await setup();const r=await command(add()),original=db.runTransaction.bind(db);
 for(let i=0;i<8;i++){
  let once=true;(db as any).runTransaction=async(...args:any[])=>{if(once){once=false;throw new Error('temporary');}return (original as any)(...args);};
  try{await assert.rejects(store.process('u',r.mutationId));}finally{(db as any).runTransaction=original;}
  time+=3600001;
 }
 const d=await receipt(r.mutationId);assert.equal(d.get('status'),'FAILED_TERMINAL');assert.equal(d.get('failures'),8);assert.equal(d.get('payloadJson'),undefined);assert.equal((await rows()).size,0);
 await store.submit({uid:'u'},r);assert.equal(await store.process('u',r.mutationId),'FAILED_TERMINAL');
 await assert.rejects(store.submit({uid:'u'},{...r,payloadJson:JSON.stringify(add(2))}),/ID_CONFLICT/);
});
test('mixed bulk reports granular stale/not-found and applied results without retrying',async()=>{
 const i=await seed();const r=await command([{type:'DELETE',itemId:i.id,expectedRevision:0},{type:'DELETE',itemId:'missing',expectedRevision:0},add(5)]);
 assert.equal(await store.process('u',r.mutationId),'PARTIAL');
 assert.deepEqual((await receipt(r.mutationId)).get('results').map((x:{code:string})=>x.code),['REJECTED_STALE','REJECTED_NOT_FOUND','APPLIED']);
 await store.process('u',r.mutationId);assert.equal((await i.ref.get()).get('quantity'),1005);
});
for(const corruption of ['missingMember','wrongRole','pointer','reverse'])test(`pending request rechecks authority: ${corruption}`,async()=>{
 await setup();const r=await command(add()),home=db.doc(`households/${r.householdId}`);
 if(corruption==='missingMember')await home.collection('members').doc('u').delete();
 if(corruption==='wrongRole')await home.collection('members').doc('u').update({role:'member'});
 if(corruption==='pointer')await db.doc('users/u').update({activeHouseholdId:'other'});
 if(corruption==='reverse')await db.doc('familyMemberships/u').set({householdId:'other',role:'member',state:'ACTIVE',operationId:null});
 assert.ok(['REJECTED_CONTEXT_CHANGED','REJECTED_UNAUTHORIZED'].includes(await store.process('u',r.mutationId)));assert.equal((await rows()).size,0);
});
