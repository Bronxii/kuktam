import {test} from 'node:test';
import assert from 'node:assert/strict';
import {getApps} from 'firebase-admin/app';
import {createRuntimeHandlers, RuntimeDependencies} from '../src/runtime/handlers';
import {loadBindingKeys} from '../src/runtime/keys';
import {runtimeConfig as cfg} from '../src/runtime/config';
import {parseEnvelope} from '../src/billing/rtdn/notification';
import {TransportError} from '../src/transport/monetization';
const now=1800000000000;
const auth={uid:'trusted',token:{auth_time:now/1000}};
function setup(){
 const calls:unknown[]=[];
 const services:RuntimeDependencies={
  monetization:{prepareProPurchase:async r=>{calls.push(r);return {schemaVersion:1,productId:cfg.productId,opaqueAccountId:'opaque'};},
   verifyProPurchase:async r=>{calls.push(r);return {schemaVersion:1,outcome:'verified'};},
   getEntitlementProof:async r=>{calls.push(r);return {schemaVersion:1,active:false,sources:[],validUntil:null,revision:0,verifiedAt:now,updatedAt:now,proofIssuedAt:now};}},
  deletion:{begin:async(r,data)=>{calls.push(r);if(Object.keys(data as object).length)throw new Error('invalidArgument');return {outcome:'deletionStarted',operationId:'private'};},
   finalize:async(r,data)=>{calls.push(r);if(Object.keys(data as object).length)throw new Error('invalidArgument');return 'cleanupIncomplete';}},
  fallback:{handleAuthUserDeleted:async uid=>{calls.push(uid);return 'deletionCompleted';}},
  rtdn:{handle:async e=>{calls.push(e);return {outcome:'processed'};}},dispatcher:{run:async()=>{calls.push('maintenance');}},
 };
 let obtains=0;const handlers=createRuntimeHandlers(()=>{obtains++;return services;},()=>now);
 return {services,handlers,calls,obtains:()=>obtains};
}
for(const name of ['prepareProPurchase','verifyProPurchase','getEntitlementProof','beginAccountDeletion','finalizeAccountDeletion'] as const){
 test(name+' blocks absent auth without constructing graph',async()=>{const s=setup();assert.deepEqual(await s.handlers[name]({data:{uid:'spoof'}}),{schemaVersion:1,error:'unauthenticated'});assert.equal(s.obtains(),0);});
}
test('authenticated UID forwarded only from runtime auth; proof shape preserved',async()=>{const s=setup();const response=await s.handlers.getEntitlementProof({auth,data:{}});assert.equal((s.calls[0] as any).auth.uid,'trusted');assert.equal((response as any).proofIssuedAt,now);assert.ok(!JSON.stringify(response).includes('private'));});
for(const code of ['accountDeleting','accountDeleted','tokenBindingConflict','retryableUnavailable','configuration'] as const)test('existing callable envelope preserved '+code,async()=>{const s=setup();s.services.monetization.verifyProPurchase=async()=>{throw new TransportError(code);};assert.deepEqual(await s.handlers.verifyProPurchase({auth,data:{}}),{schemaVersion:1,error:code});});
for(const time of [undefined,now/1000-301,now/1000+1,'1800000000'])test('deletion rejects untrusted/recent-auth failure '+time,async()=>{const s=setup();const result=await s.handlers.beginAccountDeletion({auth:{uid:'trusted',token:{auth_time:time}},data:{}});assert.deepEqual(result,{schemaVersion:1,error:'recentAuthRequired'});assert.equal(s.calls.length,0);});
test('deletion fresh begin redacts operation; finalize rejects evidence/UID',async()=>{const s=setup();assert.deepEqual(await s.handlers.beginAccountDeletion({auth,data:{}}),{schemaVersion:1,outcome:'deletionStarted'});for(const data of [{uid:'spoof'},{cleanupComplete:true}])assert.deepEqual(await s.handlers.finalizeAccountDeletion({auth,data}),{schemaVersion:1,error:'invalidArgument'});assert.deepEqual(await s.handlers.finalizeAccountDeletion({auth,data:{}}),{schemaVersion:1,outcome:'cleanupIncomplete'});});
test('missing secret and raw exceptions never escape',async()=>{const h=createRuntimeHandlers(()=>{throw new Error('raw-secret-token');});assert.deepEqual(await h.prepareProPurchase({auth,data:{}}),{schemaVersion:1,error:'configuration'});});
const event=(payload:unknown)=>({data:{message:{messageId:'id1',publishTime:new Date(now).toISOString(),data:Buffer.from(JSON.stringify(payload)).toString('base64')}}});
const notification={version:'1.0',packageName:cfg.packageName,eventTimeMillis:String(now),testNotification:{version:'1.0'}};
test('RTDN official envelope uses configured source and existing parser',async()=>{const s=setup();await s.handlers.rtdn(event(notification));const e=s.calls[0];assert.equal(typeof parseEnvelope(e,cfg.topic),'object');assert.equal((e as any).source,cfg.topic);});
for(const data of ['!!!',Buffer.from('{bad').toString('base64')])test('RTDN malformed controlled without poison retry '+data,async()=>{const s=setup();await s.handlers.rtdn({data:{message:{messageId:'x',publishTime:new Date(now).toISOString(),data}}});assert.ok(s.calls.length<=1);});
for(const outcome of ['retryablePlayFailure','internalConflict','busyLease','duplicate','unsupportedNotification','permanentConfigurationFailure'] as const)test('RTDN completion/redelivery '+outcome,async()=>{const s=setup();s.services.rtdn.handle=async()=>({outcome});if(['retryablePlayFailure','internalConflict','busyLease'].includes(outcome))await assert.rejects(s.handlers.rtdn(event(notification)),/^Error: rtdnRetryRequired$/);else await s.handlers.rtdn(event(notification));});
test('Auth fallback only trusted event; malformed ignored and raw errors sanitized',async()=>{const s=setup();await s.handlers.authDeleted({});assert.equal(s.calls.length,0);await s.handlers.authDeleted({uid:'trusted'});await s.handlers.authDeleted({uid:'trusted'});assert.deepEqual(s.calls,['trusted','trusted']);s.services.fallback.handleAuthUserDeleted=async()=>{throw new Error('secret');};await assert.rejects(s.handlers.authDeleted({uid:'trusted'}),/^Error: deletionRetryRequired$/);});
test('maintenance delegates once and sanitizes failure',async()=>{const s=setup();await s.handlers.maintenance();assert.deepEqual(s.calls,['maintenance']);s.services.dispatcher.run=async()=>{throw new Error('token');};await assert.rejects(s.handlers.maintenance(),/^Error: maintenanceRetryRequired$/);});
test('runtime key JSON current/previous strict canonical base64, no fallback',()=>{const secret=Buffer.alloc(32,17).toString('base64');const keys=loadBindingKeys(JSON.stringify({v1:secret,v2:secret}));assert.equal(keys.currentVersion,'v1');assert.equal(keys.material('v2').length,32);for(const value of ['', '{}','{bad',JSON.stringify({v1:'bad'}),JSON.stringify({v9:secret})])assert.throws(()=>loadBindingKeys(value),/^Error: configurationUnavailable$/);});
test('root discovery has no secret/credential/Admin/network side effects and only expected exports',async()=>{
 const before=getApps().length; const project=process.env.GCLOUD_PROJECT; process.env.GCLOUD_PROJECT='demo-kuktam-local';
 const http=require('node:http'),https=require('node:https');const hr=http.request,hs=https.request,fetch=globalThis.fetch;
 http.request=https.request=globalThis.fetch=()=>{throw new Error('NETWORK_FORBIDDEN');};
 try{const root=await import('../src/index');assert.equal(getApps().length,before);
 assert.deepEqual(Object.keys(root).sort(),['authUserDeleted','beginAccountDeletion','billingMaintenance','finalizeAccountDeletion','getEntitlementProof','playRtdn','prepareProPurchase','verifyProPurchase'].sort());
 assert.equal((root.prepareProPurchase as any).__endpoint.platform,'gcfv2');
 assert.equal((root.authUserDeleted as any).__endpoint.platform,'gcfv1');
 assert.notEqual((root.prepareProPurchase as any).__endpoint.callableTrigger.enforceAppCheck,true);
 assert.ok(!(root.authUserDeleted as any).__endpoint.callableTrigger);
 }finally{http.request=hr;https.request=hs;globalThis.fetch=fetch;if(project===undefined)delete process.env.GCLOUD_PROJECT;else process.env.GCLOUD_PROJECT=project;}
});
