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
import { MemberAccountDeletionStore } from '../src/households/member-account-deletion';
requireLocalEmulator(process.env);
const app=initializeApp({projectId:'demo-kuktam-local'},'family-rejoin'),db=getFirestore(app);
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


async function ready(){const f=await fixture([milk()]);await f.finish();for(let n=0;n<10&&(await f.op()).status!=='DONE';n++)await f.tick();assert.equal((await f.op()).status,'DONE');return f;}
async function complete(f:Awaited<ReturnType<typeof ready>>,id:string,inviteId:string){
 const engine=new JoinTransferStore(db,f.clock);await f.join.resume(id);await engine.prepare({uid:'guest'},id,inviteId);
 for(let n=0;n<45;n++){
  const o=readJoinOperation((await db.doc(`familyOperations/${id}`).get()).data(),id);
  if(o.status==='DONE')return o;
  assert.equal(o.status,'READY');
  if(o.mode==='DELETE'&&o.phase==='SOURCE_FENCED_WAITING_CONFIRMATION'){
   const v=await engine.state({uid:'guest'},id,inviteId);
   await engine.confirm({uid:'guest'},{operationId:id,inviteId,sourceEpoch:v.sourceEpoch!,snapshotHash:v.snapshotHash!,sourceItemCount:v.sourceItemCount!,consentVersion:1});
  }
  f.advance();await f.join.resume(id);
 }
 throw new Error('joinDidNotFinish');
}
for(const removal of [false,true])for(const mode of ['ADD','DELETE'] as const)test(`7D0A real ${removal?'remove':'leave'} A to B ${mode} then C`,async()=>{
 const f=await ready(),exit=new MemberLeaveStore(db,f.clock),a=await f.ref.get();
 const b=await f.invites.create({uid:'owner'});await assert.rejects(f.join.reserve({uid:'guest'},b.token,mode),/ALREADY_IN_FAMILY/);
 const oldContext=await f.shopping.ensureContext({uid:'guest'}),oldRequest=newMutationId(oldContext.epoch);
 await f.shopping.submit({uid:'guest'},{schemaVersion:1,actorUid:'guest',...oldContext,mutationId:oldRequest,kind:'ADD',payloadJson:JSON.stringify({type:'ADD',name:'Stale A',quantity:1,unit:'db'}),submittedAt:f.clock()});
 assert.equal(await f.join.reserve({uid:'guest'},f.invite.token,'ADD'),f.id); // active same-JOIN retry
 const leaveA=()=>removal?exit.remove({uid:'owner'},'guest',f.invite.inviteId):exit.leave({uid:'guest'},f.invite.inviteId);
 assert.equal((await leaveA()).outcome,'DONE');
 assert.equal((await db.doc('users/guest').get()).get('activeHouseholdId'),privateHouseholdId('guest'));
 await assert.rejects(f.join.reserve({uid:'guest'},f.invite.token,'ADD'),/USED/);
 await f.source.doc('new-private').set({...milk(2,'l'),isChecked:false,createdAt:now});
 const ids=await Promise.all([f.join.reserve({uid:'guest'},b.token,mode),f.join.reserve({uid:'guest'},b.token,mode)]);
 const id=ids[0]!;assert.equal(ids[1],id);assert.notEqual(id,f.id);
 assert.equal(await f.join.reserve({uid:'guest'},b.token,mode),id); // lost admission ACK
 const c=await f.invites.create({uid:'owner'});await assert.rejects(f.join.reserve({uid:'guest'},c.token,'ADD'),/IN_PROGRESS|ALREADY_IN_FAMILY/);
 await assert.rejects(leaveA(),/STALE_MEMBERSHIP/);
 await Promise.all([f.join.reserve({uid:'guest'},b.token,mode),assert.rejects(f.join.reserve({uid:'guest'},f.invite.token,'ADD'),/USED|IN_PROGRESS/)]);
 const current=await complete(f,id,b.inviteId);assert.equal(current.inviteId,b.inviteId);
 const activatedEpoch=(await f.home.get()).get('shoppingEpoch');assert.notEqual(activatedEpoch,oldContext.epoch);
 assert.equal(await f.shopping.process('guest',oldRequest),'REJECTED_CONTEXT_CHANGED');
 assert.equal((await f.shopping.ensureContext({uid:'guest'})).epoch,activatedEpoch);
 assert.equal(await f.join.reserve({uid:'guest'},b.token,mode),id);
 assert.equal(await f.join.resume(f.id),'DONE');
 assert.equal((await f.home.get()).get('shoppingEpoch'),activatedEpoch);
 assert.deepEqual((await f.ref.get()).data(),a.data());assert.ok((await f.ref.get()).updateTime!.isEqual(a.updateTime!));
 assert.equal((await db.doc(`familyInvites/${f.invite.inviteId}`).get()).get('status'),'USED');
 assert.equal((await db.doc(`familyInvites/${b.inviteId}`).get()).get('status'),'USED');
 assert.deepEqual((await db.doc('users/guest').get()).get('familyJoinBinding'),{operationId:id,inviteId:b.inviteId});
 await assert.rejects(exit.leave({uid:'guest'},f.invite.inviteId),/STALE_MEMBERSHIP/);
 await assert.rejects(exit.remove({uid:'owner'},'guest',f.invite.inviteId),/STALE_MEMBERSHIP/);
 const list=await f.home.collection('shoppingItems').get();assert.equal(list.size,1);assert.equal(list.docs[0]!.get('quantity'),mode==='ADD'?2300:300);
 assert.equal((await f.source.get()).size,0);assert.equal((await f.home.collection('members').get()).size,2);
 const cap=await db.doc('familyJoinCapacity/family-test').get();assert.deepEqual(cap.get('operationIds'),[]);assert.equal(cap.get('structuralOperationId'),null);
 const leaveB=()=>removal?exit.remove({uid:'owner'},'guest',b.inviteId):exit.leave({uid:'guest'},b.inviteId);
 assert.equal((await leaveB()).outcome,'DONE');assert.equal((await leaveB()).outcome,'DONE');
 const cId=await f.join.reserve({uid:'guest'},c.token,'ADD');assert.notEqual(cId,id);await complete(f,cId,c.inviteId);
 assert.equal((await db.doc(`familyOperations/${id}`).get()).get('status'),'DONE');
 assert.equal((await db.doc(`familyOperations/${cId}`).get()).get('status'),'DONE');
});

