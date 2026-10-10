import { GoogleAuth } from 'google-auth-library';
import { AdapterError, classify, productionAdapterConfig as cfg } from './config';
export interface RestRequest { readonly method:'GET'|'POST'; readonly path:string; readonly query?:Readonly<Record<string,string>>; }
export interface PlayTransport { request(r:RestRequest,signal?:AbortSignal):Promise<unknown>; }
export interface AccessCredential { getAccessToken():Promise<string|null|undefined>; }
/** Constructed only by a future runtime composition. No credential discovery on import. */
export function createAdcPlayTransport(){return new GooglePlayRest(new GoogleAuth({scopes:[cfg.scope]}));}
export class GooglePlayRest implements PlayTransport {
 constructor(private readonly credentials:AccessCredential,private readonly fetcher:typeof fetch=fetch){}
 async request(r:RestRequest,signal?:AbortSignal):Promise<unknown>{
  if(!r.path.startsWith(`/androidpublisher/v3/applications/${cfg.packageName}/purchases/`)||r.path.includes('?')||r.path.includes('#'))throw new AdapterError('invalidArgument');
  const prefix= `/androidpublisher/v3/applications/${cfg.packageName}/purchases/`;
  const suffix=r.path.slice(prefix.length);
  if(!(r.method==='GET'&&(/^productsv2\/tokens\/[^/]+$/.test(suffix)||suffix==='voidedpurchases')||r.method==='POST'&&suffix.startsWith(`products/${cfg.productId}/tokens/`)&&/^[^/]+:acknowledge$/.test(suffix.slice(`products/${cfg.productId}/tokens/`.length)))||new URL(r.path,cfg.origin).pathname!==r.path)throw new AdapterError('invalidArgument');
  const controller=new AbortController();const abort=()=>controller.abort();signal?.addEventListener('abort',abort,{once:true});
  if(signal?.aborted)controller.abort();
  let timer:ReturnType<typeof setTimeout>|undefined;
  try {
   return await Promise.race([this.perform(r,controller.signal),new Promise<never>((_,reject)=>{
    timer=setTimeout(()=>{controller.abort();reject(new AdapterError('retryableUnavailable'));},cfg.timeoutMs);
   })]);
  }catch(e){throw e instanceof AdapterError?e:new AdapterError('retryableUnavailable');}
  finally{if(timer)clearTimeout(timer);signal?.removeEventListener('abort',abort);}
 }
 private async perform(r:RestRequest,signal:AbortSignal){
  if(signal.aborted)throw new AdapterError('retryableUnavailable');
  let token:string|null|undefined;
  try{token=await this.credentials.getAccessToken();}catch{throw new AdapterError('unauthenticatedCredential');}
  if(!token)throw new AdapterError('unauthenticatedCredential');
  if(signal.aborted)throw new AdapterError('retryableUnavailable');
  const url=new URL(r.path,cfg.origin);for(const [k,v]of Object.entries(r.query??{}))url.searchParams.set(k,v);
  const response=await this.fetcher(url,{method:r.method,headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},...(r.method==='POST'?{body:'{}'}:{}),signal,redirect:'error'});
  const reader=response.body?.getReader();let size=0;const chunks:Uint8Array[]=[];
  if(reader){try{while(true){const {done,value}=await reader.read();if(done)break;size+=value.byteLength;if(size>cfg.maxResponseBytes)throw new AdapterError('malformedResponse');chunks.push(value);}}finally{await reader.cancel().catch(()=>{});}}
  let text:string;try{text=new TextDecoder('utf-8',{fatal:true}).decode(Buffer.concat(chunks));}catch{throw new AdapterError('malformedResponse');}let data:unknown;
  try{data=text?JSON.parse(text):{};}catch{if(!response.ok)throw new AdapterError(classify(response.status,null));throw new AdapterError('malformedResponse');}
  if(!response.ok)throw new AdapterError(classify(response.status,data));return data;
 }
}
