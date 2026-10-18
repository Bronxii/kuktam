import { createHash, randomBytes } from 'node:crypto';
import { Timestamp } from 'firebase-admin/firestore';

export const EPOCH_MS=30*86400000, RETENTION_MS=7*86400000;
export const epochPattern=/^[0-9]{13}-[a-f0-9]{32}$/;
export const mutationPattern=/^[0-9]{13}-[a-f0-9]{32}_[a-f0-9]{64}$/;
export const safeId=(v:unknown):v is string=>typeof v==='string'&&/^[a-zA-Z0-9_-]{1,128}$/.test(v);
export const safeActor=(v:unknown):v is string=>typeof v==='string'&&v.length>0&&v.length<=128&&!v.includes('/')&&v.trim()===v;
export type Outcome='APPLIED'|'REJECTED_STALE'|'REJECTED_CONTEXT_CHANGED'|'REJECTED_NOT_FOUND'|'REJECTED_UNAUTHORIZED'|'FAILED_TERMINAL';
export type Child={type:'ADD';name:string;quantity:number;unit:string}|{type:'EDIT';itemId:string;expectedRevision:number;name:string;quantity:number;unit:string}|{type:'DELETE';itemId:string;expectedRevision:number}|{type:'SET_CHECKED';itemId:string;expectedRevision:number;isChecked:boolean};
export interface Request {schemaVersion:1;mutationId:string;actorUid:string;householdId:string;epoch:string;kind:'ADD'|'EDIT'|'DELETE'|'SET_CHECKED'|'BULK';payloadJson:string;submittedAt:Timestamp}
export class MutationError extends Error {constructor(readonly code:Outcome|'INVALID_ARGUMENT'|'ID_CONFLICT'|'FEATURE_DISABLED'){super(code);}}
const invalid=():never=>{throw new MutationError('INVALID_ARGUMENT');};
export function exact(v:unknown,keys:string[]):asserts v is Record<string,unknown>{
  if(!v||typeof v!=='object'||Array.isArray(v)||Object.keys(v).sort().join(',')!==keys.sort().join(','))invalid();
}
export function epochExpiry(epoch:string){if(!epochPattern.test(epoch))invalid();return Number(epoch.slice(0,13));}
export function newEpoch(now:Timestamp){return `${now.toMillis()+EPOCH_MS}-${randomBytes(16).toString('hex')}`;}
export function newMutationId(epoch:string){epochExpiry(epoch);return `${epoch}_${randomBytes(32).toString('hex')}`;}
export function revision(v:unknown):number {if(v===undefined)return 0;if(!Number.isSafeInteger(v)||(v as number)<0)throw new MutationError('FAILED_TERMINAL');return v as number;}
function item(v:Record<string,unknown>){
  if(typeof v.name!=='string'||!v.name.trim()||[...v.name].length>200||typeof v.quantity!=='number'||!Number.isFinite(v.quantity)||v.quantity<=0||typeof v.unit!=='string'||!['g','kg','ml','l','db','tk','ek','csomag','üveg','doboz','konzerv'].includes(v.unit))invalid();
  const unit=v.unit as string,quantity=(v.quantity as number)*(['kg','l'].includes(unit)?1000:1);
  if(!Number.isFinite(quantity)||quantity>Number.MAX_SAFE_INTEGER)invalid();
  return {name:(v.name as string).trim().toLowerCase(),quantity,unit:unit==='kg'?'g':unit==='l'?'ml':unit};
}
function child(v:unknown):Child {
  const c=v as Record<string,unknown>;
  if(!c||typeof c!=='object')invalid();
  if(c.type==='ADD'){exact(c,['type','name','quantity','unit']);return {type:'ADD',...item(c)};}
  const keys=c.type==='EDIT'?['name','quantity','unit']:c.type==='SET_CHECKED'?['isChecked']:c.type==='DELETE'?[]:invalid();
  exact(c,['type','itemId','expectedRevision',...keys]);
  if(!safeId(c.itemId)||!Number.isSafeInteger(c.expectedRevision)||(c.expectedRevision as number)<0)invalid();
  const base={itemId:c.itemId as string,expectedRevision:c.expectedRevision as number};
  if(c.type==='EDIT')return {type:'EDIT',...base,...item(c)};
  if(c.type==='SET_CHECKED'){if(typeof c.isChecked!=='boolean')invalid();return {type:'SET_CHECKED',...base,isChecked:c.isChecked as boolean};}
  return {type:'DELETE',...base};
}
export function parseRequest(raw:unknown,uid:string,id:string):{request:Request;children:Child[];hash:string}{
  exact(raw,['schemaVersion','mutationId','actorUid','householdId','epoch','kind','payloadJson','submittedAt']);
  const r=raw as unknown as Request;
  if(r.schemaVersion!==1||!safeActor(uid)||r.actorUid!==uid||r.mutationId!==id||!mutationPattern.test(id)||!epochPattern.test(r.epoch)||!id.startsWith(r.epoch+'_')||!safeId(r.householdId)||!(r.submittedAt instanceof Timestamp)||typeof r.payloadJson!=='string'||Buffer.byteLength(r.payloadJson)>262144)invalid();
  let payload:unknown;try{payload=JSON.parse(r.payloadJson);}catch{invalid();}
  let children:Child[];
  if(r.kind==='BULK'){
    exact(payload,['items']);const items=payload.items;
    if(!Array.isArray(items)||items.length<1||items.length>200)invalid();
    children=(items as unknown[]).map(child);
  }else{const c=child(payload);if(c.type!==r.kind)invalid();children=[c];}
  // Exact immutable payload bytes. Even a semantically equivalent replacement
  // is not permitted under an existing action ID. Transport time is not intent.
  const hash=createHash('sha256').update(JSON.stringify([1,id,uid,r.householdId,r.epoch,r.kind,r.payloadJson])).digest('hex');
  return {request:r,children,hash};
}
export function requestFields(v:FirebaseFirestore.DocumentData):Request {
  return Object.fromEntries(['schemaVersion','mutationId','actorUid','householdId','epoch','kind','payloadJson','submittedAt'].map(k=>[k,v[k]])) as unknown as Request;
}
