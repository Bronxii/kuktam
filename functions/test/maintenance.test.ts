import { before, beforeEach, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeApp, deleteApp, App } from 'firebase-admin/app';
import { Firestore, Timestamp, getFirestore } from 'firebase-admin/firestore';
import { requireLocalEmulator } from './emulator-guard';
import { AccountBinding } from '../src/billing/account-binding';
import { AccountLifecycleStore } from '../src/accounts/account-lifecycle-store';
import { PurchaseVerifier } from '../src/billing/verify-purchase';
import { PurchaseRevoker } from '../src/billing/revoke-purchase';
import { PurchaseAcknowledger } from '../src/billing/acknowledge-purchase';
import { LifecycleStore } from '../src/billing/lifecycle-store';
import { tokenHash, playGrantId } from '../src/billing/purchase-identity';
import { PACKAGE_NAME, PRODUCT_ID, PlayLookupError } from '../src/billing/play-purchase-api';
import { Maintenance } from '../src/jobs/maintenance';
import { MaintenanceStore, workKey, WorkClaim } from '../src/jobs/maintenance-store';
import { defaultMaintenancePolicy, Category } from '../src/jobs/maintenance-policy';
import { RtdnProcessor } from '../src/billing/rtdn/processor';
import { RtdnInboxStore, readInbox } from '../src/billing/rtdn/inbox-store';
import { parseEnvelope, dedupeKey } from '../src/billing/rtdn/notification';
import { FakePlayApi } from './fake-play-api';
import { FakeVoidedApi } from './fake-voided-api';
import { FakeAcknowledgmentApi } from './fake-acknowledgment-api';
import { FakeVoidedFeed } from './fake-voided-feed';
import { delivery, rtdnSource } from './rtdn-fixtures';
import { now, grant } from './fixtures';
requireLocalEmulator(process.env);
let db:Firestore,app:App,sequence=0;
before(()=>{app=initializeApp({projectId:'demo-kuktam-local'},'n4b6');db=getFirestore(app);});
beforeEach(async()=>{const response=await fetch('http://127.0.0.1:8088/emulator/v1/projects/demo-kuktam-local/databases/(default)/documents',{method:'DELETE'});assert.ok(response.ok);});
after(async()=>{await deleteApp(app);});
const binding=new AccountBinding(Buffer.alloc(32,84));
const policy={...defaultMaintenancePolicy,pageSize:2,retry:{...defaultMaintenancePolicy.retry,attemptsPerGeneration:2}};
function deferred<T>(){let resolve!:(v:T)=>void;const promise=new Promise<T>(r=>{resolve=r;});return {promise,resolve};}
async function setup(seed=true){
 const uid=`maintenance-${++sequence}`,token=`synthetic-maintenance-${sequence}`,hash=tokenHash(token);let time=now;
 const clock=()=>time,accounts=new AccountLifecycleStore(db,binding,clock);await accounts.initializeActive({uid});await accounts.register({uid},1);
 const play=new FakePlayApi(),voided=new FakeVoidedApi(),ack=new FakeAcknowledgmentApi(),feed=new FakeVoidedFeed();
 const response={packageName:PACKAGE_NAME,productId:PRODUCT_ID,purchaseToken:token,purchaseState:'PURCHASED',acknowledgementState:'PENDING',obfuscatedExternalAccountId:binding.forAuthenticatedAccount({uid}),testPurchase:false};
 const observation={packageName:PACKAGE_NAME,productId:PRODUCT_ID,purchaseToken:token,state:'entitlementRevoked',authoritative:true,testPurchase:false};
 play.respond(token,response);voided.respond(observation);
 const verify=()=>new PurchaseVerifier(db,play,binding,clock).verify({uid},{purchaseToken:token});if(seed)await verify();
 const deps={play,voided,ack,feed,binding};
 const service=(work?:MaintenanceStore)=>new Maintenance(db,deps,clock,policy,()=>0.5,work);
 const run=(only:Category[],work?:MaintenanceStore)=>service(work).run({now:clock(),only});
 const inbox=new RtdnInboxStore(db,clock,policy.retry,()=>0.5),processor=new RtdnProcessor(db,rtdnSource,play,voided,binding,clock,inbox);
 const event=()=>delivery(token,uid),key=dedupeKey(rtdnSource,uid),inboxRef=db.doc(`rtdnInbox/${key}`);
 const ledger=db.doc(`billingPurchases/${hash}`),effective=db.doc(`users/${uid}/entitlements/pro`),ackRef=ledger.collection('acknowledgment').doc('state');
 return {uid,token,hash,clock,accounts,play,voided,ack,feed,response,observation,verify,service,run,inbox,processor,event,key,inboxRef,ledger,effective,ackRef,
  advance:(ms=policy.recoveryRoundMs)=>{time=Timestamp.fromMillis(time.toMillis()+ms);},
  acknowledge:()=>new PurchaseAcknowledger(db,ack,clock,policy.retry,()=>0.5).run(hash),
  revoke:()=>new PurchaseRevoker(db,voided,new LifecycleStore(db,clock)).run(token)};
}
type S=Awaited<ReturnType<typeof setup>>;
async function exhausted(s:S){s.ack.handler=async()=>({status:'temporaryFailure'});await s.acknowledge();s.advance(60000);await s.acknowledge();assert.equal((await s.ackRef.get()).data()!.status,'acknowledgmentExhausted');s.advance();s.ack.handler=async()=>({status:'success'});}
async function legacy(s:S){const d=(await s.ledger.get()).data()!;for(const k of ['lifecycleRevision','lastCheckedAt','nextCheckAt','operationalError','accountGeneration','bindingKeyVersion'])delete d[k];d.schemaVersion=1;await s.ledger.set(d);}
async function received(s:S){const d=parseEnvelope(s.event(),rtdnSource);assert.ok(typeof d!=='string');await s.inbox.receive(d);return d;}
test('unchanged acknowledged recheck updates schedule without either revision',async()=>{const s=await setup();s.play.respond(s.token,{...s.response,acknowledgementState:'ACKNOWLEDGED'});await s.verify();const before=(await s.ledger.get()).data()!;await s.run(['active']);const after=(await s.ledger.get()).data()!;assert.equal(after.lifecycleRevision,before.lifecycleRevision);assert.equal((await s.effective.get()).data()!.revision,1);assert.equal(after.nextCheckAt.toMillis(),s.clock().toMillis()+policy.activeIntervalMs);assert.equal(s.ack.calls,0);const calls=s.play.calls;await s.run(['active']);assert.equal(s.play.calls,calls);});
for(const config of [false,true])test(`active lookup ${config?'config':'transient'} preserves Pro and schedules safely`,async()=>{const s=await setup();s.play.handlers.set(s.token,async()=>{throw new PlayLookupError(config?'configuration':'unavailable');});await s.run(['active']);assert.equal((await s.effective.get()).data()!.active,true);const w=(await db.doc(`billingMaintenance/${workKey('purchase',s.hash)}`).get()).data()!;assert.equal(w.status,config?'OPERATOR':'READY');const calls=s.play.calls;await s.run(['active']);assert.equal(s.play.calls,calls);});
test('active canceled observation requires fresh revoke proof',async()=>{const s=await setup();s.play.respond(s.token,{...s.response,purchaseState:'CANCELED'});await s.run(['active']);assert.equal((await s.effective.get()).data()!.active,false);assert.equal(s.voided.calls,1);});
test('wrong binding cannot alter grant',async()=>{const s=await setup();s.play.respond(s.token,{...s.response,obfuscatedExternalAccountId:'invalid'});await s.run(['active']);assert.equal((await s.effective.get()).data()!.revision,1);});
for(const state of ['DELETING','DELETED'] as const)test(`active recheck on ${state} never activates`,async()=>{const s=await setup();await s.accounts.advance({uid:s.uid},1,'DELETING');if(state==='DELETED')await s.accounts.advance({uid:s.uid},2,'DELETED');await s.run(['active']);assert.equal(s.ack.calls,0);assert.equal((await s.effective.get()).data()!.revision,2);assert.equal((await s.effective.get()).data()!.active,false);});
test('exhausted ack starts fresh generation preserving total attempts',async()=>{const s=await setup();await exhausted(s);await s.run(['ack']);const a=(await s.ackRef.get()).data()!;assert.equal(a.status,'acknowledged');assert.equal(a.recoveryGeneration,2);assert.equal(a.totalAttempts,3);assert.equal(a.attemptCount,1);assert.equal((await s.effective.get()).data()!.revision,1);});
test('exhausted but Play acknowledged repairs without extra ack',async()=>{const s=await setup();await exhausted(s);s.play.respond(s.token,{...s.response,acknowledgementState:'ACKNOWLEDGED'});await s.run(['ack']);assert.equal(s.ack.calls,2);assert.equal((await s.ackRef.get()).data()!.status,'acknowledged');});
test('exhausted revoked purchase uses revoke not restart',async()=>{const s=await setup();await exhausted(s);s.play.respond(s.token,{...s.response,purchaseState:'CANCELED'});await s.run(['ack']);assert.equal(s.ack.calls,2);assert.equal((await s.effective.get()).data()!.active,false);});
for(const state of ['DELETING','DELETED'] as const)test(`exhausted ${state} no restart`,async()=>{const s=await setup();await exhausted(s);await s.accounts.advance({uid:s.uid},1,'DELETING');if(state==='DELETED')await s.accounts.advance({uid:s.uid},2,'DELETED');await s.run(['ack']);assert.equal(s.ack.calls,2);assert.equal((await s.ackRef.get()).data()!.recoveryGeneration,1);});
test('exhausted lookup failure preserves total and Pro',async()=>{const s=await setup();await exhausted(s);s.play.handlers.set(s.token,async()=>{throw new PlayLookupError('unavailable');});await s.run(['ack']);assert.equal((await s.ackRef.get()).data()!.totalAttempts,2);assert.equal((await s.effective.get()).data()!.active,true);});
test('retry inbox only processes when due',async()=>{const s=await setup();s.play.handlers.set(s.token,async()=>{throw new PlayLookupError('unavailable');});await s.processor.handle(s.event());s.play.respond(s.token,s.response);const calls=s.play.calls;await s.run(['retryInbox']);assert.equal(s.play.calls,calls);s.advance();await s.run(['retryInbox']);assert.equal((await s.inboxRef.get()).data()!.status,'PROCESSED');assert.equal((await s.inboxRef.get()).data()!.totalAttempts,2);});
test('expired inbox lease takeover fences old completion',async()=>{const s=await setup();await received(s);const old=await s.inbox.claim(s.key);assert.ok(typeof old!=='string');await s.run(['expiredInbox']);assert.equal((await s.inboxRef.get()).data()!.status,'PROCESSING');s.advance();await s.run(['expiredInbox']);assert.equal((await s.inboxRef.get()).data()!.status,'PROCESSED');assert.equal(await s.inbox.finish(old,'RETRY','retryablePlayFailure'),false);});
test('unresolved later binding resolution succeeds and purges token',async()=>{const s=await setup(false);const ref=db.doc(`billingAccountBindings/${s.response.obfuscatedExternalAccountId}`),b=(await ref.get()).data()!;await ref.delete();await s.processor.handle(s.event());assert.equal((await s.inboxRef.get()).data()!.transientToken,s.token);await ref.set(b);s.advance();await s.run(['unresolvedInbox']);assert.equal((await s.effective.get()).data()!.active,true);assert.equal((await s.inboxRef.get()).data()!.transientToken,undefined);});
test('unresolved rounds preserve totals then operator hold without spin',async()=>{const s=await setup(false);s.play.respond(s.token,{...s.response,obfuscatedExternalAccountId:null});await s.processor.handle(s.event());for(let i=0;i<12;i++){s.advance(2*86400000);await s.run(['unresolvedInbox']);}const r=readInbox((await s.inboxRef.get()).data());assert.equal(r.operatorRequired,true);assert.equal(r.totalAttempts,6);assert.equal(r.recoveryGeneration,3);assert.equal(r.transientToken,s.token);const calls=s.play.calls;await s.run(['unresolvedInbox']);assert.equal(s.play.calls,calls);});
test('tombstone closes unresolved and removes transient token',async()=>{const s=await setup(false);await db.doc(`billingAccountBindings/${s.response.obfuscatedExternalAccountId}`).set({schemaVersion:1,state:'TOMBSTONED',keyVersion:'v1',createdAt:now,updatedAt:now});await received(s);await s.run(['retryInbox']);assert.equal((await s.inboxRef.get()).data()!.transientToken,undefined);assert.equal((await s.effective.get()).exists,false);});
test('token copy becomes redundant after external verification',async()=>{const s=await setup(false);await received(s);await s.verify();await s.run(['tokens']);assert.equal((await s.inboxRef.get()).data()!.transientToken,undefined);await s.run(['retryInbox']);assert.equal((await s.inboxRef.get()).data()!.status,'PROCESSED');});
for(const kind of ['revoke','refund','PROMO','ADMIN','legacy'] as const)test(`voided catchup ${kind} uses authoritative path`,async()=>{const s=await setup();if(kind==='legacy')await legacy(s);if(kind==='PROMO'||kind==='ADMIN'){await db.doc(`users/${s.uid}/entitlementGrants/other`).set(grant({source:kind}));await s.verify();}if(kind==='refund')s.voided.respond({...s.observation,state:'financialRefund'});s.feed.handler=async()=>({items:[{purchaseToken:s.token,voidedTimeMs:now.toMillis()}],nextPageToken:null});await s.run(['voided']);assert.equal((await s.effective.get()).data()!.active,['refund','PROMO','ADMIN'].includes(kind));assert.equal(s.voided.calls,1);});
test('feed page checkpoint survives duplicate records and cursor resume',async()=>{const s=await setup();s.feed.handler=async q=>({items:[{purchaseToken:s.token,voidedTimeMs:now.toMillis()}],nextPageToken:q.pageToken===null?'next':null});await s.run(['voided']);await s.run(['voided']);assert.equal(s.feed.calls[1]!.pageToken,'next');assert.equal((await s.effective.get()).data()!.revision,2);assert.equal((await db.collection('rtdnInbox').get()).size,1);});
test('unknown catchup owner is durable unresolved; feed cursor can advance',async()=>{const s=await setup(false);s.play.respond(s.token,{...s.response,obfuscatedExternalAccountId:null});s.feed.handler=async()=>({items:[{purchaseToken:s.token,voidedTimeMs:now.toMillis()}],nextPageToken:null});await s.run(['voided']);const e=(await db.collection('rtdnInbox').get()).docs[0]!.data();assert.equal(e.status,'UNRESOLVED');assert.equal(e.transientToken,s.token);assert.equal((await s.effective.get()).exists,false);});
test('feed outage keeps entitlement and retries without advancing checkpoint',async()=>{const s=await setup();s.feed.handler=async()=>{throw new Error('unavailable');};await s.run(['voided']);assert.equal((await s.effective.get()).data()!.active,true);const w=(await db.doc(`billingMaintenance/${workKey('feed','voided')}`).get()).data()!;assert.equal(w.progress,null);assert.equal(w.status,'READY');});
test('grant future start and expiry recompute once per effective change',async()=>{const s=await setup(false);await db.doc(`users/${s.uid}/entitlementGrants/promo`).set(grant({startsAt:Timestamp.fromMillis(now.toMillis()+1000),expiresAt:Timestamp.fromMillis(now.toMillis()+2000)}));await s.run(['grants']);assert.equal((await s.effective.get()).exists,false);s.advance(1000);await s.run(['grants']);assert.equal((await s.effective.get()).data()!.active,true);await s.run(['grants']);assert.equal((await s.effective.get()).data()!.revision,1);s.advance(1000);await s.run(['grants']);assert.equal((await s.effective.get()).data()!.active,false);assert.equal((await s.effective.get()).data()!.revision,2);});
test('pagination limit plus one, cursor resume, and wrap',async()=>{const s=await setup();await setup();await setup();const first=await s.service().run({now:s.clock(),only:['active']});assert.equal(first.items.length,2);assert.ok(first.cursors.active);const second=await s.service().run({now:s.clock(),only:['active'],cursors:first.cursors});assert.equal(second.items.length,1);assert.equal(second.cursors.active,null);assert.notEqual(first.items[0]!.key,second.items[0]!.key);});
test('concurrent maintenance workers share one live purchase lease',async()=>{const s=await setup();const entered=deferred<void>(),reply=deferred<unknown>();s.play.handlers.set(s.token,async()=>{entered.resolve();return reply.promise;});const first=s.run(['active']);await entered.promise;const second=await s.run(['active']);assert.equal(second.items[0]!.outcome,'notDueOrBusy');reply.resolve(s.response);await first;assert.equal(s.ack.calls,1);assert.equal((await s.effective.get()).data()!.revision,1);});
for(const race of ['revoke','delete','directVerify'] as const)test(`maintenance lookup raced with ${race} cannot overwrite newer state`,async()=>{const s=await setup();const entered=deferred<void>(),reply=deferred<unknown>();s.play.handlers.set(s.token,async()=>{entered.resolve();return reply.promise;});const running=s.run(['active']);await entered.promise;if(race==='revoke')await s.revoke();else if(race==='delete')await s.accounts.advance({uid:s.uid},1,'DELETING');else {s.play.respond(s.token,s.response);await s.verify();}reply.resolve(s.response);await running;assert.equal((await s.effective.get()).data()!.active,race==='directVerify');if(race!=='directVerify')assert.equal(s.ack.calls,0);});
test('lifecycle success then work completion crash safely replays',async()=>{const s=await setup();class CrashStore extends MaintenanceStore{override async finish(..._args:Parameters<MaintenanceStore['finish']>):Promise<boolean>{throw new Error('crash');}}const store=new CrashStore(db,s.clock,policy.leaseMs);await s.run(['active'],store);assert.equal((await s.effective.get()).data()!.revision,1);const rev=(await s.ledger.get()).data()!.lifecycleRevision;s.advance(policy.activeIntervalMs+policy.leaseMs);s.play.respond(s.token,{...s.response,acknowledgementState:'ACKNOWLEDGED'});await s.run(['active']);assert.equal((await s.ledger.get()).data()!.lifecycleRevision,rev);assert.equal((await s.effective.get()).data()!.revision,1);assert.equal(s.ack.calls,1);});
test('work lease crash takeover rejects stale writer',async()=>{const s=await setup();const store=new MaintenanceStore(db,s.clock,policy.leaseMs),key=workKey('purchase',s.hash),a=await store.claim(key);assert.ok(a);assert.equal(await store.claim(key),null);s.advance();const b=await store.claim(key);assert.ok(b);await assert.rejects(store.finish(a,'success',null));await store.finish(b,'success',null);});
test('v1 ledger is recovered through maintenance existing writer',async()=>{const s=await setup();await legacy(s);await s.run(['active']);assert.equal((await s.ledger.get()).data()!.schemaVersion,2);assert.equal((await s.effective.get()).data()!.revision,1);});

