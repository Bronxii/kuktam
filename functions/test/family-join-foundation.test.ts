import { JoinTransferStore } from '../src/households/join-transfer';
import { canonicalValue, digest, sourceFingerprint } from '../src/households/join-snapshot';
import { ShoppingMutationStore } from '../src/shopping/mutation-store';
import { newMutationId } from '../src/shopping/mutation-contract';
import { LifecycleStore } from '../src/billing/lifecycle-store';
import { FamilyJoinStore, joinOperationId, readJoinOperation, localJoinRuntime } from '../src/households/family-join';
import { acceptFamilyHandler } from '../src/households/join-handler';
import { Maintenance } from '../src/jobs/maintenance';
import { FakePlayApi } from './fake-play-api';
import { FakeVoidedApi } from './fake-voided-api';
import { FakeAcknowledgmentApi } from './fake-acknowledgment-api';
import { FakeVoidedFeed } from './fake-voided-feed';
import { AccountBinding } from '../src/billing/account-binding';
import { after, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeApp, deleteApp } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { requireLocalEmulator } from './emulator-guard';
import { grant, now } from './fixtures';
import { HouseholdStore, privateHouseholdId } from '../src/households/household-store';
import { FamilyCreateStore } from '../src/households/family-create';
import { FamilyInviteStore } from '../src/households/family-invites';
import { FamilyInviteError, hashInviteToken, INVITE_SECONDS, readInvite } from '../src/households/invite-contract';
import { MemberEmail, MemberEmailResolver } from '../src/households/member-email';
import { AccountDeletionService } from '../src/accounts/account-deletion';
import { FakeAuthDeletionApi } from './fake-auth-deletion-api';
requireLocalEmulator(process.env);
const app=initializeApp({projectId:'demo-kuktam-local'},'family-join-foundation'),db=getFirestore(app);
beforeEach(async()=>{assert.ok((await fetch('http://127.0.0.1:8088/emulator/v1/projects/demo-kuktam-local/databases/(default)/documents',{method:'DELETE'})).ok);});
after(()=>deleteApp(app));
class Emails implements MemberEmailResolver {
  calls:string[][]=[];
  users=new Map<string,MemberEmail>([['owner',{exists:true,email:'owner@example.test'}],['member',{exists:true,email:'member@example.test'}]]);
  async resolve(uids:readonly string[]) {this.calls.push([...uids]);return new Map(uids.map(uid=>[uid,this.users.get(uid)??{exists:false,email:null}]));}
}
async function setup() {
  await new HouseholdStore(db).ensure({uid:'owner'});
  await db.doc('users/owner/entitlementGrants/pro').set(grant());
  await db.doc('familyRuntime/config').set({creationEnabled:false,inviteCreationEnabled:true,joinReservationEnabled:true});
  await db.doc('households/family-test').set({schemaVersion:2,kind:'family',state:'ACTIVE',operationId:null,ownerUid:'owner',createdAt:now});
  await member('owner','owner');
  await new HouseholdStore(db).ensure({uid:'guest'});
  let time=now.toMillis()+1000;const clock=()=>Timestamp.fromMillis(time),emails=new Emails();
  const store=new FamilyInviteStore(db,emails,clock);
  return {store,emails,clock,advance:(ms:number)=>{time+=ms;},create:()=>store.create({uid:'owner'})};
}
async function member(uid:string,role='member',hid='family-test') {
  if(uid!=='owner')await new HouseholdStore(db).ensure({uid});
  await db.doc(`users/${uid}`).update({familyHouseholdId:hid,activeHouseholdId:hid});
  await db.doc(`familyMemberships/${uid}`).set({householdId:hid,role,state:'ACTIVE',operationId:null});
  await db.doc(`households/${hid}/members/${uid}`).set({role});
}
const denied=(code:string)=>(e:unknown)=>e instanceof FamilyInviteError&&e.code===code;
async function snapshot() {
  const data:Record<string,unknown>={};
  async function walk(collection:FirebaseFirestore.CollectionReference):Promise<void>{
    for(const d of (await collection.get()).docs){data[d.ref.path]=d.data();for(const c of await d.ref.listCollections())await walk(c);}
  }
  for(const c of await db.listCollections())await walk(c);
  return data;
}
async function joined(mode:'ADD'|'DELETE'='ADD') {
 const s=await setup(),invite=await s.create(),join=new FamilyJoinStore(db,s.clock,1000);
 const id=await join.reserve({uid:'guest'},invite.token,mode);
 return {...s,invite,join,id,op:async()=>readJoinOperation((await db.doc(`familyOperations/${id}`).get()).data(),id)};
}

