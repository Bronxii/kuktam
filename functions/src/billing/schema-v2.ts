import { Timestamp } from 'firebase-admin/firestore';
import { BillingPurchase, EffectiveEntitlement, parsePurchase, parseEntitlement } from '../models';
import { LifecycleError, record, positive } from './lifecycle-error';

type Versioned<T> = T extends unknown ? Omit<T, 'schemaVersion'> & {
  readonly schemaVersion: 2;
  readonly lifecycleRevision: number;
  readonly lastCheckedAt: Timestamp | null;
  readonly nextCheckAt: Timestamp | null;
  readonly operationalError: 'TEMPORARY' | 'CONFIGURATION' | 'PERMANENT' | null;
  /** Null on v1 reads: requires explicit binding/account validation before writing. */
  readonly accountGeneration: number | null;
  readonly bindingKeyVersion: string | null;
} : never;
export type PurchaseV2 = Versioned<BillingPurchase>;
export type EffectiveV2 = Omit<EffectiveEntitlement, 'schemaVersion'> & { readonly schemaVersion: 2 };
const extras = ['lifecycleRevision', 'lastCheckedAt', 'nextCheckAt', 'operationalError', 'accountGeneration', 'bindingKeyVersion'] as const;

/** In-memory upgrade only; no I/O and no guessed proof freshness/account marker. */
export function readPurchase(value: unknown): PurchaseV2 {
  const v = record(value);
  if (v.schemaVersion !== 1 && v.schemaVersion !== 2) throw new LifecycleError('unsupportedSchema');
  try {
    if (v.schemaVersion === 1) return Object.freeze({ ...parsePurchase(v), schemaVersion: 2,
      lifecycleRevision: 1, lastCheckedAt: null, nextCheckAt: null, operationalError: null,
      accountGeneration: null, bindingKeyVersion: null }) as PurchaseV2;
    if (extras.some(k => !(k in v))) throw new LifecycleError('invalidSchema');
    const base = { ...v, schemaVersion: 1 };
    for (const k of extras) delete (base as Record<string, unknown>)[k];
    const parsed = parsePurchase(base);
    if (!positive(v.lifecycleRevision) ||
      !(v.lastCheckedAt === null || v.lastCheckedAt instanceof Timestamp) ||
      !(v.nextCheckAt === null || v.nextCheckAt instanceof Timestamp) ||
      ![null, 'TEMPORARY', 'CONFIGURATION', 'PERMANENT'].includes(v.operationalError as null) ||
      !(v.accountGeneration === null || positive(v.accountGeneration)) ||
      !(v.bindingKeyVersion === null || typeof v.bindingKeyVersion === 'string' && /^v[1-9][0-9]*$/.test(v.bindingKeyVersion)) ||
      (v.accountGeneration === null) !== (v.bindingKeyVersion === null) ||
      (parsed.bindingState !== 'BOUND' && (v.accountGeneration !== null || v.bindingKeyVersion !== null))) {
      throw new LifecycleError('invalidSchema');
    }
    return Object.freeze({ ...v }) as PurchaseV2;
  } catch (e) { if (e instanceof LifecycleError) throw e; throw new LifecycleError('invalidSchema'); }
}
export function readEffective(value: unknown): EffectiveV2 {
  const v = record(value);
  if (v.schemaVersion !== 1 && v.schemaVersion !== 2) throw new LifecycleError('unsupportedSchema');
  try { return Object.freeze({ ...parseEntitlement({ ...v, schemaVersion: 1 }), schemaVersion: 2 }); }
  catch { throw new LifecycleError('invalidSchema'); }
}
