import {DissolutionSourceDispositionStore,preservationCleanupId} from '../src/households/dissolution-source-disposition';
import {after,beforeEach,test} from 'node:test';
import assert from 'node:assert/strict';
import {initializeApp,deleteApp} from 'firebase-admin/app';
import {Firestore,getFirestore,Timestamp} from 'firebase-admin/firestore';
import {requireLocalEmulator} from './emulator-guard';
import {HouseholdStore,privateHouseholdId} from '../src/households/household-store';
import {DissolutionPreparationStore,dissolutionId} from '../src/households/dissolution-preparation';
import {DissolutionPreservationStore,readPreservation,preservationPageId} from '../src/households/dissolution-preservation';
import {DissolutionMergeStore} from '../src/households/dissolution-merge';
import {ShoppingMutationStore} from '../src/shopping/mutation-store';
import {MemberLeaveStore} from '../src/households/member-leave';
import {FamilyJoinStore} from '../src/households/family-join';
import {FamilyInviteStore} from '../src/households/family-invites';
import {LifecycleStore} from '../src/billing/lifecycle-store';
import {newMutationId} from '../src/shopping/mutation-contract';
import {FirestoreMeter} from './firestore-meter';
import {now,grant} from './fixtures';
requireLocalEmulator(process.env);
const app=initializeApp({projectId:'demo-kuktam-local'},'dissolution-source-disposition'),db=getFirestore(app),clock=()=>now;
beforeEach(async()=>{assert.ok((await fetch('http://127.0.0.1:8088/emulator/v1/projects/demo-kuktam-local/databases/(default)/documents',{method:'DELETE'})).ok);});
after(()=>deleteApp(app));
const list=async(c:FirebaseFirestore.CollectionReference)=>(await c.get()).docs.map(d=>[d.id,d.data(),d.updateTime]);
async function mergedFixture(n=1,repeated=false,pending=false,incompatible=false,legacy=false){
 const hid='family-merge',source=db.doc(`households/${hid}`),target=db.doc(`households/${privateHouseholdId('owner')}`),shopping=new ShoppingMutationStore(db,clock);
 for(const uid of ['owner','member'])await new HouseholdStore(db).ensure({uid});
 await db.doc('shoppingRuntime/config').set({enabled:true});await db.doc('familyRuntime/config').set({inviteCreationEnabled:true,joinReservationEnabled:true});
 const privateContext=await shopping.ensureContext({uid:'owner'}),privateId=newMutationId(privateContext.epoch);
 await shopping.submit({uid:'owner'},{schemaVersion:1,mutationId:privateId,actorUid:'owner',...privateContext,kind:'ADD',payloadJson:JSON.stringify({type:'ADD',name:'late',quantity:1,unit:'db'}),submittedAt:now});
 await source.set({schemaVersion:2,kind:'family',state:'ACTIVE',ownerUid:'owner',operationId:null,createdAt:now});
 for(const uid of ['owner','member']){await source.collection('members').doc(uid).set({role:uid==='owner'?'owner':'member'});await db.doc(`familyMemberships/${uid}`).set({householdId:hid,role:uid==='owner'?'owner':'member',state:'ACTIVE',operationId:null});await db.doc(`users/${uid}`).update({activeHouseholdId:hid,familyHouseholdId:hid});}
 await db.doc(`familyJoinCapacity/${hid}`).set({schemaVersion:2,operationIds:[],structuralOperationId:null});await db.doc(`familyInviteSlots/${hid}`).set({schemaVersion:1,inviteIds:[]});await db.doc('users/owner/entitlementGrants/pro').set(grant());
 await target.collection('shoppingItems').doc('keep').set({name:incompatible?'product0':'milk',quantity:1000,unit:'ml',revision:7,isChecked:true,createdAt:now,...(legacy?{custom:'legacy'}:{})});
 await target.collection('shoppingItems').doc('unrelated').set({name:'bread',quantity:3,unit:'db',revision:8,custom:'untouched'});
 const batch=db.batch();for(let i=0;i<n;i++)batch.create(source.collection('shoppingItems').doc(`i${String(i).padStart(4,'0')}`),{name:repeated?'Milk':`product${i}`,quantity:repeated?(n===3&&i===2?500:i%2?2:300):1,unit:repeated?(i%2?'l':'ml'):'db',isChecked:false,createdAt:now});if(n)await batch.commit();
 const invites=new FamilyInviteStore(db,{resolve:async()=>new Map()},clock),join=new FamilyJoinStore(db,clock);let reservation:any=null;
 if(pending){await new HouseholdStore(db).ensure({uid:'pending'});const inv=await invites.create({uid:'owner'});reservation=await join.reserve({uid:'pending'},inv.token,'ADD');}
 const id=dissolutionId('owner',hid),ref=db.doc(`familyOperations/${id}`),prepare=new DissolutionPreparationStore(db,clock);await prepare.prepare({uid:'owner'},hid);
 const pre=new DissolutionPreservationStore(db,clock);for(let i=0;i<2*Math.ceil(n/10)+10;i++)if(await pre.step({uid:'owner'},hid)==='PRESERVATION_COMMITTED')break;
 assert.equal((await ref.get()).get('phase'),'PRESERVATION_COMMITTED');
 const o=readPreservation((await ref.get()).data(),id),state=ref.collection('preservationMerge').doc('state'),journals=ref.collection('preservationMergeJournal');
 const refs=[source,db.doc('users/owner'),db.doc('users/member'),db.doc('familyMemberships/owner'),db.doc('familyMemberships/member'),db.doc(`familyJoinCapacity/${hid}`),db.doc(`familyInviteSlots/${hid}`),target.collection('shoppingItems').doc('unrelated')];
 const before=(await db.getAll(...refs)).map(d=>[d.data(),d.updateTime]),items=await list(source.collection('shoppingItems')),pages=await list(ref.collection('shoppingPreservation'));
 const store=new DissolutionMergeStore(db,clock),step=()=>store.step({uid:'owner'},hid);
 const finish=async()=>{for(let i=0;i<n+2*Math.ceil(n/10)+10;i++){const r=await step();if(r==='PRESERVATION_MERGE_COMPLETE')return;if(r==='OPERATOR')throw new Error('unexpectedOperator');}throw new Error('stuck');};
 const boundary=async()=>{assert.deepEqual((await db.getAll(...refs)).map(d=>[d.data(),d.updateTime]),before);assert.deepEqual(await list(source.collection('shoppingItems')),items);assert.deepEqual(await list(ref.collection('shoppingPreservation')),pages);assert.equal((await target.get()).get('operationId'),id);assert.equal((await target.get()).get('shoppingEpoch'),o.targetFence.epoch);assert.deepEqual((await ref.get()).get('participants'),o.participants);};
 return {hid,id,ref,source,target,o,state,journals,step,finish,boundary,store,shopping,privateId,pre,prepare,join,reservation};
}
async function fixture(n=1,pending=false){
 const f=await mergedFixture(n,true,pending);await f.finish();
 const refs=[f.source,f.target,db.doc('users/owner'),db.doc('users/member'),db.doc('familyMemberships/owner'),db.doc('familyMemberships/member'),f.source.collection('members').doc('owner'),f.source.collection('members').doc('member'),db.doc(`familyJoinCapacity/${f.hid}`),db.doc(`familyInviteSlots/${f.hid}`),f.state];
 const before=(await db.getAll(...refs)).map(d=>[d.data(),d.updateTime]),targetItems=await list(f.target.collection('shoppingItems')),snapshots=await list(f.ref.collection('shoppingPreservation')),mergeJournal=await list(f.journals);
 const store=new DissolutionSourceDispositionStore(db,clock),state=f.ref.collection('preservationSourceCleanup').doc('state'),journals=f.ref.collection('preservationSourceCleanupJournal'),step=()=>store.step({uid:'owner'},f.hid);
 const ready=async()=>{for(let i=0;i<Math.ceil(n/10)+4;i++){await step();if((await state.get()).get('stage')==='DELETE')return;}throw new Error('notReady');};
 const finish=async()=>{for(let i=0;i<3*Math.ceil(n/10)+10;i++){const r=await step();if(r==='PRESERVATION_SOURCE_CLEANED')return;if(r==='OPERATOR')throw new Error('unexpectedOperator');}throw new Error('stuck');};
 const boundary=async()=>{assert.deepEqual((await db.getAll(...refs)).map(d=>[d.data(),d.updateTime]),before);assert.deepEqual(await list(f.target.collection('shoppingItems')),targetItems);assert.deepEqual(await list(f.ref.collection('shoppingPreservation')),snapshots);assert.deepEqual(await list(f.journals),mergeJournal);assert.deepEqual((await f.ref.get()).get('participants'),f.o.participants);};
 return {...f,merge:f.store,store,state,journals,step,finish,ready,boundary,targetItems};
}
for(const n of [0,1,11,25,201])test(`5C3 cleanup ${n} exact preserved source only with retained boundary`,async()=>{
 const f=await fixture(n);await f.finish();assert.equal((await f.ref.get()).get('phase'),'PRESERVATION_SOURCE_CLEANED');assert.equal((await f.source.collection('shoppingItems').get()).size,0);assert.equal((await f.state.get()).get('count'),n);assert.equal((await f.journals.get()).size,Math.ceil(n/10));
 const results=(await f.journals.get()).docs.flatMap(d=>d.get('results'));assert.equal(results.length,n);assert.equal(new Set(results.map((r:any)=>r.cleanupId)).size,n);assert.ok(results.every((r:any)=>r.code==='DELETED'&&r.cleanupId===preservationCleanupId(r.transferId)));await f.boundary();
 const before=await db.getAll(f.ref,f.state,f.source,f.target);assert.equal(await f.step(),'PRESERVATION_SOURCE_CLEANED');assert.equal(await f.merge.step({uid:'owner'},f.hid),'PRESERVATION_SOURCE_CLEANED');assert.equal(await f.pre.step({uid:'owner'},f.hid),'PRESERVATION_SOURCE_CLEANED');assert.deepEqual((await db.getAll(f.ref,f.state,f.source,f.target)).map(d=>[d.data(),d.updateTime]),before.map(d=>[d.data(),d.updateTime]));
});
test('5C3 interruption resumes and already-cleaned durable prefix is accepted',async()=>{const f=await fixture(25);await f.ready();await f.step();assert.equal((await f.source.collection('shoppingItems').get()).size,15);const first=(await f.journals.get()).docs[0]!;await new DissolutionSourceDispositionStore(db,clock).step({uid:'owner'},f.hid);await f.finish();assert.ok((await first.ref.get()).updateTime!.isEqual(first.updateTime!));assert.equal((await f.source.collection('shoppingItems').get()).size,0);await f.boundary();});
function wrap(run:(cb:any)=>Promise<any>){return new Proxy(db,{get(t,k){if(k==='runTransaction')return run;const v=(t as any)[k];return typeof v==='function'?v.bind(t):v;}}) as Firestore;}
test('5C3 lost block ACK recovers durable cleanup without missing-item false positive',async()=>{const f=await fixture(11);await f.ready();const wrapped=wrap(async cb=>{await db.runTransaction(cb);throw new Error('lostAck');});await assert.rejects(new DissolutionSourceDispositionStore(wrapped,clock).step({uid:'owner'},f.hid),/lostAck/);const first=(await f.journals.get()).docs[0]!;assert.equal((await f.source.collection('shoppingItems').get()).size,1);await f.finish();assert.ok((await first.ref.get()).updateTime!.isEqual(first.updateTime!));await f.boundary();});
test('5C3 competing workers commit one logical cleanup',async()=>{const f=await fixture(11);for(let i=0;i<14;i++){const r=await Promise.all([f.step(),f.step()]);if(r.includes('PRESERVATION_SOURCE_CLEANED'))break;}assert.equal((await f.ref.get()).get('phase'),'PRESERVATION_SOURCE_CLEANED');assert.equal((await f.journals.get()).size,2);assert.equal((await f.source.collection('shoppingItems').get()).size,0);await f.boundary();});
test('5C3 forced transaction failure rolls back deletions journal and cursor',async()=>{const f=await fixture(11);await f.ready();const before=(await db.getAll(f.ref,f.state)).map(d=>[d.data(),d.updateTime]),source=await list(f.source.collection('shoppingItems'));
 const wrapped=wrap(cb=>db.runTransaction(async tx=>{await cb(tx);throw Object.assign(new Error('forcedFailure'),{code:10});},{maxAttempts:1}));await assert.rejects(new DissolutionSourceDispositionStore(wrapped,clock).step({uid:'owner'},f.hid),/forcedFailure/);assert.deepEqual(await list(f.source.collection('shoppingItems')),source);assert.equal((await f.journals.get()).size,0);assert.deepEqual((await db.getAll(f.ref,f.state)).map(d=>[d.data(),d.updateTime]),before);await f.boundary();await f.finish();
});
for(const kind of ['missing','content','updateTime','snapshot','preservationReceipt','preservationState','sourceFence','targetFence','cursor'])test(`5C3 ${kind} mismatch parks OPERATOR before deleting block`,async()=>{
 const f=await fixture(11);await f.ready();const src=f.source.collection('shoppingItems').doc('i0001');
 if(kind==='missing')await src.delete();
 if(kind==='content')await src.update({quantity:999});
 if(kind==='updateTime'){const original=(await src.get()).data()!;await src.update({quantity:999});await src.set(original);}
 if(kind==='snapshot'){const ref=f.ref.collection('shoppingPreservation').doc(preservationPageId(f.o,0)),v=(await ref.get()).data()!;v.entries[0].dataHash='a'.repeat(64);await ref.set(v);}
 if(kind==='preservationReceipt'){const ref=f.ref.collection('preservationMergeJournal').doc(preservationPageId(f.o,0)),v=(await ref.get()).data()!;v.results[0].itemId='wrong';await ref.set(v);}
 if(kind==='preservationState')await f.ref.collection('preservationMerge').doc('state').update({stage:'APPLY'});
 if(kind==='sourceFence')await f.source.update({operationId:'wrong'});
 if(kind==='targetFence')await f.target.update({operationId:'wrong'});
 if(kind==='cursor')await f.state.update({count:1});
 const source=await list(f.source.collection('shoppingItems'));assert.equal(await f.step(),'OPERATOR');assert.deepEqual(await list(f.source.collection('shoppingItems')),source);assert.equal((await f.journals.get()).size,0);assert.deepEqual(await list(f.target.collection('shoppingItems')),f.targetItems);assert.equal(await f.step(),'OPERATOR');
});
test('5C3 corrupt cleanup prefix cannot continue deleting remaining source',async()=>{const f=await fixture(11);await f.ready();await f.step();const page=(await f.journals.get()).docs[0]!,v=page.data();v.results[0].cleanupId='a'.repeat(64);await page.ref.set(v);assert.equal(await f.step(),'OPERATOR');assert.equal((await f.source.collection('shoppingItems').get()).size,1);assert.deepEqual(await list(f.target.collection('shoppingItems')),f.targetItems);});
test('5C3 missing cleanup journal is not accepted as already cleaned',async()=>{const f=await fixture(11);await f.ready();await f.step();await (await f.journals.get()).docs[0]!.ref.delete();assert.equal(await f.step(),'OPERATOR');assert.equal((await f.source.collection('shoppingItems').get()).size,1);});
for(const when of ['before','afterPartial'])test(`5C3 unexplained extra source ${when} is retained and OPERATOR`,async()=>{const f=await fixture(11);if(when==='afterPartial'){await f.ready();await f.step();}await f.source.collection('shoppingItems').doc('unrelated').set({name:'extra',quantity:50,unit:'db'});let r='';for(let i=0;i<15&&r!=='OPERATOR';i++)r=await f.step();assert.equal(r,'OPERATOR');assert.equal((await f.source.collection('shoppingItems').doc('unrelated').get()).get('quantity'),50);if(when==='before')assert.equal((await f.source.collection('shoppingItems').get()).size,12);assert.deepEqual(await list(f.target.collection('shoppingItems')),f.targetItems);});
test('5C3 recreated cleaned item is integrity failure, never deleted without fresh authority',async()=>{const f=await fixture(1);await f.ready();await f.step();await f.source.collection('shoppingItems').doc('i0000').set({name:'new',quantity:9,unit:'db'});assert.equal(await f.step(),'PRESERVATION_MERGE_COMPLETE');assert.equal(await f.step(),'OPERATOR');assert.equal((await f.source.collection('shoppingItems').doc('i0000').get()).get('quantity'),9);});
test('5C3 locks and lifecycle admission remain guarded after cleanup',async()=>{const f=await fixture(11,true);await f.ready();await f.step();for(const uid of ['owner','member'])await assert.rejects(new LifecycleStore(db,clock).beginDeletion(uid),/JOIN_COMMITTED_IN_PROGRESS/);await db.doc('users/owner/entitlementGrants/pro').delete();await f.finish();const exits=new MemberLeaveStore(db,clock);await assert.rejects(exits.leave({uid:'member'},'c'.repeat(64)),/IN_PROGRESS/);await assert.rejects(exits.remove({uid:'owner'},'member','c'.repeat(64)),/IN_PROGRESS|INTEGRITY_REQUIRES_OPERATOR/);await assert.rejects(f.prepare.prepare({uid:'owner'},f.hid),/IN_PROGRESS|INTEGRITY_REQUIRES_OPERATOR/);assert.equal(await f.join.resume(f.reservation),'IN_PROGRESS');for(const uid of ['owner','member'])await assert.rejects(new LifecycleStore(db,clock).beginDeletion(uid),/JOIN_COMMITTED_IN_PROGRESS/);await db.doc('users/owner/entitlementGrants/pro').delete();assert.equal(await f.step(),'PRESERVATION_SOURCE_CLEANED');assert.equal(await f.shopping.process('owner',f.privateId),'REJECTED_CONTEXT_CHANGED');for(const uid of ['owner','member'])await assert.rejects(f.shopping.ensureContext({uid}),/REJECTED_UNAUTHORIZED|REJECTED_CONTEXT_CHANGED/);await f.boundary();});
test('5C3 wrong actor and premature phase cannot start cleanup',async()=>{const f=await fixture(1);await assert.rejects(f.store.step({uid:'member'},f.hid),/NOT_FOUND/);await f.ref.update({phase:'PRESERVATION_COMMITTED'});await assert.rejects(f.step(),/INVALID_ARGUMENT/);assert.equal((await f.state.get()).exists,false);assert.equal((await f.source.collection('shoppingItems').get()).size,1);});
