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
const app=initializeApp({projectId:'demo-kuktam-local'},'dissolution-merge'),db=getFirestore(app),clock=()=>now;
beforeEach(async()=>{assert.ok((await fetch('http://127.0.0.1:8088/emulator/v1/projects/demo-kuktam-local/databases/(default)/documents',{method:'DELETE'})).ok);});
after(()=>deleteApp(app));
const list=async(c:FirebaseFirestore.CollectionReference)=>(await c.get()).docs.map(d=>[d.id,d.data(),d.updateTime]);
async function fixture(n=1,repeated=false,pending=false,incompatible=false,legacy=false){
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
for(const n of [0,1,11,25,201])test(`5C2B exact merge ${n} receipts sequence source and boundary`,async()=>{
 const f=await fixture(n);await f.finish();const s=(await f.state.get()).data()!;assert.equal(s.stage,'COMPLETE');assert.equal(s.count,n);assert.equal(s.blocks,Math.ceil(n/10));assert.equal((await f.target.collection('shoppingItems').get()).size,n+2);
 const journals=(await f.journals.get()).docs.sort((a,b)=>a.get('pageIndex')-b.get('pageIndex'));const results=journals.flatMap(d=>d.get('results'));assert.equal(results.length,n);assert.equal(new Set(results.map((r:any)=>r.transferId)).size,n);assert.deepEqual(results.map((r:any)=>r.revision),Array.from({length:n},(_,i)=>9+i));assert.ok(results.every((r:any)=>r.code==='APPLIED'&&r.created));
 await f.boundary();const before=await db.getAll(f.ref,f.target,f.state);assert.equal(await f.step(),'PRESERVATION_MERGE_COMPLETE');assert.equal(await f.pre.step({uid:'owner'},f.hid),'PRESERVATION_MERGE_COMPLETE');assert.deepEqual((await db.getAll(f.ref,f.target,f.state)).map(d=>[d.data(),d.updateTime]),before.map(d=>[d.data(),d.updateTime]));
});
for(const n of [2,3,25])test(`5C2B repeated compatible source ${n} within/across blocks preserves existing owner item`,async()=>{
 const f=await fixture(n,true);await f.finish();const expected=n===3?3800:1000+Math.ceil(n/2)*300+Math.floor(n/2)*2000;assert.equal((await f.target.collection('shoppingItems').doc('keep').get()).get('quantity'),expected);assert.equal((await f.target.collection('shoppingItems').get()).size,2);assert.equal((await f.target.collection('shoppingItems').doc('keep').get()).get('isChecked'),true);await f.boundary();
});
test('5C2B incompatible units remain separate',async()=>{const f=await fixture(1,false,false,true);await f.finish();const docs=(await f.target.collection('shoppingItems').where('name','==','product0').get()).docs;assert.equal(docs.length,2);assert.deepEqual(docs.map(d=>d.get('unit')).sort(),['db','ml']);await f.boundary();});
test('5C2B interruption resumes stable IDs after a durable block',async()=>{const f=await fixture(25,true);await f.step();await f.step();const first=(await f.journals.get()).docs[0]!;assert.equal(first.get('results').length,10);await new DissolutionMergeStore(db,clock).step({uid:'owner'},f.hid);await f.finish();assert.ok((await first.ref.get()).updateTime!.isEqual(first.updateTime!));assert.equal((await f.target.collection('shoppingItems').doc('keep').get()).get('quantity'),28900);await f.boundary();});
function wrap(run:(cb:any)=>Promise<any>){return new Proxy(db,{get(t,k){if(k==='runTransaction')return run;const v=(t as any)[k];return typeof v==='function'?v.bind(t):v;}}) as Firestore;}
test('5C2B lost block acknowledgement never replays quantity or receipt',async()=>{const f=await fixture(11,true);await f.step();const wrapped=wrap(async cb=>{await db.runTransaction(cb);throw new Error('lostAck');});await assert.rejects(new DissolutionMergeStore(wrapped,clock).step({uid:'owner'},f.hid),/lostAck/);const first=(await f.journals.get()).docs[0]!;await f.finish();assert.ok((await first.ref.get()).updateTime!.isEqual(first.updateTime!));assert.equal((await f.target.collection('shoppingItems').doc('keep').get()).get('quantity'),12800);await f.boundary();});
test('5C2B competing workers converge with one logical merge',async()=>{const f=await fixture(11,true);for(let i=0;i<10;i++){const r=await Promise.all([f.step(),f.step()]);if(r.includes('PRESERVATION_MERGE_COMPLETE'))break;}assert.equal((await f.ref.get()).get('phase'),'PRESERVATION_MERGE_COMPLETE');assert.equal((await f.target.collection('shoppingItems').doc('keep').get()).get('quantity'),12800);assert.equal((await f.state.get()).get('blocks'),2);await f.boundary();});
test('5C2B forced transaction retry rereads authority and commits one block',async()=>{const f=await fixture(11,true);await f.step();let attempts=0;const wrapped=wrap(cb=>db.runTransaction(async tx=>{const value=await cb(tx);if(++attempts===1)throw Object.assign(new Error('retry'),{code:10});return value;}));await new DissolutionMergeStore(wrapped,clock).step({uid:'owner'},f.hid);assert.equal(attempts,2);assert.equal((await f.state.get()).get('blocks'),1);assert.equal((await f.target.collection('shoppingItems').doc('keep').get()).get('quantity'),12500);await f.finish();assert.equal((await f.target.collection('shoppingItems').doc('keep').get()).get('quantity'),12800);await f.boundary();});
for(const kind of ['snapshot','journal','receipt','cursor','sourceFence','targetFence','targetSequence'])test(`5C2B corrupt ${kind} parks OPERATOR without replay`,async()=>{
 const f=await fixture(11,true);await f.step();await f.step();const j=f.journals.doc(preservationPageId(f.o,0));
 if(kind==='snapshot'){const page=f.ref.collection('shoppingPreservation').doc(preservationPageId(f.o,1)),v=(await page.get()).data()!;v.entries[0].addPayload.quantity=999;await page.set(v);}
 if(kind==='journal')await j.update({hash:'a'.repeat(64)});
 if(kind==='receipt'){const v=(await j.get()).data()!;v.results[0].itemId='wrong';await j.set(v);}
 if(kind==='cursor')await f.state.update({offset:5});
 if(kind==='sourceFence')await f.source.update({operationId:'foreign'});
 if(kind==='targetFence')await f.target.update({operationId:'foreign'});
 if(kind==='targetSequence')await f.target.update({shoppingRevision:999});
 let r='';for(let i=0;i<8&&r!=='OPERATOR';i++)r=await f.step();assert.equal(r,'OPERATOR');const before=await list(f.target.collection('shoppingItems'));assert.equal(await f.step(),'OPERATOR');assert.deepEqual(await list(f.target.collection('shoppingItems')),before);assert.equal((await f.source.collection('shoppingItems').get()).size,11);assert.equal((await db.doc('familyMemberships/member').get()).get('state'),'ACTIVE');
});
test('5C2B guards retained, Pro loss cannot cancel, pending JOIN remains blocked',async()=>{const f=await fixture(11,true,true);await f.step();await f.step();const exits=new MemberLeaveStore(db,clock);await assert.rejects(exits.leave({uid:'member'},'b'.repeat(64)),/IN_PROGRESS/);await assert.rejects(exits.remove({uid:'owner'},'member','b'.repeat(64)),/IN_PROGRESS|INTEGRITY_REQUIRES_OPERATOR/);await assert.rejects(f.prepare.prepare({uid:'owner'},f.hid),/IN_PROGRESS|INTEGRITY_REQUIRES_OPERATOR/);for(const uid of ['member','owner'])await assert.rejects(new LifecycleStore(db,clock).beginDeletion(uid),/JOIN_COMMITTED_IN_PROGRESS/);assert.equal(await f.join.resume(f.reservation),'IN_PROGRESS');await db.doc('users/owner/entitlementGrants/pro').delete();await f.finish();await f.boundary();});
test('5C2B old and new private mutations remain blocked throughout completion',async()=>{const f=await fixture(1);await f.finish();assert.equal(await f.shopping.process('owner',f.privateId),'REJECTED_CONTEXT_CHANGED');await assert.rejects(f.shopping.ensureContext({uid:'owner'}),/REJECTED_UNAUTHORIZED|REJECTED_CONTEXT_CHANGED/);await f.boundary();});
test('5C2B 25-item cost sanity uses three real S1D blocks',async()=>{const f=await fixture(25);const meter=new FirestoreMeter(db,f.target.id),store=new DissolutionMergeStore(meter.db,clock);const m=await meter.measure(async()=>{for(let i=0;i<15;i++)if(await store.step({uid:'owner'},f.hid)==='PRESERVATION_MERGE_COMPLETE')break;});assert.equal((await f.state.get()).get('blocks'),3);assert.equal(m.counts.transactionRetries,0);assert.equal((await f.ref.get()).get('phase'),'PRESERVATION_MERGE_COMPLETE');console.log('5C2B_COST '+JSON.stringify({R:m.readEquivalent,counts:m.counts,blocks:3,children:25}));await f.boundary();});
test('5C2B malformed identity and premature state do not start a merge',async()=>{const f=await fixture();await assert.rejects(f.store.step({uid:'member'},f.hid),/NOT_FOUND/);await f.ref.update({phase:'VERIFY_SHOPPING'});await assert.rejects(f.step(),/INVALID_ARGUMENT/);assert.equal((await f.state.get()).exists,false);});

test('5C2B legacy target keeps S1D single-child fallback and durable partial page',async()=>{const f=await fixture(11,true,false,false,true);await f.step();await f.step();assert.equal((await f.state.get()).get('offset'),1);await f.finish();assert.equal((await f.state.get()).get('blocks'),11);assert.equal((await f.target.collection('shoppingItems').doc('keep').get()).get('quantity'),12800);assert.equal((await f.target.collection('shoppingItems').doc('keep').get()).get('custom'),'legacy');await f.boundary();});

test('5C2B create then merge three equivalent deltas yields 2800 ml once',async()=>{const f=await fixture(3,true,false,true);await f.finish();const rows=(await f.target.collection('shoppingItems').where('name','==','milk').get()).docs;assert.equal(rows.length,1);assert.equal(rows[0]!.get('quantity'),2800);const results=(await f.journals.get()).docs.flatMap(d=>d.get('results'));assert.deepEqual(results.map((r:any)=>r.created),[true,false,false]);await f.boundary();});
