import {MemberAccountDeletionStore} from '../src/households/member-account-deletion';
import {AccountDeletionService} from '../src/accounts/account-deletion';
import {DeletionGateway} from '../src/accounts/deletion-gateway';
import {FakeAuthDeletionApi} from './fake-auth-deletion-api';
import {DissolutionPreparationStore,dissolutionId} from '../src/households/dissolution-preparation';
import {DissolutionPreservationStore} from '../src/households/dissolution-preservation';
import {DissolutionMergeStore} from '../src/households/dissolution-merge';
import {DissolutionSourceDispositionStore} from '../src/households/dissolution-source-disposition';
import {DissolutionMemberReleaseStore} from '../src/households/dissolution-member-release';
import {DissolutionFinalizationStore} from '../src/households/dissolution-finalization';
import { after, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeApp, deleteApp } from 'firebase-admin/app';
import { getFirestore, Timestamp, Firestore } from 'firebase-admin/firestore';
import { requireLocalEmulator } from './emulator-guard';
import { grant, now } from './fixtures';
import { HouseholdStore, privateHouseholdId } from '../src/households/household-store';
import { FamilyInviteStore } from '../src/households/family-invites';
import { FamilyJoinStore, readJoinOperation } from '../src/households/family-join';
import { JoinTransferStore } from '../src/households/join-transfer';
import { transferChildId } from '../src/households/join-transfer-execution';
import { TransferOperation } from '../src/households/join-transfer-contract';
import { ShoppingMutationStore, advanceShoppingEpoch } from '../src/shopping/mutation-store';
import { newMutationId } from '../src/shopping/mutation-contract';
import { LifecycleStore } from '../src/billing/lifecycle-store';
import { MemberLeaveStore, memberLeaveId } from '../src/households/member-leave';
import { memberLeaveHandler } from '../src/households/member-leave-handler';
requireLocalEmulator(process.env);
const app=initializeApp({projectId:'demo-kuktam-local'},'member-account-deletion'),db=getFirestore(app);
beforeEach(async()=>{assert.ok((await fetch('http://127.0.0.1:8088/emulator/v1/projects/demo-kuktam-local/databases/(default)/documents',{method:'DELETE'})).ok);});
after(()=>deleteApp(app));
type Item={name:string;quantity:number;unit:string};
const milk=(quantity=300,unit='ml'):Item=>({name:'Milk',quantity,unit});
const unique=(n:number)=>Array.from({length:n},(_,i)=>({name:`product${i}`,quantity:i+1,unit:'db'}));
async function fixture(items:Item[],mode:'ADD'|'DELETE'='ADD',pending=false){
  await new HouseholdStore(db).ensure({uid:'owner'});await new HouseholdStore(db).ensure({uid:'guest'});
  await db.doc('users/owner/entitlementGrants/pro').set(grant());
  await db.doc('familyRuntime/config').set({inviteCreationEnabled:true,joinReservationEnabled:true});
  await db.doc('shoppingRuntime/config').set({enabled:true});
  const home=db.doc('households/family-test');
  await home.set({schemaVersion:2,kind:'family',state:'ACTIVE',operationId:null,ownerUid:'owner',createdAt:now});
  await home.collection('members').doc('owner').set({role:'owner'});
  await db.doc('users/owner').update({activeHouseholdId:'family-test',familyHouseholdId:'family-test'});
  await db.doc('familyMemberships/owner').set({householdId:'family-test',role:'owner',state:'ACTIVE',operationId:null});
  let time=now.toMillis()+1000;const clock=()=>Timestamp.fromMillis(time),advance=(ms=300001)=>{time+=ms;};
  const shopping=new ShoppingMutationStore(db,clock),context=await shopping.ensureContext({uid:'owner'});
  let oldMutationId:string|null=null;
  if(pending){const old=await shopping.ensureContext({uid:'guest'});oldMutationId=newMutationId(old.epoch);
    await shopping.submit({uid:'guest'},{schemaVersion:1,actorUid:'guest',...old,mutationId:oldMutationId,kind:'ADD',payloadJson:JSON.stringify({type:'ADD',...milk()}),submittedAt:clock()});}
  const p=privateHouseholdId('guest'),source=db.collection(`households/${p}/shoppingItems`);
  const batch=db.batch();items.forEach((item,i)=>batch.create(source.doc(`i${String(i).padStart(4,'0')}`),{...item,isChecked:true,createdAt:now}));if(items.length)await batch.commit();
  const invites=new FamilyInviteStore(db,{resolve:async()=>new Map()},clock),invite=await invites.create({uid:'owner'});
  const join=new FamilyJoinStore(db,clock,1000),id=await join.reserve({uid:'guest'},invite.token,mode),ref=db.doc(`familyOperations/${id}`);
  const op=async()=>readJoinOperation((await ref.get()).data(),id) as TransferOperation;
  await join.resume(id);const engine=new JoinTransferStore(db,clock);await engine.prepare({uid:'guest'},id,invite.inviteId);
  const tick=async()=>{advance();return new FamilyJoinStore(db,clock,1000).resume(id);};
  for(let i=0;i<30&&(await op()).phase==='SNAPSHOT_SOURCE';i++)await tick();
  if(mode==='ADD')await tick();else{
    const v=await engine.state({uid:'guest'},id,invite.inviteId);
    await engine.confirm({uid:'guest'},{operationId:id,inviteId:invite.inviteId,sourceEpoch:v.sourceEpoch!,snapshotHash:v.snapshotHash!,sourceItemCount:v.sourceItemCount!,consentVersion:1});
  }
  assert.equal((await op()).phase,'COMMITTED_TRANSFER');
  const frozen=(await source.get()).docs.map(d=>[d.id,d.data(),d.updateTime]);
  const epoch=(await source.parent!.get()).get('shoppingEpoch');
  const pages=async()=>(await ref.collection('transferJournal').get()).docs.sort((a,b)=>a.get('pageIndex')-b.get('pageIndex'));
  const finish=async()=>{for(let i=0;i<40&&(await op()).phase==='COMMITTED_TRANSFER'&&(await op()).status==='READY';i++)await tick();assert.equal((await op()).phase,'CLEAN_SOURCE');assert.equal((await op()).status,'READY');};
  const boundary=async()=>{
    assert.deepEqual((await source.get()).docs.map(d=>[d.id,d.data(),d.updateTime]),frozen);
    const root=await source.parent!.get();assert.equal(root.get('operationId'),id);assert.equal(root.get('shoppingEpoch'),epoch);
    assert.equal((await db.doc('familyMemberships/guest').get()).get('state'),'RESERVED');
    assert.equal((await db.doc('users/guest').get()).get('activeHouseholdId'),p);
    assert.equal((await home.collection('members').doc('guest').get()).exists,false);
    assert.equal((await db.doc('familyJoinCapacity/family-test').get()).get('structuralOperationId'),id);
    assert.equal((await db.doc(`familyInvites/${invite.inviteId}`).get()).get('status'),'RESERVED');
  };
  const external=async(quantity:number)=>{
    const c=await shopping.ensureContext({uid:'owner'}),mutationId=newMutationId(c.epoch);
    await shopping.submit({uid:'owner'},{schemaVersion:1,actorUid:'owner',...c,mutationId,kind:'ADD',payloadJson:JSON.stringify({type:'ADD',...milk(quantity)}),submittedAt:clock()});
    return ()=>shopping.process('owner',mutationId);
  };
  return {join,id,ref,op,engine,invite,invites,clock,advance,tick,finish,boundary,source,home,pages,shopping,context,external,oldMutationId};
}