async function foundation(mode:'ADD'|'DELETE'='ADD',count=1){
 const s=await joined(mode),p=privateHouseholdId('guest');
 for(let i=0;i<count;i++)await db.doc(`households/${p}/shoppingItems/i${String(i).padStart(4,'0')}`).set({name:'Milk'+i,quantity:1,unit:'l',isChecked:false,createdAt:now});
 await s.join.resume(s.id);
 const engine=new JoinTransferStore(db,s.clock);
 await engine.prepare({uid:'guest'},s.id,s.invite.inviteId);
 const tick=async()=>{s.advance(300001);return s.join.resume(s.id);};
 const wait=async()=>{for(let i=0;i<30;i++){const o=await s.op();if(o.phase!=='SNAPSHOT_SOURCE')return o;await tick();}throw new Error('stuck');};
 const state=()=>engine.state({uid:'guest'},s.id,s.invite.inviteId);
 const consent=async()=>{const v=await state();return {operationId:s.id,inviteId:s.invite.inviteId,sourceEpoch:v.sourceEpoch!,snapshotHash:v.snapshotHash!,sourceItemCount:v.sourceItemCount!,consentVersion:1};};
 return {...s,p,engine,tick,wait,state,consent};
}
for(const count of [0,1,11,25,201])test(`ADD bounded snapshot ${count}, no live effects`,async()=>{
 const s=await foundation('ADD',count);const fence=(await s.state());const source=(await db.doc(`households/${s.p}`).get()).data();
 await s.engine.prepare({uid:'guest'},s.id,s.invite.inviteId);assert.deepEqual((await db.doc(`households/${s.p}`).get()).data(),source);
 await s.wait();assert.equal((await s.state()).sourceItemCount,count);await s.tick();assert.equal((await s.op()).phase,'COMMITTED_TRANSFER');
 assert.equal((await db.collection('households/family-test/shoppingItems').get()).size,0);
 assert.equal((await db.collection(`households/${s.p}/shoppingItems`).get()).size,count);
 assert.equal((await db.doc('familyMemberships/guest').get()).get('state'),'RESERVED');
 assert.equal((await db.doc('users/guest').get()).get('activeHouseholdId'),s.p);
 assert.equal((await db.doc('households/family-test/members/guest').get()).exists,false);
 assert.equal((await db.doc('familyJoinCapacity/family-test').get()).get('structuralOperationId'),s.id);
 const committed=(await db.doc(`familyOperations/${s.id}`).get()).get('committedAt');await s.tick();assert.deepEqual((await db.doc(`familyOperations/${s.id}`).get()).get('committedAt'),committed);
});
for(const count of [0,11])test(`DELETE ${count} waits, exact consent commits and lost ACK reentry stable`,async()=>{
 const s=await foundation('DELETE',count);await s.wait();await s.tick();assert.equal((await s.op()).phase,'SOURCE_FENCED_WAITING_CONFIRMATION');
 const challenge=await s.consent();assert.deepEqual(await s.consent(),challenge);
 const fresh=new JoinTransferStore(db,s.clock);assert.equal(await fresh.confirm({uid:'guest'},challenge),'COMMITTED_TRANSFER');
 const before=(await db.doc(`familyOperations/${s.id}`).get()).data();assert.equal(await fresh.confirm({uid:'guest'},challenge),'COMMITTED_TRANSFER');assert.deepEqual((await db.doc(`familyOperations/${s.id}`).get()).data(),before);
 assert.equal((await db.collection(`households/${s.p}/shoppingItems`).get()).size,count);
});
for(const field of ['sourceEpoch','snapshotHash','sourceItemCount','consentVersion','inviteId','operationId'])test(`DELETE rejects stale/forged ${field}`,async()=>{
 const s=await foundation('DELETE');await s.wait();const c=await s.consent();
 const bad={...c,[field]:typeof (c as any)[field]==='number'?999:'0'.repeat(64)};
 await assert.rejects(s.engine.confirm({uid:'guest'},bad));assert.equal((await s.op()).phase,'SOURCE_FENCED_WAITING_CONFIRMATION');
});
test('wrong UID and ADD consent are rejected',async()=>{const s=await foundation();await s.wait();const c=await s.consent();await assert.rejects(s.engine.confirm({uid:'other'},c));await assert.rejects(s.engine.confirm({uid:'guest'},c));});
for(const cause of ['cancel','revoke','expiry','pro','lifecycle'])test(`precommit ${cause} releases fence, preserves items`,async()=>{
 const s=await foundation('DELETE',11);await s.wait();const epoch=(await db.doc(`households/${s.p}`).get()).get('shoppingEpoch');
 if(cause==='cancel')await s.engine.cancel({uid:'guest'},s.id,s.invite.inviteId);
 if(cause==='revoke')await s.store.revoke({uid:'owner'},s.invite.inviteId);
 if(cause==='expiry')s.advance(INVITE_SECONDS*1000);
 if(cause==='pro')await db.doc('users/owner/entitlementGrants/pro').delete();
 if(cause==='lifecycle')await new LifecycleStore(db,s.clock).beginDeletion('guest');
 await s.tick();assert.equal((await s.op()).status,'ABORTED');assert.equal((await db.doc(`households/${s.p}`).get()).get('operationId'),null);
 assert.notEqual((await db.doc(`households/${s.p}`).get()).get('shoppingEpoch'),epoch);
 assert.equal((await db.collection(`households/${s.p}/shoppingItems`).get()).size,11);
 assert.equal((await db.doc('familyMemberships/guest').get()).exists,false);
 assert.equal((await db.doc(`familyInvites/${s.invite.inviteId}`).get()).get('status'),'REVOKED');
});
test('postcommit revoke/cancel/expiry/Pro loss cannot abort; actor and owner deletion blocked',async()=>{
 const s=await foundation();await s.wait();await s.tick();
 assert.equal((await s.store.revoke({uid:'owner'},s.invite.inviteId)).code,'IN_PROGRESS');
 assert.equal(await s.engine.cancel({uid:'guest'},s.id,s.invite.inviteId),'IN_PROGRESS');
 for(const uid of ['guest','owner']){await assert.rejects(new LifecycleStore(db,s.clock).beginDeletion(uid),/JOIN_COMMITTED_IN_PROGRESS/);assert.equal((await db.doc(`accountLifecycle/${uid}`).get()).get('state'),'ACTIVE');}
 s.advance(INVITE_SECONDS*1000);await db.doc('users/owner/entitlementGrants/pro').delete();await s.tick();assert.equal((await s.op()).phase,'COMMITTED_TRANSFER');assert.equal((await s.op()).status,'READY');
});
test('structural conflict cannot commit or steal lock',async()=>{
 const s=await foundation('DELETE');await s.wait();const other=joinOperationId('other');
 await db.doc('familyJoinCapacity/family-test').set({schemaVersion:2,operationIds:[s.id,other],structuralOperationId:other});
 assert.equal(await s.engine.confirm({uid:'guest'},await s.consent()),'IN_PROGRESS');assert.equal((await s.op()).phase,'SOURCE_FENCED_WAITING_CONFIRMATION');
});
test('competing confirmation workers commit identical durable evidence',async()=>{
 const s=await foundation('DELETE');await s.wait();const c=await s.consent();
 assert.deepEqual(await Promise.all([s.engine.confirm({uid:'guest'},c),new JoinTransferStore(db,s.clock).confirm({uid:'guest'},c)]),['COMMITTED_TRANSFER','COMMITTED_TRANSFER']);
 assert.equal((await db.doc('familyJoinCapacity/family-test').get()).get('structuralOperationId'),s.id);
});
test('source fence rejects old accepted command and new authority',async()=>{
 const s=await joined();await db.doc('shoppingRuntime/config').set({enabled:true});const shopping=new ShoppingMutationStore(db,s.clock),ctx=await shopping.ensureContext({uid:'guest'}),id=newMutationId(ctx.epoch);
 await shopping.submit({uid:'guest'},{schemaVersion:1,actorUid:'guest',householdId:ctx.householdId,epoch:ctx.epoch,mutationId:id,kind:'ADD',payloadJson:JSON.stringify({type:'ADD',name:'late',quantity:2,unit:'db'}),submittedAt:s.clock()});
 await s.join.resume(s.id);await new JoinTransferStore(db,s.clock).prepare({uid:'guest'},s.id,s.invite.inviteId);
 assert.notEqual(await shopping.process('guest',id),'APPLIED');await assert.rejects(shopping.ensureContext({uid:'guest'}));
 assert.equal((await db.collection(`households/${ctx.householdId}/shoppingItems`).get()).size,0);
});
test('fingerprint sorted maps and typed numeric values; source content changes',async()=>{
 assert.deepEqual(canonicalValue({mapValue:{fields:{b:{integerValue:'2'},a:{stringValue:'x'}}}}),canonicalValue({mapValue:{fields:{a:{stringValue:'x'},b:{integerValue:'2'}}}}));
 assert.notEqual(digest(canonicalValue({integerValue:'1'})),digest(canonicalValue({doubleValue:1})));
 const r=db.doc('fingerprints/a');await r.set({quantity:1});const a=sourceFingerprint(await r.get());assert.equal(a,sourceFingerprint(await r.get()));await r.update({quantity:2});assert.notEqual(a,sourceFingerprint(await r.get()));
});

