import { claimFamilyLease } from './operation-lease';
import { advanceShoppingEpoch } from '../shopping/mutation-store';
import { createHash, randomUUID } from 'node:crypto';
import { isDeepStrictEqual } from 'node:util';
import { FieldPath, Firestore, Timestamp, Transaction } from 'firebase-admin/firestore';
import { aggregateGrants } from '../aggregate';
import { parseGrant } from '../models';
import { readAccount } from '../accounts/account-lifecycle';
import { AuthContext, authenticatedUid } from '../billing/account-binding';
import { privateHouseholdId } from './household-store';
import { readFamilyMembership, validatePrivateRoot } from './household-contract';

export type CreatePhase = 'COPY' | 'VERIFY' | 'ACTIVATE' | 'CLEAN_SOURCE' | 'FINALIZE' | 'ABORT';
export interface CreateOperation {
  schemaVersion: 1; kind: 'CREATE'; actorUid: string;
  sourceHouseholdId: string; householdId: string;
  phase: CreatePhase; status: 'READY' | 'DONE' | 'ABORTED' | 'OPERATOR';
  cursor: string | null; createdAt: Timestamp; updatedAt: Timestamp;
  leaseId: string | null; leaseUntil: Timestamp | null;
  nextAt: Timestamp | null; lastOutcome: string | null;
}
export const createOperationId = (uid: string) => 'create_' + createHash('sha256').update(authenticatedUid({uid})).digest('hex');
const idPattern = /^[a-zA-Z0-9_-]{1,128}$/;
export function readCreateOperation(raw: unknown): CreateOperation {
  const v = raw as CreateOperation;
  if (!v || Object.keys(v).sort().join(',') !== 'actorUid,createdAt,cursor,householdId,kind,lastOutcome,leaseId,leaseUntil,nextAt,phase,schemaVersion,sourceHouseholdId,status,updatedAt' ||
      v.schemaVersion !== 1 || v.kind !== 'CREATE' || typeof v.actorUid !== 'string' || !v.actorUid || v.actorUid.includes('/') ||
      typeof v.householdId !== 'string' || !idPattern.test(v.householdId) ||
      v.sourceHouseholdId !== privateHouseholdId(v.actorUid) || v.householdId === v.sourceHouseholdId ||
      !['COPY','VERIFY','ACTIVATE','CLEAN_SOURCE','FINALIZE','ABORT'].includes(v.phase) ||
      !['READY','DONE','ABORTED','OPERATOR'].includes(v.status) ||
      !(v.createdAt instanceof Timestamp) || !(v.updatedAt instanceof Timestamp) ||
      !(v.cursor === null || typeof v.cursor === 'string' && v.cursor.length > 0 && !v.cursor.includes('/')) ||
      !(v.leaseId === null && v.leaseUntil === null || typeof v.leaseId === 'string' && v.leaseUntil instanceof Timestamp) ||
      !(v.status === 'READY' ? v.nextAt instanceof Timestamp : v.nextAt === null) ||
      !(v.lastOutcome === null || typeof v.lastOutcome === 'string')) throw new Error('invalidCreateOperation');
  return v;
}

/** No Play calls, effective-document writes or grant writes. Use the existing
 * complete trusted grant aggregation, including expiry and multiple sources. */
export async function hasPro(db: Firestore, tx: Transaction, uid: string, now: Timestamp): Promise<boolean> {
  const grants = await tx.get(db.collection(`users/${uid}/entitlementGrants`).limit(501));
  if (grants.size > 500) throw new Error('grantLimit');
  return aggregateGrants(grants.docs.map(d => parseGrant(d.data())), now, 1).active;
}

