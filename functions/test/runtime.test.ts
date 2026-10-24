import {test} from 'node:test';
import assert from 'node:assert/strict';
import {getApps} from 'firebase-admin/app';
import {createRuntimeHandlers, RuntimeDependencies} from '../src/runtime/handlers';
import {loadBindingKeys} from '../src/runtime/keys';
import {runtimeConfig as cfg} from '../src/runtime/config';
import {parseEnvelope} from '../src/billing/rtdn/notification';
import {TransportError} from '../src/transport/monetization';
import {createFamilyHandler} from '../src/households/family-handler';
import {FamilyCreateStore} from '../src/households/family-create';
const now=1800000000000;
test('invite/state exports are CORE GEN2 secret-free, non-enforcing and reject arbitrary lookup',async()=>{
 const root=await import('../src/index');
 for(const name of ['mergeFamilyShoppingPreservation','prepareFamilyShoppingPreservation','prepareFamilyDissolution','removeFamilyMember','leaveFamilyShare','acceptFamilyInvite','createFamilyInvite','revokeFamilyInvite','previewFamilyInvite','getFamilyShareState'] as const){
  const f=root[name],e=(f as any).__endpoint;assert.equal(e.platform,'gcfv2');assert.deepEqual(e.region,['europe-west1']);
  assert.equal(e.serviceAccountEmail.name,cfg.coreIdentityParameter);assert.notEqual(e.callableTrigger.enforceAppCheck,true);
  assert.ok(!e.secretEnvironmentVariables?.length);assert.equal(e.timeoutSeconds,60);assert.equal(e.maxInstances,5);
  await assert.rejects(f.run({data:{}} as any),(error:any)=>error.code==='unauthenticated');
  for(const data of [{uid:'other'},['mergeFamilyShoppingPreservation','prepareFamilyDissolution','prepareFamilyShoppingPreservation'].includes(name)?{householdId:'other',ownerUid:'victim'}:{householdId:'other'}])await assert.rejects(f.run({auth:{uid:'caller'},data} as any),(error:any)=>error.code==='invalid-argument');
 }
});
test('CREATE callable is CORE, secret-free, default non-enforcing and rejects client identifiers',async()=>{
 const root=await import('../src/index'), endpoint=(root.createFamilyShare as any).__endpoint;
 assert.equal(endpoint.platform,'gcfv2');assert.deepEqual(endpoint.region,['europe-west1']);
 assert.equal(endpoint.serviceAccountEmail.name,cfg.coreIdentityParameter);
 assert.notEqual(endpoint.callableTrigger.enforceAppCheck,true);assert.ok(!endpoint.secretEnvironmentVariables?.length);
 assert.equal(endpoint.timeoutSeconds,60);assert.equal(endpoint.maxInstances,5);
 let obtained=0;const handler=createFamilyHandler(()=>{obtained++;throw new Error('must not initialize');});
 await assert.rejects(handler({data:{}}),(e:any)=>e.code==='unauthenticated');
 for(const data of [null,[],{uid:'victim'},{sourceHouseholdId:'source'},{destinationHouseholdId:'target'},{pro:true}])
  await assert.rejects(handler({auth:{uid:'caller'},data}),(e:any)=>e.code==='invalid-argument');
 assert.equal(obtained,0);
});
test('CREATE forwards authenticated UID only, awaits durable work and sanitizes failures',async()=>{
 const calls:unknown[]=[];
 const service={reserve:async(auth:unknown)=>{calls.push(auth);return 'op';},resume:async(id:string)=>{calls.push(id);return 'COPY';}};
 const handler=createFamilyHandler(()=>service as unknown as FamilyCreateStore);
 assert.deepEqual(await handler({auth:{uid:'caller'},data:{}}),{schemaVersion:1,operationId:'op',outcome:'COPY'});
 assert.deepEqual(calls,[{uid:'caller'},'op']);
 for(const message of ['featureDisabled','proRequired','raw sensitive failure']){
  service.reserve=async()=>{throw new Error(message);};
  await assert.rejects(handler({auth:{uid:'caller'},data:{}}),(e:any)=>e.message===(message.startsWith('raw')?'retryableUnavailable':message));
 }
});
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
 assert.deepEqual(Object.keys(root).sort(),['mergeFamilyShoppingPreservation','prepareFamilyShoppingPreservation','prepareFamilyDissolution','removeFamilyMember','leaveFamilyShare','prepareFamilyJoinTransfer','getFamilyJoinTransferState','confirmFamilyJoinDelete','cancelFamilyJoin','ensureShoppingContext','processShoppingMutation','acceptFamilyInvite','createFamilyInvite','revokeFamilyInvite','previewFamilyInvite','getFamilyShareState','createFamilyShare','ensurePrivateHousehold','authUserDeleted','beginAccountDeletion','billingMaintenance','finalizeAccountDeletion','getEntitlementProof','playRtdn','prepareProPurchase','verifyProPurchase'].sort());
 assert.equal((root.prepareProPurchase as any).__endpoint.platform,'gcfv2');
 assert.equal((root.authUserDeleted as any).__endpoint.platform,'gcfv1');
 assert.notEqual((root.prepareProPurchase as any).__endpoint.callableTrigger.enforceAppCheck,true);
 assert.ok(!(root.authUserDeleted as any).__endpoint.callableTrigger);
 }finally{http.request=hr;https.request=hs;globalThis.fetch=fetch;if(project===undefined)delete process.env.GCLOUD_PROJECT;else process.env.GCLOUD_PROJECT=project;}
});