test('unexpected Auth deletion parks committed JOIN in OPERATOR without deleting source',async()=>{
 const s=await foundation();await s.wait();await s.tick();await new LifecycleStore(db,s.clock).beginDeletion('guest',true);
 assert.equal((await s.op()).status,'OPERATOR');assert.equal((await db.doc('accountLifecycle/guest').get()).get('state'),'DELETING');assert.equal((await db.doc('familyJoinCapacity/family-test').get()).get('structuralOperationId'),s.id);
 assert.equal((await db.collection(`households/${s.p}/shoppingItems`).get()).size,1);
});
test('general lifecycle marker cannot bypass committed deletion admission',async()=>{
 const s=await foundation();await s.wait();await s.tick();const a=(await db.doc('accountLifecycle/guest').get()).data()!;
 await assert.rejects(new LifecycleStore(db,s.clock).advanceAccountMarker({uid:'guest'},a.generation,'DELETING'),/JOIN_COMMITTED_IN_PROGRESS/);
 assert.equal((await db.doc('accountLifecycle/guest').get()).get('state'),'ACTIVE');
});
test('normal family shopping remains authorized while committed JOIN owns structural guard',async()=>{
 const s=await foundation();await s.wait();await s.tick();await db.doc('shoppingRuntime/config').set({enabled:true});
 const shopping=new ShoppingMutationStore(db,s.clock),ctx=await shopping.ensureContext({uid:'owner'}),id=newMutationId(ctx.epoch);
 await shopping.submit({uid:'owner'},{schemaVersion:1,actorUid:'owner',householdId:ctx.householdId,epoch:ctx.epoch,mutationId:id,kind:'ADD',payloadJson:JSON.stringify({type:'ADD',name:'owner milk',quantity:1,unit:'l'}),submittedAt:s.clock()});
 assert.equal(await shopping.process('owner',id),'APPLIED');assert.equal((await s.op()).phase,'COMMITTED_TRANSFER');
});
for(const mismatch of ['source','target','reservation','capacity'])test(`routing/claim mismatch ${mismatch} prevents commit`,async()=>{
 const s=await foundation('DELETE');await s.wait();const c=await s.consent();
 if(mismatch==='source')await db.doc(`familyOperations/${s.id}`).update({sourceHouseholdId:'wrong'});
 if(mismatch==='target')await db.doc(`familyOperations/${s.id}`).update({householdId:'wrong'});
 if(mismatch==='reservation')await db.doc('familyMemberships/guest').update({operationId:joinOperationId('other')});
 if(mismatch==='capacity')await db.doc('familyJoinCapacity/family-test').set({schemaVersion:1,operationIds:[]});
 await assert.rejects(s.engine.confirm({uid:'guest'},c));assert.equal((await db.doc(`familyOperations/${s.id}`).get()).get('committedAt'),null);
});
test('competing prepare and snapshot workers retain a single fence and journal',async()=>{
 const s=await joined('DELETE');await s.join.resume(s.id);const e=new JoinTransferStore(db,s.clock);
 await Promise.all([e.prepare({uid:'guest'},s.id,s.invite.inviteId),e.prepare({uid:'guest'},s.id,s.invite.inviteId)]);
 const epoch=(await db.doc(`households/${privateHouseholdId('guest')}`).get()).get('shoppingEpoch');
 s.advance(300001);await Promise.all([s.join.resume(s.id),new FamilyJoinStore(db,s.clock).resume(s.id)]);
 assert.equal((await db.doc(`households/${privateHouseholdId('guest')}`).get()).get('shoppingEpoch'),epoch);
 assert.equal((await s.op()).phase,'SOURCE_FENCED_WAITING_CONFIRMATION');
});

