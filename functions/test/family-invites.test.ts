import {familyInviteUrl} from '../src/households/invite-url';
import { familyInviteHandlers } from '../src/households/invite-handler';
import { joinOperationId } from '../src/households/family-join';
import { advanceShoppingEpoch } from '../src/shopping/mutation-store';
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
const app=initializeApp({projectId:'demo-kuktam-local'},'family-invites'),db=getFirestore(app);
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
  await db.doc('familyRuntime/config').set({creationEnabled:false,inviteCreationEnabled:true});
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
  if(role!=='member')await db.doc(`familyMemberships/${uid}`).set({householdId:hid,role,state:'ACTIVE',operationId:null});
  await db.doc(`households/${hid}/members/${uid}`).set({role});
  if(role==='member'){
    const inviteId=hashInviteToken(Buffer.from(uid.padEnd(32,'_')).toString('base64url')),id=joinOperationId(uid,inviteId);
    await db.doc(`users/${uid}`).update({familyJoinBinding:{operationId:id,inviteId}});
    const batch=db.batch();batch.set(db.doc(`familyMemberships/${uid}`),{householdId:hid,role,state:'ACTIVE',operationId:null});
    batch.set(db.doc(`familyOperations/${id}`),{schemaVersion:2,kind:'JOIN',actorUid:uid,ownerUid:'owner',inviteId,householdId:hid,sourceHouseholdId:privateHouseholdId(uid),mode:'ADD',phase:'ACTIVE',status:'DONE',sourceItemCount:0,deleteReconfirmationRequired:false,createdAt:now,updatedAt:now,nextAt:null,leaseId:null,leaseUntil:null,lastOutcome:'joinActivated',committedAt:now,sourceFence:{epoch:advanceShoppingEpoch(now).shoppingEpoch,at:now},snapshot:{version:1,count:0,hash:'a'.repeat(64)},cursor:{pageIndex:0,childOffset:0},deleteConsent:null});await batch.commit();
    await db.doc(`familyInvites/${inviteId}`).set({schemaVersion:1,householdId:hid,createdByUid:'owner',createdAt:now,expiresAt:Timestamp.fromMillis(now.toMillis()+INVITE_SECONDS*1000),status:'USED',operationId:id,usedAt:now,usedByUid:uid});
  }
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
test('owner gets 256-bit URL-safe token once; only SHA256 ID and strict metadata persist',async()=>{
  const s=await setup(),r=await s.create(),doc=await db.doc(`familyInvites/${r.inviteId}`).get();
  assert.ok(/^[A-Za-z0-9_-]{43}$/.test(r.token));assert.equal(Buffer.from(r.token,'base64url').length,32);
  assert.equal(r.inviteId,hashInviteToken(r.token));const v=readInvite(doc.data());
  assert.equal(v.expiresAt.toMillis()-v.createdAt.toMillis(),INVITE_SECONDS*1000);
  assert.equal(v.createdAt.toMillis(),s.clock().toMillis());assert.equal(v.status,'PENDING');
  assert.equal(v.operationId,null);assert.equal(v.usedAt,null);assert.equal(v.usedByUid,null);
  assert.equal(JSON.stringify(await snapshot()).includes(r.token),false);
  assert.equal(s.emails.calls.length,0);
});
for(const variant of ['absent','missing','false'])test(`invite creation gate ${variant} is OFF`,async()=>{
  const s=await setup();if(variant==='absent')await db.doc('familyRuntime/config').delete();
  else await db.doc('familyRuntime/config').set(variant==='missing'?{creationEnabled:true}:{inviteCreationEnabled:false});
  await assert.rejects(s.create(),denied('FEATURE_DISABLED'));assert.equal((await db.collection('familyInvites').get()).size,0);
});
for(const variant of ['free','expiredPro','member','nonmember','DELETING','DELETED','PREPARING','DISSOLVING','missingFamily','pointer','reverse','role','locked'])test(`invite creation denies ${variant}`,async()=>{
  const s=await setup();let caller='owner';
  if(variant==='free')await db.doc('users/owner/entitlementGrants/pro').delete();
  if(variant==='expiredPro')await db.doc('users/owner/entitlementGrants/pro').update({expiresAt:now});
  if(variant==='member'){await member('member');caller='member';}
  if(variant==='nonmember')caller='guest';
  if(['DELETING','DELETED'].includes(variant))await db.doc('accountLifecycle/owner').set({schemaVersion:1,state:variant,generation:2,updatedAt:now,deletionStartedAt:now,deletedAt:variant==='DELETED'?now:null});
  if(['PREPARING','DISSOLVING'].includes(variant))await db.doc('households/family-test').update({state:variant});
  if(variant==='missingFamily')await db.doc('households/family-test').delete();
  if(variant==='pointer')await db.doc('users/owner').update({activeHouseholdId:'wrong'});
  if(variant==='reverse')await db.doc('familyMemberships/owner').update({state:'RESERVED',operationId:'op'});
  if(variant==='role')await db.doc('households/family-test/members/owner').update({role:'member'});
  if(variant==='locked')await db.doc('households/family-test').update({operationId:'operation'});
  const beforeInvites=(await db.collection('familyInvites').get()).docs.map(d=>({id:d.id,data:d.data()}));
  await assert.rejects(s.store.create({uid:caller}));assert.deepEqual((await db.collection('familyInvites').get()).docs.map(d=>({id:d.id,data:d.data()})),beforeInvites);
});
test('another valid grant permits creation despite revoked grant and stale effective cache',async()=>{
 const s=await setup();await db.doc('users/owner/entitlementGrants/revoked').set(grant({status:'REVOKED',revokedAt:now}));
 await db.doc('users/owner/entitlements/pro').set({active:false});await s.create();
});
test('8 pending cap is transactional under simultaneous creates; distinct taps produce distinct links',async()=>{
 const s=await setup();for(let i=0;i<7;i++)await s.create();
 const results=await Promise.allSettled([s.create(),s.create(),s.create()]);
 assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
 for(const r of results)if(r.status==='rejected')assert.ok(denied('PENDING_LIMIT')(r.reason));
 assert.equal((await db.collection('familyInvites').get()).size,8);
 const ids=(await db.doc('familyInviteSlots/family-test').get()).get('inviteIds');assert.equal(new Set(ids).size,8);
});
test('expired PENDING slots release capacity without deleting audit docs; RESERVED never silently pruned',async()=>{
 const s=await setup();const invites=[];for(let i=0;i<8;i++)invites.push(await s.create());
 await db.doc(`familyInvites/${invites[0]!.inviteId}`).update({status:'RESERVED',operationId:'future-join'});
 s.advance(INVITE_SECONDS*1000);await s.create();
 assert.equal((await db.doc('familyInviteSlots/family-test').get()).get('inviteIds').length,2);
 assert.equal((await db.collection('familyInvites').get()).size,9);
});
test('token collision fails closed without overwriting invite or returning the lost token again',async()=>{
 const s=await setup(),r=await s.create(),before=await snapshot();
 const collision=new FamilyInviteStore(db,s.emails,s.clock,()=>r.token);
 await assert.rejects(collision.create({uid:'owner'}),denied('RETRYABLE_UNAVAILABLE'));assert.deepEqual(await snapshot(),before);
});
test('member cap includes owner: 8 people blocks new invites',async()=>{
 const s=await setup();for(let i=0;i<7;i++)await member(`member-${i}`);
 await assert.rejects(s.create(),denied('FAMILY_FULL'));
});
test('revoke is idempotent, releases slot, needs neither Pro nor enabled creation gate',async()=>{
 const s=await setup(),r=await s.create();await db.doc('familyRuntime/config').delete();await db.doc('users/owner/entitlementGrants/pro').delete();
 for(let i=0;i<2;i++)assert.equal((await s.store.revoke({uid:'owner'},r.inviteId)).code,'REVOKED');
 assert.deepEqual((await db.doc('familyInviteSlots/family-test').get()).get('inviteIds'),[]);
});
for(const status of ['USED','RESERVED'] as const)test(`revoke never corrupts ${status}`,async()=>{
 const s=await setup(),r=await s.create(),ref=db.doc(`familyInvites/${r.inviteId}`);
 await ref.update({status,operationId:'future-join',...(status==='USED'?{usedAt:s.clock(),usedByUid:'guest'}:{})});
 const before=await snapshot();assert.equal((await s.store.revoke({uid:'owner'},r.inviteId)).code,status==='RESERVED'?'IN_PROGRESS':'USED');
 assert.deepEqual(await snapshot(),before);
});
for(const caller of ['member','guest','otherOwner'])test(`${caller} cannot revoke owner's invite`,async()=>{
 const s=await setup(),r=await s.create();
 if(caller==='member')await member(caller);
 if(caller==='otherOwner'){
  await db.doc('households/other-family').set({schemaVersion:2,kind:'family',state:'ACTIVE',operationId:null,ownerUid:caller,createdAt:now});await member(caller,'owner','other-family');
 }
 await assert.rejects(s.store.revoke({uid:caller},r.inviteId));assert.equal((await db.doc(`familyInvites/${r.inviteId}`).get()).get('status'),'PENDING');
});
test('nonexistent revoke has safe code',async()=>{const s=await setup();await assert.rejects(s.store.revoke({uid:'owner'},'a'.repeat(64)),denied('NOT_FOUND'));});
test('valid preview counts only caller private items; no mutation, reservation or email list disclosure',async()=>{
 const s=await setup(),r=await s.create(),p=privateHouseholdId('guest');
 for(let i=0;i<3;i++)await db.doc(`households/${p}/shoppingItems/${i}`).set({name:'fixture'});
 await db.doc('households/family-test/shoppingItems/not-guest').set({name:'not counted'});
 await db.doc('familyRuntime/config').delete();const before=await snapshot();
 const result=await s.store.preview({uid:'guest'},r.token);
 assert.equal(result.code,'VALID');assert.equal(result.eligible,true);assert.equal(result.privateShoppingItemCount,3);
 assert.deepEqual(result.owner,{email:'owner@example.test',displayIdentity:'owner@example.test'});
 assert.ok(!('members' in result));assert.ok(!('ownerUid' in result));assert.deepEqual(s.emails.calls,[['owner']]);
 assert.deepEqual(await snapshot(),before);
});
const previewCases:Record<string,string>={expired:'EXPIRED',revoked:'REVOKED',used:'USED',reserved:'IN_PROGRESS',self:'SELF_INVITE',
 sameFamily:'ALREADY_MEMBER',otherFamily:'ALREADY_IN_FAMILY',full:'FAMILY_FULL',lostPro:'OWNER_NOT_PRO',ownerDeleted:'OWNER_UNAVAILABLE',
 ownerMarkerMissing:'OWNER_UNAVAILABLE',ownerAuthMissing:'OWNER_UNAVAILABLE',missingFamily:'FAMILY_UNAVAILABLE',PREPARING:'FAMILY_PREPARING',DISSOLVING:'FAMILY_DISSOLVING',
 guestDeleted:'ACCOUNT_UNAVAILABLE',guestMissing:'ACCOUNT_UNAVAILABLE',notReady:'ACCOUNT_NOT_READY',wrongPrivate:'ACCOUNT_NOT_READY',reservedGuest:'IN_PROGRESS',dissolved:'FAMILY_UNAVAILABLE'};
