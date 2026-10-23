import { HttpsError } from 'firebase-functions/v2/https';
import { JoinTransferStore } from './join-transfer';
import { FamilyInviteError } from './invite-contract';
export function joinTransferHandler(factory:()=>JoinTransferStore,action:'prepare'|'state'|'confirm'|'cancel'){
  return async(r:{auth?:{uid:string}|null;data:unknown})=>{
    if(!r.auth)throw new HttpsError('unauthenticated','Authentication required');
    const d=r.data as Record<string,unknown>,fields=action==='confirm'?['operationId','inviteId','sourceEpoch','snapshotHash','sourceItemCount','consentVersion']:['operationId','inviteId'];
    if(!d||typeof d!=='object'||Array.isArray(d)||Object.keys(d).sort().join(',')!==fields.sort().join(',')||typeof d.operationId!=='string'||typeof d.inviteId!=='string')throw new HttpsError('invalid-argument','INVALID_ARGUMENT');
    try{
      const store=factory(),ctx={uid:r.auth.uid};
      if(action==='confirm'){
        if(typeof d.sourceEpoch!=='string'||typeof d.snapshotHash!=='string'||!Number.isSafeInteger(d.sourceItemCount)||d.consentVersion!==1)throw new FamilyInviteError('INVALID_ARGUMENT');
        return {schemaVersion:1,outcome:await store.confirm(ctx,{operationId:d.operationId,inviteId:d.inviteId,sourceEpoch:d.sourceEpoch,snapshotHash:d.snapshotHash,sourceItemCount:d.sourceItemCount as number,consentVersion:1})};
      }
      if(action==='cancel')return {schemaVersion:1,outcome:await store.cancel(ctx,d.operationId,d.inviteId)};
      return store[action](ctx,d.operationId,d.inviteId);
    }catch(e){const code=e instanceof FamilyInviteError?e.code:'RETRYABLE_UNAVAILABLE';throw new HttpsError(code==='INVALID_ARGUMENT'?'invalid-argument':code==='RETRYABLE_UNAVAILABLE'?'unavailable':'failed-precondition',code);}
  };
}
