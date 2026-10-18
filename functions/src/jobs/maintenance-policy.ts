import { RetryPolicy, defaultRetryPolicy, beginAttempt } from '../billing/retry-policy';
export const categories = ['ack', 'expiredInbox', 'retryInbox', 'unresolvedInbox', 'voided', 'active', 'grants', 'tokens', 'deletion', 'family', 'shopping'] as const;
export type Category = typeof categories[number];
export interface MaintenancePolicy {
  readonly pageSize: number; readonly runBudgetMs: number; readonly leaseMs: number; readonly ioTimeoutMs: number;
  readonly activeIntervalMs: number; readonly spread: number; readonly transientDelayMs: number;
  readonly unresolvedDelayMs: number; readonly unresolvedCapMs: number; readonly recoveryRoundMs: number;
  readonly maxRecoveryGenerations: number; readonly maxFailures: number; readonly voidedIntervalMs: number; readonly voidedLookbackMs: number;
  readonly retry: RetryPolicy;
}
const hour = 3600000, day = 24 * hour;
export const defaultMaintenancePolicy: MaintenancePolicy = Object.freeze({
  pageSize: 50, runBudgetMs: 60000,
  leaseMs: 120000, ioTimeoutMs: 30000, activeIntervalMs: day, spread: 0.2, transientDelayMs: 300000,
  unresolvedDelayMs: 1800000, unresolvedCapMs: day, recoveryRoundMs: hour, maxRecoveryGenerations: 3,
  maxFailures: 8, voidedIntervalMs: 6 * hour, voidedLookbackMs: 30 * day, retry: defaultRetryPolicy
});
export function validatePolicy(p: MaintenancePolicy) {
  beginAttempt({ generation: 1, generationAttempts: 0, totalAttempts: 0 }, p.retry);
  for (const [k, v] of Object.entries(p)) if (k !== 'retry' && k !== 'spread' && (!Number.isSafeInteger(v) || v <= 0)) throw new Error('invalidMaintenancePolicy');
  if (p.pageSize > 100 || p.spread < 0 || p.spread > 0.5 || !Number.isFinite(p.spread) ||
    p.ioTimeoutMs * 3 >= p.leaseMs || p.voidedLookbackMs > 30 * day || p.unresolvedCapMs < p.unresolvedDelayMs) throw new Error('invalidMaintenancePolicy');
}
export function nextActiveCheck(now: number, rng: () => number, p = defaultMaintenancePolicy): number {
  const r = rng(); if (!Number.isFinite(r) || r < 0 || r >= 1) throw new Error('invalidRandom');
  return now + Math.floor(p.activeIntervalMs * (1 - p.spread + 2 * p.spread * r));
}
export function nextFailure(now: number, failures: number, p = defaultMaintenancePolicy): number {
  return now + Math.min(p.unresolvedCapMs, p.transientDelayMs * 2 ** Math.min(Math.max(0, failures - 1), 30));
}
export function voidedWindow(now: number, p = defaultMaintenancePolicy) { return { startMs: Math.max(0, now - p.voidedLookbackMs), endMs: now }; }
/** Current ledger has no trusted purchase-completion timestamp. Unknown stays
 * unknown; verifiedAt is NOT purchase time. Future adapter may supply proof. */
export function ackDeadline(completedAtMs: number | null): number | null { return completedAtMs === null ? null : completedAtMs + 3 * day; }
export async function bounded<T>(call: (signal: AbortSignal) => Promise<T>, timeoutMs: number): Promise<T> {
  const controller = new AbortController(); let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([call(controller.signal), new Promise<never>((_, reject) => {
      timer = setTimeout(() => { controller.abort(); reject(new Error('dependencyTimeout')); }, timeoutMs);
    })]);
  } finally { if (timer) clearTimeout(timer); }
}