test('active path cannot bypass exhausted cooldown',async()=>{const s=await setup();s.ack.handler=async()=>({status:'temporaryFailure'});await s.acknowledge();s.advance(60000);await s.acknowledge();await s.run(['active']);assert.equal((await s.ackRef.get()).data()!.recoveryGeneration,1);assert.equal(s.ack.calls,2);});
test('generation cap leaves explicit operator state and Pro intact',async()=>{const s=await setup();await exhausted(s);s.ack.handler=async()=>({status:'temporaryFailure'});for(let i=0;i<8;i++){s.advance(2*policy.recoveryRoundMs);await s.run(['ack']);}const a=(await s.ackRef.get()).data()!;assert.equal(a.recoveryGeneration,3);assert.equal(a.totalAttempts,6);assert.equal((await s.effective.get()).data()!.active,true);assert.equal((await db.doc(`billingMaintenance/${workKey('purchase',s.hash)}`).get()).data()!.status,'OPERATOR');});
for(const race of ['delete','revoke'] as const)test(`maintenance external ack completion fenced after ${race}`,async()=>{const s=await setup();const entered=deferred<void>(),result=deferred<unknown>();s.ack.handler=async()=>{entered.resolve();return result.promise;};const running=s.run(['active']);await entered.promise;if(race==='delete')await s.accounts.advance({uid:s.uid},1,'DELETING');else await s.revoke();result.resolve({status:'success'});await running;assert.notEqual((await s.ledger.get()).data()!.acknowledgementState,'ACKNOWLEDGED');if(race==='revoke')assert.equal((await s.effective.get()).data()!.active,false);});
test('maintenance stale external result loses expired work lease to takeover',async()=>{const s=await setup();const entered=deferred<void>(),reply=deferred<unknown>();s.play.handlers.set(s.token,async()=>{entered.resolve();return reply.promise;});const first=s.run(['active']);await entered.promise;s.advance(policy.leaseMs+1);s.play.respond(s.token,s.response);await s.run(['active']);const revision=(await s.ledger.get()).data()!.lifecycleRevision;reply.resolve(s.response);await first;assert.equal((await s.ledger.get()).data()!.lifecycleRevision,revision);assert.equal(s.ack.calls,1);});
test('feed duplicate workers cannot steal active page claim',async()=>{const s=await setup();const entered=deferred<void>(),reply=deferred<unknown>();s.feed.handler=async()=>{entered.resolve();return reply.promise;};const a=s.run(['voided']);await entered.promise;const b=await s.run(['voided']);assert.equal(b.items[0]!.outcome,'notDueOrBusy');reply.resolve({items:[],nextPageToken:null});await a;assert.equal(s.feed.calls.length,1);});
test('malformed and configuration inbox holds do not spin',async()=>{const s=await setup();s.play.handlers.set(s.token,async()=>{throw new PlayLookupError('configuration');});await s.processor.handle(s.event());const calls=s.play.calls;s.advance(86400000);await s.run(['unresolvedInbox']);assert.equal(s.play.calls,calls);assert.equal((await s.effective.get()).data()!.active,true);});
test('legacy inbox and ack normalize without losing total attempts',async()=>{const s=await setup();await exhausted(s);const a=(await s.ackRef.get()).data()!;for(const k of ['recoveryGeneration','totalAttempts','accountGeneration','lifecycleRevision'])delete a[k];a.schemaVersion=1;await s.ackRef.set(a);await received(s);const r=(await s.inboxRef.get()).data()!;for(const k of ['recoveryGeneration','totalAttempts','lastAttemptAt','operatorRequired'])delete r[k];r.schemaVersion=1;await s.inboxRef.set(r);await s.run(['ack','retryInbox']);assert.equal((await s.ackRef.get()).data()!.totalAttempts,3);assert.equal((await s.inboxRef.get()).data()!.schemaVersion,2);});
test('exact limit followed by empty page returns null cursor',async()=>{const s=await setup();await setup();const a=await s.service().run({now:s.clock(),only:['active']});assert.ok(a.cursors.active);const b=await s.service().run({now:s.clock(),only:['active'],cursors:a.cursors});assert.equal(b.items.length,0);assert.equal(b.cursors.active,null);});
test('runtime budget returns resumable cursor without starting more work',async()=>{const s=await setup();let ticks=0;const m=new Maintenance(db,{play:s.play,voided:s.voided,ack:s.ack,feed:s.feed,binding},s.clock,policy,()=>0.5,undefined,()=>ticks++*policy.runBudgetMs);const r=await m.run({now:s.clock()});assert.equal(r.budgetReached,true);assert.equal(r.items.length,0);});
test('bad item is isolated and later item still processed',async()=>{const s=await setup();await db.doc('billingPurchases/000-corrupt').set({schemaVersion:999});const result=await s.run(['active']);assert.ok(result.items.some(i=>i.outcome==='internalConflict'));assert.equal(s.ack.calls,1);});
test('grant expiry recompute cannot reactivate DELETING account',async()=>{const s=await setup(false);await db.doc(`users/${s.uid}/entitlementGrants/promo`).set(grant());await s.accounts.advance({uid:s.uid},1,'DELETING');await s.run(['grants']);assert.equal((await s.effective.get()).data()!.active,false);});

