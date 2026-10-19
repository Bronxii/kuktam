import { Firestore, Timestamp, Transaction, DocumentSnapshot, FieldValue } from 'firebase-admin/firestore';
import { createHash } from 'node:crypto';
import { AuthContext, authenticatedUid } from '../billing/account-binding';
import { readFamilyMembership, validatePrivateRoot } from '../households/household-contract';
import { readAccount } from '../accounts/account-lifecycle';
import { Child, MutationError, Outcome, Request, RETENTION_MS, epochExpiry, newEpoch, parseRequest, requestFields, revision, safeId, mutationPattern } from './mutation-contract';

export const workId=(path:string)=>createHash('sha256').update(path).digest('hex');
const fail=(code:Outcome):never=>{throw new MutationError(code);};
/** All reads precede writes. This same authority guard applies to every child. */
export async function shoppingAuthority(db:Firestore,tx:Transaction,uid:string,hid:string){
  const account=await tx.get(db.doc(`accountLifecycle/${uid}`));
  try{if(!account.exists||readAccount(account.data()).state!=='ACTIVE')fail('REJECTED_UNAUTHORIZED');}catch{fail('REJECTED_UNAUTHORIZED');}
  const user=await tx.get(db.doc(`users/${uid}`)),home=await tx.get(db.doc(`households/${hid}`));
  const member=await tx.get(home.ref.collection('members').doc(uid)),index=await tx.get(db.doc(`familyMemberships/${uid}`));
  if(user.get('activeHouseholdId')!==hid||user.get('shoppingMigrationVersion')!==1)fail('REJECTED_CONTEXT_CHANGED');
  if(!home.exists||!member.exists)fail('REJECTED_UNAUTHORIZED');
  try{
    if(home.get('kind')!=='family'){
      validatePrivateRoot(home.data()!,uid);
      if((user.get('privateHouseholdId')??hid)!==hid||user.get('familyHouseholdId')!=null||member.get('role')!=='owner')fail('REJECTED_UNAUTHORIZED');
      if(index.exists){
        const b=readFamilyMembership(index.data());
        if(b.state!=='RESERVED'||b.role!=='member'||!b.operationId)fail('REJECTED_UNAUTHORIZED');
        const op=await tx.get(db.doc(`familyOperations/${b.operationId}`));
        if(op.get('kind')!=='JOIN'||op.get('status')!=='READY'||op.get('actorUid')!==uid||op.get('sourceHouseholdId')!==hid||op.get('householdId')!==b.householdId||!['RESERVED','READY_FOR_TRANSFER'].includes(op.get('phase')))fail('REJECTED_UNAUTHORIZED');
      }
    }else{
      const b=readFamilyMembership(index.data()),p=user.get('privateHouseholdId');
      if(!safeId(p)||p===hid||user.get('familyHouseholdId')!==hid||b.householdId!==hid||b.state!=='ACTIVE'||b.role!==member.get('role')||home.get('state')!=='ACTIVE'||home.get('operationId')!==null||home.get('schemaVersion')!==2||(b.role==='owner')!==(home.get('ownerUid')===uid))fail('REJECTED_UNAUTHORIZED');
      const fallback=await tx.get(db.doc(`households/${p}`)),fm=await tx.get(db.doc(`households/${p}/members/${uid}`));
      validatePrivateRoot(fallback.data()!,uid);if(fm.get('role')!=='owner')fail('REJECTED_UNAUTHORIZED');
    }
  }catch(e){if(e instanceof MutationError)throw e;fail('REJECTED_CONTEXT_CHANGED');}
  return home;
}

/** Server-only primitive for future structural transactions. Caller must read all
 * transaction dependencies first and apply this patch with its fence/pointers.
 * Never copy an epoch from source to destination or restore an old epoch. */
export function advanceShoppingEpoch(now:Timestamp){const shoppingEpoch=newEpoch(now);return {shoppingEpoch,shoppingEpochExpiresAt:Timestamp.fromMillis(epochExpiry(shoppingEpoch))};}