for(const [variant,code] of Object.entries(previewCases))test(`preview ${variant} returns ${code} without mutation`,async()=>{
 const s=await setup(),r=await s.create(),ref=db.doc(`familyInvites/${r.inviteId}`);let caller='guest';
 if(variant==='expired')s.advance(INVITE_SECONDS*1000);
 if(variant==='revoked')await ref.update({status:'REVOKED'});
 if(variant==='used')await ref.update({status:'USED',operationId:'join',usedByUid:'someone',usedAt:s.clock()});
 if(variant==='reserved')await ref.update({status:'RESERVED',operationId:'join'});
 if(variant==='self')caller='owner';
 if(variant==='sameFamily')await member('guest');
 if(variant==='otherFamily')await db.doc('familyMemberships/guest').set({householdId:'other',state:'ACTIVE',role:'member',operationId:null});
 if(variant==='reservedGuest')await db.doc('familyMemberships/guest').set({householdId:'other',state:'RESERVED',role:'member',operationId:'join'});
 if(variant==='full')for(let i=0;i<7;i++)await member(`member-${i}`);
 if(variant==='lostPro')await db.doc('users/owner/entitlementGrants/pro').delete();
 if(variant==='ownerDeleted'||variant==='guestDeleted')await db.doc(`accountLifecycle/${variant==='ownerDeleted'?'owner':'guest'}`).set({schemaVersion:1,state:'DELETED',generation:3,updatedAt:now,deletionStartedAt:now,deletedAt:now});
 if(variant==='ownerMarkerMissing'||variant==='guestMissing')await db.doc(`accountLifecycle/${variant==='guestMissing'?'guest':'owner'}`).delete();
 if(variant==='ownerAuthMissing')s.emails.users.delete('owner');
 if(variant==='missingFamily')await db.doc('households/family-test').delete();
 if(variant==='dissolved'){
  await db.doc('familyMemberships/owner').delete();await db.doc('users/owner').update({familyHouseholdId:null,activeHouseholdId:privateHouseholdId('owner')});
 }
 if(['PREPARING','DISSOLVING'].includes(variant))await db.doc('households/family-test').update({state:variant});
 if(variant==='notReady')await db.doc('users/guest').delete();
 if(variant==='wrongPrivate')await db.doc('users/guest').update({privateHouseholdId:privateHouseholdId('owner')});
 const before=await snapshot(),result=await s.store.preview({uid:caller},r.token);assert.equal(result.code,code);assert.equal(result.eligible,false);
 assert.ok(!('owner' in result));assert.deepEqual(await snapshot(),before);
});
test('unknown well-formed token is NOT_FOUND; malformed token does not query or leak data',async()=>{
 const s=await setup();assert.equal((await s.store.preview({uid:'guest'},Buffer.alloc(32,7).toString('base64url'))).code,'NOT_FOUND');
 await assert.rejects(s.store.preview({uid:'guest'},'secret/raw/input'),denied('INVALID_ARGUMENT'));assert.equal(s.emails.calls.length,0);
});
test('standalone state is minimal and performs no Auth lookup',async()=>{
 const s=await setup();assert.deepEqual(await s.store.state({uid:'guest'}),{schemaVersion:1,familyActive:false});assert.equal(s.emails.calls.length,0);
});
for(const caller of ['owner','member'])test(`${caller} sees bounded current member emails; only owner sees invite metadata`,async()=>{
 const s=await setup();await member('member');const r=await s.create(),state=await s.store.state({uid:caller});
 assert.ok(state.familyActive);assert.equal(state.members?.length,2);
 assert.equal(state.members?.find(m=>m.memberId==='member')?.email,'member@example.test');
 assert.equal(state.members?.find(m=>m.memberId==='owner')?.email,'owner@example.test');
 assert.equal('invites' in state,caller==='owner');
 if(caller==='owner')assert.deepEqual(state.invites,[{inviteId:r.inviteId,createdAt:s.clock().toMillis(),expiresAt:r.expiresAt,status:'PENDING'}]);
 assert.equal(JSON.stringify(state).includes(r.token),false);assert.equal(s.emails.calls.length,1);
 for(const d of (await db.collection('households/family-test/members').get()).docs)assert.deepEqual(Object.keys(d.data()),['role']);
});
test('email changes are visible on next call; missing/no-email members never display UID',async()=>{
 const s=await setup();await member('member');await member('missing');await member('noemail');s.emails.users.set('noemail',{exists:true,email:null});
 await s.store.state({uid:'owner'});s.emails.users.set('member',{exists:true,email:'new@example.test'});
 const state=await s.store.state({uid:'owner'});assert.ok(state.familyActive);assert.equal(state.members?.find(m=>m.memberId==='member')?.displayIdentity,'new@example.test');
 for(const uid of ['missing','noemail'])assert.deepEqual(state.members?.find(m=>m.memberId===uid),{memberId:uid,role:'member',email:null,displayIdentity:'Ismeretlen tag',membershipInviteId:(await db.doc(`users/${uid}`).get()).get('familyJoinBinding.inviteId')});
});
test('owner with no email previews using neutral identity, not UID',async()=>{
 const s=await setup(),r=await s.create();s.emails.users.set('owner',{exists:true,email:null});
 assert.deepEqual((await s.store.preview({uid:'guest'},r.token)).owner,{email:null,displayIdentity:'Ismeretlen tag'});
});
test('more than 8 members fails closed before any Auth lookup',async()=>{
 const s=await setup();for(let i=0;i<8;i++)await member(`member-${i}`);
 await assert.rejects(s.store.state({uid:'owner'}),denied('FAMILY_UNAVAILABLE'));assert.equal(s.emails.calls.length,0);
});
test('exactly 8 verified member identities fit one Auth batch',async()=>{
 const s=await setup();for(let i=0;i<7;i++)await member(`member-${i}`);
 const result=await s.store.state({uid:'owner'});assert.ok(result.familyActive);assert.equal(result.members.length,8);
 assert.equal(s.emails.calls.length,1);assert.equal(s.emails.calls[0]!.length,8);
});
test('missing slot targets fail closed; no replacement capacity is silently invented',async()=>{
 const s=await setup(),r=await s.create();await db.doc(`familyInvites/${r.inviteId}`).delete();
 await assert.rejects(s.create(),denied('INVITE_STATE_UNAVAILABLE'));
});
test('preview expiry uses exact server boundary and succeeds immediately before it',async()=>{
 const s=await setup(),r=await s.create();s.advance(INVITE_SECONDS*1000-1);
 assert.equal((await s.store.preview({uid:'guest'},r.token)).code,'VALID');s.advance(1);
 assert.equal((await s.store.preview({uid:'guest'},r.token)).code,'EXPIRED');
});
test('Auth lookup error is not converted into a fabricated unknown member list',async()=>{
 const s=await setup();s.emails.resolve=async()=>{throw new Error('synthetic Auth failure');};
 await assert.rejects(s.store.state({uid:'owner'}));
});
for(const variant of ['missingIndex','missingMember','pointer','role'])test(`inconsistent caller ${variant} cannot enumerate email`,async()=>{
 const s=await setup();await member('member');
 if(variant==='missingIndex')await db.doc('familyMemberships/member').delete();
 if(variant==='missingMember')await db.doc('households/family-test/members/member').delete();
 if(variant==='pointer')await db.doc('users/member').update({activeHouseholdId:'other'});
 if(variant==='role')await db.doc('familyMemberships/member').update({role:'owner'});
 await assert.rejects(s.store.state({uid:'member'}));assert.equal(s.emails.calls.length,0);
});
test('Phase 2 output supports invite creation and deletion waits for Family lifecycle with pending invite',async()=>{
 await new HouseholdStore(db).ensure({uid:'realCreator'});await db.doc('users/realCreator/entitlementGrants/pro').set(grant());
 await db.doc('familyRuntime/config').set({creationEnabled:true,inviteCreationEnabled:true});
 const engine=new FamilyCreateStore(db),id=await engine.reserve({uid:'realCreator'});
 for(let i=0;i<10&&(await db.doc(`familyOperations/${id}`).get()).get('status')!=='DONE';i++)await engine.resume(id);
 const store=new FamilyInviteStore(db,new Emails());await store.create({uid:'realCreator'});
 const deletion=new AccountDeletionService(db,new FakeAuthDeletionApi());
 assert.equal((await deletion.beginAccountDeletion({uid:'realCreator'})).outcome,'familyDissolutionPending');
 assert.equal((await db.doc('familyOwnerDeletions/realCreator').get()).get('phase'),'DISSOLUTION_IN_PROGRESS');
 assert.equal((await db.doc('accountDeletions/realCreator').get()).exists,false);
 assert.equal((await db.doc('accountLifecycle/realCreator').get()).get('state'),'ACTIVE');
 assert.equal((await db.collection('familyInvites').get()).size,1);
});

