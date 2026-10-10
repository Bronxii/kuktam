import { PACKAGE_NAME, PRODUCT_ID } from '../billing/play-purchase-api';
export const productionAdapterConfig = Object.freeze({
 packageName:PACKAGE_NAME, productId:PRODUCT_ID,
 origin:'https://androidpublisher.googleapis.com', scope:'https://www.googleapis.com/auth/androidpublisher',
 timeoutMs:20000, maxResponseBytes:1048576, voidedWindowMs:30*86400000, maxVoidedPages:10,
});
export type AdapterCategory='retryableUnavailable'|'rateLimited'|'unauthenticatedCredential'|'permissionDenied'|'notFound'|'invalidArgument'|'malformedResponse'|'configurationError'|'permanentPurchaseState';
export class AdapterError extends Error { constructor(readonly category:AdapterCategory){super(category);} }
export interface Diagnostic { readonly operation:'lookup'|'ack'|'voided'|'authDelete'; readonly category:AdapterCategory; readonly retryable:boolean; }
export type Diagnostics=(event:Diagnostic)=>void;
export function retryable(c:AdapterCategory){return c==='retryableUnavailable'||c==='rateLimited';}
export function diagnose(sink:Diagnostics|undefined,operation:Diagnostic['operation'],category:AdapterCategory){
 try{sink?.(Object.freeze({operation,category,retryable:retryable(category)}));}catch{/* Diagnostics cannot affect purchase processing. */}
}
export function object(v:unknown):Record<string,unknown>{if(!v||typeof v!=='object'||Array.isArray(v))throw new AdapterError('malformedResponse');return v as Record<string,unknown>;}
export function classify(status:number,data:unknown):AdapterCategory {
 const e=(data as any)?.error; const canonical=e?.status;
 const reasons=[...(Array.isArray(e?.errors)?e.errors.map((x:any)=>x?.reason):[]),...(Array.isArray(e?.details)?e.details.map((x:any)=>x?.reason):[])];
 if(canonical==='RESOURCE_EXHAUSTED'||status===429||reasons.some(x=>['rateLimitExceeded','userRateLimitExceeded','quotaExceeded'].includes(x)))return 'rateLimited';
 if(canonical==='UNAUTHENTICATED'||status===401)return 'unauthenticatedCredential';
 if(reasons.some(x=>['SERVICE_DISABLED','accessNotConfigured','API_KEY_INVALID'].includes(x)))return 'configurationError';
 if(canonical==='PERMISSION_DENIED'||status===403)return 'permissionDenied';
 if(canonical==='NOT_FOUND'||status===404)return 'notFound';
 if(canonical==='INVALID_ARGUMENT'||status===400)return 'invalidArgument';
 if(status===408||status===409||status>=500||['UNAVAILABLE','DEADLINE_EXCEEDED','ABORTED'].includes(canonical))return 'retryableUnavailable';
 return 'configurationError';
}
