import { HttpsError } from 'firebase-functions/v2/https';
import { DissolutionPreparationError, DissolutionPreparationStore } from './dissolution-preparation';
export function dissolutionPreparationHandler(factory:()=>DissolutionPreparationStore){
  return async(r:{auth?:{uid:string}|null;data:unknown})=>{
    if(!r.auth)throw new HttpsError('unauthenticated','Authentication required');
    const d=r.data as Record<string,unknown>;
    if(!d||typeof d!=='object'||Array.isArray(d)||Object.keys(d).join(',')!=='householdId'||typeof d.householdId!=='string'||!/^[A-Za-z0-9_-]{1,128}$/.test(d.householdId))throw new HttpsError('invalid-argument','INVALID_ARGUMENT');
    try{return await factory().prepare({uid:r.auth.uid},d.householdId);}
    catch(e){const code=e instanceof DissolutionPreparationError?e.code:'RETRYABLE_UNAVAILABLE';
      throw new HttpsError(code==='INVALID_ARGUMENT'?'invalid-argument':code==='RETRYABLE_UNAVAILABLE'?'unavailable':'failed-precondition',code);}
  };
}