for(const caller of ['owner','member'])test(`7D0 ${caller} receives only authorized exact current bindings`,async()=>{
 const s=await setup();await member('member');await member('peer');await member('foreign','member','other-family');
 const state=await s.store.state({uid:caller});assert.ok(state.familyActive);
 assert.equal(state.members.find(m=>m.memberId==='owner')?.membershipInviteId,undefined);
 for(const uid of ['member','peer'])assert.equal(state.members.find(m=>m.memberId===uid)?.membershipInviteId,caller==='owner'||uid===caller?(await db.doc(`users/${uid}`).get()).get('familyJoinBinding.inviteId'):undefined);
 assert.equal(state.members.some(m=>m.memberId==='foreign'),false);
});
for(const defect of ['missingPointerOperation','corruptPointer','wrongInvite','wrongIndex','wrongFamily','wrongActor','unfinished','revoked'])test(`7D0 malformed ${defect} fails before identity lookup`,async()=>{
 const s=await setup();await member('member');const u=await db.doc('users/member').get(),binding=u.get('familyJoinBinding');
 if(defect==='missingPointerOperation')await db.doc(`familyOperations/${binding.operationId}`).delete();
 if(defect==='corruptPointer')await u.ref.update({familyJoinBinding:{operationId:'bad',inviteId:binding.inviteId}});
 if(defect==='wrongInvite')await u.ref.update({'familyJoinBinding.inviteId':'f'.repeat(64)});
 if(defect==='wrongIndex')await db.doc('familyMemberships/member').update({householdId:'other'});
 if(defect==='wrongFamily')await db.doc(`familyOperations/${binding.operationId}`).update({householdId:'other'});
 if(defect==='wrongActor')await db.doc(`familyOperations/${binding.operationId}`).update({actorUid:'other'});
 if(defect==='unfinished')await db.doc(`familyOperations/${binding.operationId}`).update({phase:'TRANSFER_COMPLETE',status:'READY',nextAt:now});
 if(defect==='revoked')await db.doc(`familyInvites/${binding.inviteId}`).update({status:'REVOKED'});
 await assert.rejects(s.store.state({uid:'owner'}),denied('FAMILY_UNAVAILABLE'));assert.equal(s.emails.calls.length,0);
});
test('7D0 historical DISSOLVED records do not supply live binding',async()=>{
 const s=await setup();await db.doc('households/old').set({kind:'family',state:'DISSOLVED',ownerUid:'guest'});
 assert.deepEqual(await s.store.state({uid:'guest'}),{schemaVersion:1,familyActive:false});
});

