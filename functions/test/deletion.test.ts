import { DeletionGateway } from '../src/accounts/deletion-gateway';
import { before, beforeEach, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeApp, deleteApp, App } from 'firebase-admin/app';
import { Firestore, Timestamp, getFirestore } from 'firebase-admin/firestore';
import { requireLocalEmulator } from './emulator-guard';
import { AccountBinding } from '../src/billing/account-binding';
import { AccountLifecycleStore } from '../src/accounts/account-lifecycle-store';
import { AccountDeletionService } from '../src/accounts/account-deletion';
import { defaultDeletionPolicy } from '../src/accounts/deletion-contract';
import { PurchaseVerifier } from '../src/billing/verify-purchase';
import { PurchaseRevoker } from '../src/billing/revoke-purchase';
import { PurchaseAcknowledger } from '../src/billing/acknowledge-purchase';
import { LifecycleStore } from '../src/billing/lifecycle-store';
import { tokenHash } from '../src/billing/purchase-identity';
import { PACKAGE_NAME, PRODUCT_ID } from '../src/billing/play-purchase-api';
import { Maintenance } from '../src/jobs/maintenance';
import { defaultMaintenancePolicy } from '../src/jobs/maintenance-policy';
import { RtdnProcessor } from '../src/billing/rtdn/processor';
import { RtdnInboxStore } from '../src/billing/rtdn/inbox-store';
import { parseEnvelope, dedupeKey } from '../src/billing/rtdn/notification';
import { FakePlayApi } from './fake-play-api';
import { FakeVoidedApi } from './fake-voided-api';
import { FakeAcknowledgmentApi } from './fake-acknowledgment-api';
import { FakeVoidedFeed } from './fake-voided-feed';
import { FakeAuthDeletionApi } from './fake-auth-deletion-api';
import { delivery, rtdnSource } from './rtdn-fixtures';
import { now, grant } from './fixtures';
requireLocalEmulator(process.env);
let db:Firestore,app:App,seq=0;
before(()=>{app=initializeApp({projectId:'demo-kuktam-local'},'n4b7');db=getFirestore(app);});
beforeEach(async()=>{const r=await fetch('http://127.0.0.1:8088/emulator/v1/projects/demo-kuktam-local/databases/(default)/documents',{method:'DELETE'});assert.ok(r.ok);});
after(async()=>{await deleteApp(app);});
const binding=new AccountBinding(Buffer.alloc(32,42));
function deferred<T>(){let resolve!:(v:T)=>void;const promise=new Promise<T>(r=>{resolve=r;});return {promise,resolve};}
async function setup(seed=true){
 const uid=`deletion-${++seq}`,token=`synthetic-delete-${seq}`,hash=tokenHash(token);let time=now;const clock=()=>time;
 const accounts=new AccountLifecycleStore(db,binding,clock);await accounts.initializeActive({uid});await accounts.register({uid},1);
 const play=new FakePlayApi(),voided=new FakeVoidedApi(),ack=new FakeAcknowledgmentApi(),auth=new FakeAuthDeletionApi(),feed=new FakeVoidedFeed();
 const response={packageName:PACKAGE_NAME,productId:PRODUCT_ID,purchaseToken:token,purchaseState:'PURCHASED',acknowledgementState:'PENDING',obfuscatedExternalAccountId:binding.forAuthenticatedAccount({uid}),testPurchase:false};
 play.respond(token,response);voided.respond({packageName:PACKAGE_NAME,productId:PRODUCT_ID,purchaseToken:token,state:'entitlementRevoked',authoritative:true,testPurchase:false});
 const store=new LifecycleStore(db,clock),deletion=new AccountDeletionService(db,auth,clock,store);
 const verify=()=>new PurchaseVerifier(db,play,binding,clock).verify({uid},{purchaseToken:token});if(seed)await verify();
 const ledger=db.doc(`billingPurchases/${hash}`),effective=db.doc(`users/${uid}/entitlements/pro`),marker=db.doc(`accountLifecycle/${uid}`),job=db.doc(`accountDeletions/${uid}`),registry=db.doc(`billingAccountBindings/${response.obfuscatedExternalAccountId}`);
 const inbox=new RtdnInboxStore(db,clock),rtdn=new RtdnProcessor(db,rtdnSource,play,voided,binding,clock,inbox);
 const maintenance=new Maintenance(db,{play,voided,ack,feed,binding,deletion},clock,defaultMaintenancePolicy,()=>0.5);
 return {uid,token,hash,clock,accounts,play,voided,ack,auth,feed,response,store,deletion,verify,ledger,effective,marker,job,registry,inbox,rtdn,maintenance,
 begin:async()=>{const r=await deletion.beginAccountDeletion({uid});await store.verifyDeletionContent({uid});return r;},finish:()=>deletion.resume(uid,50,2),advance:(ms=300000)=>{time=Timestamp.fromMillis(time.toMillis()+ms);},
 acknowledge:()=>new PurchaseAcknowledger(db,ack,clock).run(hash),revoke:()=>new PurchaseRevoker(db,voided,store).run(token)};
}
type S=Awaited<ReturnType<typeof setup>>;
async function assertClosed(s:S){assert.equal((await s.marker.get()).data()!.state,'DELETED');assert.equal((await s.effective.get()).exists,false);assert.equal((await db.collection(`users/${s.uid}/entitlementGrants`).get()).size,0);}
async function reachAuth(s:S){for(let i=0;i<20;i++){if((await s.job.get()).data()!.stage==='AUTH')return;await s.store.deletionStep(s.uid,2);}assert.fail('did not reach Auth');}
test('begin atomic barrier immediately inactivates and replay has no generation/revision churn',async()=>{const s=await setup();const a=await s.begin();assert.equal(a.outcome,'deletionStarted');assert.equal((await s.marker.get()).data()!.generation,2);assert.equal((await s.effective.get()).data()!.active,false);const b=await s.begin();assert.equal(b.operationId,a.operationId);assert.equal((await s.effective.get()).data()!.revision,2);assert.equal((await s.marker.get()).data()!.generation,2);});
test('two concurrent begins create one canonical operation',async()=>{const s=await setup();const [a,b]=await Promise.all([s.begin(),s.begin()]);assert.equal(a.operationId,b.operationId);assert.equal((await s.marker.get()).data()!.generation,2);});
for(const source of ['PROMO','ADMIN','TEST'] as const)test(`${source} account grants also disabled and removed`,async()=>{const s=await setup(false);await db.doc(`users/${s.uid}/entitlementGrants/other`).set(grant({source}));await s.store.recomputeGrants(s.uid,1);await s.begin();assert.equal((await s.effective.get()).data()!.active,false);await s.finish();await assertClosed(s);});
test('deletion waits for verified content before billing and Auth cleanup',async()=>{
 const s=await setup();const recipe=db.doc(`users/${s.uid}/recipes/keep`),shopping=db.doc(`users/${s.uid}/shopping/keep`);
 await recipe.set({title:'keep'});await shopping.set({name:'keep'});await s.begin();
 assert.equal(await s.finish(),'cleanupIncomplete');assert.equal(s.auth.calls,0);
 assert.equal((await s.ledger.get()).data()!.bindingState,'BOUND');
 await recipe.delete();await shopping.delete();await s.store.verifyDeletionContent({uid:s.uid});
 assert.equal(await s.finish(),'deletionCompleted');await assertClosed(s);
 assert.equal((await s.registry.get()).data()!.uid,undefined);
 assert.equal((await s.ledger.get()).data()!.purchaseToken,undefined);
 assert.equal(await s.deletion.handleAuthUserDeleted(s.uid),'alreadyDeleted');
});

