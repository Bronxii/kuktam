import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Timestamp } from 'firebase-admin/firestore';
import { newInviteToken, hashInviteToken, readInvite, readInviteSlots, INVITE_SECONDS } from '../src/households/invite-contract';
import { AdminMemberEmailResolver } from '../src/households/member-email';
import { familyInviteHandlers } from '../src/households/invite-handler';
import { FamilyInviteStore } from '../src/households/family-invites';

const createdAt=new Timestamp(1800000000,123),expiresAt=new Timestamp(createdAt.seconds+INVITE_SECONDS,123);
const invite={schemaVersion:1,householdId:'family',createdByUid:'owner',createdAt,expiresAt,status:'PENDING',operationId:null,usedAt:null,usedByUid:null};
test('token is canonical 32-byte base64url with distinct SHA256 IDs',()=>{
 const values=Array.from({length:20},()=>newInviteToken());assert.equal(new Set(values).size,20);
 for(const token of values){assert.ok(/^[A-Za-z0-9_-]{43}$/.test(token));assert.equal(Buffer.from(token,'base64url').length,32);assert.ok(/^[a-f0-9]{64}$/.test(hashInviteToken(token)));}
 for(const raw of ['',null,{},'a/b','a'.repeat(44),'!'.repeat(43),'A'.repeat(42)+'B'])assert.throws(()=>hashInviteToken(raw));
});
test('strict single-use schema supports PENDING → RESERVED → USED and stable revocation',()=>{
 assert.equal(readInvite(invite).status,'PENDING');
 const reserved={...invite,status:'RESERVED',operationId:'futureJoin'};assert.equal(readInvite(reserved).status,'RESERVED');
 assert.equal(readInvite({...reserved,status:'USED',usedByUid:'guest',usedAt:expiresAt}).status,'USED');
 assert.equal(readInvite({...invite,status:'REVOKED'}).status,'REVOKED');
 for(const v of [{...invite,rawToken:'never'},{...invite,email:'never'},{...reserved,operationId:null},
  {...invite,status:'USED'},{...invite,usedByUid:'guest'},{...invite,status:'REVOKED',operationId:'join'},
  {...invite,expiresAt:new Timestamp(expiresAt.seconds+1,123)}])assert.throws(()=>readInvite(v));
});
test('slot contract strictly bounded, unique, hash-only',()=>{
 assert.deepEqual(readInviteSlots({schemaVersion:1,inviteIds:[]}),[]);
 for(const ids of [['raw-token'],Array(9).fill('a'.repeat(64)),['a'.repeat(64),'a'.repeat(64)]])assert.throws(()=>readInviteSlots({schemaVersion:1,inviteIds:ids}));
});
test('Auth adapter uses one bounded UID batch, strips all unrelated Auth data and handles missing users',async()=>{
 let calls=0;
 const resolver=new AdminMemberEmailResolver({getUsers:async identifiers=>{
  calls++;assert.deepEqual(identifiers,[{uid:'owner'},{uid:'missing'},{uid:'noemail'}]);
  return {users:[{uid:'owner',email:'current@example.test',phoneNumber:'not-returned',providerData:['not-returned']},{uid:'noemail'},{uid:'unrequested',email:'private@example.test'}] as any,notFound:[{uid:'missing'}]};
 }});
 assert.deepEqual(await resolver.resolve(['owner','missing','noemail']),new Map([
  ['owner',{exists:true,email:'current@example.test'}],['missing',{exists:false,email:null}],['noemail',{exists:true,email:null}]]));
 assert.equal(calls,1);
 await assert.rejects(resolver.resolve(Array.from({length:9},(_,i)=>String(i))));await assert.rejects(resolver.resolve(['owner','owner']));assert.equal(calls,1);
});
for(const name of ['create','revoke','preview','state'] as const)test(`${name} handler denies auth/input injection before service initialization`,async()=>{
 let calls=0;const handlers=familyInviteHandlers(()=>{calls++;throw new Error('not initialized');});
 await assert.rejects(handlers[name]({data:{}}),(e:any)=>e.code==='unauthenticated');
 for(const data of [{uid:'victim'},{householdId:'victim'},{role:'owner'},{expiresAt:1},[],null])
  await assert.rejects(handlers[name]({auth:{uid:'caller'},data}),(e:any)=>e.code==='invalid-argument');
 assert.equal(calls,0);
});
test('handlers forward trusted UID, validate identifiers, and sanitize raw errors without logging tokens',async()=>{
 const calls:unknown[]=[];const token=newInviteToken(),id=hashInviteToken(token);
 const service={create:async(c:unknown)=>{calls.push(c);return 'created';},revoke:async(c:unknown,i:string)=>{calls.push(c,i);return 'revoked';},
  preview:async(c:unknown,t:string)=>{calls.push(c,hashInviteToken(t));return 'preview';},state:async(c:unknown)=>{calls.push(c);return 'state';}};
 const h=familyInviteHandlers(()=>service as unknown as FamilyInviteStore),auth={uid:'trusted'};
 await h.create({auth,data:{}});await h.revoke({auth,data:{inviteId:id}});await h.preview({auth,data:{token}});await h.state({auth,data:{}});
 assert.deepEqual(calls,[{uid:'trusted'},{uid:'trusted'},id,{uid:'trusted'},id,{uid:'trusted'}]);
 service.preview=async()=>{throw new Error(token);};
 await assert.rejects(h.preview({auth,data:{token}}),(e:any)=>e.message==='RETRYABLE_UNAVAILABLE'&&!JSON.stringify(e).includes(token));
 await assert.rejects(h.preview({auth,data:{token:'bad'}}),(e:any)=>e.code==='invalid-argument');
 await assert.rejects(h.revoke({auth,data:{inviteId:'bad'}}),(e:any)=>e.code==='invalid-argument');
});