export class FamilyCreateStore {
  constructor(private readonly db: Firestore, private readonly clock = Timestamp.now,
    readonly pageSize = 25, readonly leaseMs = 120000) {
    if (!Number.isInteger(pageSize) || pageSize < 1 || pageSize > 50 || !Number.isSafeInteger(leaseMs) || leaseMs < 1000) throw new Error('invalidCreatePolicy');
  }
  /** One deterministic per-UID operation slot is the idempotency key. A new
   * destination is allocated only when no live operation/family exists. */
  async reserve(context: AuthContext): Promise<string> {
    const uid = authenticatedUid(context), operationId = createOperationId(uid), hid = 'family_' + randomUUID();
    const ref = this.db.doc(`familyOperations/${operationId}`), p = privateHouseholdId(uid);
    return this.db.runTransaction(async tx => {
      const now = this.clock();
      const opDoc = await tx.get(ref), indexRef = this.db.doc(`familyMemberships/${uid}`), index = await tx.get(indexRef);
      if (opDoc.exists) {
        const old = readCreateOperation(opDoc.data());
        if (old.actorUid !== uid) throw new Error('createConflict');
        if (old.status !== 'ABORTED') return operationId;
      }
      if (index.exists) { readFamilyMembership(index.data()); throw new Error('alreadyFamily'); }
      if((await tx.get(this.db.doc(`familyMemberDeletions/${uid}`))).exists)throw new Error('accountUnavailable');
      const gate = await tx.get(this.db.doc('familyRuntime/config'));
      if (gate.get('creationEnabled') !== true) throw new Error('featureDisabled');
      const marker = await tx.get(this.db.doc(`accountLifecycle/${uid}`));
      if (!marker.exists || readAccount(marker.data()).state !== 'ACTIVE') throw new Error('accountUnavailable');
      if (!await hasPro(this.db, tx, uid, now)) throw new Error('proRequired');
      const userRef = this.db.doc(`users/${uid}`), user = await tx.get(userRef);
      const sourceRef = this.db.doc(`households/${p}`), source = await tx.get(sourceRef);
      const member = await tx.get(sourceRef.collection('members').doc(uid));
      if (!user.exists || user.get('privateHouseholdId') !== p || user.get('activeHouseholdId') !== p ||
          user.get('familyHouseholdId') !== null || user.get('shoppingMigrationVersion') !== 1 ||
          !source.exists || !member.exists || member.get('role') !== 'owner') throw new Error('invalidPrivateState');
      validatePrivateRoot(source.data()!, uid);
      if (source.get('schemaVersion') !== 2) throw new Error('initializationRequired');
      const destinationRef = this.db.doc(`households/${hid}`), destination = await tx.get(destinationRef);
      const orphanItems=await tx.get(destinationRef.collection('shoppingItems').limit(1));
      if (destination.exists || !orphanItems.empty) throw new Error('destinationCollision');
      const operation: CreateOperation = {schemaVersion:1,kind:'CREATE',actorUid:uid,sourceHouseholdId:p,householdId:hid,
        phase:'COPY',status:'READY',cursor:null,createdAt:now,updatedAt:now,leaseId:null,leaseUntil:null,nextAt:now,lastOutcome:null};
      tx.set(ref, operation);
      tx.create(destinationRef,{schemaVersion:2,kind:'family',ownerUid:uid,createdAt:now,state:'PREPARING',operationId});
      tx.create(indexRef,{householdId:hid,role:'owner',state:'RESERVED',operationId});
      tx.update(sourceRef,{operationId,...advanceShoppingEpoch(now)});
      return operationId;
    });
  }
  async claim(operationId: string): Promise<string | null> {
    return claimFamilyLease(this.db,operationId,raw=>{
      const op=readCreateOperation(raw);
      if(operationId!==createOperationId(op.actorUid))throw new Error('operationIdentityMismatch');
      return op;
    },this.clock,this.leaseMs);
  }

