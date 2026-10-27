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
import { MemberLeaveStore, memberLeaveId, ownerRemoveId } from '../src/households/member-leave';
import { ownerRemoveHandler } from '../src/households/member-leave-handler';
requireLocalEmulator(process.env);
const app=initializeApp({projectId:'demo-kuktam-local'},'family-owner-remove'),db=getFirestore(app);
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
 const leave=new MemberLeaveStore(db,f.clock),run=()=>leave.remove({uid:'owner'},'guest',f.invite.inviteId),receipt=db.doc(`familyOperations/${ownerRemoveId('owner','guest',f.invite.inviteId)}`);
 const done=async()=>{assert.equal((await db.doc('familyMemberships/guest').get()).exists,false);assert.equal((await f.home.collection('members').doc('guest').get()).exists,false);
  const u=await db.doc('users/guest').get();assert.equal(u.get('activeHouseholdId'),p);assert.equal(u.get('familyHouseholdId'),null);assert.equal(u.get('privateHouseholdId'),p);assert.equal((await root.get()).get('ownerUid'),'guest');assert.equal((await root.get()).get('operationId'),null);assert.equal((await receipt.get()).get('status'),'DONE');};
 const unchanged=async()=>{assert.equal((await db.doc('familyMemberships/guest').get()).get('state'),'ACTIVE');assert.equal((await f.home.collection('members').doc('guest').get()).get('role'),'member');assert.equal((await db.doc('users/guest').get()).get('activeHouseholdId'),f.home.id);assert.equal((await receipt.get()).exists,false);};
 const queue=async(name:string)=>{const c=await f.shopping.ensureContext({uid:'guest'}),id=newMutationId(c.epoch);await f.shopping.submit({uid:'guest'},{schemaVersion:1,actorUid:'guest',...c,mutationId:id,kind:'ADD',payloadJson:JSON.stringify({type:'ADD',name,quantity:1000,unit:'ml'}),submittedAt:f.clock()});return id;};
 return {...f,p,root,cap,leave,run,receipt,done,unchanged,preserved,queue};
}
for(const others of [0,2])test(`5B owner removes member with ${others} others preserves family and own fallback`,async()=>{
 const f=await active(others),before=await f.root.get();assert.equal((await f.run()).outcome,'DONE');await f.done();await f.preserved();assert.notEqual((await f.root.get()).get('shoppingEpoch'),before.get('shoppingEpoch'));assert.equal((await f.source.get()).size,0);assert.equal((await f.home.collection('members').get()).size,others+1);
});
test('5B owner cannot remove self or dissolve family',async()=>{const f=await active();await assert.rejects(f.leave.remove({uid:'owner'},'owner',f.invite.inviteId),/OWNER_CANNOT_REMOVE_SELF/);await f.unchanged();await f.preserved();});
test('5B delayed accepted family mutation is rejected and never retargeted',async()=>{const f=await active(),id=await f.queue('Delayed');await f.run();assert.equal(await f.shopping.process('guest',id),'REJECTED_CONTEXT_CHANGED');assert.equal((await f.source.get()).size,0);await f.done();await f.preserved();});
test('5B fresh normal ADD routes private without changing family',async()=>{const f=await active();await f.run();assert.equal((await f.shopping.ensureContext({uid:'guest'})).householdId,f.p);assert.equal(await f.shopping.process('guest',await f.queue('Private')),'APPLIED');assert.equal((await f.source.get()).size,1);await f.preserved();});
test('5B existing fallback content is preserved; no shopping copy',async()=>{const f=await active(),item=f.source.doc('existing');await item.set(milk());const before=await item.get();await f.run();await f.done();assert.ok((await item.get()).updateTime!.isEqual(before.updateTime!));await f.preserved();});
test('5B duplicate removal returns same evidence without second epoch or capacity change',async()=>{const f=await active(),a=await f.run(),root=await f.root.get(),receipt=await f.receipt.get();for(let i=0;i<3;i++)assert.deepEqual(await f.run(),a);assert.ok((await f.root.get()).updateTime!.isEqual(root.updateTime!));assert.ok((await f.receipt.get()).updateTime!.isEqual(receipt.updateTime!));await f.done();await f.preserved();});
test('5B lost acknowledgement recovers durable completion',async()=>{
 const f=await active(),original=db.runTransaction.bind(db);const wrapped=new Proxy(db,{get(t,k){if(k==='runTransaction')return async(...a:any[])=>{await (original as any)(...a);throw new Error('lostAck');};const v=(t as any)[k];return typeof v==='function'?v.bind(t):v;}}) as Firestore;
 await assert.rejects(new MemberLeaveStore(wrapped,f.clock).remove({uid:'owner'},'guest',f.invite.inviteId),/lostAck/);const root=await f.root.get();assert.equal((await f.run()).outcome,'DONE');assert.ok((await f.root.get()).updateTime!.isEqual(root.updateTime!));await f.done();await f.preserved();
});
test('5B competing removal requests commit one logical effect',async()=>{const f=await active(),r=await Promise.all([f.run(),f.run()]);assert.deepEqual(r[0],r[1]);assert.equal((await db.collection('familyOperations').where('kind','==','OWNER_REMOVE_MEMBER').get()).size,1);await f.done();await f.preserved();});
test('5B forced transaction failure leaves no partial removal',async()=>{
 const f=await active(),root=await f.root.get(),original=db.runTransaction.bind(db);const wrapped=new Proxy(db,{get(t,k){if(k==='runTransaction')return (cb:any)=>original(async tx=>{await cb(tx);throw Object.assign(new Error('forcedAbort'),{code:10});},{maxAttempts:1});const v=(t as any)[k];return typeof v==='function'?v.bind(t):v;}}) as Firestore;
 await assert.rejects(new MemberLeaveStore(wrapped,f.clock).remove({uid:'owner'},'guest',f.invite.inviteId),/forcedAbort/);await f.unchanged();await f.preserved();assert.ok((await f.root.get()).updateTime!.isEqual(root.updateTime!));await f.run();await f.done();
});
test('5B full capacity frees one slot for a later reservation, never twice',async()=>{
 const f=await active(6);await new HouseholdStore(db).ensure({uid:'newcomer'});const {newInviteToken,hashInviteToken,INVITE_SECONDS}=await import('../src/households/invite-contract');const token=newInviteToken(),id=hashInviteToken(token);
 // Existing pending invite fixture; creation itself is correctly denied at capacity.
 await db.doc(`familyInvites/${id}`).set({schemaVersion:1,householdId:f.home.id,createdByUid:'owner',createdAt:f.clock(),expiresAt:Timestamp.fromMillis(f.clock().toMillis()+INVITE_SECONDS*1000),status:'PENDING',operationId:null,usedAt:null,usedByUid:null});await db.doc('familyInviteSlots/family-test').update({inviteIds:[id]});
 const join=new FamilyJoinStore(db,f.clock);await assert.rejects(join.reserve({uid:'newcomer'},token,'ADD'),/FAMILY_FULL/);await f.run();await f.run();assert.equal((await f.home.collection('members').get()).size,7);const reservation=await join.reserve({uid:'newcomer'},token,'ADD');assert.deepEqual((await f.cap.get()).get('operationIds'),[reservation]);assert.equal((await f.home.collection('members').get()).size+(await f.cap.get()).get('operationIds').length,8);await f.done();
});
test('5B other pending invite/reservation stays unchanged',async()=>{const f=await active();await new HouseholdStore(db).ensure({uid:'newcomer'});const inv=await f.invites.create({uid:'owner'}),id=await f.join.reserve({uid:'newcomer'},inv.token,'ADD');const refs=[f.cap,db.doc('familyInviteSlots/family-test'),db.doc(`familyInvites/${inv.inviteId}`),db.doc(`familyOperations/${id}`),db.doc('familyMemberships/newcomer')];const before=(await db.getAll(...refs)).map(d=>[d.data(),d.updateTime]);await f.run();assert.deepEqual((await db.getAll(...refs)).map(d=>[d.data(),d.updateTime]),before);await f.done();});
test('5B private account deletion admission resumes without Phase6 implementation',async()=>{const f=await active(),s=new LifecycleStore(db,f.clock);await assert.rejects(s.beginDeletion('guest'),/FAMILY_LIFECYCLE_NOT_READY/);await f.run();assert.equal((await s.beginDeletion('guest')).outcome,'deletionStarted');assert.equal((await db.doc('accountLifecycle/guest').get()).get('state'),'DELETING');assert.ok((await db.doc('accountDeletions/guest').get()).exists);await f.preserved();});
for(const kind of ['membershipHousehold','activePointer','missingFallback','wrongFallbackOwner','fallbackFence','missingMember','wrongRole','targetOwner','join','invite','capacity','DELETING','DELETED','deletionJob'])test(`5B integrity ${kind} never partially removes`,async()=>{
 const f=await active();
 if(kind==='membershipHousehold')await db.doc('familyMemberships/guest').update({householdId:'other'});
 if(kind==='activePointer')await db.doc('users/guest').update({activeHouseholdId:'other'});
 if(kind==='missingFallback')await f.root.delete();
 if(kind==='wrongFallbackOwner')await f.root.update({ownerUid:'other'});
 if(kind==='fallbackFence')await f.root.update({operationId:'other'});
 if(kind==='missingMember')await f.home.collection('members').doc('guest').delete();
 if(kind==='wrongRole')await f.home.collection('members').doc('guest').update({role:'owner'});
 if(kind==='targetOwner')await f.home.update({ownerUid:'guest'});
 if(kind==='join')await f.ref.update({householdId:'other'});
 if(kind==='invite')await db.doc(`familyInvites/${f.invite.inviteId}`).update({usedByUid:'other'});
 if(kind==='capacity')await f.cap.update({operationIds:[f.id]});
 if(kind==='deletionJob')await db.doc('accountDeletions/guest').set({testOnly:true});
 if(kind==='DELETING'||kind==='DELETED')await db.doc('accountLifecycle/guest').update({state:kind,deletionStartedAt:f.clock(),deletedAt:kind==='DELETED'?f.clock():null,updatedAt:f.clock()});
 const refs=[db.doc('familyMemberships/guest'),db.doc('users/guest'),f.root,f.home,f.home.collection('members').doc('guest'),f.cap],before=(await db.getAll(...refs)).map(d=>[d.data(),d.updateTime]);
 await assert.rejects(f.run(),kind==='membershipHousehold'?/WRONG_FAMILY/:/INTEGRITY_REQUIRES_OPERATOR|ACCOUNT_UNAVAILABLE|OWNER_CANNOT_LEAVE/);assert.deepEqual((await db.getAll(...refs)).map(d=>[d.data(),d.updateTime]),before);assert.equal((await f.receipt.get()).exists,false);
});
test('5B foreign structural lock is never stolen by expired lease takeover',async()=>{const f=await active(),id='join_'+'a'.repeat(64);await f.cap.update({operationIds:[id],structuralOperationId:id});await db.doc(`familyOperations/${id}`).set({leaseUntil:Timestamp.fromMillis(1)});const before=await f.cap.get();await assert.rejects(f.run(),/IN_PROGRESS/);assert.ok((await f.cap.get()).updateTime!.isEqual(before.updateTime!));await f.unchanged();});
test('5B JOIN incarnation binding prevents stale request affecting a future membership',async()=>{const f=await active();await assert.rejects(f.leave.remove({uid:'owner'},'guest','a'.repeat(64)),/STALE_MEMBERSHIP/);await f.unchanged();const result=await f.run();
 // Future relationship fixture only; no re-JOIN feature is implemented here.
 await db.doc('familyMemberships/guest').set({householdId:'future-family',role:'member',state:'ACTIVE',operationId:null});await db.doc('users/guest').update({familyHouseholdId:'future-family',activeHouseholdId:'future-family'});const before=await db.doc('familyMemberships/guest').get();await assert.rejects(f.run(),/STALE_MEMBERSHIP/);assert.ok((await before.ref.get()).updateTime!.isEqual(before.updateTime!));assert.equal((await db.doc('users/guest').get()).get('activeHouseholdId'),'future-family');});