test('token replay on new UID is rejected even fake Play advertises new binding',async()=>{const s=await setup();await s.begin();await s.finish();const b=await setup(false);b.play.respond(s.token,{...s.response,obfuscatedExternalAccountId:b.response.obfuscatedExternalAccountId});await assert.rejects(new PurchaseVerifier(db,b.play,binding,b.clock).verify({uid:b.uid},{purchaseToken:s.token}),{code:'tokenAlreadyBound'});assert.equal((await b.effective.get()).exists,false);});
test('tombstoned binding for unknown RTDN does not transfer',async()=>{const s=await setup(false);await s.begin();await s.finish();const r=await s.rtdn.handle(delivery(s.token,'late'));assert.equal(r.outcome,'bindingTombstoned');assert.equal((await s.effective.get()).exists,false);await assert.rejects(s.accounts.initializeActive({uid:s.uid}));await assert.rejects(s.accounts.register({uid:s.uid},3));});
for(const category of ['oneTime','voided'])test(`late ${category} RTDN remains terminal after tombstone`,async()=>{const s=await setup();await s.begin();await s.finish();const r=await s.rtdn.handle(delivery(s.token,'late',category));assert.equal(r.outcome,'bindingTombstoned');await assertClosed(s);const rows=(await db.collection('rtdnInbox').get()).docs;assert.equal(rows[0]!.data().transientToken,undefined);});
for(const full of [false,true])test(`verification lookup delayed across ${full?'DELETED':'DELETING'} cannot activate`,async()=>{const s=await setup(false),entered=deferred<void>(),reply=deferred<unknown>();s.play.handlers.set(s.token,async()=>{entered.resolve();return reply.promise;});const running=s.verify();const rejected=assert.rejects(running);await entered.promise;await s.begin();if(full)await s.finish();reply.resolve(s.response);await rejected;assert.notEqual((await s.effective.get()).data()?.active,true);});
for(const full of [false,true])test(`late ack success after ${full?'DELETED':'DELETING'} cannot activate`,async()=>{const s=await setup(),entered=deferred<void>(),reply=deferred<unknown>();s.ack.handler=async()=>{entered.resolve();return reply.promise;};const running=s.acknowledge().catch(()=>null);await entered.promise;await s.begin();if(full)await s.finish();reply.resolve({status:'success'});await running;assert.notEqual((await s.effective.get()).data()?.active,true);});
for(const category of ['active','grants','ack'] as const)test(`maintenance ${category} respects deletion barrier`,async()=>{const s=await setup();await s.begin();await s.maintenance.run({now:s.clock(),only:[category]});assert.equal((await s.effective.get()).data()!.active,false);assert.equal(s.ack.calls,0);});
test('maintenance deletion category resumes bounded steps to DONE',async()=>{const s=await setup();await s.begin();for(let i=0;i<12;i++)await s.maintenance.run({now:s.clock(),only:['deletion']});await assertClosed(s);assert.equal(s.auth.calls,1);});
for(const state of ['acknowledged','revoked','v1'] as const)test(`${state} ledger safely retires without inventing Play revoke`,async()=>{const s=await setup();if(state==='acknowledged')await s.acknowledge();if(state==='revoked')await s.revoke();if(state==='v1'){const d=(await s.ledger.get()).data()!;for(const k of ['lifecycleRevision','lastCheckedAt','nextCheckAt','operationalError','accountGeneration','bindingKeyVersion'])delete d[k];d.schemaVersion=1;await s.ledger.set(d);}await s.begin();await s.finish();const d=(await s.ledger.get()).data()!;assert.equal(d.schemaVersion,2);assert.equal(d.bindingState,'ACCOUNT_DELETED');assert.equal(d.purchaseToken,undefined);assert.equal((await s.ledger.collection('acknowledgment').doc('state').get()).exists,false);});
for(const stage of ['GRANTS','PURCHASES','BINDINGS','AUTH'])test(`crash/replay at ${stage} checkpoint`,async()=>{const s=await setup();await s.begin();for(let i=0;i<20&&(await s.job.get()).data()!.stage!==stage;i++)await s.store.deletionStep(s.uid,1);assert.equal((await s.job.get()).data()!.stage,stage);assert.equal((await s.effective.get()).data()!.active,false);const restarted=new AccountDeletionService(db,s.auth,s.clock);await restarted.resume(s.uid,50,1);await assertClosed(s);});
test('Auth success before completion crash is retried as already missing',async()=>{const s=await setup();await s.begin();await reachAuth(s);const claim=await s.store.deletionStep(s.uid,2);assert.equal(claim.kind,'auth');await s.auth.deleteUser(s.uid,{signal:new AbortController().signal});s.advance();await s.finish();await assertClosed(s);assert.equal(s.auth.calls,2);});
for(const status of ['temporaryFailure','permanentFailure','notFound'] as const)test(`Auth ${status} policy`,async()=>{const s=await setup();s.auth.handler=async()=>status;await s.begin();const r=await s.finish();if(status==='notFound'){assert.equal(r,'deletionCompleted');await assertClosed(s);}else{assert.equal((await s.marker.get()).data()!.state,'DELETING');assert.equal((await s.effective.get()).data()!.active,false);assert.equal(r,status==='temporaryFailure'?'authDeleteRetryRequired':'supportRequired');assert.equal(await s.finish(),status==='temporaryFailure'?'busy':'supportRequired');if(status==='temporaryFailure'){s.advance();s.auth.handler=async()=> 'deleted';await s.finish();await assertClosed(s);}}});
test('fallback needs no Auth existence or lookup and overrides permanent Auth hold',async()=>{const s=await setup();s.auth.handler=async()=> 'permanentFailure';await s.begin();await s.finish();await s.deletion.handleAuthUserDeleted(s.uid,50);await assertClosed(s);assert.equal(s.auth.calls,1);});
test('fallback unknown legacy UID creates barrier without active initialization',async()=>{const uid='legacy-gone',auth=new FakeAuthDeletionApi(),service=new AccountDeletionService(db,auth,()=>now);await db.doc(`users/${uid}/entitlementGrants/promo`).set(grant());assert.equal(await service.handleAuthUserDeleted(uid,50),'deletionCompleted');assert.equal((await db.doc(`accountLifecycle/${uid}`).get()).data()!.state,'DELETED');assert.equal(auth.calls,0);});
test('concurrent cleanup and Auth workers share durable claim',async()=>{const s=await setup();await s.begin();await reachAuth(s);const entered=deferred<void>(),reply=deferred<'deleted'>();s.auth.handler=async()=>{entered.resolve();return reply.promise;};const a=s.finish();await entered.promise;assert.equal(await s.finish(),'busy');reply.resolve('deleted');await a;await assertClosed(s);assert.equal(s.auth.calls,1);});
test('known-owner inbox rows are removed but unrelated unresolved remains',async()=>{const s=await setup();const parsed=parseEnvelope(delivery(s.token,'known'),rtdnSource);assert.ok(typeof parsed!=='string');await s.inbox.receive(parsed);const other=parseEnvelope(delivery('other-synthetic','unknown'),rtdnSource);assert.ok(typeof other!=='string');await s.inbox.receive(other);await s.begin();await s.finish();assert.equal((await db.doc(`rtdnInbox/${parsed.key}`).get()).exists,false);assert.equal((await db.doc(`rtdnInbox/${other.key}`).get()).exists,true);});
test('multiple grants/purchases/bindings paginate without skips',async()=>{const s=await setup();for(let i=0;i<5;i++){await db.doc(`users/${s.uid}/entitlementGrants/promo-${i}`).set(grant());const token=`many-${i}`;s.play.respond(token,{...s.response,purchaseToken:token});await new PurchaseVerifier(db,s.play,binding,s.clock).verify({uid:s.uid},{purchaseToken:token});}await s.begin();await s.deletion.resume(s.uid,50,1);await assertClosed(s);assert.equal((await db.collection('billingPurchases').where('boundUid','==',s.uid).get()).size,0);});
test('deleted replay does not churn marker, tombstone or Auth calls',async()=>{const s=await setup();await s.begin();await s.finish();const before=await s.marker.get(),ledger=await s.ledger.get();assert.equal((await s.begin()).outcome,'alreadyDeleted');await s.finish();assert.ok(before.updateTime!.isEqual((await s.marker.get()).updateTime!));assert.ok(ledger.updateTime!.isEqual((await s.ledger.get()).updateTime!));assert.equal(s.auth.calls,1);});
test('stale Auth lease completion cannot overwrite fallback DONE',async()=>{const s=await setup();await s.begin();await reachAuth(s);const c=await s.store.deletionStep(s.uid,1);assert.ok(c.kind==='auth');await s.deletion.handleAuthUserDeleted(s.uid,50);assert.equal(await s.store.completeDeletionAuth(s.uid,c.operationId,c.generation,c.leaseId,'deleted'),false);await assertClosed(s);});

