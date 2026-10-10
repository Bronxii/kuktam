import { compareTime } from '../../models';
import { Firestore, Timestamp, Transaction, FieldValue } from 'firebase-admin/firestore';
import { randomUUID } from 'node:crypto';
import { ParsedDelivery, RtdnOutcome, rtdnOutcomes } from './notification';
import { defaultRetryPolicy, RetryPolicy, retryAt, beginAttempt } from '../retry-policy';
import { readPurchase } from '../schema-v2';
import { tokenHash } from '../purchase-identity';
export type InboxStatus = 'RECEIVED' | 'PROCESSING' | 'PROCESSED' | 'RETRY' | 'UNRESOLVED' | 'IGNORED' | 'FAILED_TERMINAL';
export interface InboxRecord {
  schemaVersion: 2; recoveryGeneration: number; totalAttempts: number; lastAttemptAt: Timestamp | null; operatorRequired: boolean; source: string; messageId: string; fingerprint: string; receivedAt: Timestamp; publishTime: Timestamp;
  category: ParsedDelivery['notification']['category']; notificationType: number | null; eventTimeMillis: number | null;
  tokenHash: string | null; transientToken?: string;
  status: InboxStatus; attemptCount: number; leaseId: string | null; leaseUntil: Timestamp | null;
  processedAt: Timestamp | null; nextRetryAt: Timestamp | null; lastOutcome: RtdnOutcome | null;
}
export interface InboxClaim { readonly key: string; readonly leaseId: string; readonly record: Readonly<InboxRecord>; }
const final = (s: InboxStatus) => ['PROCESSED','IGNORED','FAILED_TERMINAL'].includes(s);
export function readInbox(value: unknown): InboxRecord {
  const raw = value as any;
  if (!raw || ![1,2].includes(raw.schemaVersion)) throw new Error('invalidInbox');
  if (raw.schemaVersion === 1 && ['recoveryGeneration','totalAttempts','lastAttemptAt','operatorRequired'].some(k => k in raw)) throw new Error('invalidInbox');
  const v = (raw.schemaVersion === 1 ? {...raw,schemaVersion:2,recoveryGeneration:1,totalAttempts:raw.attemptCount,
    lastAttemptAt:raw.attemptCount > 0 ? raw.receivedAt : null,operatorRequired:false} : raw) as InboxRecord;
  const keys = ['recoveryGeneration','totalAttempts','lastAttemptAt','operatorRequired','schemaVersion','source','messageId','fingerprint','receivedAt','publishTime','category','notificationType','eventTimeMillis','tokenHash',
    'status','attemptCount','leaseId','leaseUntil','processedAt','nextRetryAt','lastOutcome', ...(v?.transientToken !== undefined ? ['transientToken'] : [])];
  if (!v || Object.keys(v).length !== keys.length || keys.some(k => !(k in v)) || v.schemaVersion !== 2 ||
    typeof v.source !== 'string' || !v.source || v.source.length > 512 || typeof v.messageId !== 'string' || !v.messageId || v.messageId.length > 256 || !/^[a-f0-9]{64}$/.test(v.fingerprint) ||
    !(v.receivedAt instanceof Timestamp) || !(v.publishTime instanceof Timestamp) ||
    !['oneTime','voided','test','unsupported','rejected'].includes(v.category) ||
    !['RECEIVED','PROCESSING','PROCESSED','RETRY','UNRESOLVED','IGNORED','FAILED_TERMINAL'].includes(v.status) ||
    !Number.isSafeInteger(v.attemptCount) || v.attemptCount < 0 ||
    !Number.isSafeInteger(v.recoveryGeneration) || v.recoveryGeneration < 1 || !Number.isSafeInteger(v.totalAttempts) || v.totalAttempts < v.attemptCount ||
    !(v.lastAttemptAt === null || v.lastAttemptAt instanceof Timestamp) || typeof v.operatorRequired !== 'boolean' ||
    !(v.tokenHash === null || /^[a-f0-9]{64}$/.test(v.tokenHash)) ||
    !(v.notificationType === null || Number.isSafeInteger(v.notificationType)) ||
    !(v.eventTimeMillis === null || Number.isSafeInteger(v.eventTimeMillis) && v.eventTimeMillis >= 0 && v.eventTimeMillis <= 253402300799999) ||
    !(v.lastOutcome === null || rtdnOutcomes.includes(v.lastOutcome)) ||
    ![v.processedAt,v.nextRetryAt,v.leaseUntil].every(t => t === null || t instanceof Timestamp) ||
    (v.status === 'PROCESSING' ? typeof v.leaseId !== 'string' || !v.leaseId || !v.leaseUntil : v.leaseId !== null || v.leaseUntil !== null) ||
    (v.transientToken !== undefined && (typeof v.transientToken !== 'string' || !v.transientToken || v.transientToken.length > 4096 || tokenHash(v.transientToken) !== v.tokenHash)) ||
    (final(v.status) && (v.transientToken !== undefined || v.processedAt === null || v.nextRetryAt !== null))) throw new Error('invalidInbox');
  return Object.freeze({ ...v });
}
/** Owns ONLY inbox writes. Purchase mutations belong to LifecycleStore. */
export class RtdnInboxStore {
  constructor(private readonly db: Firestore, private readonly clock: () => Timestamp = Timestamp.now,
    private readonly policy: RetryPolicy = defaultRetryPolicy, private readonly rng: () => number = Math.random, private readonly unresolvedPolicy: RetryPolicy = policy) {}
  private ref(key: string) { if (!/^[a-f0-9]{64}$/.test(key)) throw new Error('invalidInboxKey'); return this.db.doc(`rtdnInbox/${key}`); }
  async receive(d: ParsedDelivery): Promise<'received' | 'duplicate' | 'messageConflict'> {
    return this.db.runTransaction(async tx => {
      const ref = this.ref(d.key), old = await tx.get(ref);
      if (old.exists) return readInbox(old.data()).fingerprint === d.fingerprint ? 'duplicate' : 'messageConflict';
      const n = d.notification; let transientToken: string | undefined;
      if (n.token && n.tokenHash) {
        const ledger = await tx.get(this.db.doc(`billingPurchases/${n.tokenHash}`));
        const purchase = ledger.exists ? readPurchase(ledger.data()) : null;
        if (!purchase || !('purchaseToken' in purchase) || purchase.purchaseToken !== n.token) transientToken = n.token;
      }
      const ignored = n.category === 'test' || n.category === 'unsupported', failed = n.category === 'rejected';
      const now = this.clock();
      const record: InboxRecord = { schemaVersion: 2,recoveryGeneration:1,totalAttempts:0,lastAttemptAt:null,operatorRequired:false, source: d.source, messageId: d.messageId, fingerprint: d.fingerprint,
        receivedAt: now, publishTime: Timestamp.fromMillis(d.publishTimeMillis), category: n.category, notificationType: n.notificationType,
        eventTimeMillis: n.eventTimeMillis, tokenHash: n.tokenHash, ...(transientToken ? { transientToken } : {}),
        status: ignored ? 'IGNORED' : failed ? 'FAILED_TERMINAL' : 'RECEIVED', attemptCount: 0,
        leaseId: null, leaseUntil: null, processedAt: ignored || failed ? now : null, nextRetryAt: null,
        lastOutcome: n.category === 'test' ? 'ignoredTestNotification' : n.rejection };
      tx.create(ref, readInbox(record)); return 'received';
    });
  }
  async claim(key: string): Promise<InboxClaim | RtdnOutcome> {
    return this.db.runTransaction(async tx => {
      const ref = this.ref(key), doc = await tx.get(ref); if (!doc.exists) return 'purchaseUnresolved';
      const r = readInbox(doc.data()), now = this.clock();
      if (final(r.status)) return 'duplicate';
      if (r.operatorRequired || r.lastOutcome === 'permanentConfigurationFailure') return 'recoveryRequired';
      if (r.leaseUntil && compareTime(r.leaseUntil, now) > 0) return 'busyLease';
      if (r.nextRetryAt && compareTime(r.nextRetryAt, now) > 0) return 'retryDeferred';
      if (r.attemptCount >= this.policy.attemptsPerGeneration) {
        if (r.status !== 'UNRESOLVED' || r.leaseId !== null) {
          tx.update(ref, { ...readInbox({ ...r, status: 'UNRESOLVED', leaseId: null, leaseUntil: null,
            nextRetryAt: null, processedAt: null, lastOutcome: 'recoveryRequired' }) });
        }
        return 'recoveryRequired';
      }
      const next = beginAttempt({ generation: r.recoveryGeneration, generationAttempts: r.attemptCount, totalAttempts: r.totalAttempts }, this.policy)!;
      const leaseId = randomUUID(), record = readInbox({ ...r, status: 'PROCESSING', attemptCount: next.generationAttempts,totalAttempts:next.totalAttempts,lastAttemptAt:now,
        leaseId, leaseUntil: Timestamp.fromMillis(now.toMillis() + this.policy.leaseMs), nextRetryAt: null });
      tx.update(ref, { ...record }); return { key, leaseId, record };
    });
  }
  /** Read inside the PURCHASE transaction as well: expired/replaced workers cannot
   * change purchase state even when their external lookup eventually succeeds. */
  async assertLease(tx: Transaction, claim: InboxClaim): Promise<void> {
    const doc = await tx.get(this.ref(claim.key)); const r = doc.exists ? readInbox(doc.data()) : null;
    if (!r || r.status !== 'PROCESSING' || r.leaseId !== claim.leaseId || !r.leaseUntil ||
      compareTime(r.leaseUntil, this.clock()) <= 0) throw new Error('staleInboxLease');
  }
  /** Trusted maintenance-only round recovery. Configuration holds are never
   * auto-reset; total attempts are monotonic. No lookup result is reused. */
  async recover(key: string, roundDelayMs: number, maxGenerations: number): Promise<boolean> {
    return this.db.runTransaction(async tx => {
      const ref=this.ref(key),doc=await tx.get(ref); if(!doc.exists) return false;
      const r=readInbox(doc.data()),now=this.clock();
      if(final(r.status) || r.operatorRequired || r.lastOutcome==='permanentConfigurationFailure' ||
        r.leaseUntil && compareTime(r.leaseUntil, now) > 0 || r.attemptCount<this.policy.attemptsPerGeneration) return false;
      if(r.recoveryGeneration>=maxGenerations) {
        tx.update(ref,{...r,status:'UNRESOLVED',leaseId:null,leaseUntil:null,nextRetryAt:null,operatorRequired:true}); return false;
      }
      const due=(r.lastAttemptAt ?? r.receivedAt).toMillis()+roundDelayMs;
      if(due>now.toMillis()) {
        if(r.nextRetryAt===null) tx.update(ref,{...r,status:'UNRESOLVED',leaseId:null,leaseUntil:null,nextRetryAt:Timestamp.fromMillis(due)});
        return false;
      }
      tx.update(ref,{...readInbox({...r,status:'RECEIVED',attemptCount:0,recoveryGeneration:r.recoveryGeneration+1,
        leaseId:null,leaseUntil:null,nextRetryAt:null,lastOutcome:null})});return true;
    });
  }
  /** No time-based retention: remove only final or now-redundant token copies. */
  async minimizeToken(key:string):Promise<boolean> {
    return this.db.runTransaction(async tx=>{
      const ref=this.ref(key),doc=await tx.get(ref);if(!doc.exists)return false;
      const r=readInbox(doc.data());if(!r.transientToken)return false;
      const ledger=r.tokenHash ? await tx.get(this.db.doc(`billingPurchases/${r.tokenHash}`)) : null;
      const p=ledger?.exists ? readPurchase(ledger.data()) : null;
      if(!final(r.status) && !(p && 'purchaseToken' in p && p.purchaseToken===r.transientToken)) return false;
      tx.update(ref,{transientToken:FieldValue.delete()});return true;
    });
  }
  async finish(claim: InboxClaim, status: Exclude<InboxStatus,'RECEIVED' | 'PROCESSING'>, outcome: RtdnOutcome): Promise<boolean> {
    const sample = this.rng();
    return this.db.runTransaction(async tx => {
      try { await this.assertLease(tx, claim); } catch { return false; }
      const ref = this.ref(claim.key), doc = await tx.get(ref), r = readInbox(doc.data()), now = this.clock();
      const retry = (status === 'RETRY' || status === 'UNRESOLVED') && outcome !== 'permanentConfigurationFailure';
      const nextMs = retry ? retryAt({ generation: r.recoveryGeneration, generationAttempts: r.attemptCount, totalAttempts: r.totalAttempts }, now.seconds * 1000 + Math.ceil(now.nanoseconds / 1000000), () => sample, status === 'UNRESOLVED' ? this.unresolvedPolicy : this.policy) : null;
      const next = { ...r, operatorRequired: outcome === 'permanentConfigurationFailure', status: retry && nextMs === null ? 'UNRESOLVED' as const : status,
        leaseId: null, leaseUntil: null, nextRetryAt: nextMs === null ? null : Timestamp.fromMillis(nextMs),
        processedAt: final(status) ? now : null, lastOutcome: outcome };
      if (final(status)) delete next.transientToken;
      readInbox(next);
      tx.update(ref, { ...next, ...(final(status) ? { transientToken: FieldValue.delete() } : {}) }); return true;
    });
  }
}
