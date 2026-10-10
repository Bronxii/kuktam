import { Firestore, Timestamp } from 'firebase-admin/firestore';
import { PACKAGE_NAME, PRODUCT_ID } from './play-purchase-api';
import { AckFailure, AcknowledgmentError, PlayAcknowledgmentApi } from './play-acknowledgment-api';
import { LifecycleStore, AckResult } from './lifecycle-store';
import { LifecycleError } from './lifecycle-error';
import { RetryPolicy, defaultRetryPolicy, beginAttempt } from './retry-policy';
export type { AckResult } from './lifecycle-store';
/** Orchestrates I/O only. All durable claim/completion writes use LifecycleStore. */
export class PurchaseAcknowledger {
  private readonly policy: RetryPolicy;
  constructor(db: Firestore, private readonly api: PlayAcknowledgmentApi,
    clock: () => Timestamp = Timestamp.now, policy: RetryPolicy = defaultRetryPolicy,
    private readonly random: () => number = Math.random,
    private readonly store: LifecycleStore = new LifecycleStore(db, clock)) {
    this.policy = Object.freeze({ ...policy });
    beginAttempt({ generation: 1, generationAttempts: 0, totalAttempts: 0 }, this.policy);
  }
  async run(hash: string): Promise<AckResult> {
    try {
      const acquired = await this.store.claimAck(hash, this.policy);
      if ('result' in acquired) return acquired.result;
      const claim = acquired.claim, controller = new AbortController();
      let timer: ReturnType<typeof setTimeout> | undefined;
      let failure: AckFailure | null = null;
      try {
        const timeout = new Promise<never>((_, reject) => { timer = setTimeout(() => { controller.abort(); reject(new Error('ackTimeout')); }, this.policy.ioTimeoutMs); });
        const reply = await Promise.race([this.api.acknowledge({ packageName: PACKAGE_NAME, productId: PRODUCT_ID,
          purchaseToken: claim.token }, { signal: controller.signal }), timeout]);
        const r = reply as { status?: unknown } | null;
        if (!r || typeof r !== 'object' || Object.keys(r).length !== 1 || !('status' in r)) failure = 'unexpectedResponse';
        else if (r.status === 'temporaryFailure') failure = 'acknowledgmentTemporaryFailure';
        else if (r.status === 'permanentFailure') failure = 'acknowledgmentPermanentFailure';
        else if (r.status !== 'success' && r.status !== 'alreadyAcknowledged') failure = 'unexpectedResponse';
      } catch { failure = 'acknowledgmentTemporaryFailure'; }
      finally { if (timer !== undefined) clearTimeout(timer); }
      return await this.store.completeAck(claim, failure, this.policy, this.random);
    } catch (e) {
      if (e instanceof AcknowledgmentError || e instanceof LifecycleError) throw e;
      throw new AcknowledgmentError('internalConflict');
    }
  }
}