test('binding gets explicit DELETING state before UID-free tombstone',async()=>{const s=await setup();await s.begin();await s.store.deletionStep(s.uid,1);assert.equal((await s.registry.get()).data()!.state,'DELETING');await assert.rejects(s.accounts.register({uid:s.uid},2));await s.finish();assert.equal((await s.registry.get()).data()!.state,'TOMBSTONED');assert.equal((await s.registry.get()).data()!.uid,undefined);});
test('unrelated binding and grants remain untouched',async()=>{const a=await setup(),b=await setup();const before=await b.registry.get();await a.begin();await a.finish();assert.ok(before.updateTime!.isEqual((await b.registry.get()).updateTime!));assert.equal((await b.effective.get()).data()!.active,true);});
for(const kind of ['purchased','voided','unknown'] as const)test(`RTDN ${kind} lookup races deletion barrier`,async()=>{const s=await setup(kind!=='unknown'),entered=deferred<void>(),reply=deferred<unknown>();if(kind==='voided')s.voided.handler=async()=>{entered.resolve();return reply.promise;};else s.play.handlers.set(s.token,async()=>{entered.resolve();return reply.promise;});const running=s.rtdn.handle(delivery(s.token,'race',kind==='voided'?'voided':'oneTime'));await entered.promise;await s.begin();reply.resolve(kind==='voided'?{packageName:PACKAGE_NAME,productId:PRODUCT_ID,purchaseToken:s.token,state:'entitlementRevoked',authoritative:true,testPurchase:false}:s.response);await running;assert.equal((await s.effective.get()).data()!.active,false);await s.finish();await assertClosed(s);});
test('expired RTDN lease after deletion cannot recreate grant',async()=>{const s=await setup();const p=parseEnvelope(delivery(s.token,'lease'),rtdnSource);assert.ok(typeof p!=='string');await s.inbox.receive(p);const claim=await s.inbox.claim(p.key);assert.ok(typeof claim!=='string');await s.begin();s.advance();await s.maintenance.run({now:s.clock(),only:['expiredInbox']});assert.equal((await s.effective.get()).data()!.active,false);assert.equal(await s.inbox.finish(claim,'PROCESSED','lifecycleApplied'),false);});
test('maintenance fresh active lookup across begin deletion cannot activate',async()=>{const s=await setup(),entered=deferred<void>(),reply=deferred<unknown>();s.play.handlers.set(s.token,async()=>{entered.resolve();return reply.promise;});const running=s.maintenance.run({now:s.clock(),only:['active']});await entered.promise;await s.begin();reply.resolve(s.response);await running;assert.equal((await s.effective.get()).data()!.active,false);assert.equal(s.ack.calls,0);});
test('voided catch-up during deletion is safe and does not affect user content',async()=>{const s=await setup();await s.begin();s.feed.handler=async()=>({items:[{purchaseToken:s.token,voidedTimeMs:now.toMillis()}],nextPageToken:null});await s.maintenance.run({now:s.clock(),only:['voided']});assert.equal((await s.effective.get()).data()!.active,false);await s.finish();await assertClosed(s);});
test('barrier transaction failure leaves generation and entitlement unchanged',async()=>{const s=await setup();await s.job.set({schemaVersion:999});await assert.rejects(s.begin());assert.equal((await s.marker.get()).data()!.state,'ACTIVE');assert.equal((await s.effective.get()).data()!.active,true);});
test('corrupt ledger never blindly minimalized; cleanup stays recoverable',async()=>{const s=await setup();await s.begin();const valid=(await s.ledger.get()).data()!;await s.ledger.update({schemaVersion:999});assert.equal(await s.finish(),'cleanupRetryRequired');assert.equal((await s.marker.get()).data()!.state,'DELETING');assert.equal((await s.effective.get()).data()!.active,false);assert.equal(s.auth.calls,0);await s.ledger.set(valid);await s.finish();await assertClosed(s);});
test('stale deletion generation cannot cleanup or call Auth',async()=>{const s=await setup();await s.begin();await s.marker.update({generation:99});assert.equal(await s.finish(),'cleanupRetryRequired');assert.equal(s.auth.calls,0);assert.equal((await s.ledger.get()).data()!.bindingState,'BOUND');});
test('bounded grant pages resume from remaining rows without skipping',async()=>{const s=await setup(false);for(let i=0;i<7;i++)await db.doc(`users/${s.uid}/entitlementGrants/${i}`).set(grant());await s.begin();await s.store.deletionStep(s.uid,2);await s.store.deletionStep(s.uid,2);await s.store.deletionStep(s.uid,2);assert.equal((await db.collection(`users/${s.uid}/entitlementGrants`).get()).size,5);await s.finish();await assertClosed(s);});
test('fallback crash after barrier resumes without invoking Auth adapter',async()=>{const s=await setup();assert.equal(await s.deletion.handleAuthUserDeleted(s.uid,1),'cleanupRetryRequired');assert.equal((await s.effective.get()).data()!.active,false);await new AccountDeletionService(db,s.auth,s.clock).handleAuthUserDeleted(s.uid,50);await assertClosed(s);assert.equal(s.auth.calls,0);});
test('Auth expired lease takeover fences old completion',async()=>{const s=await setup();await s.begin();await reachAuth(s);const a=await s.store.deletionStep(s.uid,1);assert.ok(a.kind==='auth');s.advance();const b=await s.store.deletionStep(s.uid,1);assert.ok(b.kind==='auth');assert.equal(await s.store.completeDeletionAuth(s.uid,a.operationId,a.generation,a.leaseId,'deleted'),false);assert.equal(await s.store.completeDeletionAuth(s.uid,b.operationId,b.generation,b.leaseId,'notFound'),true);await s.finish();await assertClosed(s);});
test('temporary Auth timeout is bounded, aborts and preserves barrier',async()=>{const s=await setup();let signal:AbortSignal|undefined;s.auth.handler=async(_uid,o)=>{signal=o.signal;return new Promise(()=>{});};const service=new AccountDeletionService(db,s.auth,s.clock,s.store,{...defaultDeletionPolicy,ioTimeoutMs:5});await s.begin();assert.equal(await service.resume(s.uid,50),'authDeleteRetryRequired');assert.equal(signal!.aborted,true);assert.equal((await s.marker.get()).data()!.state,'DELETING');assert.equal((await s.effective.get()).data()!.active,false);});