test('7D0 max eight participants uses four bounded binding batches',async()=>{
 const s=await setup();for(let n=0;n<7;n++)await member(`m${n}`);
 const batches:number[]=[],original=db.runTransaction.bind(db);
 const wrapped=new Proxy(db,{get(t,k){if(k==='runTransaction')return (cb:any,options:any)=>original(tx=>cb(new Proxy(tx,{get(t,k){if(k==='getAll')return (...refs:any[])=>{batches.push(refs.length);return (t.getAll as any)(...refs);};const v=(t as any)[k];return typeof v==='function'?v.bind(t):v;}})),options);const v=(t as any)[k];return typeof v==='function'?v.bind(t):v;}});
 const state=await new FamilyInviteStore(wrapped,s.emails,s.clock).state({uid:'owner'});assert.ok(state.familyActive);
 assert.equal(state.members.length,8);assert.equal(state.members.filter(m=>m.membershipInviteId).length,7);assert.deepEqual(batches,[4,7,7,7,7]);
});
test('7D0 read callable cannot select arbitrary Family, UID or invitation',async()=>{
 let calls=0;const handler=familyInviteHandlers(()=>{calls++;throw new Error('notCalled');}).state;
 for(const data of [{householdId:'other'},{uid:'other'},{inviteId:'a'.repeat(64)}])await assert.rejects(handler({auth:{uid:'owner'},data}),(e:any)=>e.code==='invalid-argument');
 assert.equal(calls,0);
});