for(const end of ['acknowledged','revoke'] as const)test(`crash after new recovery generation before first attempt then ${end}`,async()=>{const s=await setup();await exhausted(s);await new PurchaseVerifier(db,s.play,binding,s.clock).verify({uid:s.uid},{purchaseToken:s.token},{maxGenerations:3,cooldownMs:policy.recoveryRoundMs,policy:policy.retry});assert.equal((await s.ackRef.get()).data()!.attemptCount,0);if(end==='revoke'){await s.revoke();assert.equal((await s.effective.get()).data()!.active,false);assert.equal((await s.ackRef.get()).data()!.status,'acknowledgmentCanceled');}else{s.play.respond(s.token,{...s.response,acknowledgementState:'ACKNOWLEDGED'});await s.run(['ack']);assert.equal((await s.ackRef.get()).data()!.status,'acknowledged');assert.equal(s.ack.calls,2);}assert.equal((await s.ackRef.get()).data()!.totalAttempts,2);});

test('closure: maintenance lease respects nanosecond expiry and exact boundary',async()=>{
 const s=await setup(false),work=new MaintenanceStore(db,s.clock,120000),key=workKey('closure','lease');
 const c=await work.claim(key);assert.ok(c);s.advance(120000);const t=s.clock();
 await db.doc(`billingMaintenance/${key}`).update({leaseUntil:new Timestamp(t.seconds,t.nanoseconds+1000)});
 assert.equal(await work.claim(key),null);assert.equal(await work.finish(c,'success',null),true);
 const d=await work.claim(workKey('closure','expiry'));assert.ok(d);s.advance(120000);
 await assert.rejects(work.finish(d,'success',null),/staleMaintenanceLease/);
});
test('closure: next category resumes after budget exhaustion without starvation',async()=>{
 const s=await setup(false);let tick=0;
 const m=new Maintenance(db,{play:s.play,voided:s.voided,ack:s.ack,feed:s.feed,binding},s.clock,{...policy,runBudgetMs:10},()=>0.5,undefined,()=>tick++*6);
 const first=await m.run({now:s.clock(),only:['ack','active']});assert.equal(first.budgetReached,true);
 assert.notEqual(first.nextCategory,'ack');
 const second=await s.service().run({now:s.clock(),only:['ack','active'],nextCategory:first.nextCategory,cursors:first.cursors});
 assert.equal(second.budgetReached,false);assert.ok(Object.hasOwn(second.cursors,'active'));
});
test('closure: grant submillisecond expiry schedules at next safe millisecond',async()=>{
 const s=await setup(false),t=s.clock();const expiry=new Timestamp(t.seconds,t.nanoseconds+1000);
 await db.doc(`users/${s.uid}/entitlementGrants/nanos`).set(grant({expiresAt:expiry}));
 const next=await new LifecycleStore(db,s.clock).recomputeGrants(s.uid,1);
 assert.equal(next,t.toMillis()+1);assert.equal((await s.effective.get()).data()!.active,true);
 s.advance(1);await new LifecycleStore(db,s.clock).recomputeGrants(s.uid,1);assert.equal((await s.effective.get()).data()!.active,false);
});

