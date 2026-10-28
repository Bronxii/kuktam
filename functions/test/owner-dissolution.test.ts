import {after,beforeEach,test} from 'node:test';
import assert from 'node:assert/strict';
import {initializeApp,deleteApp} from 'firebase-admin/app';
import {getFirestore,Timestamp,Firestore} from 'firebase-admin/firestore';
import {requireLocalEmulator} from './emulator-guard';
import {grant,now} from './fixtures';
import {OwnerProLossStore} from '../src/households/owner-pro-loss';
import {HouseholdStore,privateHouseholdId} from '../src/households/household-store';
import {DissolutionPreparationStore,dissolutionId} from '../src/households/dissolution-preparation';
import {FamilyInviteStore} from '../src/households/family-invites';
import {FamilyJoinStore} from '../src/households/family-join';
import {JoinTransferStore} from '../src/households/join-transfer';
import {MemberLeaveStore} from '../src/households/member-leave';
import {LifecycleStore} from '../src/billing/lifecycle-store';
requireLocalEmulator(process.env);
const app=initializeApp({projectId:'demo-kuktam-local'},'owner-dissolution'),db=getFirestore(app);
beforeEach(async()=>{assert.ok((await fetch('http://127.0.0.1:8088/emulator/v1/projects/demo-kuktam-local/databases/(default)/documents',{method:'DELETE'})).ok);});
after(()=>deleteApp(app));
async function fixture(count=2){
 let ms=now.toMillis()+1000;const clock=()=>Timestamp.fromMillis(ms),advance=()=>{ms+=300001;};
 const uids=['owner',...Array.from({length:count-1},(_,i)=>`member${i}`)],hid='family-pro-loss',id=dissolutionId('owner',hid),source=db.doc(`households/${hid}`),target=db.doc(`households/${privateHouseholdId('owner')}`);
 for(const uid of uids)await new HouseholdStore(db).ensure({uid});
 await source.set({schemaVersion:2,kind:'family',state:'ACTIVE',operationId:null,ownerUid:'owner',createdAt:now});
 for(const uid of uids){await source.collection('members').doc(uid).set({role:uid==='owner'?'owner':'member'});await db.doc(`familyMemberships/${uid}`).set({householdId:hid,role:uid==='owner'?'owner':'member',state:'ACTIVE',operationId:null});await db.doc(`users/${uid}`).update({activeHouseholdId:hid,familyHouseholdId:hid});await db.doc(`households/${privateHouseholdId(uid)}/shoppingItems/keep`).set({name:uid==='owner'?'milk':'privateKeep',quantity:uid==='owner'?1000:7,unit:uid==='owner'?'ml':'db',revision:1});}
 await source.collection('shoppingItems').doc('milk1').set({name:'Milk',quantity:300,unit:'ml',revision:1});await source.collection('shoppingItems').doc('milk2').set({name:'Milk',quantity:2,unit:'l',revision:2});
 await db.doc(`familyJoinCapacity/${hid}`).set({schemaVersion:2,operationIds:[],structuralOperationId:null});await db.doc(`familyInviteSlots/${hid}`).set({schemaVersion:1,inviteIds:[]});
 await db.doc('familyRuntime/config').set({inviteCreationEnabled:true,joinReservationEnabled:true});await db.doc('shoppingRuntime/config').set({enabled:true});await db.doc('users/owner/entitlementGrants/pro').set(grant());
 const store=new OwnerProLossStore(db,clock),ref=db.doc(`familyOperations/${id}`),intent=db.doc(`familyProLoss/${id}`),lose=()=>db.doc('users/owner/entitlementGrants/pro').delete();
 const finish=async()=>{for(let n=0;n<60;n++){advance();const result=await store.step(id);assert.notEqual(result,'OPERATOR');if(result==='DONE')return;}throw new Error('stuck');};
 const done=async(expected=3300)=>{assert.equal((await source.get()).get('state'),'DISSOLVED');assert.equal((await source.collection('shoppingItems').get()).size,0);assert.equal((await source.collection('members').get()).size,0);assert.equal((await ref.get()).get('status'),'DONE');assert.equal((await intent.get()).get('status'),'DONE');assert.equal((await intent.get()).get('nextAt'),undefined);assert.equal((await db.doc(`familyJoinCapacity/${hid}`).get()).get('structuralOperationId'),null);const milk=(await target.collection('shoppingItems').get()).docs;assert.equal(milk.length,1);assert.equal(milk[0]!.get('quantity'),expected);for(const uid of uids){assert.equal((await db.doc(`familyMemberships/${uid}`).get()).exists,false);assert.equal((await db.doc(`users/${uid}`).get()).get('activeHouseholdId'),privateHouseholdId(uid));if(uid!=='owner')assert.equal((await db.doc(`households/${privateHouseholdId(uid)}/shoppingItems/keep`).get()).get('quantity'),7);}};
 return {uids,hid,id,source,target,clock,advance,store,ref,intent,lose,finish,done};
}
async function joining(f:Awaited<ReturnType<typeof fixture>>,committed:boolean,active=false){
 await new HouseholdStore(db).ensure({uid:'guest'});await db.doc(`households/${privateHouseholdId('guest')}/shoppingItems/milk`).set({name:'Milk',quantity:200,unit:'ml'});
 const invite=await new FamilyInviteStore(db,{resolve:async()=>new Map()},f.clock).create({uid:'owner'}),join=new FamilyJoinStore(db,f.clock),jid=await join.reserve({uid:'guest'},invite.token,'ADD'),ref=db.doc(`familyOperations/${jid}`);
 await join.resume(jid);await new JoinTransferStore(db,f.clock).prepare({uid:'guest'},jid,invite.inviteId);
 if(committed){for(let i=0;i<15&&(await ref.get()).get('phase')!=='COMMITTED_TRANSFER';i++){f.advance();await join.resume(jid);}assert.equal((await ref.get()).get('phase'),'COMMITTED_TRANSFER');}
 if(active){for(let i=0;i<15&&(await ref.get()).get('phase')!=='ACTIVE';i++){f.advance();await join.resume(jid);}assert.equal((await ref.get()).get('phase'),'ACTIVE');}
 return {invite,join,jid,ref};
}