test('5B corrupt completion receipt fails closed',async()=>{const f=await active();await f.run();await f.receipt.update({actorUid:'other'});await assert.rejects(f.run(),/INTEGRITY_REQUIRES_OPERATOR/);await f.preserved();});
test('5B deployed/non-demo runtime cannot execute removal',async()=>{const f=await active(),project=process.env.GCLOUD_PROJECT,service=process.env.K_SERVICE;try{process.env.GCLOUD_PROJECT='not-demo';await assert.rejects(f.run(),/FEATURE_DISABLED/);process.env.GCLOUD_PROJECT=project;process.env.K_SERVICE='deployed';await assert.rejects(f.run(),/FEATURE_DISABLED/);}finally{process.env.GCLOUD_PROJECT=project;if(service===undefined)delete process.env.K_SERVICE;else process.env.K_SERVICE=service;}await f.unchanged();});
test('5B callable authenticates owner and accepts no household or actor override',async()=>{
 let calls=0;const handler=ownerRemoveHandler(()=>{calls++;throw new Error('internal secret');});
 await assert.rejects(handler({data:{targetUid:'guest',inviteId:'a'.repeat(64)}}),(e:any)=>e.code==='unauthenticated');
 for(const data of [null,{},[],{targetUid:'guest',inviteId:'bad'},{targetUid:'a/b',inviteId:'a'.repeat(64)},{targetUid:'guest',inviteId:'a'.repeat(64),uid:'owner'},{targetUid:'guest',inviteId:'a'.repeat(64),householdId:'other'}])
  await assert.rejects(handler({auth:{uid:'owner'},data}),(e:any)=>e.code==='invalid-argument');
 assert.equal(calls,0);await assert.rejects(handler({auth:{uid:'owner'},data:{targetUid:'guest',inviteId:'a'.repeat(64)}}),(e:any)=>e.code==='unavailable'&&e.message==='RETRYABLE_UNAVAILABLE');
 const f=await active();assert.equal((await ownerRemoveHandler(()=>f.leave)({auth:{uid:'owner'},data:{targetUid:'guest',inviteId:f.invite.inviteId}})).outcome,'DONE');await f.done();
});

