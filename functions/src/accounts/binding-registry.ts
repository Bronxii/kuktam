import { Timestamp } from 'firebase-admin/firestore';
import { LifecycleError, record, exact } from '../billing/lifecycle-error';
export type BindingRecord = {
  readonly schemaVersion: 1; readonly keyVersion: string; readonly createdAt: Timestamp; readonly updatedAt: Timestamp;
} & ({ readonly state: 'ACTIVE' | 'DELETING'; readonly uid: string } | { readonly state: 'TOMBSTONED' });
export function readBinding(value: unknown): BindingRecord {
  const v = record(value);
  exact(v, ['schemaVersion', 'keyVersion', 'createdAt', 'updatedAt', 'state', ...(v.state !== 'TOMBSTONED' ? ['uid'] : [])]);
  if (v.schemaVersion !== 1 || typeof v.keyVersion !== 'string' || !/^v[1-9][0-9]*$/.test(v.keyVersion) ||
    !(v.createdAt instanceof Timestamp) || !(v.updatedAt instanceof Timestamp) ||
    !['ACTIVE', 'DELETING', 'TOMBSTONED'].includes(v.state as string) ||
    (v.state !== 'TOMBSTONED' && (typeof v.uid !== 'string' || !v.uid || v.uid.includes('/')))) throw new LifecycleError('invalidSchema');
  return Object.freeze({ ...v }) as BindingRecord;
}
export function bindingVersion(binding: string): string {
  if (!/^v[1-9][0-9]*_[A-Za-z0-9_-]{43}$/.test(binding)) throw new LifecycleError('bindingConflict');
  return binding.split('_')[0]!;
}
