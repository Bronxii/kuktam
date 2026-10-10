import { Timestamp } from 'firebase-admin/firestore';
import { Grant } from '../models';
import { aggregateGrants } from '../aggregate';
import { EffectiveV2 } from './schema-v2';

/** Shared effective revision contract: active, validity or source-set changes.
 * Deleting/deleted accounts cannot acquire effective access from remaining grants.
 * Grant records themselves are not deleted here. */
export function effectiveUpdate(grants: readonly Grant[], now: Timestamp, prior: EffectiveV2 | null,
  accountActive = true): EffectiveV2 | null {
  const computed = aggregateGrants(accountActive ? grants : [], now, prior?.revision ?? 1);
  const changed = !prior || prior.active !== computed.active || prior.sources.length !== computed.sources.length ||
    !prior.sources.every(s => computed.sources.includes(s)) ||
    (prior.validUntil === null ? computed.validUntil !== null : computed.validUntil === null || !prior.validUntil.isEqual(computed.validUntil));
  return changed ? { ...computed, schemaVersion: 2, revision: prior ? prior.revision + 1 : 1 } : null;
}
