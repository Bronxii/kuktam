import { compareTime } from '../models';
import { Firestore, Timestamp, Transaction } from 'firebase-admin/firestore';
import { createHash, randomUUID } from 'node:crypto';
export type WorkStatus = 'READY' | 'PROCESSING' | 'CLOSED' | 'OPERATOR';
export interface FeedProgress { readonly startMs: number; readonly endMs: number; readonly pageToken: string | null; }
export interface WorkRecord {
  readonly schemaVersion: 1; readonly status: WorkStatus; readonly leaseId: string | null; readonly leaseUntil: Timestamp | null;
  readonly nextAt: Timestamp | null; readonly attempts: number; readonly failures: number;
  readonly lastOutcome: 'success' | 'retry' | 'configuration' | 'conflict' | 'inactive' | 'exhausted' | null;
  readonly fingerprint: string | null; readonly progress: FeedProgress | null;
}
export interface WorkClaim { readonly key: string; readonly leaseId: string; readonly record: WorkRecord; }
export function workKey(kind: string, identity: string) { return createHash('sha256').update(JSON.stringify([kind, identity])).digest('hex'); }
export function readWork(v: any): WorkRecord {
  const keys = ['schemaVersion', 'status', 'leaseId', 'leaseUntil', 'nextAt', 'attempts', 'failures', 'lastOutcome', 'fingerprint', 'progress'];
  if (!v || Object.keys(v).length !== keys.length || keys.some(k => !(k in v)) || v.schemaVersion !== 1 ||
    !['READY', 'PROCESSING', 'CLOSED', 'OPERATOR'].includes(v.status) || !Number.isSafeInteger(v.attempts) || v.attempts < 0 ||
    !Number.isSafeInteger(v.failures) || v.failures < 0 || ![null, 'success', 'retry', 'configuration', 'conflict', 'inactive', 'exhausted'].includes(v.lastOutcome) ||
    !(v.fingerprint === null || typeof v.fingerprint === 'string' && /^[a-f0-9]{64}$/.test(v.fingerprint)) ||
    ![v.leaseUntil, v.nextAt].every(t => t === null || t instanceof Timestamp) ||
    (v.status === 'PROCESSING' ? typeof v.leaseId !== 'string' || !v.leaseId || !v.leaseUntil : v.leaseId !== null || v.leaseUntil !== null) ||
    (v.progress !== null && (Object.keys(v.progress).sort().join(',') !== 'endMs,pageToken,startMs' ||
      !Number.isSafeInteger(v.progress.startMs) || !Number.isSafeInteger(v.progress.endMs) || v.progress.startMs < 0 || v.progress.endMs < v.progress.startMs ||
      !(v.progress.pageToken === null || typeof v.progress.pageToken === 'string' && v.progress.pageToken.length <= 4096)))) throw new Error('invalidMaintenanceState');
  return Object.freeze({ ...v });
}
/** Technical leases/scheduling only. Never writes purchases, grants or access. */
export class MaintenanceStore {
  constructor(private readonly db: Firestore, private readonly clock: () => Timestamp, private readonly leaseMs: number) { }
  private ref(key: string) { if (!/^[a-f0-9]{64}$/.test(key)) throw new Error('invalidWorkKey'); return this.db.doc(`billingMaintenance/${key}`); }
  async claim(key: string, fingerprint: string | null = null): Promise<WorkClaim | null> {
    return this.db.runTransaction(async tx => {
      const ref = this.ref(key), doc = await tx.get(ref), now = this.clock();
      const r = doc.exists ? readWork(doc.data()) : null;
      if (r?.status === 'PROCESSING' && compareTime(r.leaseUntil!, now) > 0) return null;
      // A changed grant boundary can reopen closed recompute metadata, not an operator hold.
      if (r && (r.status === 'OPERATOR' || r.fingerprint === fingerprint &&
        (r.status === 'CLOSED' || r.nextAt && compareTime(r.nextAt, now) > 0))) return null;
      const leaseId = randomUUID(), next = readWork({
        schemaVersion: 1, status: 'PROCESSING', leaseId,
        leaseUntil: Timestamp.fromMillis(now.toMillis() + this.leaseMs), nextAt: null, attempts: (r?.attempts ?? 0) + 1,
        failures: r?.failures ?? 0, lastOutcome: r?.lastOutcome ?? null, fingerprint, progress: r?.progress ?? null
      });
      tx.set(ref, next); return { key, leaseId, record: next };
    });
  }
  async guard(tx: Transaction, c: WorkClaim): Promise<void> {
    const doc = await tx.get(this.ref(c.key)), r = doc.exists ? readWork(doc.data()) : null;
    if (!r || r.status !== 'PROCESSING' || r.leaseId !== c.leaseId || compareTime(r.leaseUntil!, this.clock()) <= 0) throw new Error('staleMaintenanceLease');
  }
  async finish(c: WorkClaim, outcome: WorkRecord['lastOutcome'], nextAt: number | null,
    operator = false, progress: FeedProgress | null = c.record.progress): Promise<boolean> {
    return this.db.runTransaction(async tx => {
      await this.guard(tx, c);
      const next = readWork({
        ...c.record, status: operator ? 'OPERATOR' : nextAt === null ? 'CLOSED' : 'READY', leaseId: null, leaseUntil: null,
        nextAt: nextAt === null ? null : Timestamp.fromMillis(nextAt), lastOutcome: outcome,
        failures: outcome === 'success' ? 0 : c.record.failures + 1, progress
      });
      tx.set(this.ref(c.key), next); return true;
    });
  }
}