test('legacy DELETED marker without coordinated cleanup is repaired by fallback',async()=>{const s=await setup();await s.accounts.advance({uid:s.uid},1,'DELETING');await s.accounts.advance({uid:s.uid},2,'DELETED');assert.equal((await s.effective.get()).data()!.active,false);await s.deletion.handleAuthUserDeleted(s.uid,50);await assertClosed(s);assert.equal((await s.marker.get()).data()!.generation,3);assert.equal(s.auth.calls,0);assert.equal((await s.ledger.get()).data()!.purchaseToken,undefined);});
test('transaction failure during ledger retirement rolls back the whole page',async()=>{const s=await setup();await s.begin();for(let i=0;i<10&&(await s.job.get()).data()!.stage!=='PURCHASES';i++)await s.store.deletionStep(s.uid,1);const before=await s.ledger.get();const original=db.runTransaction.bind(db);(db as any).runTransaction=(fn:any)=>original(async tx=>{await fn(tx);throw new Error('injected-commit-crash');});try{await assert.rejects(s.store.deletionStep(s.uid,1));}finally{(db as any).runTransaction=original;}assert.ok(before.updateTime!.isEqual((await s.ledger.get()).updateTime!));assert.equal((await s.effective.get()).data()!.active,false);await s.finish();await assertClosed(s);});