test('closure: cursor wrap visits inserted-earlier and newly-due documents after deletion',async()=>{
 const s=await setup(false);const collection=db.collection('billingPurchases');
 await collection.doc('b').set({invalid:true});await collection.doc('c').set({invalid:true});
 const first=await s.service().run({now:s.clock(),only:['active']});assert.equal(first.items.length,2);
 await collection.doc('a').set({invalid:true});await collection.doc('c').delete();
 const second=await s.service().run({now:s.clock(),only:['active'],cursors:first.cursors});assert.equal(second.cursors.active,null);
 const third=await s.service().run({now:s.clock(),only:['active'],cursors:second.cursors});
 assert.ok(third.items.some(i=>i.key===workKey('active','billingPurchases/a')));
 // A not-due record skipped in one sweep becomes eligible on the next wrap.
 await collection.doc('a').delete();await collection.doc('b').delete();await s.verify();
 await s.ledger.update({nextCheckAt:Timestamp.fromMillis(s.clock().toMillis()+1)});
 const skipped=await s.run(['active']);assert.equal(skipped.items[0]!.outcome,'notDue');s.advance(1);
 const due=await s.run(['active']);assert.notEqual(due.items[0]!.outcome,'notDue');
});

test('closure: submillisecond clock schedules RTDN retry',async()=>{
 const s=await setup(false),precise=new Timestamp(now.seconds,1000);
 const inbox=new RtdnInboxStore(db,()=>precise,policy.retry,()=>0.5),parsed=parseEnvelope(s.event(),rtdnSource);
 assert.ok(typeof parsed!=='string');await inbox.receive(parsed);const c=await inbox.claim(parsed.key);assert.ok(typeof c!=='string');
 assert.equal(await inbox.finish(c,'RETRY','retryablePlayFailure'),true);
 assert.equal((await s.inboxRef.get()).data()!.nextRetryAt.toMillis(),now.toMillis()+60001);
});
