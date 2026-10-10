import { compareTime } from '../models';
import { Timestamp } from 'firebase-admin/firestore';
import { LifecycleError, exact, positive, record } from '../billing/lifecycle-error';
export interface AccountLifecycle {
  readonly schemaVersion: 1;
  readonly state: 'ACTIVE' | 'DELETING' | 'DELETED';
  readonly generation: number;
  readonly updatedAt: Timestamp;
  readonly deletionStartedAt: Timestamp | null;
  readonly deletedAt: Timestamp | null;
}
export function readAccount(value: unknown): AccountLifecycle {
  const v = record(value);
  exact(v, ['schemaVersion', 'state', 'generation', 'updatedAt', 'deletionStartedAt', 'deletedAt']);
  if (v.schemaVersion !== 1 || !['ACTIVE', 'DELETING', 'DELETED'].includes(v.state as string) ||
    !positive(v.generation) || !(v.updatedAt instanceof Timestamp) ||
    (v.state === 'ACTIVE' ? v.deletionStartedAt !== null || v.deletedAt !== null :
      !(v.deletionStartedAt instanceof Timestamp) ||
      (v.state === 'DELETED' ? !(v.deletedAt instanceof Timestamp) : v.deletedAt !== null))) throw new LifecycleError('invalidSchema');
  if (v.deletionStartedAt instanceof Timestamp && compareTime(v.deletionStartedAt, v.updatedAt) > 0 ||
    v.deletedAt instanceof Timestamp && (compareTime(v.deletedAt, v.deletionStartedAt as Timestamp) < 0 || compareTime(v.deletedAt, v.updatedAt) > 0)) throw new LifecycleError('invalidSchema');
  return Object.freeze({ ...v }) as unknown as AccountLifecycle;
}
export function advanceAccount(current: AccountLifecycle, target: AccountLifecycle['state'], expectedGeneration: number, now: Timestamp): AccountLifecycle {
  if (current.generation !== expectedGeneration) throw new LifecycleError('internalConflict');
  if (current.state === target) return current;
  if (!(current.state === 'ACTIVE' && target === 'DELETING' || current.state === 'DELETING' && target === 'DELETED')) throw new LifecycleError('invalidTransition');
  return readAccount({ ...current, state: target, generation: current.generation + 1, updatedAt: now,
    deletionStartedAt: current.deletionStartedAt ?? now, deletedAt: target === 'DELETED' ? now : null });
}
