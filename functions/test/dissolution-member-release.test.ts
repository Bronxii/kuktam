import {after,beforeEach,test} from 'node:test';
import assert from 'node:assert/strict';
import {initializeApp,deleteApp} from 'firebase-admin/app';
import {getFirestore,Timestamp,Firestore} from 'firebase-admin/firestore';
import {requireLocalEmulator} from './emulator-guard';
import {grant,now} from './fixtures';
import {HouseholdStore,privateHouseholdId} from '../src/households/household-store';
import {DissolutionPreparationStore,dissolutionId} from '../src/households/dissolution-preparation';
import {DissolutionPreservationStore,readPreservation} from '../src/households/dissolution-preservation';
import {DissolutionMergeStore} from '../src/households/dissolution-merge';
import {DissolutionSourceDispositionStore} from '../src/households/dissolution-source-disposition';
import {DissolutionMemberReleaseStore,participantReleaseId} from '../src/households/dissolution-member-release';
import {ShoppingMutationStore} from '../src/shopping/mutation-store';
import {newMutationId} from '../src/shopping/mutation-contract';
import {LifecycleStore} from '../src/billing/lifecycle-store';
import {MemberLeaveStore} from '../src/households/member-leave';
import {FamilyInviteStore} from '../src/households/family-invites';
import {FamilyJoinStore} from '../src/households/family-join';

