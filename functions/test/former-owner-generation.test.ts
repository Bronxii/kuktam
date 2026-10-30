import {after,beforeEach,test} from 'node:test';
import assert from 'node:assert/strict';
import {initializeApp,deleteApp} from 'firebase-admin/app';
import {getFirestore,Timestamp,FieldValue} from 'firebase-admin/firestore';
import {requireLocalEmulator} from './emulator-guard';
import {grant,now} from './fixtures';
import {HouseholdStore} from '../src/households/household-store';
import {FamilyCreateStore,createOperationId} from '../src/households/family-create';
import {createFamilyHandler} from '../src/households/family-handler';
import {FamilyInviteStore} from '../src/households/family-invites';
import {FamilyJoinStore} from '../src/households/family-join';
import {JoinTransferStore} from '../src/households/join-transfer';
import {MemberLeaveStore} from '../src/households/member-leave';
import {OwnerProLossStore} from '../src/households/owner-pro-loss';
import {dissolutionId} from '../src/households/dissolution-preparation';
import {DissolutionFinalizationStore} from '../src/households/dissolution-finalization';
import {HistoricalFamilyAuditStore} from '../src/households/historical-family-audit';
requireLocalEmulator(process.env);
const app=initializeApp({projectId:'demo-kuktam-local'},'former-owner'),db=getFirestore(app);
beforeEach(async()=>assert.ok((await fetch('http://127.0.0.1:8088/emulator/v1/projects/demo-kuktam-local/databases/(default)/documents',{method:'DELETE'})).ok));
after(()=>deleteApp(app));
async function setup(){
 let ms=now.toMillis()+1000;const clock=()=>Timestamp.fromMillis(ms),advance=()=>{ms+=300001;};
 for(const uid of ['owner','other']){await new HouseholdStore(db).ensure({uid});await db.doc(`users/${uid}/entitlementGrants/pro`).set(grant());}
 await db.doc('familyRuntime/config').set({creationEnabled:true,inviteCreationEnabled:true,joinReservationEnabled:true});
 const create=new FamilyCreateStore(db,clock),life=new OwnerProLossStore(db,clock);
 const invites=new FamilyInviteStore(db,{resolve:async uids=>new Map(uids.map(uid=>[uid,{exists:true,email:null}]))},clock);
 async function finishCreate(id:string){for(let n=0;n<20;n++){advance();await create.resume(id);if((await db.doc(`familyOperations/${id}`).get()).get('status')==='DONE')return;}throw Error('createStuck');}
 async function make(uid='owner'){const id=await create.reserve({uid});await finishCreate(id);return {id,hid:(await db.doc(`familyOperations/${id}`).get()).get('householdId') as string};}
 async function finishLife(id:string){for(let n=0;n<60;n++){advance();if(await life.step(id)==='DONE')return;}throw Error('lifeStuck');}
 async function dissolve(){const r=await life.startOwner('owner');await finishLife(r.operationId);assert.equal((await invites.state({uid:'owner'})).familyActive,false);}
 async function preserved(paths:string[]){const docs=await db.getAll(...paths.map(p=>db.doc(p)));return async()=>{for(const before of docs){const after=await before.ref.get();assert.deepEqual(after.data(),before.data());assert.ok(after.updateTime!.isEqual(before.updateTime!));}};}
 return {clock,advance,create,life,invites,finishCreate,make,finishLife,dissolve,preserved};
}
test('9B0 legacy A dissolve new B duplicates stale A Pro-loss B then C history and audit',async()=>{
 const f=await setup(),a=await f.make();assert.equal(a.id,createOperationId('owner'));
 // Existing first-generation records need no migration.
 await db.doc(`familyOperations/${a.id}`).update({schemaVersion:1,accountGeneration:FieldValue.delete()});
 await db.doc('users/owner').update({familyCreateBinding:FieldValue.delete()});
 assert.equal(await f.create.reserve({uid:'owner'}),a.id);
 await f.dissolve();const didA=dissolutionId('owner',a.hid);
 const old=await f.preserved([`familyOperations/${a.id}`,`familyOperations/${didA}`,`households/${a.hid}`]);
 const ids=await Promise.all([f.create.reserve({uid:'owner'}),f.create.reserve({uid:'owner'})]);assert.equal(ids[0],ids[1]);assert.notEqual(ids[0],a.id);
 const bid=ids[0]!;assert.equal(await f.create.reserve({uid:'owner'}),bid); // lost reservation ACK
 await Promise.all([f.create.resume(bid),f.create.resume(bid)]);await f.finishCreate(bid);
 const b=(await db.doc(`familyOperations/${bid}`).get()).get('householdId');assert.notEqual(b,a.hid);
 const active=await f.invites.state({uid:'owner'});assert.ok(active.familyActive);assert.equal(active.role,'owner');
 assert.equal((await createFamilyHandler(()=>f.create)({auth:{uid:'owner'},data:{}})).operationId,bid);
 await assert.rejects(createFamilyHandler(()=>f.create)({auth:{uid:'owner'},data:{operationId:a.id}}),/Empty request/);
 const current=await f.preserved(['users/owner','familyMemberships/owner',`households/${b}`]);
 assert.equal(await f.create.resume(a.id),'DONE');assert.equal(await new DissolutionFinalizationStore(db,f.clock).step({uid:'owner'},a.hid),'DONE');await f.life.step(didA);await current();await old();
 await db.doc('users/owner/entitlementGrants/pro').delete();const didB=await f.life.observe('owner');await f.finishLife(didB);
 await assert.rejects(f.create.reserve({uid:'owner'}),/proRequired/);
 const oldB=await f.preserved([`familyOperations/${bid}`,`familyOperations/${didB}`,`households/${b}`]);
 await db.doc('users/owner/entitlementGrants/pro').set(grant());const c=await f.make();assert.notEqual(c.id,bid);assert.notEqual(c.hid,b);await old();await oldB();
 assert.equal((await db.collection('households').where('ownerUid','==','owner').where('kind','==','family').where('state','==','ACTIVE').get()).size,1);
 await f.dissolve();
 // Existing deletion audit parser must accept all CREATE generations without rewriting history.
 const audit=new HistoricalFamilyAuditStore(db,f.clock);await audit.admitHistorical({uid:'owner'});
 for(let n=0;n<80;n++){f.advance();await audit.step('owner');if((await db.doc('familyOwnerDeletions/owner').get()).get('phase')==='HISTORICAL_AUDIT_READY')break;}
 assert.equal((await db.doc('familyOwnerDeletions/owner').get()).get('phase'),'HISTORICAL_AUDIT_READY');
});
for(const mode of ['ADD','DELETE'] as const)test(`9B0 former owner dissolve JOIN ${mode} leave then CREATE`,async()=>{
 const f=await setup(),a=await f.make();await f.dissolve();const old=await f.preserved([`familyOperations/${a.id}`,`households/${a.hid}`]);
 const other=await f.make('other'),invite=await f.invites.create({uid:'other'});
 await db.doc('users/owner/entitlementGrants/pro').delete();assert.equal((await f.invites.preview({uid:'owner'},invite.token)).code,'VALID');
 const join=new FamilyJoinStore(db,f.clock),transfer=new JoinTransferStore(db,f.clock),jid=await join.reserve({uid:'owner'},invite.token,mode);
 await join.resume(jid);await transfer.prepare({uid:'owner'},jid,invite.inviteId);
 for(let n=0;n<40;n++){const v=await transfer.state({uid:'owner'},jid,invite.inviteId);if(v.status==='DONE')break;
  if(mode==='DELETE'&&v.phase==='SOURCE_FENCED_WAITING_CONFIRMATION')await transfer.confirm({uid:'owner'},{operationId:jid,inviteId:invite.inviteId,sourceEpoch:v.sourceEpoch!,snapshotHash:v.snapshotHash!,sourceItemCount:v.sourceItemCount!,consentVersion:1});
  f.advance();await join.resume(jid);
 }
 const state=await f.invites.state({uid:'owner'});assert.ok(state.familyActive);assert.equal(state.role,'member');assert.equal(state.members.find(m=>m.memberId==='owner')!.membershipInviteId,invite.inviteId);
 assert.equal((await db.doc('users/owner').get()).get('activeHouseholdId'),other.hid);
 await assert.rejects(f.create.reserve({uid:'owner'}),/alreadyFamily|inProgress/);await old();
 await new MemberLeaveStore(db,f.clock).leave({uid:'owner'},invite.inviteId);
 await db.doc('users/owner/entitlementGrants/pro').set(grant());const c=await f.make();assert.notEqual(c.id,a.id);await old();
});
test('9B0 terminal proof account generation and deletion guards fail closed',async()=>{
 const f=await setup(),a=await f.make();await f.make('other');const invitation=await f.invites.create({uid:'other'});const join=new FamilyJoinStore(db,f.clock);
 await f.life.startOwner('owner');
 await assert.rejects(f.create.reserve({uid:'owner'}));await assert.rejects(join.reserve({uid:'owner'},invitation.token,'ADD'));
 await f.finishLife(dissolutionId('owner',a.hid));
 const paths=[`familyOperations/${dissolutionId('owner',a.hid)}/finalization/state`,`households/${a.hid}`,`familyJoinCapacity/${a.hid}`,'accountLifecycle/owner','users/owner'];
 const docs=await db.getAll(...paths.map(p=>db.doc(p)));
 const changes=[()=>docs[0]!.ref.delete(),()=>docs[1]!.ref.update({state:'ACTIVE'}),()=>docs[2]!.ref.update({structuralOperationId:dissolutionId('owner',a.hid)}),()=>docs[3]!.ref.update({generation:2}),()=>docs[4]!.ref.update({familyCreateBinding:{operationId:'create_'+'0'.repeat(64),accountGeneration:1}})];
 for(let i=0;i<changes.length;i++){await changes[i]!();await assert.rejects(f.create.reserve({uid:'owner'}));await assert.rejects(join.reserve({uid:'owner'},invitation.token,'ADD'));await docs[i]!.ref.set(docs[i]!.data()!);}
 for(const collection of ['familyOwnerDeletions','familyMemberDeletions','accountDeletions']){
  const ref=db.doc(`${collection}/owner`);await ref.set({pending:true});
  // Private deletion admission atomically sets DELETING; Family handoffs precede it.
  if(collection==='accountDeletions')await docs[3]!.ref.update({state:'DELETING',generation:2,deletionStartedAt:f.clock()});
  await assert.rejects(f.create.reserve({uid:'owner'}),/accountUnavailable/);
  await assert.rejects(join.reserve({uid:'owner'},invitation.token,'ADD'));
  await ref.delete();await docs[3]!.ref.set(docs[3]!.data()!);
 }
 assert.equal((await db.collection('familyOperations').where('kind','==','CREATE').get()).size,2);
});
test('9B0 stale READY create cannot activate for a recreated account generation',async()=>{
 const f=await setup(),id=await f.create.reserve({uid:'owner'});
 await db.doc('accountLifecycle/owner').update({generation:3});
 await assert.rejects(f.create.reserve({uid:'owner'}),/accountUnavailable/);
 await f.create.resume(id);
 assert.notEqual((await db.doc(`familyOperations/${id}`).get()).get('phase'),'ACTIVATE');
 assert.equal((await db.collection('households').where('kind','==','family').where('state','==','ACTIVE').get()).size,0);
});