export class ShoppingMutationStore {
  constructor(private readonly db:Firestore,private readonly clock=Timestamp.now){}
  private ref(uid:string,id:string){authenticatedUid({uid});if(!mutationPattern.test(id))throw new MutationError('INVALID_ARGUMENT');return this.db.doc(`users/${uid}/shoppingMutations/${id}`);}
  async ensureContext(context:AuthContext){
    const uid=authenticatedUid(context);
    return this.db.runTransaction(async tx=>{
      const gate=await tx.get(this.db.doc('shoppingRuntime/config'));if(gate.get('enabled')!==true)throw new MutationError('FEATURE_DISABLED');
      const u=await tx.get(this.db.doc(`users/${uid}`)),hid=u.get('activeHouseholdId');if(!safeId(hid))fail('REJECTED_CONTEXT_CHANGED');
      const home=await shoppingAuthority(this.db,tx,uid,hid),now=this.clock();
      const current=home.get('shoppingEpoch');
      const valid=typeof current==='string'&&epochExpiry(current)>now.toMillis();
      if(valid&&home.get('shoppingEpochExpiresAt')?.toMillis()!==epochExpiry(current))fail('FAILED_TERMINAL');
      if(valid&&home.get('shoppingRevision')!==undefined){revision(home.get('shoppingRevision'));return {householdId:hid,epoch:current as string};}
      const max=await tx.get(home.ref.collection('shoppingItems').orderBy('revision','desc').limit(1));
      const seq=Math.max(revision(home.get('shoppingRevision')),max.empty?0:revision(max.docs[0]!.get('revision')));
      const patch=valid?{shoppingEpoch:current as string,shoppingEpochExpiresAt:Timestamp.fromMillis(epochExpiry(current))}:advanceShoppingEpoch(now);tx.update(home.ref,{...patch,shoppingRevision:seq});
      return {householdId:hid,epoch:patch.shoppingEpoch};
    });
  }
  /** Authenticated transport helper; no actor/household inference from untrusted overrides. */
  async submit(context:AuthContext,raw:unknown){
    const uid=authenticatedUid(context),id=(raw as Request)?.mutationId;
    const parsed=parseRequest(raw,uid,id),ref=this.ref(uid,id);
    await this.db.runTransaction(async tx=>{
      const existing=await tx.get(ref);
      if(existing.exists){
        const hash=existing.get('requestHash')??parseRequest(requestFields(existing.data()!),uid,id).hash;
        if(hash!==parsed.hash)throw new MutationError('ID_CONFLICT');return;
      }
      const gate=await tx.get(this.db.doc('shoppingRuntime/config'));if(gate.get('enabled')!==true)throw new MutationError('FEATURE_DISABLED');
      const home=await shoppingAuthority(this.db,tx,uid,parsed.request.householdId);
      this.epoch(home,parsed.request,this.clock());tx.create(ref,parsed.request);
    });
    return id;
  }
  private epoch(home:DocumentSnapshot,r:Request,now:Timestamp){
    if(home.get('shoppingEpoch')!==r.epoch||epochExpiry(r.epoch)<=now.toMillis()||home.get('shoppingEpochExpiresAt')?.toMillis()!==epochExpiry(r.epoch))fail('REJECTED_CONTEXT_CHANGED');
  }
  async process(uid:string,id:string,maxSteps=10):Promise<string>{
    if(!Number.isSafeInteger(maxSteps)||maxSteps<1||maxSteps>20)throw new MutationError('INVALID_ARGUMENT');
    let status='PENDING';
    try{for(let i=0;i<maxSteps;i++){status=await this.step(uid,id);if(status!=='PROCESSING')break;}return status;}
    catch(e){await this.defer(uid,id);throw e;}
  }
  private async defer(uid:string,id:string){
    const ref=this.ref(uid,id),work=this.db.doc(`shoppingMutationWork/${workId(ref.path)}`);
    await this.db.runTransaction(async tx=>{
      const d=await tx.get(ref);if(!d.exists||d.get('status')&&!['PROCESSING','FAILED_RETRYABLE'].includes(d.get('status')))return;
      let requestHash=d.get('requestHash');
      if(!requestHash){try{requestHash=parseRequest(requestFields(d.data()!),uid,id).hash;}catch{/* Invalid requests are terminalized by the executor. */}}
      const now=this.clock(),failures=(d.get('failures')??0)+1,terminal=failures>=8;
      const next=Timestamp.fromMillis(terminal?Math.max(now.toMillis(),epochExpiry(id.split('_')[0]!))+RETENTION_MS:now.toMillis()+Math.min(3600000,300000*2**(failures-1)));
      tx.update(ref,{status:terminal?'FAILED_TERMINAL':'FAILED_RETRYABLE',failures,retryAt:next,updatedAt:now,
        cursor:d.get('cursor')??0,results:d.get('results')??[],appliedCount:d.get('appliedCount')??0,
        ...(requestHash?{requestHash}:{}),...(terminal?{payloadJson:FieldValue.delete(),purgeAfter:next}:{})});
      tx.set(work,{uid,mutationId:id,nextAt:next});
    });
  }
  private async step(uid:string,id:string):Promise<string>{
    const ref=this.ref(uid,id),work=this.db.doc(`shoppingMutationWork/${workId(ref.path)}`);
    return this.db.runTransaction(async tx=>{
      const doc=await tx.get(ref);if(!doc.exists){tx.delete(work);return 'ABSENT';}
      const d=doc.data()!,now=this.clock();
      if(d.status&&d.status!=='PROCESSING'&&d.status!=='FAILED_RETRYABLE')return d.status;
      if(d.status==='FAILED_RETRYABLE'&&d.retryAt instanceof Timestamp&&d.retryAt.toMillis()>now.toMillis())return d.status;
      let parsed:ReturnType<typeof parseRequest>;
      try{parsed=parseRequest(requestFields(d),uid,id);}catch{
        tx.update(ref,{status:'FAILED_TERMINAL',cursor:0,results:[],appliedCount:0,payloadJson:FieldValue.delete(),updatedAt:now,purgeAfter:Timestamp.fromMillis(Math.max(now.toMillis(),epochExpiry(id.split('_')[0]!))+RETENTION_MS)});
        tx.set(work,{uid,mutationId:id,nextAt:Timestamp.fromMillis(Math.max(now.toMillis(),epochExpiry(id.split('_')[0]!))+RETENTION_MS)});return 'FAILED_TERMINAL';
      }
      const {request:r,children,hash}=parsed,cursor=d.cursor??0,results:{code:Outcome;itemId?:string;revision?:number}[]=d.results??[];
      if(d.requestHash&&d.requestHash!==hash)throw new MutationError('ID_CONFLICT');
      if(!Number.isSafeInteger(cursor)||cursor<0||cursor>=children.length||results.length!==cursor)throw new MutationError('FAILED_TERMINAL');
      let result:{code:Outcome;itemId?:string;revision?:number},stop=false;
      try{
        const home=await shoppingAuthority(this.db,tx,uid,r.householdId);this.epoch(home,r,now);
        result=await this.apply(tx,home,children[cursor]!,now);
      }catch(e){if(!(e instanceof MutationError)||!['REJECTED_STALE','REJECTED_CONTEXT_CHANGED','REJECTED_NOT_FOUND','REJECTED_UNAUTHORIZED','FAILED_TERMINAL'].includes(e.code))throw e;
        result={code:e.code as Outcome};stop=['REJECTED_CONTEXT_CHANGED','REJECTED_UNAUTHORIZED','FAILED_TERMINAL'].includes(e.code);
      }
      results.push(result);
      if(stop)while(results.length<children.length)results.push({code:result.code});
      const complete=results.length===children.length,applied=results.filter(r=>r.code==='APPLIED').length;
      const status=complete?(applied===children.length?'APPLIED':applied>0?'PARTIAL':results.every(r=>r.code===results[0]!.code)?results[0]!.code:'PARTIAL'):'PROCESSING';
      const purgeAfter=Timestamp.fromMillis(epochExpiry(r.epoch)+RETENTION_MS);
      tx.update(ref,{requestHash:hash,status,cursor:results.length,results,appliedCount:applied,updatedAt:now,purgeAfter,...(complete?{payloadJson:FieldValue.delete()}:{} )});
      tx.set(work,{uid,mutationId:id,nextAt:complete?purgeAfter:now});return status;
    });
  }
  private async apply(tx:Transaction,home:DocumentSnapshot,c:Child,now:Timestamp):Promise<{code:Outcome;itemId:string;revision:number;created?:boolean}>{
    const items=home.ref.collection('shoppingItems');
    const source=c.type==='ADD'?null:await tx.get(items.doc(c.itemId));
    if(source&&!source.exists)fail('REJECTED_NOT_FOUND');
    if(source&&revision(source.get('revision'))!==(c as Exclude<Child,{type:'ADD'}>).expectedRevision)fail('REJECTED_STALE');
    const matches=c.type==='ADD'||c.type==='EDIT'?await tx.get(items.where('name','==',c.name).where('unit','==',c.unit).limit(3)):null;
    const targets=matches?.docs.filter(d=>d.id!==source?.id)??[];
    if(targets.length>1)fail('FAILED_TERMINAL');
    const target=targets[0];
    const seq=Math.max(revision(home.get('shoppingRevision')),source?revision(source.get('revision')):0,target?revision(target.get('revision')):0)+1;
    if(!Number.isSafeInteger(seq))fail('FAILED_TERMINAL');
    // Validate EVERYTHING before scheduling any transaction write.
    let quantity:number|undefined;
    if(c.type==='ADD'||c.type==='EDIT'){
      quantity=c.quantity;
      if(target){const old=target.get('quantity');if(typeof old!=='number'||!Number.isFinite(old)||old<=0)fail('FAILED_TERMINAL');quantity+=old;}
      if(!Number.isFinite(quantity)||quantity>Number.MAX_SAFE_INTEGER)fail('FAILED_TERMINAL');
    }
    const destination=target?.ref??source?.ref??items.doc();
    tx.update(home.ref,{shoppingRevision:seq});
    if(c.type==='DELETE')tx.delete(source!.ref);
    else if(c.type==='SET_CHECKED')tx.update(source!.ref,{isChecked:c.isChecked,revision:seq});
    else if(target){tx.update(target.ref,{quantity,revision:seq});if(source)tx.delete(source.ref);}
    else if(source)tx.update(source.ref,{name:c.name,quantity,unit:c.unit,revision:seq});
    else tx.create(destination,{name:c.name,quantity,unit:c.unit,isChecked:false,createdAt:now,revision:seq});
    return {code:'APPLIED',itemId:destination.id,revision:seq,...(c.type==='ADD'?{created:!target}:{})};
  }
  /** Terminal work stays indexed until expiry; no unbounded collection-group scan. */
  async continueWork(uid:string,id:string){
    const ref=this.ref(uid,id),work=this.db.doc(`shoppingMutationWork/${workId(ref.path)}`);
    const removed=await this.db.runTransaction(async tx=>{
      const d=await tx.get(ref);if(!d.exists){tx.delete(work);return true;}
      if(d.get('status')&&d.get('status')!=='PROCESSING'&&d.get('purgeAfter') instanceof Timestamp&&d.get('purgeAfter').toMillis()<=this.clock().toMillis()&&epochExpiry(id.split('_')[0]!)<=this.clock().toMillis()){
        tx.delete(ref);tx.delete(work);return true;
      }return false;
    });
    return removed?'CLEANED':this.process(uid,id);
  }
}
