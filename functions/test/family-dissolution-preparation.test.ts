import { DissolutionPreparationStore, dissolutionId, readDissolutionPreparation } from '../src/households/dissolution-preparation';
import { dissolutionPreparationHandler } from '../src/households/dissolution-preparation-handler';
import { readJoinCapacity } from '../src/households/join-capacity';
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
const app=initializeApp({projectId:'demo-kuktam-local'},'family-dissolution-preparation'),db=getFirestore(app);
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

async function database(){const out:Record<string,unknown>={};async function walk(c:FirebaseFirestore.CollectionReference){for(const d of (await c.get()).docs){out[d.ref.path]=[d.data(),d.updateTime];for(const sub of await d.ref.listCollections())await walk(sub);}}for(const c of await db.listCollections())await walk(c);return out;}
async function preparedFixture(count=2){
 const f=await active(Math.max(0,count-2));if(count===1)await f.leave.leave({uid:'guest'},f.invite.inviteId);
 const users=(await f.home.collection('members').get()).docs.map(d=>d.id);
 for(const u of users)await db.doc(`households/${privateHouseholdId(u)}/shoppingItems/preserved`).set(milk(17));
 const preparation=new DissolutionPreparationStore(db,f.clock),id=dissolutionId('owner',f.home.id),ref=db.doc(`familyOperations/${id}`),run=()=>preparation.prepare({uid:'owner'},f.home.id);
 const op=async()=>readDissolutionPreparation((await ref.get()).data(),id),before=await database();
 const unchanged=async()=>assert.deepEqual(await database(),before);
 const boundary=async()=>{const after=await database(),expected={...before};delete after[ref.path];delete after[f.cap.path];delete expected[f.cap.path];assert.deepEqual(after,expected);
  const o=await op();assert.equal(o.phase,'PREPARED');assert.equal(o.status,'READY');assert.equal(o.nextAt,null);assert.equal((await f.cap.get()).get('structuralOperationId'),id);};
 return {...f,users,preparation,id,ref,run,op,boundary,unchanged};
}
for(const count of [1,2,4,8])test(`5C1 exact immutable participant snapshot ${count}`,async()=>{
 const f=await preparedFixture(count),result=await f.run(),o=await f.op();assert.equal(result.participantCount,count);assert.equal(o.participantCount,count);
 assert.deepEqual(o.participants.map(p=>p.uid),[...f.users].sort());
 for(const p of o.participants){assert.equal(p.privateHouseholdId,privateHouseholdId(p.uid));assert.equal(p.activeHouseholdId,f.home.id);assert.equal(p.role,p.uid==='owner'?'owner':'member');}
 await f.boundary();const saved=await database();assert.deepEqual(await f.run(),result);assert.deepEqual(await database(),saved);
});
test('5C1 non-owner and wrong-family request denied',async()=>{const f=await preparedFixture();await assert.rejects(f.preparation.prepare({uid:'guest'},f.home.id),/NOT_OWNER/);await assert.rejects(f.preparation.prepare({uid:'owner'},'another-family'),/WRONG_FAMILY/);await f.unchanged();});
for(const kind of ['missingFallback','wrongFallbackOwner','wrongFallbackPointer','memberPointer','reverseRole','missingReverse','orphanReverse','ownerMismatch','ownerIndex','lifecycle','deletionJob'])test(`5C1 integrity ${kind} is atomic`,async()=>{
 const f=await preparedFixture();
 if(kind==='missingFallback')await f.root.delete();
 if(kind==='wrongFallbackOwner')await f.root.update({ownerUid:'owner'});
 if(kind==='wrongFallbackPointer')await db.doc('users/guest').update({privateHouseholdId:privateHouseholdId('owner')});
 if(kind==='memberPointer')await db.doc('users/guest').update({activeHouseholdId:f.p});
 if(kind==='reverseRole')await db.doc('familyMemberships/guest').update({role:'owner'});
 if(kind==='missingReverse')await db.doc('familyMemberships/guest').delete();
 if(kind==='orphanReverse')await db.doc('familyMemberships/orphan').set({householdId:f.home.id,state:'ACTIVE',role:'member',operationId:null});
 if(kind==='ownerMismatch')await f.home.update({ownerUid:'guest'});
 if(kind==='ownerIndex')await db.doc('familyMemberships/owner').update({householdId:'other'});
 if(kind==='lifecycle')await db.doc('accountLifecycle/guest').update({state:'DELETING',deletionStartedAt:f.clock(),updatedAt:f.clock()});
 if(kind==='deletionJob')await db.doc('accountDeletions/guest').set({testOnly:true});
 const before=await database();await assert.rejects(f.run(),/INTEGRITY_REQUIRES_OPERATOR|ACCOUNT_UNAVAILABLE/);assert.deepEqual(await database(),before);
});
test('5C1 foreign JOIN lock never stolen',async()=>{const f=await preparedFixture(),other='join_'+'a'.repeat(64);await f.cap.set({schemaVersion:2,operationIds:[other],structuralOperationId:other});const before=await database();await assert.rejects(f.run(),/IN_PROGRESS/);assert.deepEqual(await database(),before);});
test('5C1 missing capacity supports valid owner-only family',async()=>{const f=await preparedFixture(1);await f.cap.delete();await f.run();assert.equal((await f.op()).participantCount,1);assert.deepEqual((await f.cap.get()).get('operationIds'),[]);});
test('5C1 lost ACK returns same preparation without rewriting snapshot or lock',async()=>{
 const f=await preparedFixture(),original=db.runTransaction.bind(db),wrapped=new Proxy(db,{get(t,k){if(k==='runTransaction')return async(...a:any[])=>{await (original as any)(...a);throw new Error('lostAck');};const v=(t as any)[k];return typeof v==='function'?v.bind(t):v;}}) as Firestore;
 await assert.rejects(new DissolutionPreparationStore(wrapped,f.clock).prepare({uid:'owner'},f.home.id),/lostAck/);const before=await database();assert.equal((await f.run()).phase,'PREPARED');assert.deepEqual(await database(),before);await f.boundary();
});
test('5C1 competing preparation has one operation and snapshot',async()=>{const f=await preparedFixture(),r=await Promise.all([f.run(),f.run()]);assert.deepEqual(r[0],r[1]);assert.equal((await db.collection('familyOperations').where('kind','==','FAMILY_DISSOLUTION').get()).size,1);await f.boundary();});
test('5C1 forced transaction failure leaves no orphan lock or partial snapshot',async()=>{
 const f=await preparedFixture(),original=db.runTransaction.bind(db),wrapped=new Proxy(db,{get(t,k){if(k==='runTransaction')return (cb:any)=>original(async tx=>{await cb(tx);throw Object.assign(new Error('forcedAbort'),{code:10});},{maxAttempts:1});const v=(t as any)[k];return typeof v==='function'?v.bind(t):v;}}) as Firestore;
 await assert.rejects(new DissolutionPreparationStore(wrapped,f.clock).prepare({uid:'owner'},f.home.id),/forcedAbort/);await f.unchanged();await f.run();await f.boundary();
});
test('5C1 prepared lock blocks leave/remove and deletion but permits normal family ADD',async()=>{
 const f=await preparedFixture();await f.run();const snapshot=await f.ref.get(),cap=await f.cap.get();
 await assert.rejects(f.leave.leave({uid:'guest'},f.invite.inviteId),/IN_PROGRESS/);await assert.rejects(f.leave.remove({uid:'owner'},'guest',f.invite.inviteId),/IN_PROGRESS/);
 for(const uid of ['owner','guest'])await assert.rejects(new LifecycleStore(db,f.clock).beginDeletion(uid),/JOIN_COMMITTED_IN_PROGRESS/);
 await db.doc('users/owner/entitlementGrants/pro').delete();assert.equal((await f.run()).phase,'PREPARED');
 assert.equal(await (await f.external(500))(),'APPLIED');assert.equal(await f.shopping.process('guest',await f.queue('Guest normal')),'APPLIED');
 assert.ok((await f.ref.get()).updateTime!.isEqual(snapshot.updateTime!));assert.ok((await f.cap.get()).updateTime!.isEqual(cap.updateTime!));
 for(const uid of ['owner','guest'])assert.equal((await db.doc(`users/${uid}`).get()).get('activeHouseholdId'),f.home.id);
});
for(const mode of ['leave','remove'])for(const order of ['prepare','exit','race'])test(`5C1 ${mode} race ${order}`,async()=>{
 const f=await preparedFixture(),exit=()=>mode==='leave'?f.leave.leave({uid:'guest'},f.invite.inviteId):f.leave.remove({uid:'owner'},'guest',f.invite.inviteId);
 if(order==='prepare'){await f.run();await assert.rejects(exit(),/IN_PROGRESS/);}
 if(order==='exit'){await exit();await f.run();}
 if(order==='race'){const results=await Promise.allSettled([f.run(),exit()]);assert.equal(results[0]!.status,'fulfilled');if(results[1]!.status==='rejected')assert.match(results[1].reason.message,/IN_PROGRESS/);}
 const present=(await db.doc('familyMemberships/guest').get()).exists,o=await f.op();assert.equal(o.participantCount,present?2:1);assert.equal(o.participants.some(p=>p.uid==='guest'),present);
 assert.equal((await db.doc('users/guest').get()).get('activeHouseholdId'),present?f.home.id:f.p);assert.equal((await f.cap.get()).get('structuralOperationId'),f.id);
 assert.equal((await f.home.collection('shoppingItems').get()).docs[0]!.get('quantity'),1000);
});
async function waitingJoin(f:Awaited<ReturnType<typeof preparedFixture>>){
 await new HouseholdStore(db).ensure({uid:'newcomer'});const invite=await f.invites.create({uid:'owner'}),id=await f.join.reserve({uid:'newcomer'},invite.token,'DELETE');
 await f.join.resume(id);const engine=new JoinTransferStore(db,f.clock);await engine.prepare({uid:'newcomer'},id,invite.inviteId);
 const tick=async()=>{f.advance();return f.join.resume(id);};for(let n=0;n<4;n++){const d=await db.doc(`familyOperations/${id}`).get();if(d.get('phase')==='SOURCE_FENCED_WAITING_CONFIRMATION')break;await tick();}
 const state=await engine.state({uid:'newcomer'},id,invite.inviteId),confirm=()=>engine.confirm({uid:'newcomer'},{operationId:id,inviteId:invite.inviteId,sourceEpoch:state.sourceEpoch!,snapshotHash:state.snapshotHash!,sourceItemCount:state.sourceItemCount!,consentVersion:1});
 return {id,invite,engine,tick,confirm};
}
for(const order of ['prepare','join','race'])test(`5C1 JOIN commit race ${order}`,async()=>{
 const f=await preparedFixture(),j=await waitingJoin(f);
 if(order==='prepare'){await f.run();assert.equal(await j.confirm(),'IN_PROGRESS');}
 if(order==='join'){assert.equal(await j.confirm(),'COMMITTED_TRANSFER');await assert.rejects(f.run(),/IN_PROGRESS/);}
 if(order==='race'){const results=await Promise.allSettled([f.run(),j.confirm()]);if(results[0]!.status==='rejected')assert.match(results[0].reason.message,/IN_PROGRESS/);}
 const committed=(await db.doc(`familyOperations/${j.id}`).get()).get('committedAt')!=null;
 if(committed){assert.equal((await f.ref.get()).exists,false);for(let n=0;n<5&&(await db.doc(`familyOperations/${j.id}`).get()).get('status')!=='DONE';n++)await j.tick();await f.run();assert.equal((await f.op()).participantCount,3);}
 else {assert.equal((await f.op()).participantCount,2);assert.equal(await j.confirm(),'IN_PROGRESS');assert.equal(await j.tick(),'IN_PROGRESS');assert.equal((await db.doc(`familyOperations/${j.id}`).get()).get('phase'),'SOURCE_FENCED_WAITING_CONFIRMATION');}
 assert.equal((await f.cap.get()).get('structuralOperationId'),f.id);
});
test('5C1 preserves pending reservations/invites and denies new JOIN admission',async()=>{
 const f=await preparedFixture(),j=await waitingJoin(f),refs=[db.doc(`familyOperations/${j.id}`),db.doc(`familyInvites/${j.invite.inviteId}`),db.doc('familyMemberships/newcomer')],before=(await db.getAll(...refs)).map(d=>[d.data(),d.updateTime]);
 const pending=await f.invites.create({uid:'owner'});await new HouseholdStore(db).ensure({uid:'another'});await f.run();assert.deepEqual((await db.getAll(...refs)).map(d=>[d.data(),d.updateTime]),before);
 assert.deepEqual((await f.op()).reservedJoinOperationIds,[j.id]);assert.ok((await f.op()).inviteIds.includes(pending.inviteId));await assert.rejects(f.join.reserve({uid:'another'},pending.token,'ADD'),/IN_PROGRESS/);
 assert.equal((await db.doc('familyMemberships/another').get()).exists,false);await assert.rejects(j.engine.prepare({uid:'newcomer'},j.id,j.invite.inviteId),/IN_PROGRESS/);
});
for(const damage of ['snapshot','lock','generation'])test(`5C1 corrupt prepared ${damage} cannot be silently rewritten`,async()=>{
 const f=await preparedFixture();await f.run();if(damage==='snapshot')await f.ref.update({snapshotHash:'a'.repeat(64)});if(damage==='lock')await f.cap.update({structuralOperationId:'dissolve_'+'b'.repeat(64)});if(damage==='generation')await f.home.update({createdAt:Timestamp.fromMillis(1)});
 const before=await database();await assert.rejects(f.run(),/INTEGRITY_REQUIRES_OPERATOR/);assert.deepEqual(await database(),before);
});
test('5C1 callable denies arbitrary routing and local-only runtime stays guarded',async()=>{
 let calls=0;const h=dissolutionPreparationHandler(()=>{calls++;throw new Error('secret');});await assert.rejects(h({data:{householdId:'family-test'}}),(e:any)=>e.code==='unauthenticated');
 for(const data of [null,{},[],{householdId:'a/b'},{householdId:'family-test',ownerUid:'owner'}])await assert.rejects(h({auth:{uid:'owner'},data}),(e:any)=>e.code==='invalid-argument');assert.equal(calls,0);
 await assert.rejects(h({auth:{uid:'owner'},data:{householdId:'family-test'}}),(e:any)=>e.code==='unavailable'&&e.message==='RETRYABLE_UNAVAILABLE');
 const f=await preparedFixture(),project=process.env.GCLOUD_PROJECT;try{process.env.GCLOUD_PROJECT='not-demo';await assert.rejects(f.run(),/FEATURE_DISABLED/);}finally{process.env.GCLOUD_PROJECT=project;}
 await f.unchanged();assert.equal((await dissolutionPreparationHandler(()=>f.preparation)({auth:{uid:'owner'},data:{householdId:f.home.id}})).phase,'PREPARED');await f.boundary();
});

