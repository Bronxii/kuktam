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
const app=initializeApp({projectId:'demo-kuktam-local'},'final-family-deletion'),db=getFirestore(app);
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


async function ready(count=1,intent=true){const f=await historical(count,'family-audit',intent);if(!intent)await f.audit.admitHistorical({uid:'owner'});await f.ready();return f;}
type F=Awaited<ReturnType<typeof ready>>;
async function auditSnapshot(){
 const result:any[]=[];
 async function visit(ref:any){const d=await ref.get();if(d.exists)result.push(d);for(const c of await ref.listCollections())for(const child of (await c.get()).docs)await visit(child.ref);}
 for(const c of ['familyOperations','familyInvites','familyJoinCapacity','familyInviteSlots'])for(const d of (await db.collection(c).get()).docs)await visit(d.ref);
 for(const d of (await db.collection('households').where('kind','==','family').get()).docs)await visit(d.ref);
 for(const c of ['historicalAudit','historicalFamilies'])for(const d of (await db.collection(`familyOwnerDeletions/owner/${c}`).get()).docs)await visit(d.ref);
 return async()=>{for(const d of result){const a=await d.ref.get();assert.deepEqual(a.data(),d.data());assert.ok(a.updateTime!.isEqual(d.updateTime!));}};
}
async function finish(f:F,service=f.service){for(let n=0;n<6;n++){const result=await service.resume('owner',50,2);if(result==='deletionCompleted')return;f.advance();}throw new Error('notDeleted');}
async function closed(f:F,calls=1){assert.equal((await db.doc('accountLifecycle/owner').get()).get('state'),'DELETED');assert.equal((await db.doc('accountDeletions/owner').get()).get('stage'),'DONE');assert.equal((await f.intent.get()).get('phase'),'DELETED');assert.equal((await db.doc('users/owner').get()).exists,false);assert.equal((await f.target.get()).exists,false);assert.equal((await f.target.collection('shoppingItems').get()).size,0);assert.equal(f.auth.calls,calls);assert.equal(f.auth.deleted.size,1);assert.equal((await f.source.get()).get('ownerUid'),null);}
async function authStage(f:F){const store=new LifecycleStore(db,f.clock);for(let n=0;n<40;n++){const j=await db.doc('accountDeletions/owner').get();if(j.get('stage')==='AUTH')return store;await store.deletionStep('owner',2);}throw new Error('notAuthStage');}
for(const count of [1,3])test(`6C2 ACTIVE owner full local lifecycle ${count} participants`,async()=>{
 const f=await fixture(count);assert.equal((await f.service.beginAccountDeletion({uid:'owner'})).outcome,'familyDissolutionPending');await f.finish();
 const a=new HistoricalFamilyAuditStore(db,f.clock);for(let n=0;n<40&&(await f.intent.get()).get('phase')!=='HISTORICAL_AUDIT_READY';n++)await a.step('owner');
 const preserved=await auditSnapshot(),members=await Promise.all(f.uids.slice(1).map(async uid=>({uid,user:await db.doc(`users/${uid}`).get(),home:await db.doc(`households/${privateHouseholdId(uid)}`).get(),item:await db.doc(`households/${privateHouseholdId(uid)}/shoppingItems/keep`).get()})));
 assert.equal((await f.target.collection('shoppingItems').get()).docs[0]!.get('quantity'),3300);
 const result=await f.service.beginAccountDeletion({uid:'owner'});assert.equal(result.outcome,'deletionStarted');assert.equal((await f.intent.get()).get('phase'),'DELETION_IN_PROGRESS');assert.equal((await db.doc('accountLifecycle/owner').get()).get('state'),'DELETING');assert.equal(f.auth.calls,0);
 const handler=f.auth.handler;f.auth.handler=async(uid,options)=>{assert.equal((await f.ref.get()).get('phase'),'DONE');assert.equal((await db.doc('accountDeletions/owner').get()).get('stage'),'AUTH');assert.equal((await f.intent.get()).get('phase'),'DELETION_IN_PROGRESS');return handler(uid,options);};
 await finish(f as F);await closed(f as F);await preserved();for(const m of members)for(const old of [m.user,m.home,m.item])assert.deepEqual((await old.ref.get()).data(),old.data());
});
test('6C2 already historical owner deletes without new dissolution',async()=>{const f=await ready(1,false),preserved=await auditSnapshot();await f.service.beginAccountDeletion({uid:'owner'});await finish(f);await closed(f);await preserved();assert.equal((await db.collection('familyOperations').where('kind','==','FAMILY_DISSOLUTION').get()).size,1);});
test('6C2 multiple historical families all survive deletion',async()=>{await historical(1,'family-a',false);const f=await historical(1,'family-z',false);await f.audit.admitHistorical({uid:'owner'});await f.ready();assert.equal((await f.state.get()).get('count'),2);const preserved=await auditSnapshot();await f.service.beginAccountDeletion({uid:'owner'});await finish(f);await closed(f);await preserved();});
for(const defect of ['incomplete','member','activeFamily','work','lock','invite','receipt','secondHistorical','missingReceipt','generation','sourceItem'])test(`6C2 admission blocks ${defect}`,async()=>{
 const f=await ready();
 if(defect==='incomplete')await f.state.update({stage:'VERIFY'});
 if(defect==='member')await db.doc('familyMemberships/owner').set({householdId:f.hid,state:'ACTIVE',role:'owner',operationId:null});
 if(defect==='activeFamily')await db.doc('households/new-family').set({kind:'family',state:'ACTIVE',ownerUid:'owner'});
 if(defect==='work')await db.doc('familyOperations/new-work').set({ownerUid:'owner',status:'READY'});
 if(defect==='lock')await db.doc(`familyJoinCapacity/${f.hid}`).set({schemaVersion:3,operationIds:[],structuralOperationId:f.id});
 if(defect==='invite')await db.doc('familyInvites/unsafe').set({householdId:f.hid,status:'RESERVED'});
 if(defect==='receipt')await f.receipts.doc(f.hid).update({hash:'bad'});
 if(defect==='secondHistorical')await db.doc('households/another-history').set({kind:'family',state:'DISSOLVED',ownerUid:'owner'});
 if(defect==='missingReceipt')await db.doc('households/extra-detached').set({kind:'family',state:'DISSOLVED',ownerUid:null,auditOwnerUid:'owner'});
 if(defect==='generation')await db.doc('accountLifecycle/owner').update({generation:9});
 if(defect==='sourceItem')await f.source.collection('shoppingItems').doc('extra').set({name:'unexpected'});
 await assert.rejects(f.service.beginAccountDeletion({uid:'owner'}));assert.equal((await db.doc('accountLifecycle/owner').get()).get('state'),'ACTIVE');assert.equal((await db.doc('accountDeletions/owner').get()).exists,false);assert.equal(f.auth.calls,0);
});
test('6C2 pending lifecycle blocks new create and JOIN',async()=>{const f=await ready();await assert.rejects(new FamilyCreateStore(db,f.clock).reserve({uid:'owner'}),/accountUnavailable/);await assert.rejects(new FamilyJoinStore(db,f.clock).reserve({uid:'owner'},Buffer.alloc(32,1).toString('base64url'),'ADD'),(e:any)=>e.code==='ACCOUNT_UNAVAILABLE');await f.safety();});
test('6C2 duplicate requests competing admission workers and terminal reentry',async()=>{const f=await ready();const results=await Promise.all([f.service.beginAccountDeletion({uid:'owner'}),f.service.beginAccountDeletion({uid:'owner'})]);assert.equal(new Set(results.map(r=>r.operationId)).size,1);assert.equal((await db.collection('accountDeletions').get()).size,1);await Promise.all([f.service.resume('owner',50,2),f.service.resume('owner',50,2)]);await finish(f);await closed(f);const refs=[f.intent,db.doc('accountLifecycle/owner'),db.doc('accountDeletions/owner')],before=await db.getAll(...refs);assert.equal((await f.service.beginAccountDeletion({uid:'owner'})).outcome,'alreadyDeleted');await finish(f);for(let n=0;n<refs.length;n++)assert.ok((await refs[n]!.get()).updateTime!.isEqual(before[n]!.updateTime!));await closed(f);});
test('6C2 failed final admission rolls back marker job and intent together',async()=>{const f=await ready();const broken=wrap(cb=>db.runTransaction(async tx=>{await cb(tx);throw new Error('forced');}));const s=new AccountDeletionService(broken,f.auth,f.clock);await assert.rejects(s.beginAccountDeletion({uid:'owner'}),/forced/);await f.safety();assert.equal((await f.intent.get()).get('phase'),'HISTORICAL_AUDIT_READY');});
test('6C2 lost atomic admission ACK recovers same job',async()=>{const f=await ready();let lost=false;const broken=wrap(async cb=>{const r=await db.runTransaction(cb);if(!lost&&(await db.doc('accountDeletions/owner').get()).exists){lost=true;throw new Error('lostAck');}return r;});const service=new AccountDeletionService(broken,f.auth,f.clock);await service.beginAccountDeletion({uid:'owner'});const job=await db.doc('accountDeletions/owner').get();await f.service.beginAccountDeletion({uid:'owner'});assert.equal((await db.doc('accountDeletions/owner').get()).get('operationId'),job.get('operationId'));await finish(f);await closed(f);});
for(const point of ['privateCleanup','authRecorded','terminal'])test(`6C2 lost ACK ${point} resumes existing engine`,async()=>{const f=await ready();await f.service.beginAccountDeletion({uid:'owner'});let lost=false;const broken=wrap(async cb=>{const r=await db.runTransaction(cb);const j=await db.doc('accountDeletions/owner').get();if(!lost&&(point==='privateCleanup'&&!(await f.target.get()).exists||point==='authRecorded'&&j.get('authGone')===true||point==='terminal'&&j.get('stage')==='DONE')){lost=true;throw new Error('lostAck');}return r;});await new AccountDeletionService(broken,f.auth,f.clock).resume('owner',50,2);assert.equal(lost,true);await finish(f);await closed(f);});
test('6C2 Auth success before durable ACK retries notFound with one logical effect',async()=>{const f=await ready();await f.service.beginAccountDeletion({uid:'owner'});const store=await authStage(f),claim=await store.deletionStep('owner',2);assert.equal(claim.kind,'auth');assert.equal(await f.auth.deleteUser('owner',{signal:new AbortController().signal}),'deleted');f.advance();await finish(f);await closed(f,2);});
test('6C2 stale admitted generation cannot clean recreated account',async()=>{const f=await ready();await f.service.beginAccountDeletion({uid:'owner'});await db.doc('accountLifecycle/owner').set({schemaVersion:1,state:'ACTIVE',generation:99,updatedAt:f.clock(),deletionStartedAt:null,deletedAt:null});assert.equal(await f.service.resume('owner',50),'cleanupRetryRequired');await assert.rejects(f.service.beginAccountDeletion({uid:'owner'}));assert.equal(f.auth.calls,0);assert.equal((await f.target.collection('shoppingItems').get()).size,1);});

