import { Timestamp } from 'firebase-admin/firestore';
import { compareTime, EffectiveEntitlement, Grant, parseEntitlement, parseGrant, sources } from './models';

/** N1 semantics: start inclusive, expiry exclusive, any revocation disqualifies.
 * Caller supplies a complete trusted grant set for one account. This pure
 * calculation does not verify a purchase or allocate a concurrent revision.
 */
export function aggregateGrants(
  input: readonly Grant[], now: Timestamp, revision: number,
): EffectiveEntitlement {
  const active = input.map(parseGrant).filter(g => g.status === 'ACTIVE' &&
    g.revokedAt === null && compareTime(g.startsAt, now) <= 0 &&
    (g.expiresAt === null || compareTime(now, g.expiresAt) < 0));
  let validUntil: Timestamp | null = null;
  if (active.length > 0 && active.every(g => g.expiresAt !== null)) {
    validUntil = active.reduce((latest, g) =>
      compareTime(g.expiresAt!, latest) > 0 ? g.expiresAt! : latest, active[0]!.expiresAt!);
  }
  return parseEntitlement({
    schemaVersion: 1, active: active.length > 0, validUntil,
    sources: sources.filter(source => active.some(g => g.source === source)),
    revision, verifiedAt: now, updatedAt: now,
  });
}
