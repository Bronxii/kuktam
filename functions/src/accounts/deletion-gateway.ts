import { authenticatedUid } from '../billing/account-binding';
import { AccountDeletionService } from './account-deletion';

/** Only Firebase runtime verified auth/token fields may populate this context.
 * Neither auth_time nor UID may be copied from request.data. */
export interface DeletionAuth { readonly uid:string; readonly authTimeSeconds:number; }
export function requireRecentDeletionAuth(auth:DeletionAuth|null,nowMs:number,maxAgeMs=300000) {
 const uid=authenticatedUid(auth);
 if(!auth||!Number.isSafeInteger(auth.authTimeSeconds)||!Number.isSafeInteger(nowMs)||
    !Number.isSafeInteger(maxAgeMs)||maxAgeMs<=0||auth.authTimeSeconds<0||
    auth.authTimeSeconds*1000>nowMs||nowMs-auth.authTimeSeconds*1000>maxAgeMs)
   throw new Error('recentAuthenticationRequired');
 return {uid};
}
/** Modern transport surface intentionally has no fallback/authGone input. */
export class DeletionGateway {
 constructor(private readonly service:AccountDeletionService,private readonly now:()=>number,private readonly maxAgeMs=300000){}
 async begin(auth:DeletionAuth|null,data:unknown){
  this.empty(data);return this.service.beginAccountDeletion(requireRecentDeletionAuth(auth,this.now(),this.maxAgeMs));
 }
 async finalize(auth:DeletionAuth|null,data:unknown){
  this.empty(data);return this.service.finalizeContent({uid:authenticatedUid(auth)});
 }
 private empty(data:unknown){
  if(!data||typeof data!=='object'||Array.isArray(data)||Object.keys(data).length!==0)
   throw new Error('invalidArgument');
 }
}
