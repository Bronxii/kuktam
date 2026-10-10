/** Structured local-domain failures; never include token/UID/SDK messages. */
export class LifecycleError extends Error {
  constructor(readonly code: 'invalidSchema' | 'unsupportedSchema' | 'internalConflict' | 'accountInactive' | 'bindingConflict' | 'invalidTransition' | 'accountDeleting' | 'accountDeleted' | 'staleAccountGeneration' | 'staleLifecycleRevision' | 'verificationRejected') { super(code); }
}
export function record(v: unknown): Record<string, unknown> {
  if (!v || typeof v !== 'object' || Array.isArray(v)) throw new LifecycleError('invalidSchema');
  return v as Record<string, unknown>;
}
export function exact(v: Record<string, unknown>, fields: readonly string[]) {
  if (Object.keys(v).length !== fields.length || fields.some(k => !(k in v))) throw new LifecycleError('invalidSchema');
}
export function positive(v: unknown): v is number { return Number.isSafeInteger(v) && (v as number) > 0; }
