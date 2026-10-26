import {Firestore,Timestamp,Transaction} from 'firebase-admin/firestore';
import {readOwnerDeletionIntent} from './owner-account-deletion';
import {readAccount} from '../accounts/account-lifecycle';
import {readDeletion} from '../accounts/deletion-contract';

/** Durable binding only. Cleanup/Auth/retry remain exclusively the private engine. */
export async function readOwnerDeletionHandoff(db:Firestore,tx:Transaction,uid:string){
 const ref=db.doc(`familyOwnerDeletions/${uid}`),doc=await tx.get(ref);
 if(!doc.exists)return null;
 const i=readOwnerDeletionIntent(doc.data(),uid),v=doc.data()!;
 if(!['DELETION_IN_PROGRESS','DELETED'].includes(i.phase))throw new Error('HISTORICAL_AUDIT_HANDOFF_REQUIRED');
 const a=readAccount((await tx.get(db.doc(`accountLifecycle/${uid}`))).data()),j=readDeletion((await tx.get(db.doc(`accountDeletions/${uid}`))).data());
 const terminal=i.phase==='DELETED',generation=i.accountGeneration+(terminal?2:1);
 if(a.state!==(terminal?'DELETED':'DELETING')||a.generation!==generation||j.generation!==generation||
    (j.stage==='DONE')!==terminal||v.deletionOperationId!==j.operationId||v.deletionGeneration!==i.accountGeneration+1||!(v.handedOffAt instanceof Timestamp)||terminal&&!(v.deletedAt instanceof Timestamp))throw new Error('historicalDeletionGenerationConflict');
 return {ref,intent:i,job:j};
}