test('5B nonmember and RESERVED target cannot be removed',async()=>{
 const f=await active();await new HouseholdStore(db).ensure({uid:'standalone'});await assert.rejects(f.leave.remove({uid:'owner'},'standalone',f.invite.inviteId),/NOT_ACTIVE_MEMBER/);
 await db.doc('familyMemberships/guest').update({state:'RESERVED',operationId:f.id});const before=await db.doc('users/guest').get();await assert.rejects(f.run(),/IN_PROGRESS/);assert.ok((await before.ref.get()).updateTime!.isEqual(before.updateTime!));assert.equal((await f.receipt.get()).exists,false);
});
test('5B historical DONE JOIN reentry never resurrects departed membership',async()=>{const f=await active();await f.run();assert.equal(await f.join.resume(f.id),'DONE');await f.done();await f.preserved();});

test('5B ordinary member cannot remove another member',async()=>{const f=await active(1);await assert.rejects(f.leave.remove({uid:'other0'},'guest',f.invite.inviteId),/NOT_OWNER/);await f.unchanged();await f.preserved();});

test('5B owner of another family cannot redirect target removal',async()=>{
 const f=await active();await new HouseholdStore(db).ensure({uid:'owner2'});
 await db.doc('households/second-family').set({schemaVersion:2,kind:'family',state:'ACTIVE',operationId:null,ownerUid:'owner2',createdAt:now});
 await db.doc('households/second-family/members/owner2').set({role:'owner'});
 await db.doc('familyMemberships/owner2').set({householdId:'second-family',role:'owner',state:'ACTIVE',operationId:null});
 await db.doc('users/owner2').update({activeHouseholdId:'second-family',familyHouseholdId:'second-family'});
 await assert.rejects(f.leave.remove({uid:'owner2'},'guest',f.invite.inviteId),/WRONG_FAMILY/);await f.unchanged();await f.preserved();
});

