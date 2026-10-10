import { Timestamp } from 'firebase-admin/firestore';
import { BoundPurchase, Grant } from '../src/models';
export const now = Timestamp.fromDate(new Date('2026-10-06T00:00:00Z'));
export const later = new Timestamp(now.seconds + 86400, 0);
export const grant = (overrides: Partial<Grant> = {}): Grant => ({
  source: 'PROMO', status: 'ACTIVE', startsAt: now, expiresAt: null,
  createdAt: now, revokedAt: null, ...overrides,
});
// Synthetic token only; never a real purchase or a Play API request.
export const purchase = (): BoundPurchase => ({
  schemaVersion: 1, packageName: 'com.bronxii.kuktam', productId: 'kuktam_pro_lifetime',
  purchaseToken: 'synthetic-test-token', boundUid: 'alice', accountBinding: 'synthetic-binding',
  bindingState: 'BOUND', purchaseState: 'PURCHASED', acknowledgementState: 'PENDING',
  verifiedAt: now, updatedAt: now, revokedAt: null, revokeReason: null, testPurchase: true,
});
