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
const app=initializeApp({projectId:'demo-kuktam-local'},'family-join'),db=getFirestore(app);
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
test('production runtime never enabled by demo-host or config alone',()=>{
 assert.equal(localJoinRuntime('kuktam-67768','127.0.0.1:8088'),false);
 assert.equal(localJoinRuntime('demo-test',undefined),false);
 assert.equal(localJoinRuntime('demo-test','remote:8088'),false);
 assert.equal(localJoinRuntime('demo-test','127.0.0.1:8088'),true);
});
for(const mode of ['ADD','DELETE'] as const)test(`${mode} reserves atomically without changing shopping or user pointers`,async()=>{
 const s=await setup(),p=privateHouseholdId('guest'),item={name:'milk',quantity:2,unknown:{future:true},createdAt:now};
 await db.doc(`households/${p}/shoppingItems/a`).set(item);
 const before=(await db.doc('users/guest').get()).data(),invite=await s.create(),join=new FamilyJoinStore(db,s.clock);
 const id=await join.reserve({uid:'guest'},invite.token,mode),op=readJoinOperation((await db.doc(`familyOperations/${id}`).get()).data(),id);
 assert.equal(op.mode,mode);assert.equal(op.sourceHouseholdId,p);assert.equal(op.householdId,'family-test');
 assert.equal(op.sourceItemCount,1);assert.equal(op.deleteReconfirmationRequired,mode==='DELETE');
 assert.equal((await db.doc(`familyInvites/${invite.inviteId}`).get()).get('status'),'RESERVED');
 assert.deepEqual((await db.doc('familyMemberships/guest').get()).data(),{state:'RESERVED',role:'member',householdId:'family-test',operationId:id});
 assert.deepEqual((await db.doc('users/guest').get()).data(),before);
 assert.deepEqual((await db.doc(`households/${p}/shoppingItems/a`).get()).data(),item);
 assert.equal((await db.doc('households/family-test/members/guest').get()).exists,false);
 assert.equal(JSON.stringify(await snapshot()).includes(invite.token),false);
 assert.equal(await join.resume(id),'READY_FOR_TRANSFER');
 assert.deepEqual(await new HouseholdStore(db).ensure({uid:'guest'}),{schemaVersion:1,householdId:p,ready:true});
 assert.deepEqual((await db.doc('users/guest').get()).data(),before);
});
for(const variant of ['absentGate','disabledGate','cloudRuntime','self','expired','revoked','used','reserved','missing',
 'ownerFree','ownerDELETING','ownerDELETED','guestDELETING','guestDELETED','PREPARING','DISSOLVING','missingFamily',
 'sameFamily','otherFamily','migration','private','pointer','createInProgress'])test(`validation denies ${variant} without reservation`,async()=>{
 const s=await setup(),i=await s.create(),j=new FamilyJoinStore(db,s.clock);let uid='guest';
 if(variant==='absentGate')await db.doc('familyRuntime/config').set({});
 if(variant==='disabledGate')await db.doc('familyRuntime/config').update({joinReservationEnabled:false});
 if(variant==='self')uid='owner';
 if(variant==='expired')s.advance(INVITE_SECONDS*1000);
 if(variant==='revoked')await s.store.revoke({uid:'owner'},i.inviteId);
 if(variant==='used')await db.doc(`familyInvites/${i.inviteId}`).update({status:'USED',operationId:'old',usedAt:s.clock(),usedByUid:'other'});
 if(variant==='reserved')await db.doc(`familyInvites/${i.inviteId}`).update({status:'RESERVED',operationId:'other'});
 if(variant==='missing')await db.doc(`familyInvites/${i.inviteId}`).delete();
 if(variant==='ownerFree')await db.doc('users/owner/entitlementGrants/pro').delete();
 for(const actor of ['owner','guest'])for(const state of ['DELETING','DELETED'])if(variant===actor+state)
  await db.doc(`accountLifecycle/${actor}`).set({schemaVersion:1,state,generation:2,updatedAt:now,deletionStartedAt:now,deletedAt:state==='DELETED'?now:null});
 if(['PREPARING','DISSOLVING'].includes(variant))await db.doc('households/family-test').update({state:variant});
 if(variant==='missingFamily')await db.doc('households/family-test').delete();
 if(['sameFamily','otherFamily'].includes(variant))await member('guest','member',variant==='sameFamily'?'family-test':'other');
 if(variant==='migration')await db.doc('users/guest').update({shoppingMigrationVersion:0});
 if(variant==='private')await db.doc(`households/${privateHouseholdId('guest')}`).delete();
 if(variant==='pointer')await db.doc('users/guest').update({activeHouseholdId:'wrong'});
 if(variant==='createInProgress') {const {createOperationId}=await import('../src/households/family-create');await db.doc(`familyOperations/${createOperationId('guest')}`).set({status:'READY'});}
 const before=await snapshot();const saved=process.env.K_SERVICE;
 try{if(variant==='cloudRuntime')process.env.K_SERVICE='deployed';await assert.rejects(j.reserve({uid},i.token,'ADD'));}
 finally{if(saved===undefined)delete process.env.K_SERVICE;else process.env.K_SERVICE=saved;}
 assert.deepEqual(await snapshot(),before);
});
test('Free or Pro invitee eligible; canonical multiple owner grants remain effective',async()=>{
 const s=await setup();await db.doc('users/owner/entitlementGrants/revoked').set(grant({status:'REVOKED',revokedAt:now}));
 await db.doc('users/guest/entitlementGrants/pro').set(grant());
 const i=await s.create();await new FamilyJoinStore(db,s.clock).reserve({uid:'guest'},i.token,'ADD');
});
test('same token same UID concurrent and repeated accepts produce one operation/slot',async()=>{
 const s=await setup(),i=await s.create(),j=new FamilyJoinStore(db,s.clock);
 const ids=await Promise.all([j.reserve({uid:'guest'},i.token,'ADD'),j.reserve({uid:'guest'},i.token,'ADD')]);
 assert.equal(ids[0],ids[1]);assert.equal((await db.collection('familyOperations').get()).size,1);
 assert.deepEqual((await db.doc('familyJoinCapacity/family-test').get()).get('operationIds'),[ids[0]]);
 await assert.rejects(j.reserve({uid:'guest'},i.token,'DELETE')); // Choice never overwritten.
});
test('same token two UIDs has exactly one winner',async()=>{
 const s=await setup(),i=await s.create(),j=new FamilyJoinStore(db,s.clock);await new HouseholdStore(db).ensure({uid:'other'});
 const r=await Promise.allSettled(['guest','other'].map(uid=>j.reserve({uid},i.token,'ADD')));
 assert.equal(r.filter(x=>x.status==='fulfilled').length,1);assert.equal((await db.collection('familyOperations').get()).size,1);
});
test('two tokens same UID has one reservation',async()=>{
 const s=await setup(),a=await s.create(),b=await s.create(),j=new FamilyJoinStore(db,s.clock);
 const r=await Promise.allSettled([a,b].map(i=>j.reserve({uid:'guest'},i.token,'ADD')));
 assert.equal(r.filter(x=>x.status==='fulfilled').length,1);assert.equal((await db.doc('familyJoinCapacity/family-test').get()).get('operationIds').length,1);
});
test('last slot races atomically including owner and active members',async()=>{
 const s=await setup();for(let n=0;n<6;n++)await member('member'+n);
 await new HouseholdStore(db).ensure({uid:'other'});const a=await s.create(),b=await s.create(),j=new FamilyJoinStore(db,s.clock);
 const r=await Promise.allSettled([j.reserve({uid:'guest'},a.token,'ADD'),j.reserve({uid:'other'},b.token,'ADD')]);
 assert.equal(r.filter(x=>x.status==='fulfilled').length,1);
 assert.equal((await db.collection('households/family-test/members').get()).size+(await db.doc('familyJoinCapacity/family-test').get()).get('operationIds').length,8);
});
test('crash after atomic reservation or lease can resume; live lease excludes second worker',async()=>{
 const s=await joined(),lease=await s.join.claim(s.id);assert.ok(lease);
 assert.equal(await s.join.claim(s.id),null);assert.equal(await s.join.resume(s.id),'notDueOrBusy');
 s.advance(1001);const next=await s.join.claim(s.id);assert.ok(next);assert.notEqual(next,lease);
 assert.equal(await s.join.step(s.id,lease),'BUSY');assert.equal(await s.join.step(s.id,next),'READY_FOR_TRANSFER');
 s.advance(1001);assert.equal(await s.join.resume(s.id),'READY_FOR_TRANSFER');
 assert.equal((await s.op()).leaseId,null);assert.equal((await s.op()).phase,'READY_FOR_TRANSFER');
});
for(const cause of ['ownerFree','guestDeleting','ownerDeleting','familyMissing','DISSOLVING','expired','missingIndex','missingSlot'])test(`abort ${cause} releases claims; shopping intact; no pointer repair`,async()=>{
 const s=await joined('DELETE'),p=privateHouseholdId('guest');await db.doc(`households/${p}/shoppingItems/keep`).set({name:'keep'});
 const root=(await db.doc('users/guest').get()).data();
 if(cause==='ownerFree')await db.doc('users/owner/entitlementGrants/pro').delete();
 if(cause==='guestDeleting'||cause==='ownerDeleting')await db.doc(`accountLifecycle/${cause==='guestDeleting'?'guest':'owner'}`).set({schemaVersion:1,state:'DELETING',generation:2,updatedAt:now,deletionStartedAt:now,deletedAt:null});
 if(cause==='familyMissing')await db.doc('households/family-test').delete();
 if(cause==='DISSOLVING')await db.doc('households/family-test').update({state:'DISSOLVING'});
 if(cause==='expired')s.advance(INVITE_SECONDS*1000);
 if(cause==='missingIndex')await db.doc('familyMemberships/guest').delete();
 if(cause==='missingSlot')await db.doc('familyJoinCapacity/family-test').set({schemaVersion:1,operationIds:[]});
 assert.equal(await s.join.resume(s.id),'ABORTED');assert.equal((await s.op()).status,'ABORTED');
 assert.equal((await db.doc('familyMemberships/guest').get()).exists,false);
 assert.deepEqual((await db.doc('familyJoinCapacity/family-test').get()).get('operationIds'),[]);
 assert.equal((await db.doc(`familyInvites/${s.invite.inviteId}`).get()).get('status'),'REVOKED');
 assert.deepEqual((await db.doc('users/guest').get()).data(),root);assert.equal((await db.doc(`households/${p}/shoppingItems/keep`).get()).exists,true);
 const after=await snapshot();await s.join.resume(s.id);assert.deepEqual(await snapshot(),after);
});
test('precommit reserved revoke safely aborts without transfer',async()=>{
 const s=await joined();assert.equal((await s.store.preview({uid:'guest'},s.invite.token)).code,'IN_PROGRESS');
 assert.equal((await s.store.revoke({uid:'owner'},s.invite.inviteId)).code,'REVOKED');
 assert.equal((await s.op()).status,'ABORTED');assert.equal((await db.doc('familyMemberships/guest').get()).exists,false);
});
test('corrupt foreign invite claim is never revoked or removed from its inventory by abort',async()=>{
 const s=await joined(),ref=db.doc(`familyInvites/${s.invite.inviteId}`);
 await ref.update({operationId:'foreign-operation'});
 const invite=(await ref.get()).data(),slots=(await db.doc('familyInviteSlots/family-test').get()).data();
 assert.equal(await s.join.resume(s.id),'ABORTED');
 assert.deepEqual((await ref.get()).data(),invite);
 assert.deepEqual((await db.doc('familyInviteSlots/family-test').get()).data(),slots);
 assert.equal((await db.doc('familyMemberships/guest').get()).exists,false);
 assert.deepEqual((await db.doc('familyJoinCapacity/family-test').get()).get('operationIds'),[]);
});
test('transient worker failure retries and releases lease without abort',async()=>{
 const s=await joined();const original=s.join.step.bind(s.join);s.join.step=async()=>{throw new Error('temporary');};
 assert.equal(await s.join.resume(s.id),'retry');assert.equal((await s.op()).leaseId,null);assert.equal((await s.op()).status,'READY');
 s.advance(30001);s.join.step=original;assert.equal(await s.join.resume(s.id),'READY_FOR_TRANSFER');
});
test('DELETE remains unfenced, later edits require Phase4B reconfirmation; no automatic execution',async()=>{
 const s=await joined('DELETE'),p=privateHouseholdId('guest');await db.doc(`households/${p}/shoppingItems/new`).set({name:'unseen'});
 for(let n=0;n<3;n++){await s.join.resume(s.id);s.advance(300001);}
 assert.equal((await s.op()).deleteReconfirmationRequired,true);assert.equal((await s.op()).phase,'READY_FOR_TRANSFER');
 assert.equal((await db.doc(`households/${p}/shoppingItems/new`).get()).exists,true);
});
test('callable rejects identifiers and sanitizes errors before exposing tokens',async()=>{
 let calls=0;const h=acceptFamilyHandler(()=>{calls++;throw new Error('secret');});
 await assert.rejects(h({data:{}}),(e:any)=>e.code==='unauthenticated');
 for(const data of [{token:'x',mode:'ADD',uid:'victim'},{token:'x',mode:'OTHER'},{token:'x',mode:'ADD'}])
  await assert.rejects(h({auth:{uid:'guest'},data}),(e:any)=>e.message==='INVALID_ARGUMENT');
 assert.equal(calls,0);
 const token=Buffer.alloc(32,1).toString('base64url');await assert.rejects(h({auth:{uid:'guest'},data:{token,mode:'ADD'}}),(e:any)=>e.message==='RETRYABLE_UNAVAILABLE');
});
for(const cut of [1,2,3,4])test(`transaction interruption after write ${cut} leaves no partial claims`,async()=>{
 const s=await setup(),invite=await s.create(),j=new FamilyJoinStore(db,s.clock),before=await snapshot();
 const original=db.runTransaction.bind(db);
 (db as any).runTransaction=(fn:any)=>original(async tx=>{
  let writes=0;const proxy=new Proxy(tx,{get(target,key){
   const value=(target as any)[key];
   if(['set','create','update'].includes(String(key)))return (...args:any[])=>{
    const result=value.apply(target,args);if(++writes===cut)throw new Error('simulated crash before commit');return result;
   };
   return typeof value==='function'?value.bind(target):value;
  }});return fn(proxy);
 });
 try{await assert.rejects(j.reserve({uid:'guest'},invite.token,'ADD'));}finally{db.runTransaction=original;}
 assert.deepEqual(await snapshot(),before);
 await j.reserve({uid:'guest'},invite.token,'ADD');assert.equal((await db.collection('familyOperations').get()).size,1);
});
test('maintenance and callable compete safely; invalid job cannot block JOIN; billing untouched',async()=>{
 const s=await joined(),play=new FakePlayApi(),ack=new FakeAcknowledgmentApi();
 const binding=new AccountBinding({currentVersion:'v1',material:()=>Buffer.alloc(32,1)});
 const worker=new Maintenance(db,{play,ack,voided:new FakeVoidedApi(),feed:new FakeVoidedFeed(),binding},s.clock);
 await db.doc('familyRuntime/config').set({joinReservationEnabled:false});
 await db.doc('familyOperations/malformed').set({kind:'JOIN',nextAt:s.clock()});
 await Promise.all([worker.run({now:s.clock(),only:['family']}),s.join.resume(s.id)]);
 assert.equal((await s.op()).phase,'READY_FOR_TRANSFER');assert.equal((await s.op()).leaseId,null);
 assert.equal(play.calls,0);assert.equal(ack.calls,0);
 assert.equal((await db.doc('households/family-test/members/guest').get()).exists,false);
});
test('deletion cannot declare DONE with reserved relationship; abort releases it without resurrecting root',async()=>{
 const s=await joined(),deletion=new AccountDeletionService(db,new FakeAuthDeletionApi());
 await deletion.beginAccountDeletion({uid:'guest'});assert.equal(await deletion.resume('guest',1),'cleanupRetryRequired');
 assert.notEqual((await db.doc('accountDeletions/guest').get()).get('stage'),'DONE');
 await db.doc('users/guest').delete();assert.equal(await s.join.resume(s.id),'ABORTED');
 assert.equal((await db.doc('users/guest').get()).exists,false);
 assert.equal((await db.doc('familyMemberships/guest').get()).exists,false);
 assert.equal((await db.doc('households/family-test/members/owner').get()).exists,true);
});