requireLocalEmulator(process.env);
const app=initializeApp({projectId:'demo-kuktam-local'},'dissolution-member-release'),db=getFirestore(app),clock=()=>Timestamp.fromMillis(now.toMillis()+1000);
beforeEach(async()=>{assert.ok((await fetch('http://127.0.0.1:8088/emulator/v1/projects/demo-kuktam-local/databases/(default)/documents',{method:'DELETE'})).ok);});
after(()=>deleteApp(app));
const list=async(q:FirebaseFirestore.Query)=>(await q.get()).docs.map(d=>[d.id,d.data(),d.updateTime]);
const values=async(refs:FirebaseFirestore.DocumentReference[])=>(await db.getAll(...refs)).map(d=>[d.data(),d.updateTime]);
async function fixture(count=2,pending=false){
 const uids=['owner',...Array.from({length:count-1},(_,i)=>`member${i}`)],members=uids.slice(1),hid='family-release',source=db.doc(`households/${hid}`),target=db.doc(`households/${privateHouseholdId('owner')}`);
 for(const uid of uids)await new HouseholdStore(db).ensure({uid});
 await db.doc('shoppingRuntime/config').set({enabled:true});await db.doc('familyRuntime/config').set({inviteCreationEnabled:true,joinReservationEnabled:true});await db.doc('users/owner/entitlementGrants/pro').set(grant());
 await source.set({schemaVersion:2,kind:'family',state:'ACTIVE',ownerUid:'owner',operationId:null,createdAt:now});
 for(const uid of uids){await source.collection('members').doc(uid).set({role:uid==='owner'?'owner':'member'});await db.doc(`familyMemberships/${uid}`).set({householdId:hid,role:uid==='owner'?'owner':'member',state:'ACTIVE',operationId:null});await db.doc(`users/${uid}`).update({activeHouseholdId:hid,familyHouseholdId:hid});await db.doc(`households/${privateHouseholdId(uid)}/shoppingItems/keep`).set({name:'existing',quantity:13,unit:'db',revision:1,custom:'preserved'});}
 await db.doc(`familyJoinCapacity/${hid}`).set({schemaVersion:2,operationIds:[],structuralOperationId:null});await db.doc(`familyInviteSlots/${hid}`).set({schemaVersion:1,inviteIds:[]});
 const shopping=new ShoppingMutationStore(db,clock),oldIds=new Map<string,string>();
 for(const uid of members){const c=await shopping.ensureContext({uid}),mutationId=newMutationId(c.epoch);await shopping.submit({uid},{schemaVersion:1,actorUid:uid,...c,mutationId,kind:'ADD',payloadJson:JSON.stringify({type:'ADD',name:'late',quantity:1,unit:'db'}),submittedAt:clock()});oldIds.set(uid,mutationId);}
 await source.collection('shoppingItems').doc('preserve').set({name:'milk',quantity:300,unit:'ml',revision:1});
 const join=new FamilyJoinStore(db,clock);let reservation:string|undefined;
 if(pending){await new HouseholdStore(db).ensure({uid:'pending'});const inv=await new FamilyInviteStore(db,{resolve:async()=>new Map()},clock).create({uid:'owner'});reservation=await join.reserve({uid:'pending'},inv.token,'ADD');}
 const prepare=new DissolutionPreparationStore(db,clock);await prepare.prepare({uid:'owner'},hid);
 const id=dissolutionId('owner',hid),ref=db.doc(`familyOperations/${id}`),pre=new DissolutionPreservationStore(db,clock),merge=new DissolutionMergeStore(db,clock),cleanup=new DissolutionSourceDispositionStore(db,clock);
 for(const [engine,phase] of [[pre,'PRESERVATION_COMMITTED'],[merge,'PRESERVATION_MERGE_COMPLETE'],[cleanup,'PRESERVATION_SOURCE_CLEANED']] as const){let done=false;for(let i=0;i<20;i++)if(await engine.step({uid:'owner'},hid)===phase){done=true;break;}assert.ok(done);}
 const o=readPreservation((await ref.get()).data(),id),store=new DissolutionMemberReleaseStore(db,clock),state=ref.collection('participantRelease').doc('state'),journal=ref.collection('participantReleaseJournal');
 const protectedRefs=[source,target,db.doc('users/owner'),db.doc('familyMemberships/owner'),source.collection('members').doc('owner'),db.doc(`familyJoinCapacity/${hid}`),db.doc(`familyInviteSlots/${hid}`),ref.collection('preservationMerge').doc('state'),ref.collection('preservationSourceCleanup').doc('state')];
 const before=await values(protectedRefs),targetBefore=await list(target.collection('shoppingItems')),privateBefore=new Map<string,unknown>();for(const uid of members)privateBefore.set(uid,await list(db.collection(`households/${privateHouseholdId(uid)}/shoppingItems`)));
 const step=()=>store.step({uid:'owner'},hid),finish=async()=>{for(let i=0;i<count+3;i++){const r=await step();if(r==='NON_OWNER_RELEASE_COMPLETE')return;assert.notEqual(r,'OPERATOR');}throw new Error('stuck');};
 const boundary=async()=>{assert.deepEqual(await values(protectedRefs),before);assert.deepEqual(await list(target.collection('shoppingItems')),targetBefore);assert.equal((await source.collection('shoppingItems').get()).size,0);assert.deepEqual((await ref.get()).get('participants'),o.participants);for(const uid of members)assert.deepEqual(await list(db.collection(`households/${privateHouseholdId(uid)}/shoppingItems`)),privateBefore.get(uid));};
 const done=async()=>{assert.equal((await ref.get()).get('phase'),'NON_OWNER_RELEASE_COMPLETE');assert.equal((await state.get()).get('cursor'),members.length);assert.equal((await journal.get()).size,members.length);assert.equal((await source.collection('members').get()).size,1);for(const uid of members){assert.equal((await db.doc(`familyMemberships/${uid}`).get()).exists,false);assert.equal((await db.doc(`users/${uid}`).get()).get('activeHouseholdId'),privateHouseholdId(uid));const p=o.participants.find(p=>p.uid===uid)!,r=await journal.doc(participantReleaseId(o,p)).get();assert.equal(r.get('epoch'),(await db.doc(`households/${p.privateHouseholdId}`).get()).get('shoppingEpoch'));}await boundary();};
 return {uids,members,hid,id,source,target,ref,o,store,state,journal,step,finish,boundary,done,shopping,oldIds,join,reservation,prepare};
}
for(const n of [1,2,4,8])test(`5C4A ${n} participants release only nonowners with exact capacity and retained boundary`,async()=>{const f=await fixture(n);await f.finish();await f.done();const refs=[f.ref,f.state,...f.members.map(u=>db.doc(`households/${privateHouseholdId(u)}`))],before=await values(refs);assert.equal(await f.step(),'NON_OWNER_RELEASE_COMPLETE');assert.deepEqual(await values(refs),before);});
test('5C4A interruption resumes without replaying released epoch',async()=>{const f=await fixture(4);await f.step();const uid=f.members[0]!,home=db.doc(`households/${privateHouseholdId(uid)}`),before=await values([home]);await new DissolutionMemberReleaseStore(db,clock).step({uid:'owner'},f.hid);await f.finish();await f.done();assert.deepEqual(await values([home]),before);});
function wrap(run:(cb:any)=>Promise<any>){return new Proxy(db,{get(t,k){if(k==='runTransaction')return run;const v=(t as any)[k];return typeof v==='function'?v.bind(t):v;}}) as Firestore;}
test('5C4A lost ACK retains one receipt and one epoch',async()=>{const f=await fixture(2);await assert.rejects(new DissolutionMemberReleaseStore(wrap(async cb=>{await db.runTransaction(cb);throw new Error('lostAck');}),clock).step({uid:'owner'},f.hid),/lostAck/);const r=(await f.journal.get()).docs[0]!,home=db.doc(`households/${privateHouseholdId('member0')}`),before=await values([r.ref,home]);await f.finish();await f.done();assert.deepEqual(await values([r.ref,home]),before);});
test('5C4A competing workers release each member once',async()=>{const f=await fixture(4);for(let i=0;i<5;i++){const r=await Promise.all([f.step(),f.step()]);if(r.includes('NON_OWNER_RELEASE_COMPLETE'))break;}await f.done();});
test('5C4A forced transaction failure leaves full participant and cursor unchanged',async()=>{const f=await fixture(2),refs=[f.ref,f.state,db.doc('familyMemberships/member0'),db.doc('users/member0'),f.source.collection('members').doc('member0'),db.doc(`households/${privateHouseholdId('member0')}`)],before=await values(refs);await assert.rejects(new DissolutionMemberReleaseStore(wrap(cb=>db.runTransaction(async tx=>{await cb(tx);throw Object.assign(new Error('forced'),{code:10});},{maxAttempts:1})),clock).step({uid:'owner'},f.hid),/forced/);assert.deepEqual(await values(refs),before);assert.equal((await f.journal.get()).size,0);await f.boundary();await f.finish();await f.done();});
test('5C4A stale family rejected fresh shopping writes private without affecting preserved data',async()=>{const f=await fixture(2);await f.finish();await f.done();assert.equal(await f.shopping.process('member0',f.oldIds.get('member0')!),'REJECTED_CONTEXT_CHANGED');const c=await f.shopping.ensureContext({uid:'member0'});assert.equal(c.householdId,privateHouseholdId('member0'));const mutationId=newMutationId(c.epoch);await f.shopping.submit({uid:'member0'},{schemaVersion:1,actorUid:'member0',...c,mutationId,kind:'ADD',payloadJson:JSON.stringify({type:'ADD',name:'fresh',quantity:2,unit:'db'}),submittedAt:clock()});assert.equal(await f.shopping.process('member0',mutationId),'APPLIED');assert.equal((await db.collection(`households/${c.householdId}/shoppingItems`).get()).size,2);assert.equal((await f.source.collection('shoppingItems').get()).size,0);assert.equal(await f.step(),'NON_OWNER_RELEASE_COMPLETE');});
test('5C4A private deletion admission restored during progress owner remains guarded',async()=>{const f=await fixture(4),life=new LifecycleStore(db,clock);await f.step();await assert.rejects(life.beginDeletion('owner'),/JOIN_COMMITTED_IN_PROGRESS/);assert.equal((await life.beginDeletion('member0')).outcome,'deletionStarted');await f.finish();assert.equal(await f.step(),'NON_OWNER_RELEASE_COMPLETE');await f.boundary();await assert.rejects(life.beginDeletion('owner'),/JOIN_COMMITTED_IN_PROGRESS/);});
test('5C4A fresh private activity during release does not stall remaining members',async()=>{
 const f=await fixture(4),ownerBefore=await list(f.target.collection('shoppingItems'));await f.step();
 const c=await f.shopping.ensureContext({uid:'member0'}),mutationId=newMutationId(c.epoch);assert.equal(c.householdId,privateHouseholdId('member0'));
 await f.shopping.submit({uid:'member0'},{schemaVersion:1,actorUid:'member0',...c,mutationId,kind:'ADD',payloadJson:JSON.stringify({type:'ADD',name:'independent',quantity:1,unit:'db'}),submittedAt:clock()});assert.equal(await f.shopping.process('member0',mutationId),'APPLIED');
 const privateBefore=await list(db.collection(`households/${c.householdId}/shoppingItems`));await f.finish();assert.deepEqual(await list(db.collection(`households/${c.householdId}/shoppingItems`)),privateBefore);assert.deepEqual(await list(f.target.collection('shoppingItems')),ownerBefore);assert.equal((await f.source.collection('members').get()).size,1);
});
for(const kind of ['activePointer','missingFallback','wrongFallbackOwner','membershipVersion','indexMismatch','lock','completion','snapshot','account'])test(`5C4A integrity ${kind} cannot partially release`,async()=>{const f=await fixture(2),home=db.doc(`households/${privateHouseholdId('member0')}`);
 if(kind==='activePointer')await db.doc('users/member0').update({activeHouseholdId:'wrong'});
 if(kind==='missingFallback')await home.delete();
 if(kind==='wrongFallbackOwner')await home.update({ownerUid:'wrong'});
 if(kind==='membershipVersion')await f.source.collection('members').doc('member0').update({extra:'changed'});
 if(kind==='indexMismatch')await db.doc('familyMemberships/member0').update({householdId:'wrong'});
 if(kind==='lock')await db.doc(`familyJoinCapacity/${f.hid}`).update({structuralOperationId:'wrong'});
 if(kind==='completion')await f.ref.collection('preservationSourceCleanup').doc('state').update({count:99});
 if(kind==='snapshot')await f.ref.update({snapshotHash:'a'.repeat(64)});
 if(kind==='account')await db.doc('accountLifecycle/member0').update({state:'garbage'});
 const refs=[home,db.doc('users/member0'),db.doc('familyMemberships/member0'),f.source.collection('members').doc('member0')],before=await values(refs);assert.equal(await f.step(),'OPERATOR');assert.deepEqual(await values(refs),before);assert.equal((await f.journal.get()).size,0);assert.equal(await f.step(),'OPERATOR');
});
test('5C4A corrupt release evidence stops next member without replay',async()=>{const f=await fixture(4);await f.step();const r=(await f.journal.get()).docs[0]!;await r.ref.update({epoch:'wrong'});assert.equal(await f.step(),'OPERATOR');assert.equal((await db.doc('familyMemberships/member1').get()).get('state'),'ACTIVE');assert.equal((await f.journal.get()).size,1);await f.boundary();});
test('5C4A structural guards and pending reservation retained despite Pro loss',async()=>{const f=await fixture(4,true);await db.doc('users/owner/entitlementGrants/pro').delete();await f.step();const exits=new MemberLeaveStore(db,clock);await assert.rejects(exits.leave({uid:'member1'},'a'.repeat(64)),/IN_PROGRESS/);await assert.rejects(exits.remove({uid:'owner'},'member1','a'.repeat(64)),/IN_PROGRESS|INTEGRITY_REQUIRES_OPERATOR/);assert.equal(await f.join.resume(f.reservation!),'IN_PROGRESS');await assert.rejects(f.prepare.prepare({uid:'owner'},f.hid),/IN_PROGRESS|INTEGRITY_REQUIRES_OPERATOR/);await f.finish();await f.done();assert.equal((await db.doc('familyMemberships/pending').get()).get('state'),'RESERVED');});
test('5C4A wrong actor and early phase cannot release',async()=>{const f=await fixture(2);await assert.rejects(f.store.step({uid:'member0'},f.hid),/NOT_FOUND/);await f.ref.update({phase:'PRESERVATION_MERGE_COMPLETE'});await assert.rejects(f.step(),/INVALID_ARGUMENT/);assert.equal((await f.journal.get()).size,0);await f.boundary();});
