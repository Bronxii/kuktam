import {HttpsError} from 'firebase-functions/v2/https';
import {OwnerProLossStore} from './owner-pro-loss';
/** No client household, phase, operation or provenance parameters. */
export function ownerDissolutionHandler(factory:()=>Pick<OwnerProLossStore,'startOwner'>){
 return async(request:{auth?:{uid:string}|null;data:unknown})=>{
  if(!request.auth)throw new HttpsError('unauthenticated','Authentication required');
  const data=request.data;
  if(!data||typeof data!=='object'||Array.isArray(data)||Object.keys(data).length)throw new HttpsError('invalid-argument','INVALID_ARGUMENT');
  try{return await factory().startOwner(request.auth.uid);}
  catch(e){const reason=e instanceof Error&&['NOT_OWNER','IN_PROGRESS','ACCOUNT_UNAVAILABLE','FEATURE_DISABLED','INTEGRITY_REQUIRES_OPERATOR','FAMILY_UNAVAILABLE'].includes(e.message)?e.message:'RETRYABLE_UNAVAILABLE';throw new HttpsError(reason==='RETRYABLE_UNAVAILABLE'?'unavailable':'failed-precondition',reason);}
 };
}