for(const kind of ['grant','ledgerIdentity','inbox','bindingIdentity','ack'] as const)test(`closure: corrupt ${kind} preserved during cleanup`,async()=>{
 const s=await setup();await s.begin();let ref;
 if(kind==='grant'){ref=db.doc(`users/${s.uid}/entitlementGrants/corrupt`);await ref.set({source:'PROMO'});}
 else if(kind==='ledgerIdentity'){ref=s.ledger;await ref.update({purchaseToken:'different-synthetic-token'});}
 else if(kind==='inbox'){ref=db.doc('rtdnInbox/corrupt');await ref.set({tokenHash:s.hash});}
 else if(kind==='ack'){ref=s.ledger.collection('acknowledgment').doc('state');await ref.set({schemaVersion:999});}
 else{ref=s.registry;await ref.update({keyVersion:'v2'});}
 const before=await ref.get();assert.equal(await s.finish(),'cleanupRetryRequired');
 assert.ok(before.updateTime!.isEqual((await ref.get()).updateTime!));assert.equal(s.auth.calls,0);
 assert.equal((await s.effective.get()).data()!.active,false);
});
test('closure: maintenance cannot delete Auth before profile cleanup',async()=>{
 const s=await setup();const root=db.doc(`users/${s.uid}`);await root.set({legacy:true});await s.begin();
 for(let i=0;i<10;i++)await s.maintenance.run({now:s.clock(),only:['deletion']});
 assert.equal(s.auth.calls,0);assert.equal((await s.marker.get()).data()!.state,'DELETING');
 await root.delete();await s.store.verifyDeletionContent({uid:s.uid});await s.finish();await assertClosed(s);
});

