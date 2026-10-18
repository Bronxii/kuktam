import { Firestore, Timestamp, Transaction } from 'firebase-admin/firestore';
import { AuthContext, authenticatedUid } from '../billing/account-binding';
import { readAccount } from '../accounts/account-lifecycle';
import { compareTime } from '../models';
import { readFamilyMembership, validatePrivateRoot } from './household-contract';
import { privateHouseholdId } from './household-store';
import { hasPro } from './family-create';
import { MemberEmailResolver, emailIdentity } from './member-email';
import { FamilyInvite, FamilyInviteError, InviteCode, INVITE_SECONDS, MAX_FAMILY_MEMBERS, MAX_PENDING_INVITES,
  hashInviteToken, inviteIdPattern, newInviteToken, readInvite, readInviteSlots } from './invite-contract';

interface FamilyContext { householdId:string; ownerUid:string; role:'owner'|'member' }
const fail=(code:InviteCode):never=>{throw new FamilyInviteError(code);};
export class FamilyInviteStore {
  constructor(private readonly db:Firestore,private readonly emails:MemberEmailResolver,
    private readonly clock=Timestamp.now,private readonly tokenFactory=newInviteToken) {}

  private async active(tx:Transaction,uid:string):Promise<void> {
    const doc=await tx.get(this.db.doc(`accountLifecycle/${uid}`));
    if(!doc.exists)fail('ACCOUNT_UNAVAILABLE');
    try {if(readAccount(doc.data()).state!=='ACTIVE')fail('ACCOUNT_UNAVAILABLE');}
    catch {fail('ACCOUNT_UNAVAILABLE');}
  }
  private async context(tx:Transaction,uid:string):Promise<FamilyContext|null> {
    await this.active(tx,uid);
    const user=await tx.get(this.db.doc(`users/${uid}`)), reverse=await tx.get(this.db.doc(`familyMemberships/${uid}`));
    if(!reverse.exists) {
      if(user.get('familyHouseholdId')!=null)fail('FAMILY_UNAVAILABLE');
      return null;
    }
    let binding;
    try{binding=readFamilyMembership(reverse.data());}catch{return fail('FAMILY_UNAVAILABLE');}
    if(binding.state!=='ACTIVE')fail('IN_PROGRESS');
    const hid=binding.householdId,p=privateHouseholdId(uid);
    if(user.get('activeHouseholdId')!==hid || user.get('familyHouseholdId')!==hid || user.get('privateHouseholdId')!==p ||
        user.get('shoppingMigrationVersion')!==1 || hid===p)fail('FAMILY_UNAVAILABLE');
    const home=await tx.get(this.db.doc(`households/${hid}`)), member=await tx.get(home.ref.collection('members').doc(uid));
    if(home.get('state')==='PREPARING')fail('FAMILY_PREPARING');
    if(home.get('state')==='DISSOLVING')fail('FAMILY_DISSOLVING');
    if(!home.exists || home.get('schemaVersion')!==2 || home.get('kind')!=='family' || home.get('state')!=='ACTIVE' ||
        home.get('operationId')!==null || !(home.get('createdAt') instanceof Timestamp) ||
        typeof home.get('ownerUid')!=='string' || !member.exists || member.get('role')!==binding.role ||
        (binding.role==='owner')!==(home.get('ownerUid')===uid))fail('FAMILY_UNAVAILABLE');
    await this.privateHome(tx,uid,p);
    return {householdId:hid,ownerUid:home.get('ownerUid') as string,role:binding.role};
  }
  private async privateHome(tx:Transaction,uid:string,p:string):Promise<void> {
    const home=await tx.get(this.db.doc(`households/${p}`)), member=await tx.get(home.ref.collection('members').doc(uid));
    try{if(!home.exists)fail('ACCOUNT_NOT_READY');validatePrivateRoot(home.data()!,uid);}
    catch{fail('ACCOUNT_NOT_READY');}
    if(home.get('schemaVersion')!==2 || !member.exists || member.get('role')!=='owner')fail('ACCOUNT_NOT_READY');
  }
  private async owner(tx:Transaction,uid:string):Promise<FamilyContext> {
    const context=await this.context(tx,uid);
    if(!context || context.role!=='owner')return fail('NOT_OWNER');
    return context;
  }
  private async members(tx:Transaction,family:FamilyContext) {
    const docs=await tx.get(this.db.collection(`households/${family.householdId}/members`).limit(MAX_FAMILY_MEMBERS+1));
    if(docs.size>MAX_FAMILY_MEMBERS)fail('FAMILY_UNAVAILABLE');
    if(!docs.docs.some(d=>d.id===family.ownerUid && d.get('role')==='owner') ||
        docs.docs.some(d=>!['owner','member'].includes(d.get('role')) || (d.get('role')==='owner')!==(d.id===family.ownerUid)))fail('FAMILY_UNAVAILABLE');
    return docs.docs.map(d=>({memberId:d.id,role:d.get('role') as 'owner'|'member'}));
  }
  private async slots(tx:Transaction,hid:string) {
    const ref=this.db.doc(`familyInviteSlots/${hid}`), slot=await tx.get(ref);
    const ids=slot.exists?readInviteSlots(slot.data()):[];
    const docs=ids.length?await tx.getAll(...ids.map(id=>this.db.doc(`familyInvites/${id}`))):[];
    const entries=docs.map(d=>{
      if(!d.exists)fail('INVITE_STATE_UNAVAILABLE');
      const invite=readInvite(d.data());if(invite.householdId!==hid)fail('INVITE_STATE_UNAVAILABLE');
      return {id:d.id,invite};
    });
    return {ref,entries};
  }
  private live(invite:FamilyInvite,now:Timestamp) {
    // A future JOIN must explicitly release RESERVED slots, even after expiry.
    return invite.status==='RESERVED' || invite.status==='PENDING' && compareTime(invite.expiresAt,now)>0;
  }
  async create(context:AuthContext) {
    const uid=authenticatedUid(context),token=this.tokenFactory(),id=hashInviteToken(token);
    return this.db.runTransaction(async tx=>{
      const now=this.clock(),gate=await tx.get(this.db.doc('familyRuntime/config'));
      if(gate.get('inviteCreationEnabled')!==true)fail('FEATURE_DISABLED');
      const family=await this.owner(tx,uid);
      if(!await hasPro(this.db,tx,uid,now))fail('OWNER_NOT_PRO');
      if((await this.members(tx,family)).length>=MAX_FAMILY_MEMBERS)fail('FAMILY_FULL');
      const slots=await this.slots(tx,family.householdId),live=slots.entries.filter(e=>this.live(e.invite,now));
      if(live.length>=MAX_PENDING_INVITES)fail('PENDING_LIMIT');
      const ref=this.db.doc(`familyInvites/${id}`),existing=await tx.get(ref);
      if(existing.exists)fail('RETRYABLE_UNAVAILABLE'); // Cryptographic collision: never overwrite.
      const expiresAt=new Timestamp(now.seconds+INVITE_SECONDS,now.nanoseconds);
      const invite:FamilyInvite={schemaVersion:1,householdId:family.householdId,createdByUid:uid,createdAt:now,expiresAt,
        status:'PENDING',operationId:null,usedAt:null,usedByUid:null};
      tx.create(ref,invite);
      // Every create/revoke (and future JOIN) uses this bounded common guard.
      tx.set(slots.ref,{schemaVersion:1,inviteIds:[...live.map(e=>e.id),id]});
      return {schemaVersion:1,inviteId:id,token,expiresAt:expiresAt.toMillis()};
    });
  }
  async revoke(context:AuthContext,inviteId:string) {
    const uid=authenticatedUid(context);if(!inviteIdPattern.test(inviteId))fail('INVALID_ARGUMENT');
    return this.db.runTransaction(async tx=>{
      const family=await this.owner(tx,uid),ref=this.db.doc(`familyInvites/${inviteId}`),doc=await tx.get(ref);
      if(!doc.exists)fail('NOT_FOUND');
      const invite=readInvite(doc.data());
      if(invite.householdId!==family.householdId || invite.createdByUid!==uid)fail('NOT_FOUND');
      if(invite.status!=='PENDING')return {schemaVersion:1,code:invite.status==='RESERVED'?'IN_PROGRESS':invite.status};
      // Expired PENDING may still be revoked; this never extends its validity.
      const slots=await this.slots(tx,family.householdId);
      tx.update(ref,{status:'REVOKED'});
      tx.set(slots.ref,{schemaVersion:1,inviteIds:slots.entries.filter(e=>e.id!==inviteId).map(e=>e.id)});
      return {schemaVersion:1,code:'REVOKED'};
    });
  }
  async preview(context:AuthContext,token:string) {
    const uid=authenticatedUid(context),id=hashInviteToken(token);
    try {
      const result=await this.db.runTransaction(async tx=>{
        await this.active(tx,uid);
        const now=this.clock(),doc=await tx.get(this.db.doc(`familyInvites/${id}`));
        if(!doc.exists)return fail('NOT_FOUND');
        const invite=readInvite(doc.data());
        if(compareTime(invite.expiresAt,now)<=0)fail('EXPIRED');
        if(invite.status!=='PENDING')fail(invite.status==='RESERVED'?'IN_PROGRESS':invite.status);
        let family:FamilyContext;
        try{family=await this.owner(tx,invite.createdByUid);}catch(e){
          if(e instanceof FamilyInviteError){
            if(e.code==='ACCOUNT_UNAVAILABLE')fail('OWNER_UNAVAILABLE');
            if(e.code==='NOT_OWNER'||e.code==='ACCOUNT_NOT_READY')fail('FAMILY_UNAVAILABLE');
          }
          throw e;
        }
        if(family.householdId!==invite.householdId)fail('FAMILY_UNAVAILABLE');
        if(!await hasPro(this.db,tx,invite.createdByUid,now))fail('OWNER_NOT_PRO');
        if(uid===invite.createdByUid)fail('SELF_INVITE');
        const reverse=await tx.get(this.db.doc(`familyMemberships/${uid}`)),user=await tx.get(this.db.doc(`users/${uid}`));
        if(reverse.exists){
          let binding;try{binding=readFamilyMembership(reverse.data());}catch{return fail('ACCOUNT_UNAVAILABLE');}
          if(binding.state==='RESERVED')fail('IN_PROGRESS');
          fail(binding.householdId===family.householdId?'ALREADY_MEMBER':'ALREADY_IN_FAMILY');
        }
        if((await this.members(tx,family)).length>=MAX_FAMILY_MEMBERS)fail('FAMILY_FULL');
        const p=privateHouseholdId(uid);
        if(user.get('privateHouseholdId')!==p || user.get('activeHouseholdId')!==p || user.get('familyHouseholdId')!==null ||
            user.get('shoppingMigrationVersion')!==1)fail('ACCOUNT_NOT_READY');
        await this.privateHome(tx,uid,p);
        const count=await tx.get(this.db.collection(`households/${p}/shoppingItems`).count());
        return {ownerUid:invite.createdByUid,expiresAt:invite.expiresAt.toMillis(),privateShoppingItemCount:count.data().count};
      },{readOnly:true});
      const identity=(await this.emails.resolve([result.ownerUid])).get(result.ownerUid);
      if(!identity?.exists)fail('OWNER_UNAVAILABLE');
      return {schemaVersion:1,code:'VALID',eligible:true,inviteState:'PENDING',expiresAt:result.expiresAt,
        privateShoppingItemCount:result.privateShoppingItemCount,owner:emailIdentity(identity)};
    }catch(error){if(error instanceof FamilyInviteError)return {schemaVersion:1,code:error.code,eligible:false};throw error;}
  }
  async state(context:AuthContext) {
    const uid=authenticatedUid(context);
    const result=await this.db.runTransaction(async tx=>{
      const family=await this.context(tx,uid);if(!family)return null;
      const members=await this.members(tx,family);
      let invites:{inviteId:string;createdAt:number;expiresAt:number;status:string}[]|undefined;
      if(family.role==='owner'){
        const now=this.clock(),slots=await this.slots(tx,family.householdId);
        invites=slots.entries.filter(e=>this.live(e.invite,now)).map(e=>({inviteId:e.id,createdAt:e.invite.createdAt.toMillis(),expiresAt:e.invite.expiresAt.toMillis(),status:e.invite.status}));
      }
      return {family,members,invites};
    },{readOnly:true});
    if(!result)return {schemaVersion:1 as const,familyActive:false as const};
    const identities=await this.emails.resolve(result.members.map(m=>m.memberId));
    return {schemaVersion:1 as const,familyActive:true as const,role:result.family.role,
      members:result.members.map(m=>({...m,...emailIdentity(identities.get(m.memberId))})),
      ...(result.invites===undefined?{}:{invites:result.invites})};
  }
}
