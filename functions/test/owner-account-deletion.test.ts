import {OwnerAccountDeletionStore} from '../src/households/owner-account-deletion';
import {DissolutionLifecycleDriver} from '../src/households/dissolution-lifecycle-driver';
import {AccountDeletionService} from '../src/accounts/account-deletion';
import {DeletionGateway} from '../src/accounts/deletion-gateway';
import {FakeAuthDeletionApi} from './fake-auth-deletion-api';
import {FamilyCreateStore} from '../src/households/family-create';
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
const app=initializeApp({projectId:'demo-kuktam-local'},'owner-account-deletion'),db=getFirestore(app);
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
 const store=new OwnerAccountDeletionStore(db,clock),ref=db.doc(`familyOperations/${id}`),intent=db.doc('familyOwnerDeletions/owner'),lose=()=>db.doc('users/owner/entitlementGrants/pro').delete();
 const memberPrivate=await Promise.all(uids.filter(uid=>uid!=='owner').map(uid=>db.doc(`households/${privateHouseholdId(uid)}/shoppingItems/keep`).get()));
 const auth=new FakeAuthDeletionApi(),service=new AccountDeletionService(db,auth,clock);
 const safety=async()=>{assert.equal((await db.doc('accountLifecycle/owner').get()).get('state'),'ACTIVE');assert.equal((await db.doc('accountDeletions/owner').get()).exists,false);assert.equal(auth.calls,0);assert.equal(await service.finalizeContent({uid:'owner'}),'cleanupRetryRequired');assert.equal(auth.calls,0);};
 const finish=async()=>{for(let n=0;n<60;n++){advance();const result=await store.step('owner');await safety();assert.notEqual(result,'OPERATOR');if(result==='WAITING_HISTORICAL_AUDIT')return;}throw new Error('stuck');};
 const done=async(expected=3300)=>{for(const before of memberPrivate){const after=await before.ref.get();assert.deepEqual(after.data(),before.data());assert.ok(after.updateTime!.isEqual(before.updateTime!));}assert.equal((await source.get()).get('state'),'DISSOLVED');assert.equal((await source.collection('shoppingItems').get()).size,0);assert.equal((await source.collection('members').get()).size,0);assert.equal((await ref.get()).get('status'),'DONE');assert.equal((await intent.get()).get('phase'),'WAITING_HISTORICAL_AUDIT');assert.equal((await intent.get()).get('nextAt'),undefined);assert.equal((await db.doc(`familyJoinCapacity/${hid}`).get()).get('structuralOperationId'),null);const milk=(await target.collection('shoppingItems').get()).docs;assert.equal(milk.length,1);assert.equal(milk[0]!.get('quantity'),expected);for(const uid of uids){assert.equal((await db.doc(`familyMemberships/${uid}`).get()).exists,false);assert.equal((await db.doc(`users/${uid}`).get()).get('activeHouseholdId'),privateHouseholdId(uid));if(uid!=='owner')assert.equal((await db.doc(`households/${privateHouseholdId(uid)}/shoppingItems/keep`).get()).get('quantity'),7);}};
 return {uids,hid,id,source,target,clock,advance,store,ref,intent,lose,finish,done,safety,auth,service};
}
async function joining(f:Awaited<ReturnType<typeof fixture>>,committed:boolean,active=false){
 await new HouseholdStore(db).ensure({uid:'guest'});await db.doc(`households/${privateHouseholdId('guest')}/shoppingItems/milk`).set({name:'Milk',quantity:200,unit:'ml'});
 const invite=await new FamilyInviteStore(db,{resolve:async()=>new Map()},f.clock).create({uid:'owner'}),join=new FamilyJoinStore(db,f.clock),jid=await join.reserve({uid:'guest'},invite.token,'ADD'),ref=db.doc(`familyOperations/${jid}`);
 await join.resume(jid);await new JoinTransferStore(db,f.clock).prepare({uid:'guest'},jid,invite.inviteId);
 if(committed){for(let i=0;i<15&&(await ref.get()).get('phase')!=='COMMITTED_TRANSFER';i++){f.advance();await join.resume(jid);}assert.equal((await ref.get()).get('phase'),'COMMITTED_TRANSFER');}
 if(active){for(let i=0;i<15&&(await ref.get()).get('phase')!=='ACTIVE';i++){f.advance();await join.resume(jid);}assert.equal((await ref.get()).get('phase'),'ACTIVE');}
 return {invite,join,jid,ref};
}
for(const count of [1,3,8])test(`6B2 owner deletion ${count} participants reaches historical handoff without account deletion`,async()=>{
 const f=await fixture(count),gateway=new DeletionGateway(f.service,()=>f.clock().toMillis());
 await assert.rejects(gateway.begin({uid:'owner',authTimeSeconds:0},{}),/recentAuthenticationRequired/);
 await assert.rejects(gateway.begin({uid:'owner',authTimeSeconds:f.clock().seconds},{uid:'other'}),/invalidArgument/);
 assert.equal((await f.intent.get()).exists,false);
 const result=await gateway.begin({uid:'owner',authTimeSeconds:f.clock().seconds},{});assert.equal(result.outcome,'familyDissolutionPending');
 assert.equal((await f.ref.collection('lifecycleAdmission').doc('state').get()).get('reason'),'OWNER_ACCOUNT_DELETION');
 await f.safety();await f.finish();await f.done();await f.safety();
 await assert.rejects(new LifecycleStore(db,f.clock).beginDeletion('owner'),/FAMILY_LIFECYCLE_NOT_READY/);
 assert.equal((await f.intent.get()).get('completionEvidence'),f.ref.collection('finalization').doc('state').path);
});
test('6B2 duplicate request and terminal reentry preserve exact receipts epochs and audit',async()=>{
 const f=await fixture();await Promise.all([f.store.admit('owner'),f.store.admit('owner')]);await f.finish();
 const refs=[f.source,f.target,f.ref,f.intent,db.doc(`familyJoinCapacity/${f.hid}`),f.ref.collection('finalization').doc('state')];const before=await db.getAll(...refs);
 for(let n=0;n<3;n++){const r=await f.service.beginAccountDeletion({uid:'owner'});assert.equal(r.outcome,'waitingHistoricalAudit');assert.equal(r.operationId,f.id);}
 const after=await db.getAll(...refs);after.forEach((d,n)=>assert.ok(d.updateTime!.isEqual(before[n]!.updateTime!)));
 assert.equal((await db.collection('familyOwnerDeletions').get()).size,1);assert.equal((await db.collection('familyOperations').where('kind','==','FAMILY_DISSOLUTION').get()).size,1);await f.done();await f.safety();
});
test('6B2 existing owner-requested dissolution reused after preservation fence',async()=>{
 const f=await fixture();await new DissolutionPreparationStore(db,f.clock).prepare({uid:'owner'},f.hid);await new DissolutionLifecycleDriver(db,f.clock).step('owner',f.hid);
 await f.store.admit('owner');await f.finish();await f.done();assert.equal((await f.ref.collection('lifecycleAdmission').get()).size,0);await f.safety();
});
test('6B2 Pro-loss and owner deletion race reference one dissolution',async()=>{
 const f=await fixture(3),loss=new OwnerProLossStore(db,f.clock);await f.lose();await Promise.all([loss.observe('owner'),f.store.admit('owner')]);
 for(let n=0;n<50;n++){f.advance();await Promise.all([loss.step(f.id),f.store.step('owner')]);await f.safety();if((await f.intent.get()).get('phase')==='WAITING_HISTORICAL_AUDIT'&&(await db.doc(`familyProLoss/${f.id}`).get()).get('status')==='DONE')break;}
 await f.done();assert.equal((await db.doc(`familyProLoss/${f.id}`).get()).get('operationId'),f.id);assert.equal((await db.collection('familyOperations').where('kind','==','FAMILY_DISSOLUTION').get()).size,1);
});
test('6B2 existing Pro-loss dissolution reused and Pro restoration cannot cancel deletion',async()=>{
 const f=await fixture(1),loss=new OwnerProLossStore(db,f.clock);await f.lose();await loss.observe('owner');await loss.step(f.id);await f.store.admit('owner');await db.doc('users/owner/entitlementGrants/pro').set(grant());await f.finish();await f.done();assert.equal((await f.ref.collection('lifecycleAdmission').doc('state').get()).get('reason'),'OWNER_PRO_LOSS');await loss.step(f.id);assert.equal((await db.doc(`familyProLoss/${f.id}`).get()).get('status'),'DONE');
});
for(const removal of [false,true])test(`6B2 ${removal?'owner-remove':'self-leave'} race uses stable winning topology`,async()=>{
 const f=await fixture(1),j=await joining(f,true,true);await f.store.admit('owner');const exit=new MemberLeaveStore(db,f.clock);
 const outcomes=await Promise.allSettled([f.store.step('owner'),removal?exit.remove({uid:'owner'},'guest',j.invite.inviteId):exit.leave({uid:'guest'},j.invite.inviteId)]);
 assert.equal(outcomes[0]!.status,'fulfilled');const active=(await db.doc('familyMemberships/guest').get()).exists;
 assert.equal((await f.ref.get()).get('participants').some((p:any)=>p.uid==='guest'),active);
 if(outcomes[1]!.status==='rejected')assert.match(String(outcomes[1]!.reason),/IN_PROGRESS/);
 await f.finish();await f.done(3500);await f.safety();
});
test('6B2 committed JOIN forward-completes before dissolution includes new member',async()=>{
 const f=await fixture(1),j=await joining(f,true);await f.store.admit('owner');
 for(let n=0;n<15&&(await j.ref.get()).get('phase')!=='ACTIVE';n++){f.advance();await f.store.step('owner');assert.equal((await f.ref.get()).exists,false);assert.notEqual((await j.ref.get()).get('status'),'ABORTED');await f.safety();}
 assert.equal((await j.ref.get()).get('phase'),'ACTIVE');assert.equal((await j.ref.get()).get('status'),'DONE');
 await f.store.step('owner');assert.deepEqual((await f.ref.get()).get('participants').map((p:any)=>p.uid),['guest','owner']);await f.finish();await f.done(3500);
 assert.equal((await db.doc('users/guest').get()).get('activeHouseholdId'),privateHouseholdId('guest'));assert.equal((await db.doc(`familyInvites/${j.invite.inviteId}`).get()).get('status'),'USED');
});
test('6B2 precommit JOIN aborts through Phase5 pending invite reservation finalization',async()=>{
 const f=await fixture(1),j=await joining(f,false),pending=await new FamilyInviteStore(db,{resolve:async()=>new Map()},f.clock).create({uid:'owner'});
 await f.store.admit('owner');await f.finish();await f.done();assert.equal((await j.ref.get()).get('status'),'ABORTED');assert.equal((await db.doc(`familyInvites/${j.invite.inviteId}`).get()).get('status'),'REVOKED');assert.equal((await db.doc(`familyInvites/${pending.inviteId}`).get()).get('status'),'REVOKED');assert.equal((await db.doc('familyMemberships/guest').get()).exists,false);assert.equal((await db.doc(`households/${privateHouseholdId('guest')}/shoppingItems/milk`).get()).get('quantity'),200);
});
function wrap(run:(cb:any)=>Promise<any>){return new Proxy(db,{get(t,k){if(k==='runTransaction')return run;const v=(t as any)[k];return typeof v==='function'?v.bind(t):v;}}) as Firestore;}
test('6B2 lost ACK at intent creation recovers one durable request',async()=>{
 const f=await fixture(1),broken=new OwnerAccountDeletionStore(wrap(async cb=>{await db.runTransaction(cb);throw new Error('lostAck');}),f.clock);
 await assert.rejects(broken.admit('owner'),/lostAck/);assert.equal((await f.intent.get()).get('phase'),'WAITING_DISSOLUTION');await f.store.admit('owner');await f.finish();await f.done();
});
test('6B2 lost ACK after dissolution admission recovers same operation',async()=>{
 const f=await fixture(1);await f.store.admit('owner');let lost=false;
 const broken=new OwnerAccountDeletionStore(wrap(async cb=>{const r=await db.runTransaction(cb);if(!lost&&(await f.ref.get()).exists){lost=true;throw new Error('lostAck');}return r;}),f.clock);
 // A durable admission is reconciled immediately even when its ACK is uncertain.
 assert.equal(await broken.step('owner'),'DISSOLUTION_IN_PROGRESS');assert.equal(lost,true);const created=(await f.ref.get()).get('createdAt');await f.finish();assert.ok((await f.ref.get()).get('createdAt').isEqual(created));await f.done();
});
for(const boundary of ['DONE','WAITING_HISTORICAL_AUDIT'])test(`6B2 lost ACK after ${boundary} resumes without replay`,async()=>{
 const f=await fixture(1);await f.store.admit('owner');for(let n=0;n<30&&(await f.ref.get()).get('phase')!=='NON_OWNER_RELEASE_COMPLETE';n++){f.advance();await f.store.step('owner');}
 assert.equal((await f.ref.get()).get('phase'),'NON_OWNER_RELEASE_COMPLETE');let lost=false;
 const broken=new OwnerAccountDeletionStore(wrap(async cb=>{const r=await db.runTransaction(cb);const value=boundary==='DONE'?(await f.ref.get()).get('phase'):(await f.intent.get()).get('phase');if(!lost&&value===boundary){lost=true;throw new Error('lostAck');}return r;}),f.clock);
 await assert.rejects(broken.step('owner'),/lostAck/);assert.equal(lost,true);const epoch=(await f.target.get()).get('shoppingEpoch');await f.store.step('owner');assert.equal((await f.target.get()).get('shoppingEpoch'),epoch);await f.done();await f.safety();
});
test('6B2 competing workers produce one logical dissolution and handoff',async()=>{
 const f=await fixture();await Promise.all([f.store.admit('owner'),f.store.admit('owner')]);
 for(let n=0;n<50&&(await f.intent.get()).get('phase')!=='WAITING_HISTORICAL_AUDIT';n++){f.advance();await Promise.all([f.store.step('owner'),f.store.step('owner')]);await f.safety();}await f.done();
});
test('6B2 failed admission transaction leaves no intent and ACTIVE owner',async()=>{
 const f=await fixture(),broken=new OwnerAccountDeletionStore(wrap(cb=>db.runTransaction(async tx=>{await cb(tx);throw new Error('forced');})),f.clock);
 await assert.rejects(broken.admit('owner'),/forced/);assert.equal((await f.intent.get()).exists,false);assert.equal((await f.ref.get()).exists,false);assert.equal((await db.doc('familyMemberships/owner').get()).get('state'),'ACTIVE');await f.safety();
});
test('6B2 failed dissolution start keeps intent retryable without lock or deletion',async()=>{
 const f=await fixture();await f.store.admit('owner');const broken=new OwnerAccountDeletionStore(wrap(cb=>db.runTransaction(async tx=>{await cb(tx);throw new Error('forced');})),f.clock);
 await assert.rejects(broken.step('owner'),/forced/);assert.equal((await f.ref.get()).exists,false);assert.equal((await db.doc(`familyJoinCapacity/${f.hid}`).get()).get('structuralOperationId'),null);assert.equal((await f.intent.get()).get('phase'),'WAITING_DISSOLUTION');await f.safety();await f.finish();await f.done();
});
test('6B2 durable queue resumes crash and terminal dissolution handoff',async()=>{
 const f=await fixture(1);await f.store.admit('owner');await f.store.sweep();assert.equal((await f.ref.get()).get('phase'),'PREPARED');
 const driver=new DissolutionLifecycleDriver(db,f.clock);for(let n=0;n<40&&(await f.ref.get()).get('phase')!=='DONE';n++){f.advance();await driver.step('owner',f.hid);await f.safety();}
 assert.equal((await f.intent.get()).get('phase'),'DISSOLUTION_IN_PROGRESS');f.advance();await new OwnerAccountDeletionStore(db,f.clock).sweep();await f.done();
});
test('6B2 existing dissolution OPERATOR blocks deletion and keeps structural lock',async()=>{
 const f=await fixture(1);await f.store.begin('owner');await f.ref.update({status:'OPERATOR'});assert.equal(await f.store.step('owner'),'OPERATOR');assert.equal((await db.doc(`familyJoinCapacity/${f.hid}`).get()).get('structuralOperationId'),f.id);await f.safety();assert.equal((await db.doc('familyMemberships/owner').get()).get('state'),'ACTIVE');
});
for(const defect of ['missingFallback','wrongOwner','wrongLock'])test(`6B2 integrity ${defect} never starts deletion`,async()=>{
 const f=await fixture(1);await f.store.admit('owner');if(defect==='missingFallback')await f.target.delete();if(defect==='wrongOwner')await f.source.update({ownerUid:'other'});if(defect==='wrongLock')await db.doc(`familyJoinCapacity/${f.hid}`).update({schemaVersion:3,structuralOperationId:'unknown'});
 assert.equal(await f.store.step('owner'),'OPERATOR');await f.safety();assert.equal((await f.ref.get()).exists,false);
});
test('6B2 corrupt terminal receipt blocks historical handoff without audit repair',async()=>{
 const f=await fixture(1);await f.store.begin('owner');const driver=new DissolutionLifecycleDriver(db,f.clock);for(let n=0;n<40&&(await f.ref.get()).get('phase')!=='DONE';n++){f.advance();await driver.step('owner',f.hid);}
 await f.ref.collection('finalization').doc('state').update({hash:'corrupt'});assert.equal(await f.store.step('owner'),'OPERATOR');await f.safety();assert.equal((await f.source.get()).get('state'),'DISSOLVED');
});
test('6B2 unexpected terminal source data blocks handoff and is never deleted',async()=>{
 const f=await fixture(1);await f.store.begin('owner');const driver=new DissolutionLifecycleDriver(db,f.clock);for(let n=0;n<40&&(await f.ref.get()).get('phase')!=='DONE';n++){f.advance();await driver.step('owner',f.hid);}
 await f.source.collection('shoppingItems').doc('unexpected').set({name:'extra',quantity:1,unit:'db'});assert.equal(await f.store.step('owner'),'OPERATOR');assert.equal((await f.source.collection('shoppingItems').doc('unexpected').get()).exists,true);await f.safety();
});
test('6B2 historical-only owner stays under original guard without new intent',async()=>{
 const f=await fixture(1);await new DissolutionPreparationStore(db,f.clock).prepare({uid:'owner'},f.hid);const driver=new DissolutionLifecycleDriver(db,f.clock);for(let n=0;n<40&&(await f.ref.get()).get('phase')!=='DONE';n++){f.advance();await driver.step('owner',f.hid);}
 await assert.rejects(f.service.beginAccountDeletion({uid:'owner'}),/FAMILY_LIFECYCLE_NOT_READY/);assert.equal((await f.intent.get()).exists,false);await f.safety();
});
test('6B2 private-only requests use original private deletion admission',async()=>{
 await new HouseholdStore(db).ensure({uid:'private'});const auth=new FakeAuthDeletionApi(),service=new AccountDeletionService(db,auth,()=>now);
 assert.equal((await service.beginAccountDeletion({uid:'private'})).outcome,'deletionStarted');assert.equal((await db.doc('familyOwnerDeletions/private').get()).exists,false);assert.equal((await db.doc('accountLifecycle/private').get()).get('state'),'DELETING');assert.equal(auth.calls,0);
});
test('6B2 historical handoff cannot create or join a new Family',async()=>{
 const f=await fixture(1);await f.store.begin('owner');await f.finish();await db.doc('familyRuntime/config').update({creationEnabled:true});
 await assert.rejects(new FamilyCreateStore(db,f.clock).reserve({uid:'owner'}),/accountUnavailable/);
 await assert.rejects(new FamilyJoinStore(db,f.clock).reserve({uid:'owner'},Buffer.alloc(32,8).toString('base64url'),'ADD'),/ACCOUNT_UNAVAILABLE/);
 await f.safety();
});

