import { PlayPurchase, PlayPurchaseApi, PlayPurchaseQuery, PlayLookupError, parsePlayPurchase } from '../billing/play-purchase-api';
import { PlayAcknowledgmentApi } from '../billing/play-acknowledgment-api';
import { VoidedPurchaseApi, VoidedLookupError } from '../billing/voided-purchase-api';
import { VoidedPurchaseFeed, VoidedFeedQuery, VoidedFeedPage } from '../jobs/voided-feed';
import { PlayTransport } from './play-rest';
import { AdapterError, Diagnostics, diagnose, object, retryable, productionAdapterConfig as cfg } from './config';
const base=`/androidpublisher/v3/applications/${cfg.packageName}/purchases`;
function token(v:unknown):asserts v is string {if(typeof v!=='string'||!v||v==='.'||v==='..'||v.trim()!==v||v.length>4096)throw new AdapterError('invalidArgument');}
function query(q:PlayPurchaseQuery){if(q.packageName!==cfg.packageName||q.productId!==cfg.productId)throw new AdapterError('invalidArgument');token(q.purchaseToken);}
export function mapPurchase(raw:unknown,q:PlayPurchaseQuery):PlayPurchase{
 query(q);const v=object(raw);if(!Array.isArray(v.productLineItem)||v.productLineItem.length!==1)throw new AdapterError('permanentPurchaseState');
 const item=object(v.productLineItem[0]);if(item.productId!==cfg.productId)throw new AdapterError('permanentPurchaseState');
 const offer=object(item.productOfferDetails);
 if(offer.quantity!==1||offer.rentOfferDetails!==undefined||offer.preorderOfferDetails!==undefined||offer.consumptionState!=='CONSUMPTION_STATE_YET_TO_BE_CONSUMED')throw new AdapterError('permanentPurchaseState');
 const state=object(v.purchaseStateContext).purchaseState;
 if(!['PURCHASED','PENDING','CANCELLED'].includes(state as string)||!['ACKNOWLEDGEMENT_STATE_PENDING','ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED'].includes(v.acknowledgementState as string))throw new AdapterError('malformedResponse');
 if(v.testPurchaseContext!==undefined&&object(v.testPurchaseContext).fopType!=='TEST')throw new AdapterError('malformedResponse');
 const b=v.obfuscatedExternalAccountId;if(b!==undefined&&(typeof b!=='string'||!b||b.length>64))throw new AdapterError('malformedResponse');
 try{return parsePlayPurchase({...q,purchaseState:state==='CANCELLED'?'CANCELED':state,acknowledgementState:v.acknowledgementState==='ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED'?'ACKNOWLEDGED':'PENDING',obfuscatedExternalAccountId:b??null,testPurchase:v.testPurchaseContext!==undefined});}
 catch{throw new AdapterError('malformedResponse');}
}
export class GooglePlayPurchaseAdapter implements PlayPurchaseApi {
 constructor(private readonly rest:PlayTransport,private readonly diagnostics?:Diagnostics){}
 async read(q:PlayPurchaseQuery,signal?:AbortSignal){query(q);return mapPurchase(await this.rest.request({method:'GET',path:`${base}/productsv2/tokens/${encodeURIComponent(q.purchaseToken)}`},signal),q);}
 async lookup(q:PlayPurchaseQuery,o?:{signal:AbortSignal}){
  try{return await this.read(q,o?.signal);}catch(e){const c=e instanceof AdapterError?e.category:'retryableUnavailable';diagnose(this.diagnostics,'lookup',c);if(c==='notFound')return null;
   throw new PlayLookupError(retryable(c)?'unavailable':'configuration');}
 }
}
export class GooglePlayAcknowledgmentAdapter implements PlayAcknowledgmentApi {
 constructor(private readonly rest:PlayTransport,private readonly diagnostics?:Diagnostics){}
 async acknowledge(q:PlayPurchaseQuery,o?:{signal:AbortSignal}){
  try{
   const p=await new GooglePlayPurchaseAdapter(this.rest).read(q,o?.signal);
   if(p.purchaseState!=='PURCHASED')throw new AdapterError('permanentPurchaseState');
   if(p.acknowledgementState==='ACKNOWLEDGED')return {status:'alreadyAcknowledged'};
   try{const v=object(await this.rest.request({method:'POST',path:`${base}/products/${cfg.productId}/tokens/${encodeURIComponent(q.purchaseToken)}:acknowledge`},o?.signal));if(Object.keys(v).length)throw new AdapterError('malformedResponse');}
   catch(e){ // Race/ambiguous success: read back once, never retry the POST internally.
    try{const latest=await new GooglePlayPurchaseAdapter(this.rest).read(q,o?.signal);if(latest.purchaseState==='PURCHASED'&&latest.acknowledgementState==='ACKNOWLEDGED')return {status:'alreadyAcknowledged'};}catch{}
    throw e;
   }
   return {status:'success'};
  }catch(e){const c=e instanceof AdapterError?e.category:'retryableUnavailable';diagnose(this.diagnostics,'ack',c);return {status:retryable(c)?'temporaryFailure':'permanentFailure'};}
 }
}
export class GoogleVoidedFeed implements VoidedPurchaseFeed {
 constructor(private readonly rest:PlayTransport,private readonly now:()=>number,private readonly diagnostics?:Diagnostics){}
 async list(q:VoidedFeedQuery,o?:{signal:AbortSignal}):Promise<VoidedFeedPage>{
  try{
   const now=this.now();if(q.packageName!==cfg.packageName||!Number.isSafeInteger(q.startMs)||!Number.isSafeInteger(q.endMs)||q.startMs<0||q.endMs-q.startMs>cfg.voidedWindowMs||q.endMs<now-cfg.voidedWindowMs||q.endMs>now||q.startMs>q.endMs||!Number.isSafeInteger(q.limit)||q.limit<1||q.limit>1000)throw new AdapterError('invalidArgument');
   if(q.pageToken!==null)token(q.pageToken);
   // Let Google select its documented rolling 30-day window using its own clock.
   // Explicit now-30d/now boundaries can become invalid during credential/network latency.
   // startMs/endMs remain local checkpoint metadata; token continues the server snapshot.
   const v=object(await this.rest.request({method:'GET',path:`${base}/voidedpurchases`,query:{type:'0',includeQuantityBasedPartialRefund:'false',maxResults:String(q.limit),...(q.pageToken?{token:q.pageToken}:{})}},o?.signal));
   const rows=v.voidedPurchases??[];if(!Array.isArray(rows)||rows.length>q.limit)throw new AdapterError('malformedResponse');
   const items=rows.map(r=>{const x=object(r);token(x.purchaseToken);if(typeof x.voidedTimeMillis!=='string'||!/^\d+$/.test(x.voidedTimeMillis)||!Number.isSafeInteger(Number(x.voidedTimeMillis)))throw new AdapterError('malformedResponse');if(x.voidedQuantity!==undefined&&x.voidedQuantity!==1)throw new AdapterError('permanentPurchaseState');return {purchaseToken:x.purchaseToken,voidedTimeMs:Number(x.voidedTimeMillis)};});
   const next=v.tokenPagination===undefined?null:object(v.tokenPagination).nextPageToken??null;if(next!==null)token(next);
   return {items:[...new Map(items.map(i=>[i.purchaseToken,i])).values()],nextPageToken:next as string|null};
  }catch(e){const c=e instanceof AdapterError?e.category:'retryableUnavailable';diagnose(this.diagnostics,'voided',c);throw new VoidedLookupError(retryable(c)?'unavailable':'configuration');}
 }
}
export class GoogleVoidedPurchaseAdapter implements VoidedPurchaseApi {
 constructor(private readonly purchases:GooglePlayPurchaseAdapter,private readonly feed:VoidedPurchaseFeed,private readonly now:()=>number){}
 async lookup(q:PlayPurchaseQuery,o?:{signal:AbortSignal}){
  try{
   query(q);const p=await this.purchases.read(q,o?.signal);const now=this.now();let pageToken:string|null=null;const seen=new Set<string>();
   for(let n=0;n<cfg.maxVoidedPages;n++){
    const page=await this.feed.list({packageName:cfg.packageName,startMs:Math.max(0,now-cfg.voidedWindowMs),endMs:now,pageToken,limit:100},o) as VoidedFeedPage;
    if(page.items.some(i=>i.purchaseToken===q.purchaseToken))return {...q,state:'entitlementRevoked',authoritative:true,testPurchase:p.testPurchase};
    if(page.nextPageToken===null)return {...q,state:'unknown',authoritative:false,testPurchase:p.testPurchase};
    if(seen.has(page.nextPageToken))throw new AdapterError('malformedResponse');seen.add(page.nextPageToken);pageToken=page.nextPageToken;
   }
   throw new VoidedLookupError('unavailable');
  }catch(e){if(e instanceof VoidedLookupError)throw e;const c=e instanceof AdapterError?e.category:'retryableUnavailable';throw new VoidedLookupError(retryable(c)||c==='notFound'?'unavailable':'configuration');}
 }
}