test('7D0A member deletion admission resolves B, preserving existing exit engine',async()=>{
 const f=await ready();await new MemberLeaveStore(db,f.clock).leave({uid:'guest'},f.invite.inviteId);
 const b=await f.invites.create({uid:'owner'}),id=await f.join.reserve({uid:'guest'},b.token,'ADD');await complete(f,id,b.inviteId);
 const deletion=new MemberAccountDeletionStore(db,f.clock),intent=await deletion.admit('guest');
 assert.equal(intent?.joinOperationId,id);assert.equal(intent?.inviteId,b.inviteId);
 assert.equal((await db.doc('accountLifecycle/guest').get()).get('state'),'ACTIVE');
 assert.equal((await db.doc('accountDeletions/guest').get()).exists,false);
});

test('7D0A corrupt current binding and surviving prior member cannot admit B',async()=>{
 const f=await ready(),user=db.doc('users/guest');
 await user.update({'familyJoinBinding.inviteId':'f'.repeat(64)});
 const b=await f.invites.create({uid:'owner'});
 await assert.rejects(f.join.reserve({uid:'guest'},b.token,'ADD'),/INVITE_STATE_UNAVAILABLE/);
 await user.update({'familyJoinBinding.inviteId':f.invite.inviteId});
 await new MemberLeaveStore(db,f.clock).leave({uid:'guest'},f.invite.inviteId);
 await f.home.collection('members').doc('guest').set({role:'member'});
 await assert.rejects(f.join.reserve({uid:'guest'},b.token,'ADD'),/INVITE_STATE_UNAVAILABLE/);
 assert.equal((await db.doc(`familyInvites/${b.inviteId}`).get()).get('status'),'PENDING');
});
test('7D0A legacy no-pointer user leaves and joins different Family without migration',async()=>{
 const f=await ready();const {FieldValue}=await import('firebase-admin/firestore');await db.doc('users/guest').update({familyJoinBinding:FieldValue.delete()});
 const exit=new MemberLeaveStore(db,f.clock);await exit.leave({uid:'guest'},f.invite.inviteId);
 await new HouseholdStore(db).ensure({uid:'owner2'});await db.doc('users/owner2/entitlementGrants/pro').set(grant());
 await db.doc('households/family-second').set({schemaVersion:2,kind:'family',state:'ACTIVE',operationId:null,ownerUid:'owner2',createdAt:now});
 await db.doc('households/family-second/members/owner2').set({role:'owner'});
 await db.doc('familyMemberships/owner2').set({householdId:'family-second',role:'owner',state:'ACTIVE',operationId:null});
 await db.doc('users/owner2').update({activeHouseholdId:'family-second',familyHouseholdId:'family-second'});
 const b=await f.invites.create({uid:'owner2'}),id=await f.join.reserve({uid:'guest'},b.token,'ADD');await complete(f,id,b.inviteId);
 assert.equal((await db.doc('users/guest').get()).get('activeHouseholdId'),'family-second');
 await assert.rejects(exit.remove({uid:'owner'},'guest',f.invite.inviteId),/WRONG_FAMILY|STALE_MEMBERSHIP/);
 assert.equal((await exit.remove({uid:'owner2'},'guest',b.inviteId)).outcome,'DONE');
});
test('7D0A B committed restart and lost completion ACK preserve DELETE consent boundary',async()=>{
 const f=await ready(),exit=new MemberLeaveStore(db,f.clock);await exit.leave({uid:'guest'},f.invite.inviteId);
 const b=await f.invites.create({uid:'owner'}),id=await f.join.reserve({uid:'guest'},b.token,'DELETE'),engine=new JoinTransferStore(db,f.clock);
 await f.join.resume(id);await engine.prepare({uid:'guest'},id,b.inviteId);
 for(let n=0;n<10;n++){const v=await engine.state({uid:'guest'},id,b.inviteId);if(v.phase==='SOURCE_FENCED_WAITING_CONFIRMATION')break;f.advance();await f.join.resume(id);}
 f.advance();await f.join.resume(id);const v=await engine.state({uid:'guest'},id,b.inviteId);assert.equal(v.committedAt,null);assert.equal(v.sourceItemCount,0);
 const consent={operationId:id,inviteId:b.inviteId,sourceEpoch:v.sourceEpoch!,snapshotHash:v.snapshotHash!,sourceItemCount:0,consentVersion:1};
 const original=db.runTransaction.bind(db);
 const lost=new Proxy(db,{get(t,k){if(k==='runTransaction')return async(...args:any[])=>{await (original as any)(...args);throw new Error('lostCommitAck');};const value=(t as any)[k];return typeof value==='function'?value.bind(t):value;}}) as Firestore;
 await assert.rejects(new JoinTransferStore(lost,f.clock).confirm({uid:'guest'},consent),/lostCommitAck/);
 assert.equal(await engine.confirm({uid:'guest'},consent),'COMMITTED_TRANSFER');
 assert.equal(await engine.cancel({uid:'guest'},id,b.inviteId),'IN_PROGRESS');
 await complete(f,id,b.inviteId);assert.equal(await new FamilyJoinStore(db,f.clock).resume(id),'DONE');
 assert.equal(await f.join.reserve({uid:'guest'},b.token,'DELETE'),id);
});

