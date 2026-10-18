import { HttpsError } from 'firebase-functions/v2/https';
import { FamilyInviteStore } from './family-invites';
import { FamilyInviteError, hashInviteToken, inviteIdPattern } from './invite-contract';

export function familyInviteHandlers(store:()=>FamilyInviteStore) {
  const handler=(method:'create'|'revoke'|'preview'|'state')=>async(request:{auth?:{uid:string}|null;data:unknown})=>{
    if(!request.auth)throw new HttpsError('unauthenticated','Authentication required');
    const data=request.data as Record<string,unknown>;
    const keys=method==='revoke'?'inviteId':method==='preview'?'token':'';
    if(!data || typeof data!=='object' || Array.isArray(data) || Object.keys(data).sort().join(',')!==keys)
      throw new HttpsError('invalid-argument','INVALID_ARGUMENT');
    try{
      // Reject before Admin initialization. Raw token is never placed in errors.
      if(method==='preview')hashInviteToken(data.token);
      if(method==='revoke' && (typeof data.inviteId!=='string'||!inviteIdPattern.test(data.inviteId)))throw new FamilyInviteError('INVALID_ARGUMENT');
      const service=store(),context={uid:request.auth.uid};
      if(method==='create')return await service.create(context);
      if(method==='revoke')return await service.revoke(context,data.inviteId as string);
      if(method==='preview')return await service.preview(context,data.token as string);
      return await service.state(context);
    }catch(error){
      const reason=error instanceof FamilyInviteError?error.code:'RETRYABLE_UNAVAILABLE';
      throw new HttpsError(reason==='INVALID_ARGUMENT'?'invalid-argument':reason==='RETRYABLE_UNAVAILABLE'?'unavailable':'failed-precondition',reason);
    }
  };
  return {create:handler('create'),revoke:handler('revoke'),preview:handler('preview'),state:handler('state')};
}