test('every export has its explicit role identity; runtime options unchanged', async()=>{
 const project=process.env.GCLOUD_PROJECT;process.env.GCLOUD_PROJECT='demo-kuktam-local';
 try {
  const root=await import('../src/index');
  const mapping={prepareProPurchase:cfg.coreIdentityParameter,getEntitlementProof:cfg.coreIdentityParameter,
   beginAccountDeletion:cfg.coreIdentityParameter,authUserDeleted:cfg.coreIdentityParameter,
   verifyProPurchase:cfg.playIdentityParameter,playRtdn:cfg.playIdentityParameter,
   billingMaintenance:cfg.playIdentityParameter,finalizeAccountDeletion:cfg.deletionIdentityParameter};
  assert.equal(new Set(Object.values(mapping)).size,3);
  for(const [name,parameter] of Object.entries(mapping)){
   const endpoint=(root as any)[name].__endpoint;
   assert.equal(endpoint.serviceAccountEmail.name,parameter,name);
   assert.equal(endpoint.serviceAccountEmail.toCEL(),`{{ params.${parameter} }}`,name);
   assert.deepEqual(endpoint.region,['europe-west1']);assert.equal(endpoint.timeoutSeconds,300);
   assert.equal(endpoint.maxInstances,name==='billingMaintenance'?1:5);
   assert.deepEqual(endpoint.secretEnvironmentVariables.map((s:any)=>s.key),['KUKTAM_BINDING_KEYS']);
  }
  assert.equal((root.billingMaintenance as any).__endpoint.concurrency,1);
  assert.deepEqual(JSON.parse(JSON.stringify((root.billingMaintenance as any).__endpoint.scheduleTrigger)),{schedule:'every 5 minutes',retryConfig:{retryCount:0},timeZone:'Etc/UTC'});
  assert.equal((root.playRtdn as any).__endpoint.eventTrigger.eventFilters.topic,'kuktam-play-rtdn');
  assert.equal((root.playRtdn as any).__endpoint.eventTrigger.retry,true);
 } finally {if(project===undefined)delete process.env.GCLOUD_PROJECT;else process.env.GCLOUD_PROJECT=project;}
});

test('CLI parameter resolution refuses each missing identity, including legacy-only configuration',async()=>{
 await import('../src/index');
 const {declaredParams}=require('firebase-functions/params');
 const {resolveParams}=require('firebase-tools/lib/deploy/functions/params');
 const names=[cfg.coreIdentityParameter,cfg.playIdentityParameter,cfg.deletionIdentityParameter];
 const params=declaredParams.map((p:any)=>p.toSpec()).filter((p:any)=>p.type==='string');
 assert.deepEqual(params.map((p:any)=>p.name).sort(),[...names].sort());
 for(const p of params)assert.equal(Object.hasOwn(p,'default'),false);
 const values=Object.fromEntries(names.map((name,i)=>[name,`test-runtime-${i}@demo-kuktam-local.iam.gserviceaccount.com`]));
 const options={params,firebaseConfig:{projectId:'demo-kuktam-local'},codebase:'monetization',nonInteractive:true};
 // Only string parameters: no secret resolver, cloud call or credential discovery.
 const http=require('node:http'),https=require('node:https');const hr=http.request,hs=https.request,fetch=globalThis.fetch;
 http.request=https.request=globalThis.fetch=()=>{throw new Error('NETWORK_FORBIDDEN');};
 try {
  const result=await resolveParams({...options,userEnvs:values});
  for(const name of names)assert.equal(result.paramValues[name],values[name]);
  for(const missing of names){
   const env={...values};delete env[missing];
   await assert.rejects(resolveParams({...options,userEnvs:env}),new RegExp(`no value.*${missing}`));
  }
  for(const env of [{},{KUKTAM_RUNTIME_SERVICE_ACCOUNT:'legacy@demo-kuktam-local.iam.gserviceaccount.com'}]){
   await assert.rejects(resolveParams({...options,userEnvs:env}),/no value/);
  }
 }finally{http.request=hr;https.request=hs;globalThis.fetch=fetch;}
});

test('shopping endpoints are lazy CORE, secret-free, retrying and reject UID injection',async()=>{
 const root=await import('../src/index');
 const call=(root.ensureShoppingContext as any).__endpoint,trigger=(root.processShoppingMutation as any).__endpoint;
 for(const e of [call,trigger]){assert.equal(e.platform,'gcfv2');assert.deepEqual(e.region,['europe-west1']);assert.equal(e.serviceAccountEmail.name,cfg.coreIdentityParameter);assert.ok(!e.secretEnvironmentVariables?.length);}
 assert.notEqual(call.callableTrigger.enforceAppCheck,true);assert.equal(trigger.eventTrigger.retry,true);
 await assert.rejects(root.ensureShoppingContext.run({data:{}} as any),(e:any)=>e.code==='unauthenticated');
 await assert.rejects(root.ensureShoppingContext.run({auth:{uid:'u'},data:{uid:'b'}} as any),(e:any)=>e.code==='invalid-argument');
});
test('household callable is CORE, secret-free, non-enforcing and rejects UID injection before initialization',async()=>{
  const root=await import('../src/index');const endpoint=(root.ensurePrivateHousehold as any).__endpoint;
  assert.equal(endpoint.platform,'gcfv2');assert.deepEqual(endpoint.region,['europe-west1']);
  assert.equal(endpoint.serviceAccountEmail.name,cfg.coreIdentityParameter);
  assert.notEqual(endpoint.callableTrigger.enforceAppCheck,true);
  assert.ok(!endpoint.secretEnvironmentVariables?.length);
  for(const data of [{uid:'victim'},{householdId:'victim'},[],null]){
   await assert.rejects(root.ensurePrivateHousehold.run({auth:{uid:'caller'},data} as any), (e:any)=>e.code==='invalid-argument');
  }
  await assert.rejects(root.ensurePrivateHousehold.run({data:{}} as any),(e:any)=>e.code==='unauthenticated');
 });