  /** Every page and its cursor commit together under the persisted lease. The
   * source stays frozen/intact until activation, so no payload journal is needed. */
  async step(operationId: string, leaseId: string): Promise<string> {
    return this.db.runTransaction(async tx => {
      const ref=this.db.doc(`familyOperations/${operationId}`), doc=await tx.get(ref);
      if (!doc.exists) throw new Error('missingOperation');
      const op=readCreateOperation(doc.data()), now=this.clock();
      if(operationId!==createOperationId(op.actorUid))throw new Error('operationIdentityMismatch');
      if(op.status!=='READY')return op.status;
      if(op.leaseId!==leaseId || !op.leaseUntil || op.leaseUntil.toMillis()<=now.toMillis())return 'BUSY';
      const uid=op.actorUid, sourceRef=this.db.doc(`households/${op.sourceHouseholdId}`), homeRef=this.db.doc(`households/${op.householdId}`);
      const indexRef=this.db.doc(`familyMemberships/${uid}`), userRef=this.db.doc(`users/${uid}`);
      const source=await tx.get(sourceRef), home=await tx.get(homeRef), index=await tx.get(indexRef), user=await tx.get(userRef);
      const patch=(value:Partial<CreateOperation>)=>tx.update(ref,{updatedAt:now,...value});
      const operator=()=>{patch({status:'OPERATOR',nextAt:null,lastOutcome:'invariantViolation',leaseId:null,leaseUntil:null});return 'OPERATOR';};
      const pre = op.phase==='COPY'||op.phase==='VERIFY'||op.phase==='ACTIVATE'||op.phase==='ABORT';
      if(!source.exists || source.get('kind')!=='private' || source.get('ownerUid')!==uid ||
          !home.exists || home.get('kind')!=='family' || home.get('ownerUid')!==uid ||
          !index.exists || index.get('householdId')!==op.householdId || index.get('role')!=='owner')return operator();
      if(pre) {
        if(source.get('operationId')!==operationId || home.get('state')!=='PREPARING' || home.get('operationId')!==operationId ||
            index.get('state')!=='RESERVED' || index.get('operationId')!==operationId)return operator();
        if(op.phase!=='ABORT') {
          const marker=await tx.get(this.db.doc(`accountLifecycle/${uid}`));
          let valid=false;
          try { valid=marker.exists && readAccount(marker.data()).state==='ACTIVE'; } catch { valid=false; }
          // I/O failures must retry, not be mistaken for authoritative Pro loss.
          if(valid)valid=await hasPro(this.db,tx,uid,now);
          valid=valid && source.get('state')==='ACTIVE' && user.exists && user.get('privateHouseholdId')===op.sourceHouseholdId &&
            user.get('activeHouseholdId')===op.sourceHouseholdId && user.get('familyHouseholdId')===null && user.get('shoppingMigrationVersion')===1;
          if(!valid) {patch({phase:'ABORT',lastOutcome:'eligibilityLost'});return 'ABORT';}
        }
      } else {
        // Once activated, deletion/Pro changes never roll the list back. Keep
        // finishing source cleanup even if the deleting client removed its root.
        if(home.get('state')!=='ACTIVE' || home.get('operationId')!==null || index.get('state')!=='ACTIVE' || index.get('operationId')!==null ||
            source.get('operationId')!==null)return operator();
        if(user.exists && (user.get('activeHouseholdId')!==op.householdId || user.get('familyHouseholdId')!==op.householdId || user.get('privateHouseholdId')!==op.sourceHouseholdId))return operator();
      }
      if(op.phase==='COPY'||op.phase==='VERIFY') {
        let query=sourceRef.collection('shoppingItems').orderBy(FieldPath.documentId()).limit(this.pageSize);
        if(op.cursor!==null)query=query.startAfter(op.cursor);
        const page=await tx.get(query);
        const targets=page.docs.map(d=>homeRef.collection('shoppingItems').doc(d.id));
        const existing=targets.length?await tx.getAll(...targets):[];
        // Atomic cursor means a replay never revisits a committed page. Any
        // existing target ahead of the cursor is an unproven collision.
        const invalid=op.phase==='COPY'?existing.some(d=>d.exists):existing.some((d,i)=>!d.exists||!isDeepStrictEqual(d.data(),page.docs[i]!.data()));
        if(invalid){patch({phase:'ABORT',lastOutcome:'destinationCollision'});return 'ABORT';}
        if(op.phase==='COPY')for(let i=0;i<page.size;i++)tx.create(targets[i]!,page.docs[i]!.data());
        const next=op.phase==='COPY'?'VERIFY':'ACTIVATE';
        patch(page.empty?{phase:next,cursor:null}:{cursor:page.docs[page.size-1]!.id});
        return page.empty?next:op.phase;
      }
      if(op.phase==='ACTIVATE') {
        const owner=await tx.get(homeRef.collection('members').doc(uid));
        if(owner.exists){patch({phase:'ABORT',lastOutcome:'membershipCollision'});return 'ABORT';}
        tx.create(homeRef.collection('members').doc(uid),{role:'owner'});
        tx.update(homeRef,{state:'ACTIVE',operationId:null});
        // ACTIVE index + family pointers now fence private writes, so its
        // temporary lock can be released without exposing the retained copy.
        tx.update(sourceRef,{operationId:null});
        tx.set(indexRef,{householdId:op.householdId,role:'owner',state:'ACTIVE',operationId:null});
        tx.update(userRef,{familyHouseholdId:op.householdId,activeHouseholdId:op.householdId});
        patch({phase:'CLEAN_SOURCE'});return 'CLEAN_SOURCE';
      }
      if(op.phase==='CLEAN_SOURCE') {
        const page=await tx.get(sourceRef.collection('shoppingItems').limit(this.pageSize));
        for(const item of page.docs)tx.delete(item.ref);
        if(page.empty)patch({phase:'FINALIZE'});else patch({});
        return page.empty?'FINALIZE':'CLEAN_SOURCE';
      }
      if(op.phase==='FINALIZE') {
        patch({status:'DONE',nextAt:null,lastOutcome:'created',leaseId:null,leaseUntil:null});return 'DONE';
      }
      // Abort only our reserved, unexposed destination. Never delete source
      // items or restore a deleting user's root/lifecycle.
      const page=await tx.get(homeRef.collection('shoppingItems').limit(this.pageSize));
      const members=await tx.get(homeRef.collection('members').limit(this.pageSize));
      if(!page.empty||!members.empty){for(const d of [...page.docs,...members.docs])tx.delete(d.ref);patch({});return 'ABORT';}
      tx.delete(homeRef);tx.delete(indexRef);tx.update(sourceRef,{operationId:null});
      patch({status:'ABORTED',cursor:null,nextAt:null,leaseId:null,leaseUntil:null});return 'ABORTED';
    });
  }
  async resume(operationId:string,maxSteps=4):Promise<string> {
    if(!Number.isInteger(maxSteps)||maxSteps<1||maxSteps>20)throw new Error('invalidStepLimit');
    const lease=await this.claim(operationId);
    if(!lease){
      const doc=await this.db.doc(`familyOperations/${operationId}`).get();
      return doc.exists&&readCreateOperation(doc.data()).status!=='READY'?readCreateOperation(doc.data()).status:'notDueOrBusy';
    }
    let result='READY', failed=false;
    try {
      for(let i=0;i<maxSteps;i++) {result=await this.step(operationId,lease);if(['DONE','ABORTED','OPERATOR','BUSY'].includes(result))break;}
      return result;
    } catch {failed=true;return 'retry';}
    finally {
      await this.db.runTransaction(async tx=>{
        const ref=this.db.doc(`familyOperations/${operationId}`),doc=await tx.get(ref);
        if(!doc.exists)return;
        const op=readCreateOperation(doc.data());
        if(op.status==='READY'&&op.leaseId===lease)tx.update(ref,{leaseId:null,leaseUntil:null,nextAt:Timestamp.fromMillis(this.clock().toMillis()+(failed?30000:0)),updatedAt:this.clock(),...(failed?{lastOutcome:'retry'}:{})});
      });
    }
  }
}
