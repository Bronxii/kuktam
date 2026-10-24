import { HttpsError } from 'firebase-functions/v2/https';
import { FamilyLeaveError, MemberLeaveStore } from './member-leave';
import { inviteIdPattern } from './invite-contract';

/** UID/routing are server-authoritative. inviteId binds the request to the exact
 * joined membership, not a fresh operation on whatever family is active later. */
export function memberLeaveHandler(factory:()=>MemberLeaveStore){
  return async(r:{auth?:{uid:string}|null;data:unknown})=>{
    if(!r.auth)throw new HttpsError('unauthenticated','Authentication required');
    const d=r.data as Record<string,unknown>;
    if(!d||typeof d!=='object'||Array.isArray(d)||Object.keys(d).join(',')!=='inviteId'||
      typeof d.inviteId!=='string'||!inviteIdPattern.test(d.inviteId))throw new HttpsError('invalid-argument','INVALID_ARGUMENT');
    try{return await factory().leave({uid:r.auth.uid},d.inviteId);}
    catch(e){const code=e instanceof FamilyLeaveError?e.code:'RETRYABLE_UNAVAILABLE';
      throw new HttpsError(code==='INVALID_ARGUMENT'?'invalid-argument':code==='RETRYABLE_UNAVAILABLE'?'unavailable':'failed-precondition',code);}
  };
}
