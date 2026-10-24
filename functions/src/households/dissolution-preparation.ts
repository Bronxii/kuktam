import { createHash } from 'node:crypto';
import { Firestore, Timestamp } from 'firebase-admin/firestore';
import { authenticatedUid, AuthContext } from '../billing/account-binding';
import { FamilyInviteStore } from './family-invites';
import { FamilyInviteError, readInvite, readInviteSlots } from './invite-contract';
import { readFamilyMembership } from './household-contract';
import { privateHouseholdId } from './household-store';
import { readJoinCapacity } from './join-capacity';
import { readJoinOperation } from './family-join';

export type PreparationCode='INVALID_ARGUMENT'|'FEATURE_DISABLED'|'NOT_OWNER'|'WRONG_FAMILY'|'ACCOUNT_UNAVAILABLE'|'IN_PROGRESS'|'INTEGRITY_REQUIRES_OPERATOR';
export class DissolutionPreparationError extends Error {constructor(readonly code:PreparationCode){super(code);}}
const fail=(code:PreparationCode):never=>{throw new DissolutionPreparationError(code);};
const proof=<T>(fn:()=>T):T=>{try{return fn();}catch{return fail('INTEGRITY_REQUIRES_OPERATOR');}};
const hash=(v:unknown)=>createHash('sha256').update(JSON.stringify(v)).digest('hex');
export const dissolutionId=(uid:string,householdId:string)=>'dissolve_'+hash([uid,householdId]);
const uid=(x:unknown):x is string=>typeof x==='string'&&x.length>0&&x.length<=128&&!x.includes('/')&&x.trim()===x;
const hid=(x:unknown):x is string=>typeof x==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(x);
const ordered=(a:string[])=>a.every((v,i)=>i===0||Buffer.compare(Buffer.from(a[i-1]!),Buffer.from(v))<0);
const sort=(a:string[])=>a.sort((a,b)=>Buffer.compare(Buffer.from(a),Buffer.from(b)));
const time=(t:Timestamp)=>[t.seconds,t.nanoseconds];
export interface Participant {
  uid:string;role:'owner'|'member';privateHouseholdId:string;activeHouseholdId:string;
  memberUpdateTime:Timestamp;reverseUpdateTime:Timestamp;privateCreatedAt:Timestamp;
}
export interface DissolutionPreparation {
  schemaVersion:1;kind:'FAMILY_DISSOLUTION';actorUid:string;ownerUid:string;householdId:string;
  householdCreatedAt:Timestamp;structuralOperationId:string;phase:'PREPARED';status:'READY';
  createdAt:Timestamp;updatedAt:Timestamp;nextAt:null;leaseId:null;leaseUntil:null;cursor:null;
  participantCount:number;participants:Participant[];snapshotHash:string;
  reservedJoinOperationIds:string[];inviteIds:string[];
}
export const participantHash=(p:Participant[])=>hash(p.map(v=>[v.uid,v.role,v.privateHouseholdId,v.activeHouseholdId,time(v.memberUpdateTime),time(v.reverseUpdateTime),time(v.privateCreatedAt)]));
/** Bounded immutable participant evidence. Shopping metadata is intentionally not a fence. */
export function readDissolutionPreparation(raw:unknown,id:string):DissolutionPreparation {
  const v=raw as DissolutionPreparation;
  if(!v||Object.keys(v).sort().join(',')!=='actorUid,createdAt,cursor,householdCreatedAt,householdId,inviteIds,kind,leaseId,leaseUntil,nextAt,ownerUid,participantCount,participants,phase,reservedJoinOperationIds,schemaVersion,snapshotHash,status,structuralOperationId,updatedAt'||
    v.schemaVersion!==1||v.kind!=='FAMILY_DISSOLUTION'||!uid(v.actorUid)||v.actorUid!==v.ownerUid||!hid(v.householdId)||id!==dissolutionId(v.ownerUid,v.householdId)||v.structuralOperationId!==id||
    v.phase!=='PREPARED'||v.status!=='READY'||v.nextAt!==null||v.leaseId!==null||v.leaseUntil!==null||v.cursor!==null||
    !(v.createdAt instanceof Timestamp)||!(v.updatedAt instanceof Timestamp)||!v.createdAt.isEqual(v.updatedAt)||!(v.householdCreatedAt instanceof Timestamp)||
    !Array.isArray(v.participants)||v.participants.length<1||v.participants.length>8||v.participantCount!==v.participants.length||
    v.participants.some(p=>!p||Object.keys(p).sort().join(',')!=='activeHouseholdId,memberUpdateTime,privateCreatedAt,privateHouseholdId,reverseUpdateTime,role,uid'||!uid(p.uid)||
      !['owner','member'].includes(p.role)||(p.role==='owner')!==(p.uid===v.ownerUid)||p.privateHouseholdId!==privateHouseholdId(p.uid)||p.activeHouseholdId!==v.householdId||p.privateHouseholdId===v.householdId||
      !(p.memberUpdateTime instanceof Timestamp)||!(p.reverseUpdateTime instanceof Timestamp)||!(p.privateCreatedAt instanceof Timestamp))||
    !ordered(v.participants.map(p=>p.uid))||v.participants.filter(p=>p.role==='owner').length!==1||new Set(v.participants.map(p=>p.privateHouseholdId)).size!==v.participantCount||
    !Array.isArray(v.reservedJoinOperationIds)||v.reservedJoinOperationIds.length+v.participantCount>8||!ordered(v.reservedJoinOperationIds)||v.reservedJoinOperationIds.some(id=>!/^join_[a-f0-9]{64}$/.test(id))||
    !Array.isArray(v.inviteIds)||v.inviteIds.length>8||!ordered(v.inviteIds)||v.inviteIds.some(id=>!/^[a-f0-9]{64}$/.test(id))||v.snapshotHash!==participantHash(v.participants))throw new Error('invalidDissolutionPreparation');
  return v;
}
export class DissolutionPreparationStore {
  private readonly validation:FamilyInviteStore;
  constructor(private readonly db:Firestore,private readonly clock=Timestamp.now){this.validation=new FamilyInviteStore(db,{resolve:async()=>{throw new Error('notRequired');}},clock);}
  async prepare(context:AuthContext,householdId:string){
    const ownerUid=authenticatedUid(context);
    if(!hid(householdId))fail('INVALID_ARGUMENT');
    if(process.env.K_SERVICE||process.env.FUNCTION_NAME||process.env.GCLOUD_PROJECT!=='demo-kuktam-local'||!/^(127\.0\.0\.1|localhost):[0-9]{1,5}$/.test(process.env.FIRESTORE_EMULATOR_HOST??''))fail('FEATURE_DISABLED');
    const id=dissolutionId(ownerUid,householdId);
    try{return await this.db.runTransaction(async tx=>{
      const family=await this.validation.owner(tx,ownerUid);if(family.householdId!==householdId)fail('WRONG_FAMILY');
      if((await tx.get(this.db.doc(`accountDeletions/${ownerUid}`))).exists)fail('ACCOUNT_UNAVAILABLE');
      const ref=this.db.doc(`familyOperations/${id}`),existing=await tx.get(ref),home=await tx.get(this.db.doc(`households/${householdId}`));
      const capRef=this.db.doc(`familyJoinCapacity/${householdId}`),capDoc=await tx.get(capRef),cap=proof(()=>readJoinCapacity(capDoc.data()));
      if(existing.exists){
        const o=proof(()=>readDissolutionPreparation(existing.data(),id));
        if(cap.schemaVersion!==3||cap.structuralOperationId!==id||!o.householdCreatedAt.isEqual(home.get('createdAt')))fail('INTEGRITY_REQUIRES_OPERATOR');
        return {schemaVersion:1,operationId:id,phase:o.phase,status:o.status,participantCount:o.participantCount,snapshotHash:o.snapshotHash};
      }
      if(cap.structuralOperationId)fail('IN_PROGRESS');
      const members=await this.validation.members(tx,family);
      const reverses=await tx.get(this.db.collection('familyMemberships').where('householdId','==',householdId).limit(9));
      if(reverses.size>8||members.length+cap.operationIds.length>8)fail('INTEGRITY_REQUIRES_OPERATOR');
      const indexes=new Map(reverses.docs.map(d=>[d.id,{doc:d,value:proof(()=>readFamilyMembership(d.data()))}]));
      if([...indexes.values()].filter(v=>v.value.state==='ACTIVE').length!==members.length||[...indexes.values()].filter(v=>v.value.state==='RESERVED').length!==cap.operationIds.length)fail('INTEGRITY_REQUIRES_OPERATOR');
      const participants:Participant[]=[];
      for(const m of [...members].sort((a,b)=>Buffer.compare(Buffer.from(a.memberId),Buffer.from(b.memberId)))){
        const u=m.memberId,p=privateHouseholdId(u),r=indexes.get(u);
        if(!r||r.value.state!=='ACTIVE'||r.value.role!==m.role)fail('INTEGRITY_REQUIRES_OPERATOR');
        await this.validation.active(tx,u);
        if((await tx.get(this.db.doc(`accountDeletions/${u}`))).exists)fail('ACCOUNT_UNAVAILABLE');
        const user=await tx.get(this.db.doc(`users/${u}`));
        if(user.get('activeHouseholdId')!==householdId||user.get('familyHouseholdId')!==householdId||user.get('privateHouseholdId')!==p||user.get('shoppingMigrationVersion')!==1)fail('INTEGRITY_REQUIRES_OPERATOR');
        await this.validation.privateHome(tx,u,p);
        const fallback=await tx.get(this.db.doc(`households/${p}`)),member=await tx.get(home.ref.collection('members').doc(u));
        participants.push({uid:u,role:m.role,privateHouseholdId:p,activeHouseholdId:householdId,memberUpdateTime:member.updateTime!,reverseUpdateTime:r!.doc.updateTime!,privateCreatedAt:fallback.get('createdAt')});
      }
      const slots=await tx.get(this.db.doc(`familyInviteSlots/${householdId}`)),inviteIds=slots.exists?proof(()=>readInviteSlots(slots.data())):[];
      const invites=new Map<string,ReturnType<typeof readInvite>>();
      for(const inviteId of inviteIds){const d=await tx.get(this.db.doc(`familyInvites/${inviteId}`)),v=proof(()=>readInvite(d.data()));
        if(v.householdId!==householdId||v.createdByUid!==ownerUid)fail('INTEGRITY_REQUIRES_OPERATOR');invites.set(inviteId,v);}
      for(const opId of cap.operationIds){
        const d=await tx.get(this.db.doc(`familyOperations/${opId}`)),o=proof(()=>readJoinOperation(d.data(),opId));
        const r=indexes.get(o.actorUid),inv=invites.get(o.inviteId);
        if(o.status!=='READY'||o.householdId!==householdId||o.ownerUid!==ownerUid||d.get('committedAt')!=null||
          !r||r.value.state!=='RESERVED'||r.value.role!=='member'||r.value.operationId!==opId||
          !inv||inv.status!=='RESERVED'||inv.operationId!==opId)fail('INTEGRITY_REQUIRES_OPERATOR');
      }
      if([...invites.values()].some(v=>v.status==='RESERVED'&&!cap.operationIds.includes(v.operationId!)))fail('INTEGRITY_REQUIRES_OPERATOR');
      const now=this.clock();
      const operation:DissolutionPreparation={schemaVersion:1,kind:'FAMILY_DISSOLUTION',actorUid:ownerUid,ownerUid,householdId,householdCreatedAt:home.get('createdAt'),structuralOperationId:id,
        phase:'PREPARED',status:'READY',createdAt:now,updatedAt:now,nextAt:null,leaseId:null,leaseUntil:null,cursor:null,participantCount:participants.length,participants,snapshotHash:participantHash(participants),reservedJoinOperationIds:sort([...cap.operationIds]),inviteIds:sort([...inviteIds])};
      proof(()=>readDissolutionPreparation(operation,id));
      tx.create(ref,operation);tx.set(capRef,{schemaVersion:3,operationIds:cap.operationIds,structuralOperationId:id});
      return {schemaVersion:1,operationId:id,phase:operation.phase,status:operation.status,participantCount:operation.participantCount,snapshotHash:operation.snapshotHash};
    });}catch(e){if(e instanceof FamilyInviteError)fail(e.code==='NOT_OWNER'?'NOT_OWNER':e.code==='ACCOUNT_UNAVAILABLE'?'ACCOUNT_UNAVAILABLE':'INTEGRITY_REQUIRES_OPERATOR');throw e;}
  }
}