for(const path of ['recipes/r','shopping/s',''])test(`P0C content barrier: ${path||'root'} independently blocks`,async()=>{
 const s=await setup();const ref=db.doc(`users/${s.uid}${path?'/'+path:''}`);await ref.set({keep:true});
 await s.deletion.beginAccountDeletion({uid:s.uid});
 assert.equal((await s.job.get()).data()!.cleanupState,'PENDING');
 assert.equal(await s.deletion.finalizeContent({uid:s.uid}),'cleanupIncomplete');
 for(let i=0;i<3;i++){s.advance();await s.maintenance.run({now:s.clock(),only:['deletion']});}
 assert.equal(s.auth.calls,0);assert.equal((await s.marker.get()).data()!.state,'DELETING');
 assert.equal((await s.effective.get()).data()!.active,false);
 await ref.delete();await s.store.verifyDeletionContent({uid:s.uid});await s.finish();await assertClosed(s);
});
test('P0C empty content still needs durable verification; concurrent verify is idempotent',async()=>{
 const s=await setup();await s.deletion.beginAccountDeletion({uid:s.uid});
 assert.equal(await s.finish(),'cleanupIncomplete');assert.equal(s.auth.calls,0);
 assert.deepEqual(await Promise.all([s.store.verifyDeletionContent({uid:s.uid}),s.store.verifyDeletionContent({uid:s.uid})]),['VERIFIED','VERIFIED']);
 const before=await s.job.get();await s.store.verifyDeletionContent({uid:s.uid});
 assert.ok(before.updateTime!.isEqual((await s.job.get()).updateTime!));
 await s.finish();assert.equal(s.auth.calls,1);assert.equal(await s.deletion.finalizeContent({uid:s.uid}),'alreadyDeleted');
});
test('P0C legacy operation without evidence and expired lease cannot delete Auth',async()=>{
 const s=await setup();await s.begin();await reachAuth(s);const {cleanupState,...old}=(await s.job.get()).data()!;
 await s.job.set({...old,schemaVersion:1,leaseId:'old-worker',leaseUntil:Timestamp.fromMillis(1)});
 assert.equal(await s.finish(),'cleanupIncomplete');assert.equal(s.auth.calls,0);
 assert.equal(await s.store.completeDeletionAuth(s.uid,old.operationId,old.generation,'old-worker','deleted'),false);
 await s.store.verifyDeletionContent({uid:s.uid});assert.equal((await s.job.get()).data()!.schemaVersion,2);
 await s.finish();await assertClosed(s);
});
test('P0C claim rechecks content even after VERIFIED; no stale evidence bypass',async()=>{
 const s=await setup();await s.begin();await reachAuth(s);
 await db.doc(`users/${s.uid}/recipes/admin-created`).set({title:'late'});
 assert.equal((await s.store.deletionStep(s.uid,1)).kind,'cleanupIncomplete');
 assert.equal((await s.job.get()).data()!.cleanupState,'PENDING');assert.equal(s.auth.calls,0);
});
test('P0C malformed evidence and changed generation fail closed',async()=>{
 const s=await setup();await s.begin();await s.job.update({cleanupState:'client-true'});
 assert.equal(await s.finish(),'cleanupRetryRequired');assert.equal(s.auth.calls,0);
 await assert.rejects(s.store.verifyDeletionContent({uid:s.uid}));
});
test('P0C modern gateway rejects spoofed UID, evidence and fallback flag',async()=>{
 const s=await setup();const gate=new DeletionGateway(s.deletion,()=>s.clock().toMillis());
 const auth={uid:s.uid,authTimeSeconds:Math.floor(s.clock().toMillis()/1000)};
 for(const data of [{uid:s.uid},{cleanupComplete:true},{authGone:true}]){
  await assert.rejects(gate.begin(auth,data));await assert.rejects(gate.finalize(auth,data));
 }
 await assert.rejects(gate.begin(null,{}));assert.equal((await s.job.get()).exists,false);
 await gate.begin(auth,{});assert.equal((await s.job.get()).data()!.authGone,false);
 assert.equal(await s.finish(),'cleanupIncomplete');assert.equal(s.auth.calls,0);
});
test('P0C legacy external Auth event bypasses only already-gone Auth, not content deletes',async()=>{
 const s=await setup();const ref=db.doc(`users/${s.uid}/recipes/orphan`);await ref.set({x:1});
 await s.deletion.handleAuthUserDeleted(s.uid,50);await assertClosed(s);assert.equal(s.auth.calls,0);
 assert.equal((await ref.get()).exists,true);assert.equal((await s.registry.get()).data()!.state,'TOMBSTONED');
});