test('injected lost commit acknowledgement recovers without new fence or committedAt',async()=>{
 const s=await foundation('DELETE');await s.wait();const c=await s.consent(),original=db.runTransaction.bind(db);
 (db as any).runTransaction=async(...args:any[])=>{await (original as any)(...args);throw new Error('lostAck');};
 try{await assert.rejects(s.engine.confirm({uid:'guest'},c),/lostAck/);}finally{(db as any).runTransaction=original;}
 const committed=(await db.doc(`familyOperations/${s.id}`).get()).data();
 assert.equal(await new JoinTransferStore(db,s.clock).confirm({uid:'guest'},c),'COMMITTED_TRANSFER');
 assert.deepEqual((await db.doc(`familyOperations/${s.id}`).get()).data(),committed);
});
test('final capacity overflow rejects commit and safely aborts',async()=>{
 const s=await foundation('DELETE');await s.wait();
 for(let i=0;i<7;i++)await db.doc(`households/family-test/members/m${i}`).set({role:'member'});
 assert.equal(await s.engine.confirm({uid:'guest'},await s.consent()),'ABORTED');
 assert.equal((await db.doc(`households/${s.p}`).get()).get('operationId'),null);
});
test('stale invitation incarnation cannot confirm or cancel a reused per-UID slot',async()=>{
 const s=await foundation('DELETE');await s.wait();const old=await s.consent();await s.engine.cancel({uid:'guest'},s.id,s.invite.inviteId);
 const next=await s.create();assert.notEqual(next.inviteId,s.invite.inviteId);
 await s.join.reserve({uid:'guest'},next.token,'DELETE');await s.join.resume(s.id);await s.engine.prepare({uid:'guest'},s.id,next.inviteId);
 await assert.rejects(s.engine.confirm({uid:'guest'},old));await assert.rejects(s.engine.cancel({uid:'guest'},s.id,s.invite.inviteId));
 assert.equal((await s.op()).inviteId,next.inviteId);
});

test('corrupt manifest enters OPERATOR without releasing source or looping retries',async()=>{
 const s=await foundation('DELETE',11);await s.tick();
 const pages=await db.collection(`familyOperations/${s.id}/transferJournal`).get();assert.equal(pages.size,1);
 await pages.docs[0]!.ref.update({chainHash:'forged'});await s.tick();
 assert.equal((await s.op()).status,'OPERATOR');assert.equal((await s.op()).nextAt,null);
 assert.equal((await db.doc(`households/${s.p}`).get()).get('operationId'),s.id);
 assert.equal((await db.collection(`households/${s.p}/shoppingItems`).get()).size,11);
});