async function active(others=0){
 const f=await fixture([]);await f.finish();for(let i=0;i<3&&(await f.op()).status!=='DONE';i++)await f.tick();assert.equal((await f.op()).phase,'ACTIVE');
 for(let i=0;i<others;i++){const uid=`other${i}`;await new HouseholdStore(db).ensure({uid});await f.home.collection('members').doc(uid).set({role:'member'});
  await db.doc(`familyMemberships/${uid}`).set({householdId:f.home.id,role:'member',state:'ACTIVE',operationId:null});await db.doc(`users/${uid}`).update({familyHouseholdId:f.home.id,activeHouseholdId:f.home.id});}
 await (await f.external(1000))();const p=privateHouseholdId('guest'),root=f.source.parent!,cap=db.doc('familyJoinCapacity/family-test');
 const refs=[f.home,cap,f.ref,db.doc(`familyInvites/${f.invite.inviteId}`),db.doc('familyInviteSlots/family-test'),db.doc('familyMemberships/owner'),f.home.collection('members').doc('owner'),db.doc('users/owner'),root.collection('members').doc('guest'),
  ...Array.from({length:others},(_,i)=>[db.doc(`familyMemberships/other${i}`),f.home.collection('members').doc(`other${i}`),db.doc(`users/other${i}`)]).flat()];
 const saved=(await db.getAll(...refs)).map(d=>[d.ref.path,d.data(),d.updateTime]);const familyItems=(await f.home.collection('shoppingItems').get()).docs.map(d=>[d.id,d.data(),d.updateTime]);
 const preserved=async()=>{assert.deepEqual((await db.getAll(...refs)).map(d=>[d.ref.path,d.data(),d.updateTime]),saved);assert.deepEqual((await f.home.collection('shoppingItems').get()).docs.map(d=>[d.id,d.data(),d.updateTime]),familyItems);};
 const leave=new MemberLeaveStore(db,f.clock),run=()=>leave.leave({uid:'guest'},f.invite.inviteId),receipt=db.doc(`familyOperations/${memberLeaveId('guest',f.invite.inviteId)}`);
 const done=async()=>{assert.equal((await db.doc('familyMemberships/guest').get()).exists,false);assert.equal((await f.home.collection('members').doc('guest').get()).exists,false);
  const u=await db.doc('users/guest').get();assert.equal(u.get('activeHouseholdId'),p);assert.equal(u.get('familyHouseholdId'),null);assert.equal(u.get('privateHouseholdId'),p);assert.equal((await root.get()).get('ownerUid'),'guest');assert.equal((await root.get()).get('operationId'),null);assert.equal((await receipt.get()).get('status'),'DONE');};
 const unchanged=async()=>{assert.equal((await db.doc('familyMemberships/guest').get()).get('state'),'ACTIVE');assert.equal((await f.home.collection('members').doc('guest').get()).get('role'),'member');assert.equal((await db.doc('users/guest').get()).get('activeHouseholdId'),f.home.id);assert.equal((await receipt.get()).exists,false);};
 const queue=async(name:string)=>{const c=await f.shopping.ensureContext({uid:'guest'}),id=newMutationId(c.epoch);await f.shopping.submit({uid:'guest'},{schemaVersion:1,actorUid:'guest',...c,mutationId:id,kind:'ADD',payloadJson:JSON.stringify({type:'ADD',name,quantity:1000,unit:'ml'}),submittedAt:f.clock()});return id;};
 return {...f,p,root,cap,leave,run,receipt,done,unchanged,preserved,queue};
}

