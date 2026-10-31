import {after,afterEach,beforeEach,test} from 'node:test';
import assert from 'node:assert/strict';
import {initializeApp,deleteApp} from 'firebase-admin/app';
import {getFirestore,Timestamp} from 'firebase-admin/firestore';
import {requireLocalEmulator} from './emulator-guard';
import {grant,now} from './fixtures';
import {HouseholdStore,privateHouseholdId} from '../src/households/household-store';
import {FamilyCreateStore} from '../src/households/family-create';
import {FamilyInviteStore} from '../src/households/family-invites';
import {FamilyJoinStore} from '../src/households/family-join';
import {JoinTransferStore} from '../src/households/join-transfer';
import {MemberLeaveStore} from '../src/households/member-leave';
import {OwnerProLossStore} from '../src/households/owner-pro-loss';
import {OwnerAccountDeletionStore} from '../src/households/owner-account-deletion';
import {MemberAccountDeletionStore} from '../src/households/member-account-deletion';
import {AccountDeletionService} from '../src/accounts/account-deletion';
import {FakeAuthDeletionApi} from './fake-auth-deletion-api';
import {Maintenance,MaintenanceDependencies} from '../src/jobs/maintenance';
import {familyAdmissionEnabled,internalFamilyPhaseCallsAllowed} from '../src/households/runtime-policy';
requireLocalEmulator(process.env);
const app=initializeApp({projectId:'demo-kuktam-local'}),db=getFirestore(app);
// Pin transport, independently of simulated deployed environment. No live adapter.
db.settings({host:'127.0.0.1:8088',ssl:false});
const names=['K_SERVICE','FUNCTION_NAME','GCLOUD_PROJECT','GOOGLE_CLOUD_PROJECT','FIRESTORE_EMULATOR_HOST'] as const;
const saved=Object.fromEntries(names.map(k=>[k,process.env[k]]));
function restore(){for(const k of names){if(saved[k]===undefined)delete process.env[k];else process.env[k]=saved[k];}}
beforeEach(async()=>{
 restore();assert.ok((await fetch('http://127.0.0.1:8088/emulator/v1/projects/demo-kuktam-local/databases/(default)/documents',{method:'DELETE'})).ok);
 await db.doc('testTransport/probe').get(); // Initialize local gRPC/auth before removing emulator env.
 process.env.K_SERVICE='family-runtime-test';process.env.FUNCTION_NAME='family-runtime-test';
 process.env.GCLOUD_PROJECT=process.env.GOOGLE_CLOUD_PROJECT='runtime-simulation-not-demo';delete process.env.FIRESTORE_EMULATOR_HOST;
 assert.equal(app.options.projectId,'demo-kuktam-local');
});
afterEach(restore);after(()=>deleteApp(app));
async function fixture(){
 let ms=now.toMillis()+1000;const clock=()=>Timestamp.fromMillis(ms),advance=()=>{ms+=300001;};
 for(const uid of ['owner','guest','fresh'])await new HouseholdStore(db).ensure({uid});
 for(const uid of ['owner','fresh'])await db.doc(`users/${uid}/entitlementGrants/pro`).set(grant());
 await db.doc('familyRuntime/config').set({creationEnabled:true,inviteCreationEnabled:true,joinReservationEnabled:true});
 const create=new FamilyCreateStore(db,clock),join=new FamilyJoinStore(db,clock),transfer=new JoinTransferStore(db,clock);
 const invites=new FamilyInviteStore(db,{resolve:async uids=>new Map(uids.map(uid=>[uid,{exists:true,email:null}]))},clock);
 const cid=await create.reserve({uid:'owner'});for(let n=0;n<15&&(await db.doc(`familyOperations/${cid}`).get()).get('status')!=='DONE';n++){advance();await create.resume(cid);}
 const hid=(await db.doc(`familyOperations/${cid}`).get()).get('householdId') as string;
 const off=()=>db.doc('familyRuntime/config').set({creationEnabled:false,inviteCreationEnabled:false,joinReservationEnabled:false});
 async function admitted(mode:'ADD'|'DELETE'='ADD'){
  await db.doc(`households/${privateHouseholdId('guest')}/shoppingItems/one`).set({name:'Milk',quantity:1,unit:'l',revision:1});
  const invite=await invites.create({uid:'owner'}),id=await join.reserve({uid:'guest'},invite.token,mode);if(mode==='DELETE'){await off();assert.equal(await join.reserve({uid:'guest'},invite.token,mode),id);}
  await join.resume(id);
  await transfer.prepare({uid:'guest'},id,invite.inviteId);const ref=db.doc(`familyOperations/${id}`);
  for(let n=0;n<30&&(await ref.get()).get('phase')!=='COMMITTED_TRANSFER';n++){
   const view=await transfer.state({uid:'guest'},id,invite.inviteId);
   if(mode==='DELETE'&&view.phase==='SOURCE_FENCED_WAITING_CONFIRMATION')await transfer.confirm({uid:'guest'},{operationId:id,inviteId:invite.inviteId,sourceEpoch:view.sourceEpoch!,snapshotHash:view.snapshotHash!,sourceItemCount:view.sourceItemCount!,consentVersion:1});
   else{advance();await join.resume(id);}
  }
  assert.equal((await ref.get()).get('phase'),'COMMITTED_TRANSFER');return {invite,id,ref};
 }
 const maintenance=new Maintenance(db,{} as MaintenanceDependencies,clock);
 async function activate(id:string){for(let n=0;n<40&&(await db.doc(`familyOperations/${id}`).get()).get('status')!=='DONE';n++){advance();const result=await maintenance.run({now:clock(),only:['family']});assert.ok(result.items.every(i=>!['internalConflict','queryFailure'].includes(i.outcome)));}assert.equal((await db.doc(`familyOperations/${id}`).get()).get('phase'),'ACTIVE');}
 return {clock,advance,create,cid,hid,join,transfer,invites,off,admitted,activate};
}
test('9C deployed policy is fail closed and internal phase transports stay test only',()=>{
 for(const config of [undefined,null,{}, {creationEnabled:false},{creationEnabled:'true'},[]])assert.equal(familyAdmissionEnabled(config,'creationEnabled'),false);
 assert.equal(familyAdmissionEnabled({creationEnabled:true},'creationEnabled'),true);
 assert.equal(internalFamilyPhaseCallsAllowed(),false);
});
test('9C new admission missing false and unreadable denies without writes; CREATE retry survives OFF',async()=>{
 const f=await fixture(),invite=await f.invites.create({uid:'owner'});
 for(const missing of [true,false]){
  if(missing)await db.doc('familyRuntime/config').delete();else await f.off();
  const before=(await db.collection('familyOperations').get()).size;
  await assert.rejects(f.create.reserve({uid:'fresh'}),/featureDisabled/);
  await assert.rejects(f.invites.create({uid:'owner'}),/FEATURE_DISABLED/);
  await assert.rejects(f.join.reserve({uid:'guest'},invite.token,'ADD'),/FEATURE_DISABLED/);
  assert.equal((await db.collection('familyOperations').get()).size,before);assert.equal((await db.doc(`familyInvites/${invite.inviteId}`).get()).get('status'),'PENDING');
  assert.equal(await f.create.reserve({uid:'owner'}),f.cid);
 }
 // Failed transaction reads propagate; no admission can use a cached/default true.
 const broken=new Proxy(db,{get(t,k){if(k==='runTransaction')return async()=>{throw Error('configReadUnavailable');};const v=(t as any)[k];return typeof v==='function'?v.bind(t):v;}});
 await assert.rejects(new FamilyJoinStore(broken,f.clock).reserve({uid:'guest'},invite.token,'ADD'),/configReadUnavailable/);
});
for(const mode of ['ADD','DELETE'] as const)test(`9C deployed ${mode} committed JOIN completes through shared maintenance with admission OFF`,async()=>{
 const f=await fixture(),j=await f.admitted(mode);await f.off();
 assert.equal(await f.join.reserve({uid:'guest'},j.invite.token,mode),j.id);
 assert.equal((await f.transfer.state({uid:'guest'},j.id,j.invite.inviteId)).phase,'COMMITTED_TRANSFER');
 await f.activate(j.id);assert.equal(await f.join.reserve({uid:'guest'},j.invite.token,mode),j.id);
 const state=await f.invites.state({uid:'guest'});assert.ok(state.familyActive);assert.equal(state.role,'member');
 const exit=new MemberLeaveStore(db,f.clock);
 if(mode==='ADD')await exit.leave({uid:'guest'},j.invite.inviteId);else await exit.remove({uid:'owner'},'guest',j.invite.inviteId);
 assert.equal((await f.invites.state({uid:'guest'})).familyActive,false);assert.equal((await f.invites.state({uid:'owner'})).familyActive,true);
});
for(const cause of ['owner','proLoss'] as const)test(`9C deployed ${cause} dissolution sweep completes with new admission OFF`,async()=>{
 const f=await fixture(),life=new OwnerProLossStore(db,f.clock);
 let id:string;if(cause==='owner')id=(await life.startOwner('owner')).operationId;else{await db.doc('users/owner/entitlementGrants/pro').delete();id=await life.observe('owner');}
 await f.off();
 for(let n=0;n<60&&(await db.doc(`familyProLoss/${id}`).get()).get('status')!=='DONE';n++){f.advance();await life.sweep();}
 assert.equal((await db.doc(`familyProLoss/${id}`).get()).get('status'),'DONE');assert.equal((await db.doc(`households/${f.hid}`).get()).get('state'),'DISSOLVED');assert.equal((await f.invites.state({uid:'owner'})).familyActive,false);
});
for(const role of ['member','owner'] as const)test(`9C deployed ${role} deletion handoff and simulated Auth finish with admission OFF`,async()=>{
 const f=await fixture();if(role==='member'){const j=await f.admitted();await f.activate(j.id);}
 const uid=role==='owner'?'owner':'guest',auth=new FakeAuthDeletionApi(),service=new AccountDeletionService(db,auth,f.clock);
 await service.beginAccountDeletion({uid});assert.equal(auth.calls,0);await f.off();
 const store=role==='owner'?new OwnerAccountDeletionStore(db,f.clock):new MemberAccountDeletionStore(db,f.clock);
 for(let n=0;n<100&&!(await db.doc(`accountDeletions/${uid}`).get()).exists;n++){f.advance();await store.sweep();assert.equal(auth.calls,0);}
 assert.equal((await db.doc(`accountDeletions/${uid}`).get()).exists,true);
 if(role==='owner'){const home=await db.doc(`households/${f.hid}`).get();assert.equal(home.get('state'),'DISSOLVED');assert.equal(home.get('ownerUid'),null);assert.equal(home.get('auditOwnerUid'),uid);}
 for(let n=0;n<8&&(await db.doc(`accountLifecycle/${uid}`).get()).get('state')!=='DELETED';n++){f.advance();await service.resume(uid,50,2);}
 assert.equal((await db.doc(`accountLifecycle/${uid}`).get()).get('state'),'DELETED');assert.equal(auth.calls,1);
 if(role==='member')assert.equal((await f.invites.state({uid:'owner'})).familyActive,true);
});
test('9C deployed exports invoke injected store methods and internal phase calls cannot escape',async()=>{
 const root=await import('../src/index');let observed=0,pro=0,member=0,owner=0;
 const originals=[OwnerProLossStore.prototype.observe,OwnerProLossStore.prototype.sweep,MemberAccountDeletionStore.prototype.sweep,OwnerAccountDeletionStore.prototype.sweep] as const;
 try{
  OwnerProLossStore.prototype.observe=async()=>{observed++;return 'NO_ACTIVE_FAMILY';};
  OwnerProLossStore.prototype.sweep=async()=>{pro++;return {scanned:0,processed:0};};
  MemberAccountDeletionStore.prototype.sweep=async()=>{member++;return 0;};OwnerAccountDeletionStore.prototype.sweep=async()=>{owner++;return 0;};
  await root.familyOwnerEntitlementChanged.run({params:{uid:'owner',grantId:'pro'}} as any);
  for(const fn of [root.familyOwnerProLossMaintenance,root.familyMemberDeletionMaintenance,root.familyOwnerDeletionMaintenance])await fn.run({} as any);
  assert.deepEqual([observed,pro,member,owner],[1,1,1,1]);
  for(const fn of [root.prepareFamilyDissolution,root.prepareFamilyShoppingPreservation,root.mergeFamilyShoppingPreservation,root.cleanFamilyShoppingSource,root.releaseDissolutionMembers,root.finalizeFamilyDissolution])await assert.rejects(fn.run({auth:{uid:'owner'},data:{householdId:'family-test'}} as any),/FEATURE_DISABLED/);
 }finally{[OwnerProLossStore.prototype.observe,OwnerProLossStore.prototype.sweep,MemberAccountDeletionStore.prototype.sweep,OwnerAccountDeletionStore.prototype.sweep]=originals;}
});

