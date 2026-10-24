import { HttpsError } from 'firebase-functions/v2/https';
import { DissolutionPreservationStore } from './dissolution-preservation';
export function dissolutionPreservationHandler(factory:()=>Pick<DissolutionPreservationStore,'step'>){
 return async(r:{auth?:{uid:string}|null;data:unknown})=>{
  if(!r.auth)throw new HttpsError('unauthenticated','Authentication required');
  const d=r.data as Record<string,unknown>;
  if(!d||typeof d!=='object'||Array.isArray(d)||Object.keys(d).join(',')!=='householdId'||typeof d.householdId!=='string'||!/^[A-Za-z0-9_-]{1,128}$/.test(d.householdId))throw new HttpsError('invalid-argument','INVALID_ARGUMENT');
  try{return {phase:await factory().step({uid:r.auth.uid},d.householdId)};}
  catch(e){const code=e instanceof Error&&['NOT_FOUND','FEATURE_DISABLED','INVALID_ARGUMENT'].includes(e.message)?e.message:'RETRYABLE_UNAVAILABLE';throw new HttpsError(code==='INVALID_ARGUMENT'?'invalid-argument':code==='NOT_FOUND'?'not-found':code==='FEATURE_DISABLED'?'failed-precondition':'unavailable',code);}
 };
}
