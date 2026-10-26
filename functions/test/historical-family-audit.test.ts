import {HistoricalFamilyAuditStore} from '../src/households/historical-family-audit';
import {assertNoLiveFamilyDependency} from '../src/households/join-capacity';
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
const app=initializeApp({projectId:'demo-kuktam-local'},'historical-family-audit'),db=getFirestore(app);
beforeEach(async()=>{assert.ok((await fetch('http://127.0.0.1:8088/emulator/v1/projects/demo-kuktam-local/databases/(default)/documents',{method:'DELETE'})).ok);});
after(()=>deleteApp(app));
async function fixture(count=1,hid='family-audit'){
 let ms=now.toMillis()+1000;const clock=()=>Timestamp.fromMillis(ms),advance=()=>{ms+=300001;};
 const uids=['owner',...Array.from({length:count-1},(_,i)=>`member${i}`)],id=dissolutionId('owner',hid),source=db.doc(`households/${hid}`),target=db.doc(`households/${privateHouseholdId('owner')}`);
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

async function historical(count=1,hid='family-audit',intent=true){
 const f=await fixture(count,hid);
 const engine=new DissolutionLifecycleDriver(db,f.clock);
 if(intent){await f.store.admit('owner');await f.finish();}
 else {await new DissolutionPreparationStore(db,f.clock).prepare({uid:'owner'},f.hid);for(let n=0;n<50&&(await f.ref.get()).get('phase')!=='DONE';n++){f.advance();await engine.step('owner',f.hid);}}
 const audit=new HistoricalFamilyAuditStore(db,f.clock),state=f.intent.collection('historicalAudit').doc('state'),receipts=f.intent.collection('historicalFamilies');
 const ready=async()=>{for(let n=0;n<100;n++){const r=await audit.step('owner');assert.notEqual(r,'OPERATOR');await f.safety();if(r==='HISTORICAL_AUDIT_READY')return;}throw new Error('stuckAudit');};
 const immutable=await Promise.all(['familyOperations','familyInvites','familyJoinCapacity','familyInviteSlots'].map(async c=>(await db.collection(c).get()).docs.map(d=>({path:d.ref.path,data:d.data(),time:d.updateTime}))));
 const privateBefore=await f.target.collection('shoppingItems').get();const userBefore=await db.doc('users/owner').get();
 const preserved=async()=>{for(const docs of immutable)for(const before of docs){const after=await db.doc(before.path).get();assert.deepEqual(after.data(),before.data);assert.ok(after.updateTime!.isEqual(before.time!));}for(const before of privateBefore.docs){const after=await before.ref.get();assert.deepEqual(after.data(),before.data());assert.ok(after.updateTime!.isEqual(before.updateTime!));}assert.deepEqual((await db.doc('users/owner').get()).data(),userBefore.data());await f.safety();};
 const noLive=()=>db.runTransaction(tx=>assertNoLiveFamilyDependency(db,tx,'owner'));
 return {...f,audit,state,receipts,ready,preserved,noLive};
}
function wrap(run:(cb:any)=>Promise<any>){return new Proxy(db,{get(t,k){if(k==='runTransaction')return run;const v=(t as any)[k];return typeof v==='function'?v.bind(t):v;}}) as Firestore;}

test('6C1 WAITING owner detaches only live root ownership and stops audit ready',async()=>{
 const f=await historical(2);await assert.rejects(new LifecycleStore(db,f.clock).beginDeletion('owner',true),/FAMILY_LIFECYCLE_NOT_READY/);await assert.rejects(f.noLive(),/FAMILY_LIFECYCLE_NOT_READY/);await f.ready();
 const root=await f.source.get();assert.equal(root.get('state'),'DISSOLVED');assert.equal(root.get('ownerUid'),null);assert.equal(root.get('auditOwnerUid'),'owner');assert.equal(root.get('auditDetachmentPath'),f.receipts.doc(f.hid).path);
 assert.equal((await f.state.get()).get('count'),1);assert.equal((await f.intent.get()).get('phase'),'HISTORICAL_AUDIT_READY');await f.noLive();await f.preserved();
 const {DissolutionFinalizationStore}=await import('../src/households/dissolution-finalization');assert.equal(await new DissolutionFinalizationStore(db,f.clock).step({uid:'owner'},f.hid),'DONE');
 assert.equal((await f.service.beginAccountDeletion({uid:'owner'})).outcome,'historicalAuditReady');
 for(const authGone of [false,true])await assert.rejects(new LifecycleStore(db,f.clock).beginDeletion('owner',authGone),/HISTORICAL_AUDIT_HANDOFF_REQUIRED/);
 await assert.rejects(new LifecycleStore(db,f.clock).advanceAccountMarker({uid:'owner'},1,'DELETING'),/HISTORICAL_AUDIT_HANDOFF_REQUIRED/);await f.safety();
});
test('6C1 already-private historical owner uses same intent and detachment primitive',async()=>{
 const f=await historical(1,'family-audit',false);assert.equal((await f.intent.get()).exists,false);await assert.rejects(f.service.beginAccountDeletion({uid:'owner'}),/FAMILY_LIFECYCLE_NOT_READY/);
 await f.audit.admitHistorical({uid:'owner'});assert.equal((await f.intent.get()).get('phase'),'WAITING_HISTORICAL_AUDIT');await f.ready();await f.noLive();await f.preserved();
});
test('6C1 multiple historical families detach with bounded resumable receipts',async()=>{
 const first=await historical(1,'family-a',false),f=await historical(1,'family-z',false);await f.audit.admitHistorical({uid:'owner'});
 let observed=false;for(let n=0;n<50;n++){await f.audit.step('owner');if((await f.state.get()).get('count')===1){observed=true;break;}}
 assert.equal(observed,true);assert.equal((await first.source.get()).get('ownerUid'),null);assert.equal((await f.source.get()).get('ownerUid'),'owner');
 await new HistoricalFamilyAuditStore(db,f.clock).step('owner');await f.ready();assert.equal((await f.state.get()).get('count'),2);assert.equal((await f.receipts.get()).size,2);await f.noLive();await f.preserved();
});
test('6C1 duplicate and terminal reentry do not rewrite audit or versions',async()=>{
 const f=await historical();await f.ready();const refs=[f.source,f.intent,f.state,f.receipts.doc(f.hid)],before=await db.getAll(...refs);
 await f.audit.admitHistorical({uid:'owner'});for(let n=0;n<3;n++)assert.equal(await f.audit.step('owner'),'HISTORICAL_AUDIT_READY');const after=await db.getAll(...refs);after.forEach((d,n)=>assert.ok(d.updateTime!.isEqual(before[n]!.updateTime!)));await f.preserved();
});
test('6C1 lost detach ACK recognizes root receipt and progress atomically',async()=>{
 const f=await historical();let lost=false;const broken=new HistoricalFamilyAuditStore(wrap(async cb=>{const r=await db.runTransaction(cb);if(!lost&&(await f.source.get()).get('ownerUid')===null){lost=true;throw new Error('lostAck');}return r;}),f.clock);
 await assert.rejects(async()=>{for(let n=0;n<20;n++)await broken.step('owner');},/lostAck/);assert.equal((await f.state.get()).get('count'),1);const before=await f.source.get();await f.ready();assert.ok((await f.source.get()).updateTime!.isEqual(before.updateTime!));await f.preserved();
});
test('6C1 lost final handoff ACK returns same readiness without writes',async()=>{
 const f=await historical();let lost=false;const broken=new HistoricalFamilyAuditStore(wrap(async cb=>{const r=await db.runTransaction(cb);if(!lost&&(await f.intent.get()).get('phase')==='HISTORICAL_AUDIT_READY'){lost=true;throw new Error('lostAck');}return r;}),f.clock);
 await assert.rejects(async()=>{for(let n=0;n<20;n++)await broken.step('owner');},/lostAck/);const before=await f.intent.get();await f.ready();assert.ok((await f.intent.get()).updateTime!.isEqual(before.updateTime!));await f.safety();
});
test('6C1 competing workers create one detachment receipt and final state',async()=>{
 const f=await historical();for(let n=0;n<20&&(await f.intent.get()).get('phase')!=='HISTORICAL_AUDIT_READY';n++)await Promise.all([f.audit.step('owner'),f.audit.step('owner')]);assert.equal((await f.state.get()).get('count'),1);assert.equal((await f.receipts.get()).size,1);await f.noLive();await f.preserved();
});
test('6C1 failed detach transaction leaves owner reference and progress intact',async()=>{
 const f=await historical();for(let n=0;n<10&&(await f.state.get()).get('current')?.stage!=='DETACH';n++)await f.audit.step('owner');
 const before=await f.state.get(),broken=new HistoricalFamilyAuditStore(wrap(cb=>db.runTransaction(async tx=>{await cb(tx);throw new Error('forced');})),f.clock);
 await assert.rejects(broken.step('owner'),/forced/);assert.equal((await f.source.get()).get('ownerUid'),'owner');assert.equal((await f.receipts.get()).size,0);assert.deepEqual((await f.state.get()).data(),before.data());await f.ready();await f.preserved();
});
test('6C1 stale account generation cannot detach later account history',async()=>{
 const f=await historical();await db.doc('accountLifecycle/owner').update({generation:2});assert.equal(await f.audit.step('owner'),'OPERATOR');assert.equal((await f.source.get()).get('ownerUid'),'owner');assert.equal((await f.receipts.get()).size,0);await assert.rejects(new LifecycleStore(db,f.clock).beginDeletion('owner',true),/HISTORICAL_AUDIT_HANDOFF_REQUIRED/);await f.safety();
});
for(const defect of ['notDone','unexpectedMember','wrongOwner','lock','pendingInvite','reservedInvite','corruptReceipt','inProgressOperation','proLossPending','historicalInviteOwner'])test(`6C1 integrity ${defect} blocks without erasing audit`,async()=>{
 const f=await historical();
 if(defect==='notDone')await f.ref.update({phase:'NON_OWNER_RELEASE_COMPLETE',status:'READY'});
 if(defect==='unexpectedMember')await f.source.collection('members').doc('unknown').set({role:'member'});
 if(defect==='wrongOwner')await f.source.update({ownerUid:'other'});
 if(defect==='lock')await db.doc(`familyJoinCapacity/${f.hid}`).update({schemaVersion:3,structuralOperationId:f.id});
 if(defect==='pendingInvite'||defect==='reservedInvite')await db.doc('familyInvites/'+ 'a'.repeat(64)).set({householdId:f.hid,status:defect==='pendingInvite'?'PENDING':'RESERVED',expiresAt:Timestamp.fromMillis(f.clock().toMillis()+60000)});
 if(defect==='corruptReceipt')await f.ref.collection('finalization').doc('state').update({hash:'bad'});
 if(defect==='inProgressOperation')await db.doc('familyOperations/unexpected').set({ownerUid:'owner',householdId:f.hid,status:'READY'});
 if(defect==='historicalInviteOwner')await db.doc('familyInvites/'+'b'.repeat(64)).set({schemaVersion:1,householdId:f.hid,createdByUid:'other',createdAt:now,expiresAt:new Timestamp(now.seconds+7*86400,now.nanoseconds),status:'REVOKED',operationId:null,usedAt:null,usedByUid:null});
 if(defect==='proLossPending')await db.doc(`familyProLoss/${f.id}`).set({status:'IN_PROGRESS'});
 let result;for(let n=0;n<15;n++){result=await f.audit.step('owner');if(result==='OPERATOR')break;}assert.equal(result,'OPERATOR');assert.equal((await f.source.get()).exists,true);assert.equal((await f.receipts.get()).size,0);assert.equal((await f.ref.get()).exists,true);await f.safety();
});
test('6C1 corrupt already-detached receipt blocks verification without rollback',async()=>{
 const f=await historical();for(let n=0;n<20&&(await f.state.get()).get('count')!==1;n++)await f.audit.step('owner');await f.receipts.doc(f.hid).update({accountGeneration:999});assert.equal((await f.source.get()).get('ownerUid'),null);
 let result;for(let n=0;n<5;n++){result=await f.audit.step('owner');if(result==='OPERATOR')break;}assert.equal(result,'OPERATOR');assert.equal((await f.source.get()).get('auditOwnerUid'),'owner');await f.safety();
});
test('6C1 active owner member and committed JOIN cannot enter audit detachment',async()=>{
 const f=await fixture(2),audit=new HistoricalFamilyAuditStore(db,f.clock);await assert.rejects(audit.admitHistorical({uid:'owner'}),/historicalAuditIntegrity/);await assert.rejects(audit.admitHistorical({uid:'member0'}),/historicalAuditIntegrity/);
 const j=await joining(f,true);await assert.rejects(audit.admitHistorical({uid:'guest'}),/historicalAuditIntegrity/);assert.equal((await j.ref.get()).get('phase'),'COMMITTED_TRANSFER');assert.equal((await db.collection('familyOwnerDeletions').get()).size,0);await f.safety();
});
for(const removal of [false,true])test(`6C1 historical JOIN ${removal?'remove':'leave'} USED REVOKED and paged expired invites remain immutable`,async()=>{
 const f=await fixture(1),j=await joining(f,true,true),exit=new MemberLeaveStore(db,f.clock);if(removal)await exit.remove({uid:'owner'},'guest',j.invite.inviteId);else await exit.leave({uid:'guest'},j.invite.inviteId);
 const invites=new FamilyInviteStore(db,{resolve:async()=>new Map()},f.clock),revoked=await invites.create({uid:'owner'});await invites.revoke({uid:'owner'},revoked.inviteId);
 // Eleven expired terminal-compatible invitations prove bounded pagination beyond one page.
 const template=(await db.doc(`familyInvites/${revoked.inviteId}`).get()).data()!;const past=new Timestamp(f.clock().seconds-8*86400,0);
 for(let n=0;n<11;n++)await db.doc(`familyInvites/${n.toString(16).padStart(64,'0')}`).set({...template,status:'PENDING',createdAt:past,expiresAt:new Timestamp(past.seconds+7*86400,0)});
 await f.store.admit('owner');await f.finish();const before=(await db.collection('familyInvites').get()).docs,operations=(await db.collection('familyOperations').get()).docs;
 const audit=new HistoricalFamilyAuditStore(db,f.clock);for(let n=0;n<40&&(await f.intent.get()).get('phase')!=='HISTORICAL_AUDIT_READY';n++)assert.notEqual(await audit.step('owner'),'OPERATOR');
 assert.equal((await f.intent.get()).get('phase'),'HISTORICAL_AUDIT_READY');for(const d of [...before,...operations]){const after=await d.ref.get();assert.deepEqual(after.data(),d.data());assert.ok(after.updateTime!.isEqual(d.updateTime!));}
 assert.equal((await invites.preview({uid:'guest'},j.invite.token)).code,'USED');assert.equal((await invites.preview({uid:'guest'},revoked.token)).code,'REVOKED');
 await db.runTransaction(tx=>assertNoLiveFamilyDependency(db,tx,'guest'));const {assertNoActiveFamilyDeletion}=await import('../src/households/join-capacity');await db.runTransaction(tx=>assertNoActiveFamilyDeletion(db,tx,'guest'));assert.equal((await db.doc('accountDeletions/guest').get()).exists,false);await f.safety();
});

test('6C1 terminal superseded Pro-loss is historical evidence not an active dependency',async()=>{
 const f=await fixture(1),loss=new OwnerProLossStore(db,f.clock);await f.lose();await loss.observe('owner');await db.doc('users/owner/entitlementGrants/pro').set(grant());assert.equal(await loss.step(f.id),'SUPERSEDED');
 await f.store.admit('owner');await f.finish();const before=await db.doc(`familyProLoss/${f.id}`).get(),audit=new HistoricalFamilyAuditStore(db,f.clock);
 for(let n=0;n<20&&(await f.intent.get()).get('phase')!=='HISTORICAL_AUDIT_READY';n++)assert.notEqual(await audit.step('owner'),'OPERATOR');
 assert.equal((await f.intent.get()).get('phase'),'HISTORICAL_AUDIT_READY');assert.deepEqual((await before.ref.get()).data(),before.data());await f.safety();
});
