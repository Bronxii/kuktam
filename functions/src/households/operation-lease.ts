import { randomUUID } from 'node:crypto';
import { Firestore, Timestamp } from 'firebase-admin/firestore';

export interface LeasedOperation {
  status:string; nextAt:Timestamp|null; leaseId:string|null; leaseUntil:Timestamp|null;
}
/** Shared CREATE/JOIN lease protocol. Parser also verifies operation identity. */
export async function claimFamilyLease(db:Firestore,id:string,read:(raw:unknown)=>LeasedOperation,
  clock:()=>Timestamp,leaseMs:number):Promise<string|null> {
  if(!/^[a-zA-Z0-9_-]{1,128}$/.test(id))throw new Error('invalidOperationId');
  const leaseId=randomUUID();
  return db.runTransaction(async tx=>{
    const ref=db.doc(`familyOperations/${id}`),doc=await tx.get(ref);
    if(!doc.exists)return null;
    const op=read(doc.data()),now=clock();
    if(op.status!=='READY'||!op.nextAt||op.nextAt.toMillis()>now.toMillis()||
      op.leaseUntil&&op.leaseUntil.toMillis()>now.toMillis())return null;
    tx.update(ref,{leaseId,leaseUntil:Timestamp.fromMillis(now.toMillis()+leaseMs),updatedAt:now});
    return leaseId;
  });
}
