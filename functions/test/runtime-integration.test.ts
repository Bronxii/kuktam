import {test,before,after} from 'node:test';
import assert from 'node:assert/strict';
import {initializeApp,deleteApp,App} from 'firebase-admin/app';
import {getFirestore,Firestore,Timestamp} from 'firebase-admin/firestore';
import {requireLocalEmulator} from './emulator-guard';
import {compose} from '../src/runtime/composition';
import {createRuntimeHandlers} from '../src/runtime/handlers';
import {RuntimeBindingKeys} from '../src/billing/binding-key-provider';
import {PlayTransport,RestRequest} from '../src/adapters/play-rest';
import {runtimeConfig as cfg} from '../src/runtime/config';
import {MaintenanceDispatcher} from '../src/runtime/maintenance-dispatcher';
import {MaintenanceRun} from '../src/jobs/maintenance';
import {tokenHash} from '../src/billing/purchase-identity';
requireLocalEmulator(process.env);
let app:App,db:Firestore,seq=0;
before(()=>{app=initializeApp({projectId:'demo-kuktam-local'},'runtime-integration');db=getFirestore(app);});
after(()=>deleteApp(app));
function setup(){
 const uid='runtime-'+(++seq),token='runtime-token-'+seq,calls:RestRequest[]=[],deletes:string[]=[];
 let binding='',ack=false;
 const rest:PlayTransport={request:async r=>{calls.push(r);if(r.method==='POST'){ack=true;return {};}
 return {productLineItem:[{productId:cfg.productId,productOfferDetails:{quantity:1,consumptionState:'CONSUMPTION_STATE_YET_TO_BE_CONSUMED'}}],purchaseStateContext:{purchaseState:'PURCHASED'},acknowledgementState:ack?'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED':'ACKNOWLEDGEMENT_STATE_PENDING',obfuscatedExternalAccountId:binding};}};
 const services=compose(db,rest,{deleteUser:async id=>{deletes.push(id);return 'deleted';}},new RuntimeBindingKeys('v1',()=>({v1:Buffer.alloc(32,41)})));
 const h=createRuntimeHandlers(()=>services),auth={uid,token:{auth_time:Math.floor(Date.now()/1000)}};
 return {uid,token,calls,deletes,h,services,auth,async prepare(){const result=await h.prepareProPurchase({auth,data:{}}) as any;binding=result.opaqueAccountId;return result;},verify:()=>h.verifyProPurchase({auth,data:{productId:cfg.productId,purchaseToken:token}})};
}
test('runtime graph: prepare -> real adapter/fake HTTP -> durable verified -> backend ack -> trusted proof',async()=>{
 const s=setup();await s.prepare();assert.deepEqual(await s.verify(),{schemaVersion:1,outcome:'verified'});
 assert.equal(s.calls.filter(c=>c.method==='POST').length,1);
 const first=await s.h.getEntitlementProof({auth:s.auth,data:{}}) as any;assert.equal(first.active,true);assert.ok(first.proofIssuedAt>=first.verifiedAt);
 assert.deepEqual(Object.keys(first).sort(),['schemaVersion','active','sources','validUntil','revision','verifiedAt','updatedAt','proofIssuedAt'].sort());
 await s.verify();const second=await s.h.getEntitlementProof({auth:s.auth,data:{}}) as any;assert.equal(second.revision,first.revision);assert.equal(s.calls.filter(c=>c.method==='POST').length,1);
 assert.ok(s.calls.every(c=>c.path.includes(cfg.packageName)));assert.equal((await db.doc(`billingPurchases/${tokenHash(s.token)}`).get()).exists,true);
});
for(const method of ['prepareProPurchase','verifyProPurchase','getEntitlementProof'] as const)test('runtime strict body '+method,async()=>{
 const s=setup();await s.prepare();for(const data of [{uid:'spoof'},{packageName:'evil'}, {productId:cfg.productId,purchaseToken:s.token,extra:true}])assert.deepEqual(await s.h[method]({auth:s.auth,data}),{schemaVersion:1,error:'invalidArgument'});assert.equal(s.calls.length,0);
});
for(const state of ['DELETING','DELETED'])test('runtime account '+state+' blocks prepare/verify',async()=>{
 const s=setup();await s.prepare();const at=Timestamp.now();await db.doc(`accountLifecycle/${s.uid}`).update({state,generation:2,updatedAt:at,deletionStartedAt:at,deletedAt:state==='DELETED'?at:null});
 for(const invoke of [()=>s.prepare(),s.verify])assert.equal((await invoke() as any).error,state==='DELETING'?'accountDeleting':'accountDeleted');assert.equal(s.calls.length,0);
});
test('modern runtime deletion content barrier and completion; no client evidence authority',async()=>{
 const s=setup();await s.prepare();await db.doc(`users/${s.uid}/recipes/a`).set({name:'keep until cleanup'});
 assert.equal((await s.h.beginAccountDeletion({auth:s.auth,data:{}}) as any).outcome,'deletionStarted');
 assert.equal((await s.h.finalizeAccountDeletion({auth:s.auth,data:{cleanupComplete:true}}) as any).error,'invalidArgument');
 assert.equal((await s.h.finalizeAccountDeletion({auth:s.auth,data:{}}) as any).outcome,'cleanupIncomplete');assert.equal(s.deletes.length,0);
 await db.doc(`users/${s.uid}/recipes/a`).delete();
 assert.equal((await s.h.finalizeAccountDeletion({auth:s.auth,data:{}}) as any).outcome,'deletionCompleted');assert.deepEqual(s.deletes,[s.uid]);
 assert.equal((await db.doc(`accountLifecycle/${s.uid}`).get()).data()!.state,'DELETED');
});
test('trusted fallback replay is idempotent and never invokes modern Auth adapter',async()=>{
 const s=setup();await s.prepare();await s.h.authDeleted({uid:s.uid});await s.h.authDeleted({uid:s.uid});assert.equal(s.deletes.length,0);
 assert.equal((await db.doc(`accountLifecycle/${s.uid}`).get()).data()!.state,'DELETED');
});
test('RTDN real processor deduplicates official test envelope',async()=>{
 const s=setup();const e={data:{message:{messageId:'runtime-test',publishTime:new Date().toISOString(),data:Buffer.from(JSON.stringify({version:'1.0',packageName:cfg.packageName,eventTimeMillis:String(Date.now()),testNotification:{version:'1.0'}})).toString('base64')}}};
 await s.h.rtdn(e);await s.h.rtdn(e);assert.equal(s.calls.length,0);
});
test('dispatcher persists category/cursor; concurrent invocation cannot steal claim',async()=>{
 await db.doc('billingRuntime/maintenance').delete();let release!:()=>void;const waiting=new Promise<void>(resolve=>release=resolve);let entered!:()=>void;const started=new Promise<void>(resolve=>entered=resolve);let calls=0;const inputs:MaintenanceRun[]=[];
 const d=new MaintenanceDispatcher(db,{run:async input=>{calls++;inputs.push(input);entered();await waiting;return {nextCategory:'active',cursors:{active:'billingPurchases/page'},items:[],budgetReached:true};}});
 const first=d.run();await started;await d.run();assert.equal(calls,1);release();await first;
 await d.run();assert.equal(calls,2);assert.equal(inputs[1]!.nextCategory,'active');assert.equal(inputs[1]!.cursors!.active,'billingPurchases/page');
});
test('dispatcher crash lease takeover fences old completion',async()=>{
 await db.doc('billingRuntime/maintenance').delete();let clock=1000000;let release!:()=>void;let entered!:()=>void;const started=new Promise<void>(r=>entered=r);const wait=new Promise<void>(r=>release=r);
 const old=new MaintenanceDispatcher(db,{run:async()=>{entered();await wait;return {nextCategory:'ack',cursors:{},items:[],budgetReached:false};}},()=>Timestamp.fromMillis(clock));
 const pending=old.run();await started;clock+=cfg.dispatcherLeaseMs+1;
 const next=new MaintenanceDispatcher(db,{run:async()=>({nextCategory:'grants',cursors:{grants:'users/u/entitlementGrants/g'},items:[],budgetReached:false})},()=>Timestamp.fromMillis(clock));
 await next.run();release();await pending;assert.equal((await db.doc('billingRuntime/maintenance').get()).data()!.nextCategory,'grants');
});
test('dispatcher dependency failure preserves checkpoint until lease recovery',async()=>{
 await db.doc('billingRuntime/maintenance').delete();const d=new MaintenanceDispatcher(db,{run:async()=>{throw new Error('failure');}});
 await assert.rejects(d.run());const state=(await db.doc('billingRuntime/maintenance').get()).data()!;assert.ok(state.leaseId);assert.equal(state.nextCategory,'ack');
 await db.doc('billingRuntime/maintenance').delete();
});
