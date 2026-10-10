import { PurchaseV2 } from './schema-v2';
import { AccountLifecycle } from '../accounts/account-lifecycle';
export type Observation = 'pending' | 'purchased' | 'acknowledged' | 'acknowledgmentPending' | 'acknowledgmentRetry' | 'terminalInvalid' | 'entitlementRevoked' | 'pendingCanceled';
export type Transition = { readonly outcome: 'stale' | 'rejected'; readonly reason: string } |
  { readonly outcome: 'apply' | 'noop'; readonly lifecycleRevision: number; readonly purchaseState: 'PENDING' | 'PURCHASED' | 'CANCELED'; readonly acknowledgementState: 'PENDING' | 'ACKNOWLEDGED'; readonly grantRequired: boolean };
/** Verified is an input precondition; granted is the writer's atomic postcondition.
 * Ack claim/retry belongs to operational delivery state, not purchase truth. */
export function decideTransition(current: PurchaseV2 | null, observation: Observation, account: AccountLifecycle,
  expectedRevision: number, expectedGeneration: number): Transition {
  if (account.generation !== expectedGeneration) return { outcome: 'stale', reason: 'staleAccountGeneration' };
  if ((current?.lifecycleRevision ?? 0) !== expectedRevision) return { outcome: 'stale', reason: 'staleLifecycleRevision' };
  // Negative authoritative transitions may finish during account deletion.
  // Fences still apply; neither branch can grant or reactivate anything.
  if (observation === 'entitlementRevoked' || observation === 'pendingCanceled') {
    if (!current || current.bindingState !== 'BOUND') return { outcome: 'rejected', reason: 'missingOwner' };
    if (current.revokedAt !== null || current.purchaseState === 'CANCELED') {
      const same = observation === 'entitlementRevoked' ? current.revokedAt !== null : current.revokeReason === 'PENDING_CANCELED';
      if (!same) return { outcome: 'rejected', reason: 'terminal' };
      return { outcome: 'noop', lifecycleRevision: current.lifecycleRevision, purchaseState: current.purchaseState,
        acknowledgementState: current.acknowledgementState, grantRequired: false };
    }
    if (observation === 'pendingCanceled' && (current.purchaseState !== 'PENDING' || current.acknowledgementState !== 'PENDING')) {
      return { outcome: 'rejected', reason: 'purchaseNotPending' };
    }
    return { outcome: 'apply', lifecycleRevision: current.lifecycleRevision + 1, purchaseState: 'CANCELED',
      acknowledgementState: current.acknowledgementState, grantRequired: false };
  }
  if (account.state !== 'ACTIVE') return { outcome: 'rejected', reason: 'accountInactive' };
  if (current && (current.bindingState !== 'BOUND' || current.revokedAt !== null || current.purchaseState === 'CANCELED')) return { outcome: 'rejected', reason: 'terminal' };
  if (observation === 'terminalInvalid') return { outcome: 'rejected', reason: 'purchaseInvalid' };
  if (current?.acknowledgementState === 'ACKNOWLEDGED' && observation !== 'acknowledged') return { outcome: 'stale', reason: 'acknowledgmentRegression' };
  if (observation === 'pending' && current?.purchaseState === 'PURCHASED') return { outcome: 'stale', reason: 'purchaseRegression' };
  if (observation === 'acknowledgmentPending' || observation === 'acknowledgmentRetry') {
    if (!current || current.purchaseState !== 'PURCHASED') return { outcome: 'rejected', reason: 'invalidTransition' };
    return { outcome: 'noop', lifecycleRevision: current.lifecycleRevision, purchaseState: current.purchaseState,
      acknowledgementState: current.acknowledgementState, grantRequired: true };
  }
  const purchaseState = observation === 'pending' ? 'PENDING' : 'PURCHASED';
  const acknowledgementState = observation === 'acknowledged' ? 'ACKNOWLEDGED' : 'PENDING';
  const changed = !current || current.purchaseState !== purchaseState || current.acknowledgementState !== acknowledgementState;
  return { outcome: changed ? 'apply' : 'noop', lifecycleRevision: (current?.lifecycleRevision ?? 0) + (changed ? 1 : 0),
    purchaseState, acknowledgementState, grantRequired: purchaseState === 'PURCHASED' };
}
