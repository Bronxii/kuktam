import { RuntimeServices } from './composition';
import { AuthContext, authenticatedUid } from '../billing/account-binding';
import { requireRecentDeletionAuth } from '../accounts/deletion-gateway';
import { transportResult } from '../transport/monetization';
import { LifecycleError } from '../billing/lifecycle-error';
import { VerificationError } from '../billing/errors';
import { parseEnvelope } from '../billing/rtdn/notification';
import { runtimeConfig } from './config';
export interface RuntimeRequest { readonly auth?: {readonly uid:string; readonly token?:{readonly auth_time?:unknown}} | null; readonly data:unknown; }
export type RuntimeDependencies = {
  monetization: Pick<RuntimeServices['monetization'], 'prepareProPurchase'|'verifyProPurchase'|'getEntitlementProof'>;
  deletion: Pick<RuntimeServices['deletion'], 'begin'|'finalize'>;
  fallback: Pick<RuntimeServices['fallback'], 'handleAuthUserDeleted'>;
  rtdn: Pick<RuntimeServices['rtdn'], 'handle'>;
  dispatcher: Pick<RuntimeServices['dispatcher'], 'run'>;
};
function failure(error:unknown) {
  if (error instanceof VerificationError && error.code === 'unauthenticated') return 'unauthenticated';
  if (error instanceof LifecycleError && ['accountDeleting','accountDeleted'].includes(error.code)) return error.code;
  if (error instanceof Error && ['invalidArgument','recentAuthenticationRequired'].includes(error.message))
    return error.message === 'recentAuthenticationRequired' ? 'recentAuthRequired' : 'invalidArgument';
  return 'retryableUnavailable';
}
/** No logging of requests, SDK errors or events. All runtime failures are sanitized. */
export function createRuntimeHandlers(get:()=>RuntimeDependencies, now:()=>number=Date.now) {
  const obtain = () => { try { return get(); } catch { throw new Error('configurationUnavailable'); } };
  async function callable(request:RuntimeRequest, action:(s:RuntimeDependencies, auth:AuthContext)=>Promise<unknown>) {
    try {
      const auth={uid:authenticatedUid(request.auth)};
      return await action(obtain(),auth);
    } catch(e) { return {schemaVersion:1,error:e instanceof Error && e.message==='configurationUnavailable'?'configuration':failure(e)}; }
  }
  return {
    prepareProPurchase:(r:RuntimeRequest)=>callable(r,(s,auth)=>transportResult(()=>s.monetization.prepareProPurchase({auth,data:r.data}))),
    verifyProPurchase:(r:RuntimeRequest)=>callable(r,(s,auth)=>transportResult(()=>s.monetization.verifyProPurchase({auth,data:r.data}))),
    getEntitlementProof:(r:RuntimeRequest)=>callable(r,(s,auth)=>transportResult(()=>s.monetization.getEntitlementProof({auth,data:r.data}))),
    beginAccountDeletion:(r:RuntimeRequest)=>callable(r,async(s,auth)=>{
      const context={...auth,authTimeSeconds:r.auth?.token?.auth_time as number};
      requireRecentDeletionAuth(context,now(),runtimeConfig.recentAuthMaxAgeMs);
      const result=await s.deletion.begin(context,r.data);
      return {schemaVersion:1,outcome:result.outcome};
    }),
    finalizeAccountDeletion:(r:RuntimeRequest)=>callable(r,async(s,auth)=>({schemaVersion:1,outcome:await s.deletion.finalize({...auth,authTimeSeconds:0},r.data)})),
    async authDeleted(user:{uid?:unknown}) {
      if(typeof user?.uid!=='string')return;
      try { authenticatedUid({uid:user.uid}); } catch { return; }
      try {
        const result=await obtain().fallback.handleAuthUserDeleted(user.uid);
        if(['cleanupRetryRequired','authDeleteRetryRequired','busy'].includes(result))throw new Error();
      } catch { throw new Error('deletionRetryRequired'); }
    },
    async rtdn(event:{data?:{message?:{messageId?:unknown;publishTime?:unknown;data?:unknown}}}) {
      const message=event?.data?.message;
      const envelope={source:runtimeConfig.topic,messageId:message?.messageId,publishTime:message?.publishTime,data:message?.data};
      // Reuse strict parser. Reject poison envelopes before service/secret initialization.
      const parsed=parseEnvelope(envelope,runtimeConfig.topic);
      if(typeof parsed==='string')return;
      try {
        const result=await obtain().rtdn.handle(envelope);
        if(['retryablePlayFailure','internalConflict','busyLease'].includes(result.outcome))throw new Error();
      } catch { throw new Error('rtdnRetryRequired'); }
    },
    async maintenance() {
      try { await obtain().dispatcher.run(); } catch { throw new Error('maintenanceRetryRequired'); }
    },
  };
}
