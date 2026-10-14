import {test} from 'node:test';
import assert from 'node:assert/strict';
import {GooglePlayPurchaseAdapter,GooglePlayAcknowledgmentAdapter,GoogleVoidedFeed,GoogleVoidedPurchaseAdapter} from '../src/adapters/google-play';
import {GooglePlayRest,PlayTransport,RestRequest} from '../src/adapters/play-rest';
import {AdapterError,classify,productionAdapterConfig as cfg,Diagnostic} from '../src/adapters/config';
import {FirebaseAdminAuthDeletionAdapter} from '../src/adapters/firebase-auth';
import {RuntimeBindingKeys} from '../src/billing/binding-key-provider';
import {AccountBinding} from '../src/billing/account-binding';
import {parsePlayPurchase} from '../src/billing/play-purchase-api';
import {parseVoidedObservation} from '../src/billing/voided-purchase-api';
// Any accidental default network path is a test failure. All requests injected below.
globalThis.fetch=async()=>{throw new Error('NETWORK_FORBIDDEN');};
const q={packageName:cfg.packageName,productId:cfg.productId,purchaseToken:'synthetic-private-token'};
const now=1800000000000;
function raw(state='PURCHASED',ack='PENDING') {return {productLineItem:[{productId:cfg.productId,productOfferDetails:{quantity:1,consumptionState:'CONSUMPTION_STATE_YET_TO_BE_CONSUMED'}}],purchaseStateContext:{purchaseState:state},acknowledgementState:'ACKNOWLEDGEMENT_STATE_'+ack,obfuscatedExternalAccountId:'v1_binding',testPurchaseContext:{fopType:'TEST'}};}
class Rest implements PlayTransport {
 calls:RestRequest[]=[];responses:unknown[]=[];
 async request(r:RestRequest){this.calls.push(r);const v=this.responses.shift();if(v instanceof Error)throw v;return v;}
}
for(const state of ['PURCHASED','PENDING','CANCELLED'])for(const ack of ['PENDING','ACKNOWLEDGED']){
 test(`purchase official state ${state}/${ack}`,async()=>{
  const r=new Rest();r.responses=[raw(state,ack)];const p=new GooglePlayPurchaseAdapter(r);
  if(state==='PENDING'&&ack==='ACKNOWLEDGED'){await assert.rejects(p.lookup(q));return;}
  const v=parsePlayPurchase(await p.lookup(q));assert.equal(v.purchaseState,state==='CANCELLED'?'CANCELED':state);assert.equal(v.acknowledgementState,ack);
  assert.match(r.calls[0]!.path,/productsv2\/tokens\//);assert.equal(v.testPurchase,true);
 });
}
for(const mutation of ['wrongProduct','multiItem','consumed','quantity','rental','unknownState','badBinding','malformed'])test(`purchase rejects ${mutation}`,async()=>{
 const v:any=raw();if(mutation==='wrongProduct')v.productLineItem[0].productId='wrong';if(mutation==='multiItem')v.productLineItem.push(v.productLineItem[0]);if(mutation==='consumed')v.productLineItem[0].productOfferDetails.consumptionState='CONSUMPTION_STATE_CONSUMED';if(mutation==='quantity')v.productLineItem[0].productOfferDetails.quantity=2;if(mutation==='rental')v.productLineItem[0].productOfferDetails.rentOfferDetails={};if(mutation==='unknownState')v.purchaseStateContext.purchaseState='FUTURE';if(mutation==='badBinding')v.obfuscatedExternalAccountId={secret:q.purchaseToken};
 const r=new Rest();r.responses=[mutation==='malformed'?null:v];await assert.rejects(new GooglePlayPurchaseAdapter(r).lookup(q));
});
test('not found is null, duplicate valid lookup has identical domain value, constants guarded',async()=>{
 const r=new Rest();r.responses=[new AdapterError('notFound'),raw(),raw()];const p=new GooglePlayPurchaseAdapter(r);assert.equal(await p.lookup(q),null);assert.deepEqual(await p.lookup(q),await p.lookup(q));
 await assert.rejects(p.lookup({...q,packageName:'evil'} as any));await assert.rejects(p.lookup({...q,productId:'evil'} as any));assert.equal(r.calls.length,3);
 assert.equal(cfg.packageName,'com.bronxii.kuktam');assert.equal(cfg.productId,'kuktam_pro_lifetime');
});
for(const [status,body,category] of [
 [500,{},'retryableUnavailable'],[429,{},'rateLimited'],[403,{error:{errors:[{reason:'rateLimitExceeded'}]}},'rateLimited'],[403,{},'permissionDenied'],[401,{},'unauthenticatedCredential'],[403,{error:{details:[{reason:'SERVICE_DISABLED'}]}},'configurationError'],[404,{},'notFound'],[400,{},'invalidArgument'],[409,{},'retryableUnavailable'],
] as const)test(`Google REST error ${status}/${category}`,async()=>{
 assert.equal(classify(status,body),category);const events:Diagnostic[]=[];
 const rest=new GooglePlayRest({getAccessToken:async()=> 'synthetic-bearer'},async()=>new Response(JSON.stringify({...body,private:q.purchaseToken}),{status}));
 const p=new GooglePlayPurchaseAdapter(rest,e=>events.push(e));if(status===404)assert.equal(await p.lookup(q),null);else await assert.rejects(p.lookup(q),e=>{assert.ok(!String(e).includes(q.purchaseToken));return true;});
 assert.equal(events[0]!.category,category);assert.ok(!JSON.stringify(events).includes(q.purchaseToken));
});
test('REST credential error sanitized, no fetch; malformed UTF8/JSON; abort; URL escaping and no redirect',async()=>{
 let calls=0;const credential=new GooglePlayRest({getAccessToken:async()=>{throw new Error(q.purchaseToken);}},async()=>{calls++;return new Response('{}');});await assert.rejects(new GooglePlayPurchaseAdapter(credential).lookup(q));assert.equal(calls,0);
 for(const body of [new Uint8Array([0xff]),'{bad']){const rest=new GooglePlayRest({getAccessToken:async()=> 'secret'},async()=>new Response(body));await assert.rejects(new GooglePlayPurchaseAdapter(rest).lookup(q));}
 const rest=new GooglePlayRest({getAccessToken:async()=> 'secret'},async(url,options)=>{calls++;assert.equal(options?.redirect,'error');assert.ok(String(url).includes('a%2Fb'));assert.equal((options?.headers as any).Authorization,'Bearer secret');return new Response(JSON.stringify(raw()));});
 await new GooglePlayPurchaseAdapter(rest).lookup({...q,purchaseToken:'a/b'});const c=new AbortController();c.abort();await assert.rejects(new GooglePlayPurchaseAdapter(rest).lookup(q,{signal:c.signal}));assert.equal(calls,1);
});
test('ack success, already ack, timeout replay uses readback and never consume',async()=>{
 const r=new Rest();r.responses=[raw(),{},raw('PURCHASED','ACKNOWLEDGED'),raw(),new AdapterError('retryableUnavailable'),raw('PURCHASED','ACKNOWLEDGED')];const a=new GooglePlayAcknowledgmentAdapter(r);
 assert.equal((await a.acknowledge(q)).status,'success');assert.equal((await a.acknowledge(q)).status,'alreadyAcknowledged');assert.equal((await a.acknowledge(q)).status,'alreadyAcknowledged');
 assert.equal(r.calls.filter(c=>c.method==='POST').length,2);assert.ok(r.calls.every(c=>!c.path.includes('consume')));
});
for(const category of ['retryableUnavailable','rateLimited','permissionDenied','unauthenticatedCredential','invalidArgument','notFound','configurationError'] as const)test(`ack failure ${category}`,async()=>{
 const r=new Rest();r.responses=[raw(),new AdapterError(category),raw()];const events:Diagnostic[]=[];
 assert.equal((await new GooglePlayAcknowledgmentAdapter(r,e=>events.push(e)).acknowledge(q)).status,['retryableUnavailable','rateLimited'].includes(category)?'temporaryFailure':'permanentFailure');assert.ok(!JSON.stringify(events).includes(q.purchaseToken));
});
test('ack pending rejected without POST and malformed success controlled',async()=>{
 const r=new Rest();r.responses=[raw('PENDING')];assert.equal((await new GooglePlayAcknowledgmentAdapter(r).acknowledge(q)).status,'permanentFailure');assert.equal(r.calls.length,1);
 r.responses=[raw(),{unexpected:'x'},raw()];assert.equal((await new GooglePlayAcknowledgmentAdapter(r).acknowledge(q)).status,'permanentFailure');
});
const fq={packageName:cfg.packageName,startMs:now-cfg.voidedWindowMs,endMs:now,pageToken:null,limit:100};
const row={purchaseToken:q.purchaseToken,voidedTimeMillis:String(now-1000)};
test('voided empty, duplicates, pagination and exact technical window',async()=>{
 const r=new Rest();r.responses=[{}, {voidedPurchases:[row,row,{...row,purchaseToken:'other'}],tokenPagination:{nextPageToken:'next'}},{}];const f=new GoogleVoidedFeed(r,()=>now);
 assert.deepEqual(await f.list(fq),{items:[],nextPageToken:null});const page=await f.list(fq);assert.equal(page.items.length,2);assert.equal(page.nextPageToken,'next');await f.list({...fq,pageToken:page.nextPageToken});
 assert.equal(r.calls[0]!.query!.startTime,undefined);assert.equal(r.calls[0]!.query!.endTime,undefined);assert.equal(r.calls[0]!.query!.includeQuantityBasedPartialRefund,'false');assert.equal(r.calls[0]!.query!.type,'0');assert.equal(r.calls[2]!.query!.token,'next');assert.equal(r.calls[2]!.query!.startTime,undefined);
});
for(const response of [{voidedPurchases:[{purchaseToken:q.purchaseToken}]},{voidedPurchases:'bad'},{voidedPurchases:[{...row,voidedQuantity:2}]},{tokenPagination:{nextPageToken:42}},new AdapterError('rateLimited'),new AdapterError('permissionDenied')])test('voided malformed/error is controlled and private '+JSON.stringify(response).length,async()=>{
 const r=new Rest();r.responses=[response];const events:Diagnostic[]=[];await assert.rejects(new GoogleVoidedFeed(r,()=>now,e=>events.push(e)).list(fq),e=>!String(e).includes(q.purchaseToken));assert.ok(!JSON.stringify(events).includes(q.purchaseToken));
});
test('voided per-token lookup joins fresh product identity and paginated revoke evidence',async()=>{
 const r=new Rest();r.responses=[raw('CANCELLED'),{tokenPagination:{nextPageToken:'page2'}},{voidedPurchases:[row]}];const f=new GoogleVoidedFeed(r,()=>now);const v=new GoogleVoidedPurchaseAdapter(new GooglePlayPurchaseAdapter(r),f,()=>now);
 assert.equal(parseVoidedObservation(await v.lookup(q)).state,'entitlementRevoked');
 r.responses=[raw(),{}];assert.equal(parseVoidedObservation(await v.lookup(q)).authoritative,false); // Refund-only or absent evidence never revokes.
 r.responses=[new AdapterError('notFound')];await assert.rejects(v.lookup(q));
});
test('voided repeated cursor fails closed; old/wrong window never sends HTTP',async()=>{
 const r=new Rest();r.responses=[raw(),{tokenPagination:{nextPageToken:'x'}},{tokenPagination:{nextPageToken:'x'}}];const f=new GoogleVoidedFeed(r,()=>now);await assert.rejects(new GoogleVoidedPurchaseAdapter(new GooglePlayPurchaseAdapter(r),f,()=>now).lookup(q));
 const count=r.calls.length;await assert.rejects(f.list({...fq,startMs:fq.startMs-1}));assert.equal(r.calls.length,count);
});
for(const code of [null,'auth/user-not-found','auth/internal-error','app/network-error','auth/insufficient-permission','auth/invalid-uid'])test(`Admin delete mapping ${code}`,async()=>{
 const events:Diagnostic[]=[];const a=new FirebaseAdminAuthDeletionAdapter({deleteUser:async()=>{if(code)throw {code,message:q.purchaseToken};}},e=>events.push(e));
 const expected=code===null?'deleted':code==='auth/user-not-found'?'notFound':['auth/internal-error','app/network-error'].includes(code)?'temporaryFailure':'permanentFailure';
 assert.equal(await a.deleteUser('trusted',{signal:new AbortController().signal}),expected);assert.ok(!JSON.stringify(events).includes(q.purchaseToken));
});
test('Admin invalid UID and already aborted request never call SDK',async()=>{
 let calls=0;const a=new FirebaseAdminAuthDeletionAdapter({deleteUser:async()=>{calls++;}});const c=new AbortController();for(const uid of ['', 'x/y',' x'])assert.equal(await a.deleteUser(uid,{signal:c.signal}),'permanentFailure');c.abort();assert.equal(await a.deleteUser('u',{signal:c.signal}),'temporaryFailure');assert.equal(calls,0);
});
test('HMAC current/previous rotation preserves v1 and never serializes secret',()=>{
 const old=Buffer.alloc(32,33),next=Buffer.alloc(32,44),provider=new RuntimeBindingKeys('v2',()=>({v1:old,v2:next}));const b=new AccountBinding(provider),v1=new AccountBinding(old).forAuthenticatedAccount({uid:'u'});
 assert.equal(b.matches({uid:'u'},v1),true);assert.match(b.forAuthenticatedAccount({uid:'u'}),/^v2_/);assert.equal(b.matches({uid:'other'},v1),false);
 const copy=provider.material('v1');copy.fill(0);assert.equal(b.matches({uid:'u'},v1),true);
 assert.throws(()=>provider.material('v3'),/bindingKeyUnavailable/);assert.ok(!JSON.stringify(provider).includes(old.toString('hex')));assert.ok(!JSON.stringify(b).includes('provider'));
});
for(const load of [()=>({}),()=>({v1:Buffer.alloc(3)}),()=>{throw new Error('secret-value');}])test('missing/malformed secret is controlled '+String(load).length,()=>{
 assert.throws(()=>new RuntimeBindingKeys('v1',load),e=>String(e)==='Error: bindingKeyConfiguration');
});
test('transport rejects path normalization and consume before credential access',async()=>{
 let calls=0;const transport=new GooglePlayRest({getAccessToken:async()=>{calls++;return 'fake';}});
 for(const path of [`/androidpublisher/v3/applications/${cfg.packageName}/purchases/productsv2/tokens/..`,`/androidpublisher/v3/applications/${cfg.packageName}/purchases/products/${cfg.productId}/tokens/t:consume`])await assert.rejects(transport.request({method:'POST',path}),/invalidArgument/);
 assert.equal(calls,0);
});
test('transport bounds response size without exposing response bytes',async()=>{
 const transport=new GooglePlayRest({getAccessToken:async()=> 'fake'},async()=>new Response('x'.repeat(cfg.maxResponseBytes+1)));
 await assert.rejects(transport.request({method:'GET',path:`/androidpublisher/v3/applications/${cfg.packageName}/purchases/productsv2/tokens/test`}),/malformedResponse/);
});

// Regression: model Google's clock after credential/network delay, not a frozen client clock.
for(const skew of [-60000,0,60000])test('voided first request uses server window with clock skew '+skew,async()=>{
 const requests:URL[]=[];
 const rest=new GooglePlayRest({getAccessToken:async()=> 'synthetic-bearer'},async(input,options)=>{
  const url=new URL(String(input));requests.push(url);
  assert.equal(options?.method,'GET');assert.equal(options?.body,undefined);
  assert.equal(url.pathname,'/androidpublisher/v3/applications/com.bronxii.kuktam/purchases/voidedpurchases');
  assert.deepEqual(Object.fromEntries(url.searchParams),{type:'0',includeQuantityBasedPartialRefund:'false',maxResults:'50'});
  const googleNow=now+skew+2000;
  const start=url.searchParams.get('startTime'),end=url.searchParams.get('endTime');
  if(start!==null&&Number(start)<googleNow-cfg.voidedWindowMs||end!==null&&Number(end)>googleNow)return new Response('{}',{status:400});
  return new Response('{}');
 });
 assert.deepEqual(await new GoogleVoidedFeed(rest,()=>now).list({...fq,limit:50}),{items:[],nextPageToken:null});assert.equal(requests.length,1);
});
test('voided pagination URL roundtrip, maximum page and empty GET body',async()=>{
 const pageToken='synthetic+/= token';
 const rest=new GooglePlayRest({getAccessToken:async()=> 'fake'},async(input,options)=>{
  const url=new URL(String(input));assert.deepEqual(Object.fromEntries(url.searchParams),{type:'0',includeQuantityBasedPartialRefund:'false',maxResults:'1000',token:pageToken});
  assert.equal(options?.method,'GET');assert.equal(options?.body,undefined);return new Response('{}');
 });
 await new GoogleVoidedFeed(rest,()=>now).list({...fq,limit:1000,pageToken});
});
for(const limit of [0,1001,1.5])test('voided invalid page limit makes no request '+limit,async()=>{
 const r=new Rest();await assert.rejects(new GoogleVoidedFeed(r,()=>now).list({...fq,limit}));assert.equal(r.calls.length,0);
});
test('explicit old boundary would be rejected after transport delay',()=>{
 const transmittedStart=now-cfg.voidedWindowMs,googleNow=now+1;
 assert.ok(transmittedStart<googleNow-cfg.voidedWindowMs);
});