async function setup(others=1){
 const f=await active(others),store=new MemberAccountDeletionStore(db,f.clock),auth=new FakeAuthDeletionApi(),deletion=new AccountDeletionService(db,auth,f.clock),intent=db.doc('familyMemberDeletions/guest'),marker=db.doc('accountLifecycle/guest'),job=db.doc('accountDeletions/guest');
 await f.source.doc('keep').set({name:'private',quantity:7,unit:'db',custom:'keepUntilPrivateCleanup'});
 const refs=[f.home,f.cap,f.ref,db.doc(`familyInvites/${f.invite.inviteId}`),db.doc('familyInviteSlots/family-test'),db.doc('users/owner'),db.doc('familyMemberships/owner'),f.home.collection('members').doc('owner'),...Array.from({length:others},(_,i)=>[db.doc(`users/other${i}`),db.doc(`familyMemberships/other${i}`),f.home.collection('members').doc(`other${i}`)]).flat()];
 const saved=(await db.getAll(...refs)).map(d=>[d.data(),d.updateTime]),items=(await f.home.collection('shoppingItems').get()).docs.map(d=>[d.id,d.data(),d.updateTime]);
 const preserved=async()=>{assert.deepEqual((await db.getAll(...refs)).map(d=>[d.data(),d.updateTime]),saved);assert.deepEqual((await f.home.collection('shoppingItems').get()).docs.map(d=>[d.id,d.data(),d.updateTime]),items);};
 auth.handler=async uid=>{assert.equal((await db.doc(`familyMemberships/${uid}`).get()).exists,false);assert.equal((await f.home.collection('members').doc(uid).get()).exists,false);auth.deleted.add(uid);return 'deleted';};
 const pending=async()=>{assert.equal((await marker.get()).get('state'),'ACTIVE');assert.equal((await job.get()).exists,false);assert.equal(auth.calls,0);};
 const handed=async()=>{assert.equal((await intent.get()).get('phase'),'HANDED_OFF');assert.equal((await marker.get()).get('state'),'DELETING');assert.equal((await job.get()).get('operationId'),(await intent.get()).get('deletionOperationId'));assert.equal((await db.doc('users/guest').get()).get('activeHouseholdId'),f.p);assert.equal((await db.doc('familyMemberships/guest').get()).exists,false);assert.equal(auth.calls,0);};
 const finish=async()=>{for(let n=0;n<5;n++){const r=await deletion.resume('guest',50,2);if(r==='deletionCompleted')break;f.advance();}assert.equal((await marker.get()).get('state'),'DELETED');assert.equal((await job.get()).get('stage'),'DONE');assert.equal(auth.calls,1);assert.equal((await f.root.get()).exists,false);};
 return {...f,store,auth,deletion,intent,marker,job,preserved,pending,handed,finish};
}
function wrap(run:(cb:any)=>Promise<any>){return new Proxy(db,{get(t,k){if(k==='runTransaction')return run;const v=(t as any)[k];return typeof v==='function'?v.bind(t):v;}}) as Firestore;}
test('6B1 ACTIVE member exits before private deletion and existing engine reaches DELETED',async()=>{const f=await setup(),stale=await f.queue('stale');await f.store.admit('guest');await f.pending();assert.equal(await f.store.step('guest'),'EXIT_COMPLETE');await f.pending();await f.done();assert.equal((await f.source.doc('keep').get()).get('quantity'),7);assert.equal(await f.shopping.process('guest',stale),'REJECTED_CONTEXT_CHANGED');assert.equal(await f.store.step('guest'),'HANDED_OFF');await f.handed();await f.preserved();await f.finish();await f.preserved();});
test('6B1 existing authenticated deletion gateway uses lifecycle without client routing fields',async()=>{const f=await setup(),gate=new DeletionGateway(f.deletion,()=>f.clock().toMillis());await assert.rejects(gate.begin({uid:'guest',authTimeSeconds:0},{}),/recentAuthenticationRequired/);assert.equal((await f.intent.get()).exists,false);await assert.rejects(gate.begin({uid:'guest',authTimeSeconds:f.clock().seconds},{uid:'owner'}),/invalidArgument/);const result=await gate.begin({uid:'guest',authTimeSeconds:f.clock().seconds},{});assert.ok(['deletionStarted','deletionAlreadyInProgress'].includes(result.outcome));await f.handed();});
test('6B1 repeated deletion requests retain one exit epoch and private job identity',async()=>{const f=await setup();await f.deletion.beginAccountDeletion({uid:'guest'});const epoch=(await f.root.get()).get('shoppingEpoch'),id=(await f.job.get()).get('operationId');await f.deletion.beginAccountDeletion({uid:'guest'});assert.equal((await f.root.get()).get('shoppingEpoch'),epoch);assert.equal((await f.job.get()).get('operationId'),id);await f.handed();await f.preserved();});
test('6B1 competing lifecycle workers have one membership exit and deletion job',async()=>{const f=await setup();await Promise.all([f.store.admit('guest'),f.store.admit('guest')]);for(let n=0;n<4&&(await f.intent.get()).get('phase')!=='HANDED_OFF';n++)await Promise.all([f.store.step('guest'),f.store.step('guest')]);await f.handed();assert.equal((await db.collection('familyOperations').where('kind','==','MEMBER_LEAVE').get()).size,1);await f.preserved();});
test('6B1 lost ACK after exit resumes without second epoch',async()=>{const f=await setup();await f.store.admit('guest');let lost=false;const broken=wrap(cb=>db.runTransaction(cb).then(async r=>{if(!lost&&(await f.intent.get()).get('phase')==='EXIT_COMPLETE'){lost=true;throw new Error('lostAck');}return r;}));await assert.rejects(new MemberAccountDeletionStore(broken,f.clock).step('guest'),/lostAck/);const epoch=(await f.root.get()).get('shoppingEpoch');await f.store.step('guest');assert.equal((await f.root.get()).get('shoppingEpoch'),epoch);await f.handed();});
test('6B1 lost ACK after private admission recovers existing deletion job',async()=>{const f=await setup();await f.store.admit('guest');await f.store.step('guest');const broken=wrap(async cb=>{await db.runTransaction(cb);throw new Error('lostAck');});await assert.rejects(new MemberAccountDeletionStore(db,f.clock,new LifecycleStore(broken,f.clock)).step('guest'),/lostAck/);const id=(await f.job.get()).get('operationId');assert.equal((await f.intent.get()).get('phase'),'EXIT_COMPLETE');await f.store.step('guest');await f.handed();assert.equal((await f.job.get()).get('operationId'),id);});
test('6B1 crash between exit and admission resumes through durable queue',async()=>{const f=await setup();await f.store.admit('guest');await f.store.step('guest');await f.pending();const epoch=(await f.root.get()).get('shoppingEpoch');await new MemberAccountDeletionStore(db,f.clock).sweep();await f.handed();assert.equal((await f.root.get()).get('shoppingEpoch'),epoch);});
test('6B1 forced exit transaction failure leaves ACTIVE membership and no deletion',async()=>{const f=await setup();await f.store.admit('guest');const before=(await f.root.get()).get('shoppingEpoch');const broken=wrap(cb=>db.runTransaction(async tx=>{const result=await cb(tx);if((result as any)?.outcome==='DONE')throw new Error('forced');return result;}));await assert.rejects(new MemberAccountDeletionStore(broken,f.clock).step('guest'),/forced/);await f.unchanged();await f.pending();assert.equal((await f.root.get()).get('shoppingEpoch'),before);assert.equal((await f.intent.get()).get('phase'),'WAITING_EXIT');});
for(const remove of [false,true])test(`6B1 deletion race with ${remove?'owner remove':'self leave'} reuses winning evidence`,async()=>{const f=await setup();await f.store.admit('guest');const result=await Promise.allSettled([f.store.step('guest'),remove?f.leave.remove({uid:'owner'},'guest',f.invite.inviteId):f.run()]);assert.ok(result.some(r=>r.status==='fulfilled'));const epoch=(await f.root.get()).get('shoppingEpoch');for(let n=0;n<3&&(await f.intent.get()).get('phase')!=='HANDED_OFF';n++)await f.store.step('guest');await f.handed();assert.equal((await f.root.get()).get('shoppingEpoch'),epoch);const exits=await db.collection('familyOperations').where('kind','in',['MEMBER_LEAVE','OWNER_REMOVE_MEMBER']).get();assert.equal(exits.size,1);await f.preserved();});
for(const remove of [false,true])test(`6B1 already private after ${remove?'remove':'leave'} is proven without repeat exit`,async()=>{const f=await setup();await f.store.admit('guest');if(remove)await f.leave.remove({uid:'owner'},'guest',f.invite.inviteId);else await f.run();const epoch=(await f.root.get()).get('shoppingEpoch');await f.store.step('guest');await f.pending();await f.store.step('guest');await f.handed();assert.equal((await f.root.get()).get('shoppingEpoch'),epoch);});
async function releaseByDissolution(f:Awaited<ReturnType<typeof setup>>){
 const hid=f.home.id;await new DissolutionPreparationStore(db,f.clock).prepare({uid:'owner'},hid);
 for(const [engine,phase] of [[new DissolutionPreservationStore(db,f.clock),'PRESERVATION_COMMITTED'],[new DissolutionMergeStore(db,f.clock),'PRESERVATION_MERGE_COMPLETE'],[new DissolutionSourceDispositionStore(db,f.clock),'PRESERVATION_SOURCE_CLEANED'],[new DissolutionMemberReleaseStore(db,f.clock),'NON_OWNER_RELEASE_COMPLETE']] as const){for(let n=0;n<30;n++){const result=await engine.step({uid:'owner'},hid);assert.notEqual(result,'OPERATOR');if(result===phase)break;}}
}
test('6B1 dissolution owns lock member deletion waits then proceeds after durable member release',async()=>{const f=await setup(0);await new DissolutionPreparationStore(db,f.clock).prepare({uid:'owner'},f.home.id);await f.store.admit('guest');assert.equal(await f.store.step('guest'),'WAITING_EXIT');await f.pending();assert.equal((await f.marker.get()).get('state'),'ACTIVE');await releaseByDissolution(f);assert.equal(await f.store.step('guest'),'EXIT_COMPLETE');await f.store.step('guest');await f.handed();await f.finish();assert.equal(await new DissolutionFinalizationStore(db,f.clock).step({uid:'owner'},f.home.id),'DONE');});
test('6B1 member already released by dissolution uses normal private deletion admission',async()=>{const f=await setup(0);await releaseByDissolution(f);await f.deletion.beginAccountDeletion({uid:'guest'});assert.equal((await f.intent.get()).exists,false);assert.equal((await f.marker.get()).get('state'),'DELETING');await f.finish();assert.equal(await new DissolutionFinalizationStore(db,f.clock).step({uid:'owner'},f.home.id),'DONE');});
test('6B1 ACTIVE owner and historical dissolved owner remain guarded',async()=>{const f=await setup();await assert.rejects(f.deletion.beginAccountDeletion({uid:'owner'}),/FAMILY_LIFECYCLE_NOT_READY/);assert.equal((await db.doc('familyMemberDeletions/owner').get()).exists,false);assert.equal((await db.doc('accountDeletions/owner').get()).exists,false);await db.doc('familyMemberships/owner').delete();await f.home.update({state:'DISSOLVED'});await assert.rejects(f.deletion.beginAccountDeletion({uid:'owner'}),/FAMILY_LIFECYCLE_NOT_READY/);});
test('6B1 committed JOIN remains guarded and can complete before member deletion',async()=>{const f=await fixture([]),auth=new FakeAuthDeletionApi(),service=new AccountDeletionService(db,auth,f.clock);await assert.rejects(service.beginAccountDeletion({uid:'guest'}),/JOIN_COMMITTED_IN_PROGRESS/);assert.equal((await db.doc('accountDeletions/guest').get()).exists,false);assert.equal((await f.op()).phase,'COMMITTED_TRANSFER');await f.finish();for(let n=0;n<5&&(await f.op()).status!=='DONE';n++)await f.tick();await service.beginAccountDeletion({uid:'guest'});assert.equal((await db.doc('familyMemberDeletions/guest').get()).get('phase'),'HANDED_OFF');assert.equal(auth.calls,0);});
for(const kind of ['missingFallback','wrongFallbackOwner','activePointer','reverseMismatch','corruptReceipt'])test(`6B1 integrity ${kind} cannot start private deletion`,async()=>{const f=await setup();await f.store.admit('guest');if(kind==='missingFallback')await f.root.delete();if(kind==='wrongFallbackOwner')await f.root.update({ownerUid:'other'});if(kind==='activePointer')await db.doc('users/guest').update({activeHouseholdId:'wrong'});if(kind==='reverseMismatch')await db.doc('familyMemberships/guest').update({householdId:'other'});if(kind==='corruptReceipt'){await f.run();await f.receipt.update({phase:'wrong'});}assert.equal(await f.store.step('guest'),'OPERATOR');await f.pending();});
test('6B1 no Auth call before Family exit even when finalize endpoint is retried',async()=>{const f=await setup();await f.store.admit('guest');assert.equal(await f.deletion.finalizeContent({uid:'guest'}),'cleanupRetryRequired');assert.equal(authCount(f),0);await f.unchanged();await f.pending();});
function authCount(f:Awaited<ReturnType<typeof setup>>){return f.auth.calls;}

import {FamilyCreateStore} from '../src/households/family-create';
test('6B1 pending deletion prevents new JOIN or CREATE in private handoff gap',async()=>{const f=await setup();await f.store.admit('guest');await f.store.step('guest');const invite=await f.invites.create({uid:'owner'});await assert.rejects(f.join.reserve({uid:'guest'},invite.token,'ADD'),/ACCOUNT_UNAVAILABLE/);await db.doc('familyRuntime/config').update({creationEnabled:true});await db.doc('users/guest/entitlementGrants/pro').set(grant());await assert.rejects(new FamilyCreateStore(db,f.clock).reserve({uid:'guest'}),/accountUnavailable/);await f.store.step('guest');await f.handed();});
test('6B1 historical owner who is now member remains guarded without exiting',async()=>{const f=await setup();await db.doc('households/retired-family').set({kind:'family',state:'DISSOLVED',ownerUid:'guest'});await assert.rejects(f.deletion.beginAccountDeletion({uid:'guest'}),/FAMILY_LIFECYCLE_NOT_READY/);await f.unchanged();await f.pending();assert.equal((await f.intent.get()).exists,false);});