test('8A created link is response-only same credential same expiry no stored URL or token',async()=>{
 const s=await setup(),r=await s.create(),url=new URL(r.inviteUrl),ref=db.doc(`familyInvites/${r.inviteId}`),before=await ref.get();
 assert.equal(url.searchParams.get('token'),r.token);assert.equal(r.inviteUrl,familyInviteUrl(r.token));assert.equal(r.expiresAt,before.get('expiresAt').toMillis());
 assert.deepEqual(Object.keys(Object.fromEntries(url.searchParams)),['token']);assert.equal(url.pathname,'/family/invite');
 const whole=JSON.stringify(await snapshot());assert.equal(whole.includes(r.token),false);assert.equal(whole.includes(r.inviteUrl),false);
 const state=await s.store.state({uid:'owner'});assert.ok(state.familyActive);assert.ok(state.invites!.every(i=>!('token' in i)&&!('inviteUrl' in i)));
 assert.equal((await s.store.preview({uid:'guest'},url.searchParams.get('token')!)).code,'VALID');assert.deepEqual((await ref.get()).data(),before.data());
 await s.store.revoke({uid:'owner'},r.inviteId);assert.equal((await s.store.preview({uid:'guest'},url.searchParams.get('token')!)).code,'REVOKED');
 const expired=await s.create();s.advance(INVITE_SECONDS*1000);assert.equal((await s.store.preview({uid:'guest'},new URL(expired.inviteUrl).searchParams.get('token')!)).code,'EXPIRED');
});