for(const kind of ['DELETING','deletionJob','wrongOwnerRole'])test(`5B invalid caller ${kind} cannot remove target`,async()=>{
 const f=await active();
 if(kind==='DELETING')await db.doc('accountLifecycle/owner').update({state:'DELETING',deletionStartedAt:f.clock(),updatedAt:f.clock()});
 if(kind==='deletionJob')await db.doc('accountDeletions/owner').set({testOnly:true});
 if(kind==='wrongOwnerRole')await db.doc('familyMemberships/owner').update({role:'member'});
 await assert.rejects(f.run(),/ACCOUNT_UNAVAILABLE|INTEGRITY_REQUIRES_OPERATOR|NOT_OWNER/);await f.unchanged();
});

for(const winner of ['leave','remove','race'])test(`5B self-leave/remove serialization ${winner}`,async()=>{
 const f=await active(),leave=()=>f.leave.leave({uid:'guest'},f.invite.inviteId),remove=f.run;
 let results:PromiseSettledResult<unknown>[];
 if(winner==='race')results=await Promise.allSettled([leave(),remove()]);
 else {const first=winner==='leave'?leave:remove,second=winner==='leave'?remove:leave;
  results=[{status:'fulfilled',value:await first()},...(await Promise.allSettled([second()]))];}
 assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
 const rejected=results.find(r=>r.status==='rejected') as PromiseRejectedResult;assert.match(rejected.reason.message,/NOT_ACTIVE_MEMBER/);
 const leaveDoc=await db.doc(`familyOperations/${memberLeaveId('guest',f.invite.inviteId)}`).get(),removeDoc=await f.receipt.get();
 assert.equal(Number(leaveDoc.exists)+Number(removeDoc.exists),1);
 assert.equal((await db.doc('users/guest').get()).get('activeHouseholdId'),f.p);
 assert.equal((await db.doc('familyMemberships/guest').get()).exists,false);assert.equal((await f.home.collection('members').get()).size,1);
 const before=await f.root.get();await (leaveDoc.exists?leave():remove());await assert.rejects(leaveDoc.exists?remove():leave(),/NOT_ACTIVE_MEMBER/);
 assert.ok((await f.root.get()).updateTime!.isEqual(before.updateTime!));await f.preserved();
});

test('5B historical remove receipt is bound to authenticated actor',async()=>{const f=await active(1);await f.run();await assert.rejects(f.leave.remove({uid:'other0'},'guest',f.invite.inviteId),/NOT_OWNER/);await f.done();await f.preserved();});