test('5C1 pending JOIN cancellation preserves dissolution lock and participant evidence',async()=>{
 const f=await preparedFixture(),j=await waitingJoin(f);await f.run();const o=await f.ref.get();
 assert.equal(await j.engine.cancel({uid:'newcomer'},j.id,j.invite.inviteId),'ABORTED');
 assert.equal((await f.cap.get()).get('schemaVersion'),3);assert.equal((await f.cap.get()).get('structuralOperationId'),f.id);assert.deepEqual((await f.cap.get()).get('operationIds'),[]);
 assert.equal((await f.run()).phase,'PREPARED');assert.ok((await f.ref.get()).updateTime!.isEqual(o.updateTime!));
 const due=await db.collection('familyOperations').where('nextAt','<=',f.clock()).get();assert.ok(!due.docs.some(d=>d.id===f.id));
});
test('5C1 schema-v1 reservation worker defers without advancing under dissolution',async()=>{
 const f=await preparedFixture();await new HouseholdStore(db).ensure({uid:'newcomer'});const inv=await f.invites.create({uid:'owner'}),id=await f.join.reserve({uid:'newcomer'},inv.token,'ADD');
 await f.run();assert.equal(await f.join.resume(id),'IN_PROGRESS');assert.equal((await db.doc(`familyOperations/${id}`).get()).get('phase'),'RESERVED');
 assert.equal((await f.cap.get()).get('structuralOperationId'),f.id);assert.equal((await f.op()).participantCount,2);
});