for(const removal of [false,true])test(`6C2 historical JOIN ${removal?'remove':'leave'} USED REVOKED expired audits survive Auth deletion`,async()=>{
 const f=await fixture(),j=await joining(f,true,true),exit=new MemberLeaveStore(db,f.clock);if(removal)await exit.remove({uid:'owner'},'guest',j.invite.inviteId);else await exit.leave({uid:'guest'},j.invite.inviteId);
 const invites=new FamilyInviteStore(db,{resolve:async()=>new Map()},f.clock),revoked=await invites.create({uid:'owner'});await invites.revoke({uid:'owner'},revoked.inviteId);
 const template=(await db.doc(`familyInvites/${revoked.inviteId}`).get()).data()!,past=new Timestamp(f.clock().seconds-8*86400,0);
 await db.doc('familyInvites/'+'e'.repeat(64)).set({...template,status:'PENDING',createdAt:past,expiresAt:new Timestamp(past.seconds+7*86400,0)});
 await f.store.admit('owner');await f.finish();const audit=new HistoricalFamilyAuditStore(db,f.clock);for(let n=0;n<40&&(await f.intent.get()).get('phase')!=='HISTORICAL_AUDIT_READY';n++)await audit.step('owner');
 const preserved=await auditSnapshot(),guest=await db.doc('users/guest').get();await f.service.beginAccountDeletion({uid:'owner'});await finish(f as F);await closed(f as F);await preserved();assert.deepEqual((await guest.ref.get()).data(),guest.data());assert.equal((await invites.preview({uid:'guest'},j.invite.token)).code,'USED');assert.equal((await invites.preview({uid:'guest'},revoked.token)).code,'REVOKED');
});
