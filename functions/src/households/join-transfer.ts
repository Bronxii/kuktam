import { FieldPath, Firestore, Timestamp, Transaction } from 'firebase-admin/firestore';
import { authenticatedUid, AuthContext } from '../billing/account-binding';
import { FamilyJoinStore, joinOperationId, localJoinRuntime, readJoinOperation } from './family-join';
import { TransferOperation, readTransfer, hashValue } from './join-transfer-contract';
import { readJoinCapacity } from './join-capacity';
import { FamilyInviteStore } from './family-invites';
import { FamilyInviteError, readInvite, readInviteSlots } from './invite-contract';
import { hasPro } from './family-create';
import { advanceShoppingEpoch } from '../shopping/mutation-store';
import { parseRequest } from '../shopping/mutation-contract';
import { digest, sourceFingerprint } from './join-snapshot';
import { executeTransfer, transferIntegrityError, transferPageId as pageId, transferSeed as seed } from './join-transfer-execution';

const fail=(code:ConstructorParameters<typeof FamilyInviteError>[0]):never=>{throw new FamilyInviteError(code);};
const post=(op:TransferOperation)=>op.committedAt!==null;
export class JoinTransferStore {
  private readonly validation:FamilyInviteStore;
  constructor(private readonly db:Firestore,private readonly clock=Timestamp.now){
    this.validation=new FamilyInviteStore(db,{resolve:async()=>{throw new Error('notRequired');}},clock);
  }
  private local(){if(process.env.K_SERVICE||process.env.FUNCTION_NAME||!localJoinRuntime(process.env.GCLOUD_PROJECT,process.env.FIRESTORE_EMULATOR_HOST))fail('FEATURE_DISABLED');}
  private identity(context:AuthContext,id:string,inviteId:string){const uid=authenticatedUid(context);if(id!==joinOperationId(uid)||!/^[a-f0-9]{64}$/.test(inviteId))fail('INVALID_ARGUMENT');return uid;}
  async prepare(context:AuthContext,id:string,inviteId:string){
    this.local();this.identity(context,id,inviteId);
    await this.db.runTransaction(async tx=>{
      const ref=this.db.doc(`familyOperations/${id}`),doc=await tx.get(ref),o=readJoinOperation(doc.data(),id);
      if(o.inviteId!==inviteId)fail('NOT_FOUND');
      if(o.schemaVersion===2)return;
      if(o.status!=='READY'||o.phase!=='READY_FOR_TRANSFER')fail('IN_PROGRESS');
      const gate=await tx.get(this.db.doc('familyRuntime/config'));if(gate.get('joinReservationEnabled')!==true)fail('FEATURE_DISABLED');
      tx.update(ref,{schemaVersion:2,committedAt:null,sourceFence:null,snapshot:null,cursor:null,deleteConsent:null,leaseId:null,leaseUntil:null,nextAt:this.clock()});
    });
    await new FamilyJoinStore(this.db,this.clock).resume(id);
    return this.state(context,id,inviteId);
  }
  async state(context:AuthContext,id:string,inviteId:string){
    this.local();this.identity(context,id,inviteId);
    return this.db.runTransaction(async tx=>{
      const o=readTransfer((await tx.get(this.db.doc(`familyOperations/${id}`))).data(),id);
      if(o.inviteId!==inviteId)fail('NOT_FOUND');
      const inv=readInvite((await tx.get(this.db.doc(`familyInvites/${inviteId}`))).data());
      return {schemaVersion:1,operationId:id,inviteId,phase:o.phase,status:o.status,mode:o.mode,committedAt:o.committedAt?.toMillis()??null,
        ...(o.snapshot&&o.sourceFence?{sourceHouseholdId:o.sourceHouseholdId,householdId:o.householdId,sourceEpoch:o.sourceFence.epoch,
          sourceItemCount:o.snapshot.count,snapshotHash:o.snapshot.hash,consentVersion:1,confirmationDeadline:inv.expiresAt.toMillis()}: {})};
    },{readOnly:true});
  }
  private async claims(tx:Transaction,id:string,o:TransferOperation){
    const source=await tx.get(this.db.doc(`households/${o.sourceHouseholdId}`));
    const sm=await tx.get(source.ref.collection('members').doc(o.actorUid));
    const user=await tx.get(this.db.doc(`users/${o.actorUid}`));
    const index=await tx.get(this.db.doc(`familyMemberships/${o.actorUid}`));
    const inv=await tx.get(this.db.doc(`familyInvites/${o.inviteId}`));
    const cap=await tx.get(this.db.doc(`familyJoinCapacity/${o.householdId}`)),capacity=readJoinCapacity(cap.data());
    const slots=await tx.get(this.db.doc(`familyInviteSlots/${o.householdId}`)),slotIds=readInviteSlots(slots.data());
    const member=await tx.get(this.db.doc(`households/${o.householdId}/members/${o.actorUid}`));
    if(!source.exists||!(source.get('createdAt') instanceof Timestamp)||source.get('schemaVersion')!==2||source.get('kind')!=='private'||source.get('ownerUid')!==o.actorUid||source.get('state')!=='ACTIVE'||sm.get('role')!=='owner'||
      source.get('operationId')!==(o.sourceFence?id:null)||o.sourceFence&&source.get('shoppingEpoch')!==o.sourceFence.epoch||
      member.exists||index.get('state')!=='RESERVED'||index.get('role')!=='member'||index.get('operationId')!==id||index.get('householdId')!==o.householdId||
      !capacity.operationIds.includes(id)||!slotIds.includes(o.inviteId))throw new Error('joinOwnershipInvariant');
    const invite=readInvite(inv.data());
    if(invite.status!=='RESERVED'||invite.operationId!==id||invite.householdId!==o.householdId||invite.createdByUid!==o.ownerUid)throw new Error('joinInviteInvariant');
    return {source,user,index,inv,invite,cap,capacity,slots,slotIds};
  }
  private async eligible(tx:Transaction,o:TransferOperation,c:Awaited<ReturnType<JoinTransferStore['claims']>>){
    await this.validation.active(tx,o.actorUid);
    if(c.user.get('privateHouseholdId')!==o.sourceHouseholdId||c.user.get('activeHouseholdId')!==o.sourceHouseholdId||c.user.get('familyHouseholdId')!==null||c.user.get('shoppingMigrationVersion')!==1)fail('ACCOUNT_NOT_READY');
    for(const uid of [o.actorUid,o.ownerUid])if((await tx.get(this.db.doc(`accountDeletions/${uid}`))).exists)fail('ACCOUNT_UNAVAILABLE');
    const home=await this.validation.owner(tx,o.ownerUid);
    if(home.householdId!==o.householdId)fail('FAMILY_UNAVAILABLE');
    if(!await hasPro(this.db,tx,o.ownerUid,this.clock()))fail('OWNER_NOT_PRO');
    if((await this.validation.members(tx,home)).length+c.capacity.operationIds.length>8)fail('FAMILY_FULL');
    if(c.invite.expiresAt.toMillis()<=this.clock().toMillis())fail('EXPIRED');
  }
  private abort(tx:Transaction,id:string,o:TransferOperation,c:Awaited<ReturnType<JoinTransferStore['claims']>>,reason:string){
    if(post(o))return 'IN_PROGRESS';
    if(c.capacity.structuralOperationId===id)throw new Error('uncommittedStructuralLock');
    if(o.sourceFence)tx.update(c.source.ref,{operationId:null,...advanceShoppingEpoch(this.clock())});
    tx.delete(c.index.ref);tx.set(c.cap.ref,{...c.capacity,operationIds:c.capacity.operationIds.filter(x=>x!==id)});
    tx.update(c.inv.ref,{status:'REVOKED',operationId:null});
    tx.set(c.slots.ref,{schemaVersion:1,inviteIds:c.slotIds.filter(x=>x!==o.inviteId)});
    tx.update(this.db.doc(`familyOperations/${id}`),{status:'ABORTED',nextAt:null,leaseId:null,leaseUntil:null,lastOutcome:reason,updatedAt:this.clock()});
    return 'ABORTED';
  }
  async cancel(context:AuthContext,id:string,inviteId:string){this.local();this.identity(context,id,inviteId);return this.db.runTransaction(tx=>this.cancelTransaction(tx,id,inviteId,authenticatedUid(context)));}
  async cancelTransaction(tx:Transaction,id:string,inviteId:string,uid:string){
    const base=readJoinOperation((await tx.get(this.db.doc(`familyOperations/${id}`))).data(),id);
    const o:TransferOperation=base.schemaVersion===2?base as TransferOperation:{...base,schemaVersion:2,committedAt:null,sourceFence:null,snapshot:null,cursor:null,deleteConsent:null};
    if(o.inviteId!==inviteId||![o.actorUid,o.ownerUid].includes(uid))fail('NOT_FOUND');
    if(post(o)||o.status==='OPERATOR')return 'IN_PROGRESS';
    if(o.status==='ABORTED')return 'ABORTED';
    const c=await this.claims(tx,id,o);return this.abort(tx,id,o,c,'cancelled');
  }
  private commit(tx:Transaction,id:string,o:TransferOperation,c:Awaited<ReturnType<JoinTransferStore['claims']>>,confirmed:boolean){
    if(!o.snapshot||!o.sourceFence||o.phase!=='SOURCE_FENCED_WAITING_CONFIRMATION')throw new Error('invalidCommitState');
    if(c.capacity.structuralOperationId)return 'IN_PROGRESS';
    if(o.mode==='DELETE'&&!confirmed)return o.phase;
    const now=this.clock();
    tx.set(c.cap.ref,{schemaVersion:2,operationIds:c.capacity.operationIds,structuralOperationId:id});
    tx.update(this.db.doc(`familyOperations/${id}`),{phase:'COMMITTED_TRANSFER',committedAt:now,cursor:null,updatedAt:now,nextAt:Timestamp.fromMillis(now.toMillis()+300000),leaseId:null,leaseUntil:null,
      deleteConsent:o.mode==='DELETE'?{version:1,snapshotHash:o.snapshot.hash,confirmedAt:now}:null,lastOutcome:'awaitingPhase4B1B'});
    return 'COMMITTED_TRANSFER';
  }
  async confirm(context:AuthContext,input:{operationId:string;inviteId:string;sourceEpoch:string;snapshotHash:string;sourceItemCount:number;consentVersion:number}){
    this.local();const {operationId:id,inviteId}=input;this.identity(context,id,inviteId);
    return this.db.runTransaction(async tx=>{
      const o=readTransfer((await tx.get(this.db.doc(`familyOperations/${id}`))).data(),id);
      if(o.inviteId!==inviteId||o.mode!=='DELETE'||input.consentVersion!==1||input.sourceEpoch!==o.sourceFence?.epoch||input.snapshotHash!==o.snapshot?.hash||input.sourceItemCount!==o.snapshot?.count)fail('INVALID_ARGUMENT');
      if(post(o))return o.phase;
      if(o.status!=='READY'||o.phase!=='SOURCE_FENCED_WAITING_CONFIRMATION')fail('IN_PROGRESS');
      const c=await this.claims(tx,id,o);
      try{await this.eligible(tx,o,c);}catch(e){if(e instanceof FamilyInviteError)return this.abort(tx,id,o,c,e.code);throw e;}
      return this.commit(tx,id,o,c,true);
    });
  }
  async stepTransaction(tx:Transaction,id:string,leaseId:string):Promise<string>{
    const ref=this.db.doc(`familyOperations/${id}`),o=readTransfer((await tx.get(ref)).data(),id),now=this.clock();
    if(o.status!=='READY')return o.status;
    if(o.leaseId!==leaseId||!o.leaseUntil||o.leaseUntil.toMillis()<=now.toMillis())return 'BUSY';
    const patch=(v:Record<string,unknown>)=>tx.update(ref,{...v,updatedAt:now});
    // Committed work uses server JOIN authority, never the reserved actor's public
    // shopping authority. CLEAN_SOURCE and later phases remain parked here.
    if(post(o)){
      try{
        const c=await this.claims(tx,id,o);
        if(c.capacity.structuralOperationId!==id||c.user.get('privateHouseholdId')!==o.sourceHouseholdId||c.user.get('shoppingMigrationVersion')!==1||c.user.get('activeHouseholdId')!==o.sourceHouseholdId||c.user.get('familyHouseholdId')!==null)throw new Error('joinOwnershipInvariant');
        await this.validation.active(tx,o.actorUid);
        if((await this.validation.owner(tx,o.ownerUid)).householdId!==o.householdId)throw new Error('joinOwnershipInvariant');
        for(const uid of [o.actorUid,o.ownerUid])if((await tx.get(this.db.doc(`accountDeletions/${uid}`))).exists)throw new Error('joinOwnershipInvariant');
        if(o.phase==='COMMITTED_TRANSFER')return await executeTransfer(this.db,tx,id,o,now,await tx.get(this.db.doc(`households/${o.householdId}`)));
      }catch(e){
        if(transferIntegrityError(e)||e instanceof FamilyInviteError||e instanceof Error&&['joinOwnershipInvariant','joinInviteInvariant','invalidJoinCapacity'].includes(e.message)){
          patch({status:'OPERATOR',nextAt:null,leaseId:null,leaseUntil:null,lastOutcome:'committedInvariantViolation'});return 'OPERATOR';
        }throw e;
      }
      return o.phase;
    }
    let c:Awaited<ReturnType<JoinTransferStore['claims']>>;
    try{c=await this.claims(tx,id,o);}catch(e){
      if(e instanceof Error&&['joinOwnershipInvariant','joinInviteInvariant','invalidJoinCapacity'].includes(e.message)){patch({status:'OPERATOR',nextAt:null,leaseId:null,leaseUntil:null,lastOutcome:'invariantViolation'});return 'OPERATOR';}throw e;
    }
    try{await this.eligible(tx,o,c);}catch(e){if(e instanceof FamilyInviteError)return this.abort(tx,id,o,c,e.code);throw e;}
    if(o.phase==='READY_FOR_TRANSFER'){
      const epoch=advanceShoppingEpoch(now);tx.update(c.source.ref,{operationId:id,...epoch});
      patch({phase:'SNAPSHOT_SOURCE',sourceFence:{epoch:epoch.shoppingEpoch,at:now},cursor:{pageIndex:0,childOffset:0}});return 'SNAPSHOT_SOURCE';
    }
    if(o.phase==='SOURCE_FENCED_WAITING_CONFIRMATION')return this.commit(tx,id,o,c,false);
    if(o.phase!=='SNAPSHOT_SOURCE'||!o.sourceFence||!o.cursor)throw new Error('invalidSnapshotState');
    try {
    const n=o.cursor.pageIndex;
    const previous=n?await tx.get(ref.collection('transferJournal').doc(pageId(o,n-1))):null;
    const prev=previous?.data();
    if(n&&(!prev||Object.keys(prev).sort().join(',')!=='chainHash,entries,fenceEpoch,inviteId,pageIndex,results,version'||prev.version!==1||prev.pageIndex!==n-1||prev.inviteId!==o.inviteId||prev.fenceEpoch!==o.sourceFence.epoch||
      !hashValue(prev.chainHash)||!Array.isArray(prev.results)||prev.results.length!==0||!Array.isArray(prev.entries)||prev.entries.length<1||prev.entries.length>10||
      prev.entries.some((e:any,i:number)=>!e||Object.keys(e).sort().join(',')!=='addPayloadHash,dataHash,sourceId,updateTime'||typeof e.sourceId!=='string'||!e.sourceId||e.sourceId.includes('/')||
        !(e.updateTime instanceof Timestamp)||!hashValue(e.dataHash)||(o.mode==='ADD'?!hashValue(e.addPayloadHash):e.addPayloadHash!==null)||i>0&&Buffer.compare(Buffer.from(prev.entries[i-1].sourceId),Buffer.from(e.sourceId))>=0)))throw new Error('manifestInvariant');
    let q=c.source.ref.collection('shoppingItems').orderBy(FieldPath.documentId()).limit(10);
    if(prev)q=q.startAfter(prev.entries[prev.entries.length-1].sourceId);
    const docs=await tx.get(q);let chain=prev?.chainHash??seed(id,o);
    if(docs.empty){patch({snapshot:{version:1,count:n===0?0:(n-1)*10+prev!.entries.length,hash:chain},phase:'SOURCE_FENCED_WAITING_CONFIRMATION',cursor:null});return 'SOURCE_FENCED_WAITING_CONFIRMATION';}
    const entries=[];
    for(const d of docs.docs){
      let addPayloadHash:string|null=null;
      if(o.mode==='ADD'){
        try{const payload={type:'ADD',name:d.get('name'),quantity:d.get('quantity'),unit:d.get('unit')};
          const mutationId=o.sourceFence.epoch+'_'+ '0'.repeat(64);
          const parsed=parseRequest({schemaVersion:1,mutationId,actorUid:o.actorUid,householdId:o.sourceHouseholdId,epoch:o.sourceFence.epoch,kind:'ADD',payloadJson:JSON.stringify(payload),submittedAt:now},o.actorUid,mutationId);
          addPayloadHash=digest(JSON.stringify(parsed.children[0]));
        }catch{return this.abort(tx,id,o,c,'invalidSourceAdd');}
      }
      const dataHash=sourceFingerprint(d);chain=digest(JSON.stringify([chain,dataHash,addPayloadHash]));
      entries.push({sourceId:d.id,updateTime:d.updateTime,dataHash,addPayloadHash});
    }
    tx.create(ref.collection('transferJournal').doc(pageId(o,n)),{version:1,inviteId:o.inviteId,fenceEpoch:o.sourceFence.epoch,pageIndex:n,entries,chainHash:chain,results:[]});
    patch({cursor:{pageIndex:n+1,childOffset:0}});return 'SNAPSHOT_SOURCE';
    }catch(e){
      if(e instanceof Error&&['manifestInvariant','invalidSnapshotValue','unsupportedSnapshotValue','snapshotUnavailable'].includes(e.message)){
        patch({status:'OPERATOR',nextAt:null,leaseId:null,leaseUntil:null,lastOutcome:'snapshotInvariantViolation'});return 'OPERATOR';
      }throw e;
    }
  }
}