import {ownerDissolutionHandler} from '../src/households/owner-dissolution-handler';
import {OwnerAccountDeletionStore} from '../src/households/owner-account-deletion';
const reader=(f:Awaited<ReturnType<typeof fixture>>)=>new FamilyInviteStore(db,{resolve:async()=>new Map()},f.clock);
const progress=async(f:Awaited<ReturnType<typeof fixture>>,uid='owner')=>assert.rejects(reader(f).state({uid}),e=>e instanceof Error&&e.message==='IN_PROGRESS');
for(const count of [1,3,8])test(`7E0 manual owner ${count} participants server sweep completes`,async()=>{
 const f=await fixture(count),result=await f.store.startOwner('owner');assert.equal(result.operationId,f.id);assert.equal(result.outcome,'IN_PROGRESS');assert.equal((await f.intent.get()).get('reason'),'OWNER_REQUEST');
 await progress(f);for(const uid of f.uids)await progress(f,uid);
 // ONLY the existing scheduled maintenance path runs phases after start.
 for(let n=0;n<60&&(await f.ref.get()).get('status')!=='DONE';n++){f.advance();await f.store.sweep();if((await db.doc('familyMemberships/owner').get()).exists)await progress(f);}
 await f.done();for(const uid of f.uids)assert.equal((await reader(f).state({uid})).familyActive,false);
});
test('7E0 auth and empty request reject arbitrary Family target before store access',async()=>{
 let calls=0;const handler=ownerDissolutionHandler(()=>({startOwner:async()=>{calls++;return {schemaVersion:1,operationId:'unused',outcome:'IN_PROGRESS' as const};}}));
 await assert.rejects(handler({data:{}}),/Authentication required/);
 for(const data of [null,[],{householdId:'another'},{operationId:'other'},{phase:'DONE'}])await assert.rejects(handler({auth:{uid:'owner'},data}),/INVALID_ARGUMENT/);
 assert.equal(calls,0);assert.equal((await handler({auth:{uid:'owner'},data:{}})).outcome,'IN_PROGRESS');assert.equal(calls,1);
 const root=await import('../src/index');assert.equal((root.startFamilyDissolution as any).__endpoint.platform,'gcfv2');
});
test('7E0 active member private user and historical owner cannot start',async()=>{
 const f=await fixture();await assert.rejects(f.store.startOwner('member0'),/NOT_OWNER/);await new HouseholdStore(db).ensure({uid:'private'});await assert.rejects(f.store.startOwner('private'),/NOT_OWNER/);
 assert.equal((await f.ref.get()).exists,false);await f.store.startOwner('owner');await f.finish();await assert.rejects(f.store.startOwner('owner'),/NOT_OWNER/);
});
test('7E0 duplicate competing starts and lost ACK reuse one operation through fenced phases',async()=>{
 const f=await fixture(1);await f.store.startOwner('owner');const original=(await f.ref.get()).get('createdAt');await progress(f);
 const results=await Promise.allSettled([f.store.startOwner('owner'),f.store.startOwner('owner')]);assert.ok(results.some(r=>r.status==='fulfilled'));
 await progress(f);assert.equal((await db.collection('familyOperations').where('kind','==','FAMILY_DISSOLUTION').get()).size,1);
 assert.ok((await f.ref.get()).get('createdAt').isEqual(original));await f.store.startOwner('owner');await f.finish();await f.done();
});
test('7E0 existing PREPARED and mid-phase reused without replacing provenance',async()=>{
 const f=await fixture(1);await new DissolutionPreparationStore(db,f.clock).prepare({uid:'owner'},f.hid);await progress(f);const created=(await f.ref.get()).get('createdAt');
 await f.store.startOwner('owner');await progress(f);await f.store.startOwner('owner');assert.ok((await f.ref.get()).get('createdAt').isEqual(created));await f.finish();await f.done();
});
test('7E0 Pro-loss dissolution reused and progress safe for owner and member',async()=>{
 const f=await fixture();await f.lose();await f.store.observe('owner');await progress(f);await f.store.step(f.id);await progress(f,'member0');
 await f.store.startOwner('owner');assert.equal((await f.intent.get()).get('reason'),'OWNER_PRO_LOSS');await f.finish();await f.done();
});
test('7E0 pending Pro-loss plus restored Pro manual request still completes preserving original reason',async()=>{
 const f=await fixture(1);await f.lose();await f.store.observe('owner');await db.doc('users/owner/entitlementGrants/pro').set(grant());await f.store.startOwner('owner');
 assert.equal((await f.intent.get()).get('reason'),'OWNER_PRO_LOSS');assert.ok((await f.intent.get()).get('ownerRequestedAt') instanceof Timestamp);await f.finish();await f.done();
});
test('7E0 account deletion dissolution reused without changing deletion intent provenance',async()=>{
 const f=await fixture(1),deletion=new OwnerAccountDeletionStore(db,f.clock);await deletion.admit('owner');await progress(f);await deletion.step('owner');await progress(f);
 const audit=await f.ref.collection('lifecycleAdmission').doc('state').get();await f.store.startOwner('owner');await f.finish();await f.done();
 assert.deepEqual((await audit.ref.get()).data(),audit.data());assert.equal((await db.doc('familyOwnerDeletions/owner').get()).get('reason'),'OWNER_ACCOUNT_DELETION');
});
test('7E0 committed JOIN forward completes before manual dissolution snapshot',async()=>{
 const f=await fixture(1),j=await joining(f,true);await f.store.startOwner('owner');await progress(f);assert.equal((await f.ref.get()).exists,false);
 for(let n=0;n<20&&(await j.ref.get()).get('phase')!=='ACTIVE';n++){f.advance();await f.store.sweep();}
 assert.equal((await j.ref.get()).get('phase'),'ACTIVE');assert.equal((await j.ref.get()).get('status'),'DONE');
 await f.finish();await f.done(3500);assert.ok((await f.ref.get()).get('participants').some((p:any)=>p.uid==='guest'));assert.equal((await db.doc('users/guest').get()).get('activeHouseholdId'),privateHouseholdId('guest'));
});
test('7E0 precommit JOIN reservation finalized through existing engine',async()=>{
 const f=await fixture(1),j=await joining(f,false);await f.store.startOwner('owner');await f.finish();await f.done();assert.equal((await j.ref.get()).get('status'),'ABORTED');assert.equal((await db.doc(`familyInvites/${j.invite.inviteId}`).get()).get('status'),'REVOKED');
});
for(const removal of [false,true])test(`7E0 manual dissolution vs ${removal?'remove':'leave'} snapshots stable topology`,async()=>{
 const f=await fixture(1),j=await joining(f,true,true),exit=new MemberLeaveStore(db,f.clock);
 const results=await Promise.allSettled([f.store.startOwner('owner'),removal?exit.remove({uid:'owner'},'guest',j.invite.inviteId):exit.leave({uid:'guest'},j.invite.inviteId)]);
 assert.equal(results[0]!.status,'fulfilled');const guest=(await db.doc('familyMemberships/guest').get()).exists;assert.equal((await f.ref.get()).get('participants').some((p:any)=>p.uid==='guest'),guest);await f.finish();await f.done(3500);
});
test('7E0 normal owner member private reads unchanged then reopen observes prepared',async()=>{
 const f=await fixture(1);assert.equal((await reader(f).state({uid:'owner'}) as any).role,'owner');const j=await joining(f,true,true);assert.equal((await reader(f).state({uid:'guest'}) as any).role,'member');
 await new HouseholdStore(db).ensure({uid:'private'});assert.equal((await reader(f).state({uid:'private'})).familyActive,false);
 await new DissolutionPreparationStore(db,f.clock).prepare({uid:'owner'},f.hid);await progress(f);await progress(f,'guest');assert.equal((await db.doc(`familyInvites/${j.invite.inviteId}`).get()).get('status'),'USED');
});
test('7E0 corrupt lock never reports actionable owner',async()=>{
 const f=await fixture(1);await db.doc(`familyJoinCapacity/${f.hid}`).update({schemaVersion:3,structuralOperationId:f.id});await assert.rejects(reader(f).state({uid:'owner'}),/FAMILY_UNAVAILABLE/);
});

