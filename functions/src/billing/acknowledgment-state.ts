import { compareTime } from '../models';
import { Timestamp } from 'firebase-admin/firestore';
import { AckFailure, AcknowledgmentError } from './play-acknowledgment-api';
export interface AckState {
  readonly schemaVersion: 2;
  readonly status: 'acknowledgmentPending' | 'acknowledgmentRetry' | 'acknowledged' | 'acknowledgmentFailed' | 'acknowledgmentExhausted' | 'acknowledgmentCanceled' | 'acknowledgmentReady';
  readonly attemptCount: number;
  readonly totalAttempts: number;
  readonly recoveryGeneration: number;
  readonly accountGeneration: number | null;
  readonly lifecycleRevision: number | null;
  readonly lastAttemptAt: Timestamp;
  readonly leaseId: string | null;
  readonly leaseUntil: Timestamp | null;
  readonly nextRetryAt: Timestamp | null;
  readonly failure: AckFailure | null;
}
export function parseAckState(value: unknown): AckState {
  const v = value as Record<string, unknown>;
  const oldFields = ['schemaVersion','status','attemptCount','lastAttemptAt','leaseId','leaseUntil','nextRetryAt','failure'];
  const added = ['totalAttempts','recoveryGeneration','accountGeneration','lifecycleRevision'];
  if (!v || typeof v !== 'object' || Array.isArray(v) || ![1,2].includes(v.schemaVersion as number)) throw new AcknowledgmentError('internalConflict');
  const fields = v.schemaVersion === 1 ? oldFields : [...oldFields,...added];
  if (Object.keys(v).length !== fields.length || fields.some(k => !(k in v))) throw new AcknowledgmentError('internalConflict');
  const s = (v.schemaVersion === 1 ? { ...v, schemaVersion: 2, totalAttempts: v.attemptCount, recoveryGeneration: 1,
    accountGeneration: null, lifecycleRevision: null,
    status: v.status === 'acknowledgmentFailed' && v.failure !== 'acknowledgmentPermanentFailure' ? 'acknowledgmentExhausted' : v.status } : { ...v }) as unknown as AckState;
  const positive = (n: unknown) => Number.isSafeInteger(n) && (n as number) > 0;
  if (!['acknowledgmentPending','acknowledgmentRetry','acknowledged','acknowledgmentFailed','acknowledgmentExhausted','acknowledgmentCanceled','acknowledgmentReady'].includes(s.status) ||
    !(s.status === 'acknowledgmentReady' ? s.attemptCount === 0 && s.recoveryGeneration > 1 :
      positive(s.attemptCount) || s.attemptCount === 0 && s.recoveryGeneration > 1 && ['acknowledged','acknowledgmentCanceled'].includes(s.status)) || !positive(s.totalAttempts) || s.totalAttempts < s.attemptCount || !positive(s.recoveryGeneration) ||
    !(s.accountGeneration === null || positive(s.accountGeneration)) || !(s.lifecycleRevision === null || positive(s.lifecycleRevision)) ||
    (s.accountGeneration === null) !== (s.lifecycleRevision === null) || !(s.lastAttemptAt instanceof Timestamp) ||
    ![null,'acknowledgmentTemporaryFailure','acknowledgmentPermanentFailure','unexpectedResponse'].includes(s.failure)) throw new AcknowledgmentError('internalConflict');
  if (s.status === 'acknowledgmentPending' ? typeof s.leaseId !== 'string' || !s.leaseId || !(s.leaseUntil instanceof Timestamp) || s.failure !== null || compareTime(s.leaseUntil, s.lastAttemptAt) <= 0 : s.leaseId !== null || s.leaseUntil !== null) throw new AcknowledgmentError('internalConflict');
  if (s.status === 'acknowledgmentRetry' ? !(s.nextRetryAt instanceof Timestamp) || s.failure === null || s.failure === 'acknowledgmentPermanentFailure' || compareTime(s.nextRetryAt, s.lastAttemptAt) <= 0 : s.nextRetryAt !== null) throw new AcknowledgmentError('internalConflict');
  if (['acknowledged','acknowledgmentCanceled','acknowledgmentReady'].includes(s.status) && s.failure !== null || ['acknowledgmentFailed','acknowledgmentExhausted'].includes(s.status) && s.failure === null) throw new AcknowledgmentError('internalConflict');
  return Object.freeze(s);
}
