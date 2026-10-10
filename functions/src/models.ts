import { Timestamp } from 'firebase-admin/firestore';

export const sources = ['PLAY_PURCHASE', 'PROMO', 'ADMIN', 'TEST'] as const;
export type GrantSource = typeof sources[number];
export type GrantStatus = 'ACTIVE' | 'INACTIVE' | 'REVOKED';

export interface Grant {
  readonly source: GrantSource;
  readonly status: GrantStatus;
  readonly startsAt: Timestamp;
  readonly expiresAt: Timestamp | null;
  readonly createdAt: Timestamp;
  readonly revokedAt: Timestamp | null;
  readonly sourceRef?: string;
  readonly actorRef?: string;
  readonly reasonCode?: string;
}

export interface EffectiveEntitlement {
  readonly schemaVersion: 1;
  readonly active: boolean;
  readonly validUntil: Timestamp | null;
  readonly sources: readonly GrantSource[];
  readonly revision: number;
  readonly verifiedAt: Timestamp;
  readonly updatedAt: Timestamp;
}

interface LedgerBase {
  readonly schemaVersion: 1;
  readonly packageName: string;
  readonly productId: string;
  readonly purchaseState: 'PENDING' | 'PURCHASED' | 'CANCELED';
  readonly acknowledgementState: 'PENDING' | 'ACKNOWLEDGED';
  readonly verifiedAt: Timestamp;
  readonly updatedAt: Timestamp;
  readonly revokedAt: Timestamp | null;
  readonly revokeReason: string | null;
  readonly testPurchase: boolean;
}

export interface BoundPurchase extends LedgerBase {
  readonly bindingState: 'BOUND';
  readonly purchaseToken: string;
  readonly boundUid: string;
  readonly accountBinding: string;
}

// Document ID remains the token hash. No UID or account profile in a tombstone.
// Keeping a raw token must have an explicit outstanding reconciliation purpose.
export type RetiredPurchase = LedgerBase & {
  readonly bindingState: 'ACCOUNT_DELETED' | 'REVOKED';
} & (
  { readonly reconciliationRequired: true; readonly purchaseToken: string } |
  { readonly reconciliationRequired: false; readonly purchaseToken?: never }
);
export type BillingPurchase = BoundPurchase | RetiredPurchase;

function object(value: unknown): Record<string, unknown> {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new TypeError('Expected document');
  }
  return value as Record<string, unknown>;
}
function keys(v: Record<string, unknown>, required: string[], optional: string[] = []) {
  if (required.some(k => !(k in v)) || Object.keys(v).some(k =>
    !required.includes(k) && !optional.includes(k))) throw new TypeError('Invalid document fields');
}
function text(v: unknown): asserts v is string {
  if (typeof v !== 'string' || v.trim().length === 0) throw new TypeError('Expected nonempty string');
}
function timestamp(v: unknown, nullable = false) {
  if (!(v instanceof Timestamp) && !(nullable && v === null)) throw new TypeError('Expected Timestamp');
}
function oneOf(v: unknown, choices: readonly string[]) {
  if (typeof v !== 'string' || !choices.includes(v)) throw new TypeError('Invalid enum value');
}
export function compareTime(a: Timestamp, b: Timestamp): number {
  return a.seconds === b.seconds ? a.nanoseconds - b.nanoseconds : a.seconds - b.seconds;
}

export function parseGrant(value: unknown): Grant {
  const v = object(value);
  keys(v, ['source', 'status', 'startsAt', 'expiresAt', 'createdAt', 'revokedAt'],
    ['sourceRef', 'actorRef', 'reasonCode']);
  oneOf(v.source, sources);
  oneOf(v.status, ['ACTIVE', 'INACTIVE', 'REVOKED']);
  timestamp(v.startsAt); timestamp(v.createdAt);
  timestamp(v.expiresAt, true); timestamp(v.revokedAt, true);
  for (const key of ['sourceRef', 'actorRef', 'reasonCode']) if (key in v) text(v[key]);
  if (v.expiresAt !== null && compareTime(v.expiresAt as Timestamp, v.startsAt as Timestamp) <= 0) {
    throw new TypeError('Expiry must follow start');
  }
  return Object.freeze({ ...v }) as unknown as Grant;
}

export function parseEntitlement(value: unknown): EffectiveEntitlement {
  const v = object(value);
  keys(v, ['schemaVersion', 'active', 'validUntil', 'sources', 'revision', 'verifiedAt', 'updatedAt']);
  if (v.schemaVersion !== 1 || typeof v.active !== 'boolean' ||
    !Number.isSafeInteger(v.revision) || (v.revision as number) < 1) throw new TypeError('Invalid entitlement');
  timestamp(v.validUntil, true); timestamp(v.verifiedAt); timestamp(v.updatedAt);
  if (!Array.isArray(v.sources)) throw new TypeError('Invalid sources');
  for (const source of v.sources) oneOf(source, sources);
  if (new Set(v.sources).size !== v.sources.length ||
    v.active !== (v.sources.length > 0) || (!v.active && v.validUntil !== null)) {
    throw new TypeError('Inconsistent entitlement');
  }
  return Object.freeze({ ...v, sources: Object.freeze([...v.sources]) }) as unknown as EffectiveEntitlement;
}

export function parsePurchase(value: unknown): BillingPurchase {
  const v = object(value);
  const base = ['schemaVersion', 'packageName', 'productId', 'bindingState',
    'purchaseState', 'acknowledgementState', 'verifiedAt', 'updatedAt',
    'revokedAt', 'revokeReason', 'testPurchase'];
  oneOf(v.bindingState, ['BOUND', 'ACCOUNT_DELETED', 'REVOKED']);
  if (v.bindingState === 'BOUND') {
    keys(v, [...base, 'purchaseToken', 'boundUid', 'accountBinding']);
    text(v.purchaseToken); text(v.boundUid); text(v.accountBinding);
  } else {
    if (typeof v.reconciliationRequired !== 'boolean') throw new TypeError('Missing retention purpose');
    keys(v, [...base, 'reconciliationRequired', ...(v.reconciliationRequired ? ['purchaseToken'] : [])]);
    if (v.reconciliationRequired) text(v.purchaseToken);
  }
  if (v.schemaVersion !== 1 || typeof v.testPurchase !== 'boolean') throw new TypeError('Invalid ledger');
  text(v.packageName); text(v.productId);
  oneOf(v.purchaseState, ['PENDING', 'PURCHASED', 'CANCELED']);
  oneOf(v.acknowledgementState, ['PENDING', 'ACKNOWLEDGED']);
  timestamp(v.verifiedAt); timestamp(v.updatedAt); timestamp(v.revokedAt, true);
  if (v.revokeReason !== null) text(v.revokeReason);
  if (v.bindingState === 'REVOKED' && v.revokedAt === null) throw new TypeError('Missing revocation timestamp');
  return Object.freeze({ ...v }) as unknown as BillingPurchase;
}
