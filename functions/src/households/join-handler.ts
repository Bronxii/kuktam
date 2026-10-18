import { HttpsError } from 'firebase-functions/v2/https';
import { FamilyJoinStore } from './family-join';
import { FamilyInviteError, hashInviteToken } from './invite-contract';

export function acceptFamilyHandler(factory:()=>FamilyJoinStore) {
  return async(request:{auth?:{uid:string}|null;data:unknown})=>{
    if(!request.auth)throw new HttpsError('unauthenticated','Authentication required');
    const data=request.data as Record<string,unknown>;
    if(!data||typeof data!=='object'||Array.isArray(data)||Object.keys(data).sort().join(',')!=='mode,token'||
      !['ADD','DELETE'].includes(data.mode as string))throw new HttpsError('invalid-argument','INVALID_ARGUMENT');
    try {
      hashInviteToken(data.token);
      const store=factory(),id=await store.reserve({uid:request.auth.uid},data.token as string,data.mode as 'ADD'|'DELETE');
      return {schemaVersion:1,operationId:id,outcome:await store.resume(id)};
    }catch(error){
      const reason=error instanceof FamilyInviteError?error.code:'RETRYABLE_UNAVAILABLE';
      throw new HttpsError(reason==='INVALID_ARGUMENT'?'invalid-argument':reason==='RETRYABLE_UNAVAILABLE'?'unavailable':'failed-precondition',reason);
    }
  };
}