for(const boundary of ['intent','prepared'])test(`7E0 lost ACK after ${boundary} durable commit reads progress and retries same operation`,async()=>{
 const f=await fixture(1);let count=0;
 const wrapped=new Proxy(db,{get(t,k){if(k==='runTransaction')return async(cb:any,options:any)=>{const result=await db.runTransaction(cb,options);count++;if(count===(boundary==='intent'?1:2))throw new Error('lostAck');return result;};const v=(t as any)[k];return typeof v==='function'?v.bind(t):v;}});
 if(boundary==='intent')await assert.rejects(new OwnerProLossStore(wrapped,f.clock).startOwner('owner'),/lostAck/);
 else await new OwnerProLossStore(wrapped,f.clock).startOwner('owner'); // existing admission catches a committed transaction's lost ACK
 await progress(f);const before=await f.intent.get();assert.equal(before.get('reason'),'OWNER_REQUEST');
 await f.store.startOwner('owner');assert.ok((await f.intent.get()).get('createdAt').isEqual(before.get('createdAt')));await f.finish();await f.done();
});
test('7E0 failure before admission writes no intent and leaves owner actionable',async()=>{
 const f=await fixture(1);const wrapped=new Proxy(db,{get(t,k){if(k==='runTransaction')return (cb:any)=>db.runTransaction(async tx=>{await cb(tx);throw new Error('forcedFailure');});const v=(t as any)[k];return typeof v==='function'?v.bind(t):v;}});
 await assert.rejects(new OwnerProLossStore(wrapped,f.clock).startOwner('owner'),/forcedFailure/);assert.equal((await f.intent.get()).exists,false);assert.equal((await f.ref.get()).exists,false);assert.equal((await reader(f).state({uid:'owner'}) as any).role,'owner');
});
