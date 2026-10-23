import { Timestamp } from 'firebase-admin/firestore';
import { JoinOperation, readJoinOperation } from './family-join';
import { epochPattern } from '../shopping/mutation-contract';
export interface TransferOperation extends JoinOperation {
  schemaVersion:2;
  committedAt:Timestamp|null;
  sourceFence:{epoch:string;at:Timestamp}|null;
  snapshot:{version:1;count:number;hash:string}|null;
  cursor:{pageIndex:number;childOffset:number}|null;
  deleteConsent:{version:1;snapshotHash:string;confirmedAt:Timestamp}|null;
}
const extra=['committedAt','sourceFence','snapshot','cursor','deleteConsent'];
const exact=(v:any,keys:string[])=>v&&typeof v==='object'&&!Array.isArray(v)&&Object.keys(v).sort().join(',')===keys.sort().join(',');
const count=(v:unknown)=>Number.isSafeInteger(v)&&(v as number)>=0;
export const hashValue=(v:unknown):v is string=>typeof v==='string'&&/^[a-f0-9]{64}$/.test(v);
export function readTransfer(raw:unknown,id:string):TransferOperation {
  const v=raw as TransferOperation;
  if(!v||v.schemaVersion!==2||extra.some(k=>!(k in v)))throw new Error('invalidJoinTransfer');
  const base=Object.fromEntries(Object.entries(v).filter(([k])=>!extra.includes(k)));
  readJoinOperation({...base,schemaVersion:1,phase:'READY_FOR_TRANSFER',status:v.status==='READY'?'READY':'ABORTED'},id);
  if(!['READY','ABORTED','OPERATOR','DONE'].includes(v.status)||!['READY_FOR_TRANSFER','SNAPSHOT_SOURCE','SOURCE_FENCED_WAITING_CONFIRMATION','COMMITTED_TRANSFER','CLEAN_SOURCE','TRANSFER_COMPLETE','ACTIVE'].includes(v.phase)||
    !(v.committedAt===null||v.committedAt instanceof Timestamp)||
    !(v.sourceFence===null||exact(v.sourceFence,['epoch','at'])&&epochPattern.test(v.sourceFence.epoch)&&v.sourceFence.at instanceof Timestamp)||
    !(v.snapshot===null||exact(v.snapshot,['version','count','hash'])&&v.snapshot.version===1&&count(v.snapshot.count)&&hashValue(v.snapshot.hash))||
    !(v.cursor===null||exact(v.cursor,['pageIndex','childOffset'])&&count(v.cursor.pageIndex)&&count(v.cursor.childOffset)&&v.cursor.childOffset<10)||
    !(v.deleteConsent===null||exact(v.deleteConsent,['version','snapshotHash','confirmedAt'])&&v.deleteConsent.version===1&&hashValue(v.deleteConsent.snapshotHash)&&v.deleteConsent.confirmedAt instanceof Timestamp))throw new Error('invalidJoinTransfer');
  const committed=['COMMITTED_TRANSFER','CLEAN_SOURCE','TRANSFER_COMPLETE','ACTIVE'].includes(v.phase);
  if(committed!==(v.committedAt!==null)||v.status==='ABORTED'&&committed||(v.status==='DONE')!==(v.phase==='ACTIVE')||
    v.phase!=='READY_FOR_TRANSFER'&&!v.sourceFence||committed&&!v.snapshot||
    v.phase==='SOURCE_FENCED_WAITING_CONFIRMATION'&&!v.snapshot||
    v.mode==='ADD'&&v.deleteConsent!==null||v.mode==='DELETE'&&committed&&(!v.deleteConsent||v.deleteConsent.snapshotHash!==v.snapshot?.hash)||
    !committed&&v.deleteConsent!==null)throw new Error('invalidJoinTransferState');
  if(v.phase==='READY_FOR_TRANSFER'&&(v.sourceFence!==null||v.snapshot!==null||v.cursor!==null)||
    v.phase==='SNAPSHOT_SOURCE'&&(!v.cursor||v.snapshot!==null)||
    v.phase==='SOURCE_FENCED_WAITING_CONFIRMATION'&&v.cursor!==null||
    v.committedAt&&v.sourceFence&&v.committedAt.toMillis()<v.sourceFence.at.toMillis()||
    v.deleteConsent&&v.committedAt&&!v.deleteConsent.confirmedAt.isEqual(v.committedAt))throw new Error('invalidJoinTransferEvidence');
  return v;
}
