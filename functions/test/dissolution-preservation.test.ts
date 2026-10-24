import {after,beforeEach,test} from 'node:test';
import assert from 'node:assert/strict';
import {initializeApp,deleteApp} from 'firebase-admin/app';
import {Firestore,getFirestore,Timestamp} from 'firebase-admin/firestore';
import {requireLocalEmulator} from './emulator-guard';
import {now,grant} from './fixtures';
import {HouseholdStore,privateHouseholdId} from '../src/households/household-store';
import {DissolutionPreparationStore,dissolutionId} from '../src/households/dissolution-preparation';
import {DissolutionPreservationStore,readPreservation,preservationSeed,preservationPageId,readPreservationPage,PRESERVATION_MERGE_CONTRACT} from '../src/households/dissolution-preservation';
import {dissolutionPreservationHandler} from '../src/households/dissolution-preservation-handler';
import {ShoppingMutationStore,advanceShoppingEpoch} from '../src/shopping/mutation-store';
import {newMutationId} from '../src/shopping/mutation-contract';
import {sourceFingerprint} from '../src/households/join-snapshot';
import {MemberLeaveStore} from '../src/households/member-leave';
import {FamilyJoinStore} from '../src/households/family-join';
import {FamilyInviteStore} from '../src/households/family-invites';
import {LifecycleStore} from '../src/billing/lifecycle-store';
requireLocalEmulator(process.env);
const app=initializeApp({projectId:'demo-kuktam-local'},'dissolution-preservation'),db=getFirestore(app);
beforeEach(async()=>{assert.ok((await fetch('http://127.0.0.1:8088/emulator/v1/projects/demo-kuktam-local/databases/(default)/documents',{method:'DELETE'})).ok);});
after(()=>deleteApp(app));
const list=async(c:FirebaseFirestore.CollectionReference)=>(await c.get()).docs.map(d=>[d.id,d.data(),d.updateTime]);
async function fixture(n=1,pending=false){
 let t=now.toMillis()+1000;const clock=()=>Timestamp.fromMillis(t),advance=()=>{t+=300001;};
 const shopping=new ShoppingMutationStore(db,clock),hid='family-test',p=privateHouseholdId('owner'),source=db.doc(`households/${hid}`),target=db.doc(`households/${p}`);
 await db.doc('shoppingRuntime/config').set({enabled:true});await db.doc('familyRuntime/config').set({inviteCreationEnabled:true,joinReservationEnabled:true});
 for(const uid of ['owner','member'])await new HouseholdStore(db).ensure({uid});
 const send=async(uid:string,c:{householdId:string;epoch:string},name:string)=>{const id=newMutationId(c.epoch);await shopping.submit({uid},{schemaVersion:1,mutationId:id,actorUid:uid,...c,kind:'ADD',payloadJson:JSON.stringify({type:'ADD',name,quantity:1,unit:'db'}),submittedAt:clock()});return id;};
 const oldPrivate=await shopping.ensureContext({uid:'owner'}),privatePending=await send('owner',oldPrivate,'old private');
 await source.set({schemaVersion:2,kind:'family',state:'ACTIVE',ownerUid:'owner',operationId:null,createdAt:now});
 for(const uid of ['owner','member']){await source.collection('members').doc(uid).set({role:uid==='owner'?'owner':'member'});await db.doc(`familyMemberships/${uid}`).set({householdId:hid,role:uid==='owner'?'owner':'member',state:'ACTIVE',operationId:null});await db.doc(`users/${uid}`).update({activeHouseholdId:hid,familyHouseholdId:hid});}
 await db.doc(`familyJoinCapacity/${hid}`).set({schemaVersion:2,operationIds:[],structuralOperationId:null});await db.doc(`familyInviteSlots/${hid}`).set({schemaVersion:1,inviteIds:[]});
 await db.doc('users/owner/entitlementGrants/pro').set(grant());
 await target.collection('shoppingItems').doc('keep').set({name:'Milk',quantity:1000,unit:'ml',isChecked:true,createdAt:now});
 const batch=db.batch();for(let i=0;i<n;i++)batch.create(source.collection('shoppingItems').doc(`i${String(i).padStart(4,'0')}`),{name:'Milk',quantity:i%2?2:300,unit:i%2?'l':'ml',isChecked:false,createdAt:now,extra:'preserve'});if(n)await batch.commit();
 const familyContext=await shopping.ensureContext({uid:'owner'}),familyPending=await send('member',familyContext,'old family');
 const invites=new FamilyInviteStore(db,{resolve:async()=>new Map()},clock),join=new FamilyJoinStore(db,clock,1000);let reservation:any=null;
 if(pending){await new HouseholdStore(db).ensure({uid:'pending'});const invite=await invites.create({uid:'owner'}),id=await join.reserve({uid:'pending'},invite.token,'ADD');reservation={id,invite};}
 const id=dissolutionId('owner',hid),ref=db.doc(`familyOperations/${id}`);await new DissolutionPreparationStore(db,clock).prepare({uid:'owner'},hid);
 const participant=(await ref.get()).get('participants'),participantHash=(await ref.get()).get('snapshotHash');
 const preservedRefs=[db.doc('users/owner'),db.doc('users/member'),db.doc('familyMemberships/owner'),db.doc('familyMemberships/member'),source.collection('members').doc('owner'),source.collection('members').doc('member'),db.doc(`familyJoinCapacity/${hid}`),db.doc(`familyInviteSlots/${hid}`)];
 if(reservation)preservedRefs.push(db.doc(`familyOperations/${reservation.id}`),db.doc(`familyInvites/${reservation.invite.inviteId}`),db.doc('familyMemberships/pending'));
 const before=(await db.getAll(...preservedRefs)).map(d=>[d.data(),d.updateTime]),items=await list(source.collection('shoppingItems')),privateItems=await list(target.collection('shoppingItems'));
 const store=new DissolutionPreservationStore(db,clock),step=()=>store.step({uid:'owner'},hid),op=async()=>readPreservation((await ref.get()).data(),id);
 const finish=async()=>{for(let i=0;i<2*Math.ceil(n/10)+10;i++){const r=await step();if(r==='PRESERVATION_COMMITTED')return r;if(r==='OPERATOR')throw new Error('unexpectedOperator');}throw new Error('stuck');};
 const boundary=async()=>{assert.deepEqual(await list(source.collection('shoppingItems')),items);assert.deepEqual(await list(target.collection('shoppingItems')),privateItems);assert.deepEqual((await db.getAll(...preservedRefs)).map(d=>[d.data(),d.updateTime]),before);const d=await ref.get();assert.deepEqual(d.get('participants'),participant);assert.equal(d.get('snapshotHash'),participantHash);assert.equal((await source.get()).get('state'),'ACTIVE');assert.equal((await target.get()).get('state'),'ACTIVE');};
 return {hid,p,id,ref,source,target,clock,advance,shopping,send,familyContext,oldPrivate,privatePending,familyPending,store,step,op,finish,boundary,join,invites,reservation};
}
for(const n of [0,1,11,25,201])test(`5C2A exact bounded snapshot ${n} preserves all shopping and topology`,async()=>{
 const f=await fixture(n);assert.equal(await f.step(),'SNAPSHOT_SHOPPING');const fenced=[await f.source.get(),await f.target.get()];await f.finish();const o=await f.op();assert.equal(o.shoppingSnapshot!.count,n);assert.equal(o.shoppingSnapshot!.pages,Math.ceil(n/10));assert.equal(o.mergeContract,PRESERVATION_MERGE_CONTRACT);
 let hash=preservationSeed(f.id,o),last:string|null=null,count=0;for(let i=0;i<o.shoppingSnapshot!.pages;i++){const page=(await f.ref.collection('shoppingPreservation').doc(preservationPageId(o,i)).get()).data(),v=readPreservationPage(page,o,i,hash,last);assert.deepEqual(readPreservationPage(page,o,i,hash,last),v);assert.deepEqual(readPreservationPage({...page,entries:page!.entries.map((e:any)=>({...e,addPayload:{unit:e.addPayload.unit,quantity:e.addPayload.quantity,name:e.addPayload.name,type:e.addPayload.type}}))},o,i,hash,last).chainHash,v.chainHash);hash=v.chainHash;last=v.entries.at(-1).sourceId;count+=v.entries.length;assert.equal(v.results.length,0);}
 assert.equal(count,n);assert.equal(hash,o.shoppingSnapshot!.hash);await f.boundary();const saved=await f.ref.get();assert.equal(await new DissolutionPreservationStore(db,f.clock).step({uid:'owner'},f.hid),'PRESERVATION_COMMITTED');assert.ok((await f.ref.get()).updateTime!.isEqual(saved.updateTime!));
 assert.ok((await f.source.get()).updateTime!.isEqual(fenced[0]!.updateTime!));assert.ok((await f.target.get()).updateTime!.isEqual(fenced[1]!.updateTime!));
});
test('5C2A both fences atomic on forced transaction failure',async()=>{
 const f=await fixture(),roots=await db.getAll(f.source,f.target,f.ref),original=db.runTransaction.bind(db),wrapped=new Proxy(db,{get(t,k){if(k==='runTransaction')return (cb:any)=>original(async tx=>{await cb(tx);throw Object.assign(new Error('forced'),{code:10});},{maxAttempts:1});const v=(t as any)[k];return typeof v==='function'?v.bind(t):v;}}) as Firestore;
 await assert.rejects(new DissolutionPreservationStore(wrapped,f.clock).step({uid:'owner'},f.hid),/forced/);assert.deepEqual((await db.getAll(f.source,f.target,f.ref)).map(d=>[d.data(),d.updateTime]),roots.map(d=>[d.data(),d.updateTime]));await f.boundary();await f.step();assert.equal((await f.source.get()).get('operationId'),f.id);assert.equal((await f.target.get()).get('operationId'),f.id);
});
test('5C2A old Family/private commands reject and new normal contexts cannot write either fence',async()=>{
 const f=await fixture();await f.finish();assert.equal(await f.shopping.process('member',f.familyPending),'REJECTED_UNAUTHORIZED');assert.equal(await f.shopping.process('owner',f.privatePending),'REJECTED_CONTEXT_CHANGED');
 for(const uid of ['owner','member'])await assert.rejects(f.shopping.ensureContext({uid}),/REJECTED_UNAUTHORIZED|REJECTED_CONTEXT_CHANGED/);
 await assert.rejects(f.send('owner',{householdId:f.p,epoch:(await f.op()).targetFence.epoch},'new target'),/REJECTED_CONTEXT_CHANGED|REJECTED_UNAUTHORIZED/);
 await assert.rejects(f.send('member',{householdId:f.hid,epoch:(await f.op()).sourceFence.epoch},'new family'),/REJECTED_UNAUTHORIZED|REJECTED_CONTEXT_CHANGED/);await f.boundary();
});
test('5C2A command committed before fence is included; pending contribution is not retargeted',async()=>{
 const f=await fixture(0);assert.equal(await f.shopping.process('member',f.familyPending),'APPLIED');await f.finish();assert.equal((await f.op()).shoppingSnapshot!.count,1);assert.equal((await f.target.collection('shoppingItems').get()).size,1);
});
test('5C2A content fingerprint changes and parsed semantic deltas are stored without merge',async()=>{
 const f=await fixture(2),doc=f.source.collection('shoppingItems').doc('i0000'),first=sourceFingerprint(await doc.get());assert.equal(first,sourceFingerprint(await doc.get()));await doc.update({quantity:500});assert.notEqual(sourceFingerprint(await doc.get()),first);await f.finish();const o=await f.op(),page=(await f.ref.collection('shoppingPreservation').doc(preservationPageId(o,0)).get()).data()!;
 assert.deepEqual(page.entries.map((e:any)=>e.addPayload),[{type:'ADD',name:'milk',quantity:500,unit:'ml'},{type:'ADD',name:'milk',quantity:2000,unit:'ml'}]);assert.equal((await f.target.collection('shoppingItems').doc('keep').get()).get('quantity'),1000);
});
test('5C2A partial preparation resumes with same epochs and immutable pages',async()=>{
 const f=await fixture(25);await f.step();await f.step();const first=(await f.ref.collection('shoppingPreservation').get()).docs[0]!,o=await f.op();await new DissolutionPreservationStore(db,f.clock).step({uid:'owner'},f.hid);await f.finish();assert.deepEqual((await f.op()).sourceFence,o.sourceFence);assert.deepEqual((await f.op()).targetFence,o.targetFence);assert.ok((await first.ref.get()).updateTime!.isEqual(first.updateTime!));await f.boundary();
});
test('5C2A lost final commit acknowledgement returns same durable point of no return',async()=>{
 const f=await fixture(11);for(let i=0;i<12;i++){await f.step();const o=await f.op();if(o.phase==='VERIFY_SHOPPING'&&o.cursor!.pageIndex===o.shoppingSnapshot!.pages)break;}
 const original=db.runTransaction.bind(db),wrapped=new Proxy(db,{get(t,k){if(k==='runTransaction')return async(...a:any[])=>{await (original as any)(...a);throw new Error('lostAck');};const v=(t as any)[k];return typeof v==='function'?v.bind(t):v;}}) as Firestore;
 await assert.rejects(new DissolutionPreservationStore(wrapped,f.clock).step({uid:'owner'},f.hid),/lostAck/);assert.equal((await f.op()).phase,'PRESERVATION_COMMITTED');const before=await db.getAll(f.ref,f.source,f.target);assert.equal(await f.step(),'PRESERVATION_COMMITTED');assert.deepEqual((await db.getAll(f.ref,f.source,f.target)).map(d=>[d.data(),d.updateTime]),before.map(d=>[d.data(),d.updateTime]));await f.boundary();
});
test('5C2A competing workers create one pair of fences and one snapshot',async()=>{
 const f=await fixture(25);await Promise.all([f.step(),f.step()]);const o=await f.op();for(let i=0;i<9&&(await f.op()).phase!=='PRESERVATION_COMMITTED';i++)await Promise.all([f.step(),f.step()]);assert.equal((await f.op()).phase,'PRESERVATION_COMMITTED');assert.equal((await f.ref.collection('shoppingPreservation').get()).size,3);assert.deepEqual((await f.op()).sourceFence,o.sourceFence);assert.deepEqual((await f.op()).targetFence,o.targetFence);await f.boundary();
});
for(const kind of ['participantHash','membershipVersion','sourceFence','targetFence','wrongTarget','structuralLock','pageHash','pageResult','sourceMissing','sourceChanged'])test(`5C2A corrupt ${kind} goes OPERATOR without compensation`,async()=>{
 const f=await fixture();await f.step();await f.step();const o=await f.op(),page=f.ref.collection('shoppingPreservation').doc(preservationPageId(o,0));
 if(kind==='participantHash')await f.ref.update({snapshotHash:'a'.repeat(64)});
 if(kind==='membershipVersion'){await db.doc('familyMemberships/member').update({role:'owner'});await db.doc('familyMemberships/member').update({role:'member'});}
 if(kind==='sourceFence')await f.source.update({operationId:'other'});
 if(kind==='targetFence')await f.target.update(advanceShoppingEpoch(f.clock()));
 if(kind==='wrongTarget')await f.ref.update({'targetFence.householdId':privateHouseholdId('member')});
 if(kind==='structuralLock')await db.doc(`familyJoinCapacity/${f.hid}`).update({structuralOperationId:'dissolve_'+'a'.repeat(64)});
 if(kind==='pageHash')await page.update({chainHash:'a'.repeat(64)});
 if(kind==='pageResult')await page.update({results:[{code:'APPLIED'}]});
 if(kind==='sourceMissing')await f.source.collection('shoppingItems').doc('i0000').delete();
 if(kind==='sourceChanged')await f.source.collection('shoppingItems').doc('i0000').update({quantity:999});
 let result='';for(let i=0;i<5&&result!=='OPERATOR';i++)result=await f.step();assert.equal(result,'OPERATOR');assert.equal(await f.step(),'OPERATOR');assert.equal((await f.target.collection('shoppingItems').doc('keep').get()).get('quantity'),1000);assert.equal((await db.doc('familyMemberships/member').get()).get('state'),'ACTIVE');assert.equal((await db.doc('users/member').get()).get('activeHouseholdId'),f.hid);
});
test('5C2A pre-fence participant mismatch enters OPERATOR with neither fence installed',async()=>{const f=await fixture();await db.doc('users/member').update({activeHouseholdId:privateHouseholdId('member')});assert.equal(await f.step(),'OPERATOR');assert.equal((await f.source.get()).get('operationId'),null);assert.equal((await f.target.get()).get('operationId'),null);});
test('5C2A committed forward-only guards preserve reservation evidence and tolerate Pro loss',async()=>{
 const f=await fixture(1,true);await f.finish();await f.boundary();const leaves=new MemberLeaveStore(db,f.clock);await assert.rejects(leaves.leave({uid:'member'},'a'.repeat(64)),/IN_PROGRESS/);await assert.rejects(leaves.remove({uid:'owner'},'member','a'.repeat(64)),/IN_PROGRESS|INTEGRITY_REQUIRES_OPERATOR/);
 for(const uid of ['owner','member'])await assert.rejects(new LifecycleStore(db,f.clock).beginDeletion(uid),/JOIN_COMMITTED_IN_PROGRESS/);
 f.advance();assert.equal(await f.join.resume(f.reservation.id),'IN_PROGRESS');await db.doc('users/owner/entitlementGrants/pro').delete();assert.equal(await f.step(),'PRESERVATION_COMMITTED');assert.equal((await db.doc(`familyJoinCapacity/${f.hid}`).get()).get('structuralOperationId'),f.id);
});
test('5C2A contradictory committed JOIN evidence cannot cross preservation point of no return',async()=>{const f=await fixture(1,true);await f.step();await db.doc(`familyOperations/${f.reservation.id}`).update({committedAt:f.clock()});assert.equal(await f.step(),'OPERATOR');assert.equal((await f.ref.get()).get('preservationCommittedAt'),null);});
test('5C2A callable validates identity and never accepts target or owner overrides',async()=>{
 let calls=0;const h=dissolutionPreservationHandler(()=>{calls++;throw new Error('secret');});await assert.rejects(h({data:{householdId:'family-test'}}),(e:any)=>e.code==='unauthenticated');for(const data of [{},{householdId:'a/b'},{householdId:'family-test',target:'private'},{householdId:'family-test',ownerUid:'owner'}])await assert.rejects(h({auth:{uid:'owner'},data}),(e:any)=>e.code==='invalid-argument');assert.equal(calls,0);
 const f=await fixture();await assert.rejects(f.store.step({uid:'member'},f.hid),/NOT_FOUND/);const project=process.env.GCLOUD_PROJECT;try{process.env.GCLOUD_PROJECT='not-demo';await assert.rejects(f.step(),/FEATURE_DISABLED/);}finally{process.env.GCLOUD_PROJECT=project;}assert.equal((await dissolutionPreservationHandler(()=>f.store)({auth:{uid:'owner'},data:{householdId:f.hid}})).phase,'SNAPSHOT_SHOPPING');
});