test('6B2 crash after DONE tolerates later legitimate private epoch refresh',async()=>{
 const f=await fixture(1);await f.store.begin('owner');const driver=new DissolutionLifecycleDriver(db,f.clock);for(let n=0;n<40&&(await f.ref.get()).get('phase')!=='DONE';n++){f.advance();await driver.step('owner',f.hid);}
 const {advanceShoppingEpoch}=await import('../src/shopping/mutation-store');f.advance();await f.target.update(advanceShoppingEpoch(f.clock()));
 assert.equal(await f.store.step('owner'),'WAITING_HISTORICAL_AUDIT');await f.done();await f.safety();
});
test('6B2 forced handoff transaction failure leaves DONE dissolution retryable and account ACTIVE',async()=>{
 const f=await fixture(1);await f.store.begin('owner');const driver=new DissolutionLifecycleDriver(db,f.clock);for(let n=0;n<40&&(await f.ref.get()).get('phase')!=='DONE';n++){f.advance();await driver.step('owner',f.hid);}
 const broken=new OwnerAccountDeletionStore(wrap(cb=>db.runTransaction(async tx=>{const r=await cb(tx);if(r==='WAITING_HISTORICAL_AUDIT')throw new Error('forced');return r;})),f.clock);
 await assert.rejects(broken.step('owner'),/forced/);assert.equal((await f.intent.get()).get('phase'),'DISSOLUTION_IN_PROGRESS');assert.equal((await f.ref.get()).get('phase'),'DONE');await f.safety();await f.store.step('owner');await f.done();
});
