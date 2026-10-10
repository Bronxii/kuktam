export interface RetryPolicy { readonly leaseMs: number; readonly ioTimeoutMs: number; readonly baseDelayMs: number; readonly capDelayMs: number; readonly attemptsPerGeneration: number; }
export const defaultRetryPolicy: RetryPolicy = Object.freeze({ leaseMs: 120000, ioTimeoutMs: 30000, baseDelayMs: 60000, capDelayMs: 21600000, attemptsPerGeneration: 8 });
export interface RetryProgress { readonly generation: number; readonly generationAttempts: number; readonly totalAttempts: number; }
function validate(p: RetryPolicy, s: RetryProgress) {
  if (![p.leaseMs, p.ioTimeoutMs, p.baseDelayMs, p.capDelayMs, p.attemptsPerGeneration].every(v => Number.isSafeInteger(v) && v > 0) ||
    p.ioTimeoutMs >= p.leaseMs || p.capDelayMs < p.baseDelayMs || !Number.isSafeInteger(s.generation) || s.generation < 1 ||
    !Number.isSafeInteger(s.generationAttempts) || s.generationAttempts < 0 || s.generationAttempts > p.attemptsPerGeneration ||
    !Number.isSafeInteger(s.totalAttempts) || s.totalAttempts < s.generationAttempts) throw new Error('invalidRetryState');
}
export function beginAttempt(state: RetryProgress, policy: RetryPolicy = defaultRetryPolicy): RetryProgress | null {
  validate(policy, state);
  if (state.generationAttempts === policy.attemptsPerGeneration) return null;
  const next = { ...state, generationAttempts: state.generationAttempts + 1, totalAttempts: state.totalAttempts + 1 };
  validate(policy, next); return Object.freeze(next);
}
/** Equal jitter, bounded below by base delay; caller injects RNG and time. */
export function retryAt(state: RetryProgress, nowMs: number, rng: () => number, policy: RetryPolicy = defaultRetryPolicy): number | null {
  validate(policy, state);
  if (!Number.isSafeInteger(nowMs) || state.generationAttempts === 0) throw new Error('invalidRetryState');
  if (state.generationAttempts >= policy.attemptsPerGeneration) return null;
  const random = rng(); if (!Number.isFinite(random) || random < 0 || random >= 1) throw new Error('invalidRandom');
  const ceiling = Math.min(policy.capDelayMs, policy.baseDelayMs * 2 ** Math.min(state.generationAttempts - 1, 52));
  return nowMs + Math.floor(Math.max(policy.baseDelayMs, ceiling / 2 + random * ceiling / 2));
}
/** Only future trusted re-verification may authorize this pure transition. */
export function newRecoveryGeneration(state: RetryProgress, expectedGeneration: number, policy: RetryPolicy = defaultRetryPolicy): RetryProgress {
  validate(policy, state);
  if (state.generation !== expectedGeneration || state.generationAttempts !== policy.attemptsPerGeneration) throw new Error('invalidRecoveryTransition');
  const next = { generation: state.generation + 1, generationAttempts: 0, totalAttempts: state.totalAttempts };
  validate(policy, next); return Object.freeze(next);
}
