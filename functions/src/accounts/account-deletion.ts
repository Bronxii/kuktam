import { Firestore, Timestamp } from 'firebase-admin/firestore';
import { LifecycleStore } from '../billing/lifecycle-store';
import { AuthContext, authenticatedUid } from '../billing/account-binding';
import { AuthUserDeletionApi, DeletionOutcome, DeletionPolicy, defaultDeletionPolicy, validateDeletionPolicy } from './deletion-contract';
import { bounded } from '../jobs/maintenance-policy';
/** Bounded account and billing cleanup; no Play refund/revoke/consume calls. */
export class AccountDeletionService {
 constructor(db:Firestore,private readonly auth:AuthUserDeletionApi,
 clock:()=>Timestamp=Timestamp.now,private readonly store=new LifecycleStore(db,clock),private readonly policy:DeletionPolicy=defaultDeletionPolicy){validateDeletionPolicy(policy);}
 beginAccountDeletion(context:AuthContext){return this.store.beginDeletion(authenticatedUid(context));}
 /** Trusted Auth deletion event ONLY; never exposed by the modern gateway. */
 async handleAuthUserDeleted(uid:string,maxSteps=10):Promise<DeletionOutcome>{
  authenticatedUid({uid});const result=await this.store.beginDeletion(uid,true);
  if(result.outcome==='alreadyDeleted')return 'alreadyDeleted';
  return this.resume(uid,maxSteps);
 }
 async finalizeContent(context:AuthContext):Promise<DeletionOutcome>{
  const uid=authenticatedUid(context);
  return this.resume(uid);
 }
 async resume(uid:string,maxSteps=10,pageSize=50):Promise<DeletionOutcome>{
  authenticatedUid({uid});if(!Number.isSafeInteger(maxSteps)||maxSteps<1||maxSteps>50||!Number.isSafeInteger(pageSize)||pageSize<1||pageSize>100)throw new Error('invalidDeletionLimits');
  try {
   for(let step=0;step<maxSteps;step++){
    const result=await this.store.deletionStep(uid,pageSize,this.policy);
    if(result.kind==='cleanupIncomplete')return 'cleanupIncomplete';
    if(result.kind==='done')return 'deletionCompleted';
    if(result.kind==='busy')return 'busy';
    if(result.kind==='operator')return 'supportRequired';
    if(result.kind==='auth'){
     let status:Awaited<ReturnType<AuthUserDeletionApi['deleteUser']>>;
     try{status=await bounded(signal=>this.auth.deleteUser(uid,{signal}),this.policy.ioTimeoutMs);}catch{status='temporaryFailure';}
     if(!['deleted','notFound','temporaryFailure','permanentFailure'].includes(status))status='permanentFailure';
     const applied=await this.store.completeDeletionAuth(uid,result.operationId,result.generation,result.leaseId,status,this.policy);
     if(!applied)return 'cleanupRetryRequired';
     if(status==='temporaryFailure')return 'authDeleteRetryRequired';
     if(status==='permanentFailure')return 'supportRequired';
    }
   }
   return 'cleanupRetryRequired';
  }catch{return 'cleanupRetryRequired';}
 }
}
