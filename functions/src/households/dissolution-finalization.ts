import {Firestore,Timestamp} from 'firebase-admin/firestore';
import {authenticatedUid,AuthContext} from '../billing/account-binding';
import {readAccount} from '../accounts/account-lifecycle';
import {advanceShoppingEpoch} from '../shopping/mutation-store';
import {MutationError,epochPattern} from '../shopping/mutation-contract';
import {dissolutionId} from './dissolution-preparation';
import {readPreservation} from './dissolution-preservation';
import {DissolutionMemberReleaseStore} from './dissolution-member-release';
import {commitMemberExit} from './member-leave';
import {JoinTransferStore} from './join-transfer';
import {readJoinCapacity} from './join-capacity';
import {readInvite,readInviteSlots} from './invite-contract';
import {digest} from './join-snapshot';

const invalid=():never=>{throw new Error('dissolutionFinalizationIntegrity');};
const proof=<T>(fn:()=>T):T=>{try{return fn();}catch{return invalid();}};
const receiptHash=(r:any)=>digest(JSON.stringify([r.version,r.operationId,r.snapshotHash,r.ownerUid,r.householdId,r.privateHouseholdId,r.sourceEpoch,r.targetEpoch,r.completedAt.seconds,r.completedAt.nanoseconds,r.revokedInviteIds,r.abortedJoinIds]));
export class DissolutionFinalizationStore {
 constructor(private readonly db:Firestore,private readonly clock=Timestamp.now){}
 async step(auth:AuthContext,householdId:string){
  const uid=authenticatedUid(auth);
  if(typeof householdId!=='string'||!/^[A-Za-z0-9_-]{1,128}$/.test(householdId))throw new Error('INVALID_ARGUMENT');
  if(process.env.K_SERVICE||process.env.FUNCTION_NAME||process.env.GCLOUD_PROJECT!=='demo-kuktam-local'||!/^(127\.0\.0\.1|localhost):[0-9]{1,5}$/.test(process.env.FIRESTORE_EMULATOR_HOST??''))throw new Error('FEATURE_DISABLED');
  const id=dissolutionId(uid,householdId),ref=this.db.doc(`familyOperations/${id}`),receipt=ref.collection('finalization').doc('state');
  return this.db.runTransaction(async tx=>{
   const raw=(await tx.get(ref)).data();
   if(!raw||raw.kind!=='FAMILY_DISSOLUTION'||raw.actorUid!==uid||raw.householdId!==householdId)throw new Error('NOT_FOUND');
   if(raw.status==='OPERATOR')return 'OPERATOR';
   if(!['NON_OWNER_RELEASE_COMPLETE','DONE'].includes(raw.phase))throw new Error('INVALID_ARGUMENT');
   try{
    const o=readPreservation(raw,id),prior=await tx.get(receipt),owner=o.participants.find(p=>p.role==='owner')!;
    if(o.phase==='DONE'){
     const r=prior.data(),array=(v:any,re:RegExp)=>Array.isArray(v)&&v.length<=8&&v.every((x:any,i:number)=>typeof x==='string'&&re.test(x)&&(i===0||v[i-1]<x));
     if(!r||Object.keys(r).sort().join(',')!=='abortedJoinIds,completedAt,hash,householdId,operationId,ownerUid,privateHouseholdId,revokedInviteIds,snapshotHash,sourceEpoch,targetEpoch,version'||r.version!==1||r.operationId!==id||r.snapshotHash!==o.snapshotHash||r.ownerUid!==uid||r.householdId!==householdId||r.privateHouseholdId!==owner.privateHouseholdId||!(r.completedAt instanceof Timestamp)||!r.completedAt.isEqual(o.updatedAt)||!epochPattern.test(r.sourceEpoch)||!epochPattern.test(r.targetEpoch)||r.sourceEpoch===o.sourceFence.epoch||r.targetEpoch===o.targetFence.epoch||!array(r.revokedInviteIds,/^[a-f0-9]{64}$/)||!array(r.abortedJoinIds,/^join_[a-f0-9]{64}$/)||r.hash!==receiptHash(r))invalid();
     // Historical terminal evidence: do not re-read/rewrite later private state.
     return 'DONE';
    }
    if(prior.exists)invalid();
    const {progress,participants,homes}=await new DissolutionMemberReleaseStore(this.db,this.clock).validate(tx,id,o);
    if(progress.cursor!==participants.length)invalid();
    const account=await tx.get(this.db.doc(`accountLifecycle/${uid}`)),deletion=await tx.get(this.db.doc(`accountDeletions/${uid}`));
    if(!account.exists||proof(()=>readAccount(account.data())).state!=='ACTIVE'||deletion.exists)invalid();
    const capRef=this.db.doc(`familyJoinCapacity/${householdId}`),capDoc=await tx.get(capRef),cap=proof(()=>readJoinCapacity(capDoc.data()));
    const slotsRef=this.db.doc(`familyInviteSlots/${householdId}`),slotsDoc=await tx.get(slotsRef),slots=proof(()=>readInviteSlots(slotsDoc.data())),now=this.clock();
    const invites=slots.length?await tx.getAll(...slots.map(x=>this.db.doc(`familyInvites/${x}`))):[];
    const live=await tx.get(this.db.collection('familyInvites').where('householdId','==',householdId).where('status','==','PENDING').where('expiresAt','>',now).limit(9));
    const reserved=await tx.get(this.db.collection('familyInvites').where('householdId','==',householdId).where('status','==','RESERVED').limit(9));
    if(live.size>8||reserved.size>7||[...live.docs,...reserved.docs].some(d=>!slots.includes(d.id)))invalid();
    const revoked:string[]=[];
    for(const d of invites){const v=proof(()=>readInvite(d.data()));if(v.householdId!==householdId||v.createdByUid!==uid)invalid();if(v.status==='PENDING'||v.status==='RESERVED')revoked.push(d.id);}
    const join=new JoinTransferStore(this.db,this.clock),aborts:Awaited<ReturnType<JoinTransferStore['prepareDissolutionAbort']>>[]=[];
    for(const jid of cap.operationIds){const a=await join.prepareDissolutionAbort(tx,jid,id);if(a.operation.householdId!==householdId||a.operation.ownerUid!==uid)invalid();aborts.push(a);}
    if(reserved.size!==aborts.length||reserved.docs.some(d=>!aborts.some(a=>a.operation.inviteId===d.id)))invalid();
    // All reads/claims finished. Every remaining structural effect has one commit.
    for(const a of aborts)a.commit();
    for(const d of invites)if(d.get('status')==='PENDING')tx.update(d.ref,{status:'REVOKED',operationId:null});
    const targetEpoch=commitMemberExit(tx,{member:homes.source.ref.collection('members').doc(uid),index:this.db.doc(`familyMemberships/${uid}`),user:this.db.doc(`users/${uid}`),fallback:homes.target.ref},now);
    tx.update(homes.target.ref,{operationId:null});
    const sourceEpoch=advanceShoppingEpoch(now);
    tx.update(homes.source.ref,{state:'DISSOLVED',operationId:null,...sourceEpoch});
    tx.set(slotsRef,{schemaVersion:1,inviteIds:[]});
    const r={version:1,operationId:id,snapshotHash:o.snapshotHash,ownerUid:uid,householdId,privateHouseholdId:owner.privateHouseholdId,sourceEpoch:sourceEpoch.shoppingEpoch,targetEpoch:targetEpoch.shoppingEpoch,completedAt:now,revokedInviteIds:revoked.sort(),abortedJoinIds:[...cap.operationIds].sort()};
    tx.create(receipt,{...r,hash:receiptHash(r)});
    tx.update(ref,{phase:'DONE',status:'DONE',updatedAt:now,lastOutcome:'dissolutionDone'});
    // Last scheduled structural write; visibility is atomic with every write above.
    tx.set(capRef,{schemaVersion:2,operationIds:[],structuralOperationId:null});return 'DONE';
   }catch(e){if(e instanceof MutationError||e instanceof Error&&['dissolutionFinalizationIntegrity','participantReleaseIntegrity','preservationIntegrity','preservationMergeIntegrity','sourceDispositionIntegrity','joinOwnershipInvariant','joinInviteInvariant','invalidJoinOperation','invalidJoinTransfer','invalidJoinTransferState','invalidJoinTransferEvidence'].includes(e.message)){
    tx.update(ref,{status:'OPERATOR',updatedAt:this.clock(),lastOutcome:'dissolutionFinalizationIntegrity'});return 'OPERATOR';}throw e;}
  });
 }
}
