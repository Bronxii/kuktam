import { Timestamp } from 'firebase-admin/firestore';
import { exact, record, positive, LifecycleError } from '../billing/lifecycle-error';
export const deletionStages = ['BINDINGS_MARK','GRANTS','PURCHASES','BINDINGS','AUTH','DONE'] as const;
export interface DeletionOperation {
 readonly schemaVersion:2; readonly cleanupState:'PENDING'|'VERIFIED'; readonly operationId:string; readonly generation:number;
 readonly stage:typeof deletionStages[number]; readonly authGone:boolean;
 readonly leaseId:string|null; readonly leaseUntil:Timestamp|null; readonly nextAt:Timestamp|null;
 readonly lastOutcome:'cleanupRetryRequired'|'authDeleteRetryRequired'|'supportRequired'|null;
 readonly updatedAt:Timestamp;
}
export function readDeletion(value:unknown):DeletionOperation {
 const raw=record(value); const legacy=raw.schemaVersion===1;
 const v=legacy?{...raw,schemaVersion:2,cleanupState:'PENDING'}:raw;
 if(legacy && 'cleanupState' in raw)throw new LifecycleError('invalidSchema');
 exact(v,['cleanupState','schemaVersion','operationId','generation','stage','authGone','leaseId','leaseUntil','nextAt','lastOutcome','updatedAt']);
 if(v.schemaVersion!==2||!['PENDING','VERIFIED'].includes(v.cleanupState as string)||typeof v.operationId!=='string'||!v.operationId||!positive(v.generation)||!deletionStages.includes(v.stage as DeletionOperation['stage'])||typeof v.authGone!=='boolean'||!(v.updatedAt instanceof Timestamp)||
 ![v.leaseUntil,v.nextAt].every(t=>t===null||t instanceof Timestamp)||!(v.leaseId===null||typeof v.leaseId==='string'&&!!v.leaseId)||
 (v.leaseId===null)!==(v.leaseUntil===null)||v.leaseId!==null&&v.stage!=='AUTH'||![null,'cleanupRetryRequired','authDeleteRetryRequired','supportRequired'].includes(v.lastOutcome as null))throw new LifecycleError('invalidSchema');
 if(v.stage==='DONE' && (v.authGone!==true||v.leaseId!==null||v.nextAt!==null||v.lastOutcome!==null))throw new LifecycleError('invalidSchema');
 return Object.freeze({...v}) as unknown as DeletionOperation;
}
/** Trusted caller only. Future transport MUST validate UID and recent authentication. */
export interface AuthUserDeletionApi {
 deleteUser(uid:string,options:{signal:AbortSignal}):Promise<'deleted'|'notFound'|'temporaryFailure'|'permanentFailure'>;
}
export type DeletionOutcome='deletionStarted'|'deletionAlreadyInProgress'|'deletionCompleted'|'alreadyDeleted'|'cleanupRetryRequired'|'authDeleteRetryRequired'|'supportRequired'|'busy'|'cleanupIncomplete';
export interface DeletionPolicy { readonly leaseMs:number; readonly ioTimeoutMs:number; readonly retryMs:number; }
export const defaultDeletionPolicy:DeletionPolicy=Object.freeze({leaseMs:120000,ioTimeoutMs:30000,retryMs:300000});
export function validateDeletionPolicy(p:DeletionPolicy){if(![p.leaseMs,p.ioTimeoutMs,p.retryMs].every(n=>Number.isSafeInteger(n)&&n>0)||p.ioTimeoutMs>=p.leaseMs)throw new LifecycleError('invalidTransition');}
