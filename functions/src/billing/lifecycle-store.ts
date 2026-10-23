import { assertNoCommittedJoin, assertNoActiveFamilyDeletion, blockingJoin } from '../households/join-capacity';
import { cleanupPrivateHousehold } from '../households/household-store';
import { workId as shoppingWorkId } from '../shopping/mutation-store';
import { readDeletion, AuthUserDeletionApi, DeletionPolicy, defaultDeletionPolicy, validateDeletionPolicy } from '../accounts/deletion-contract';
import { advanceAccount } from '../accounts/account-lifecycle';
import { workKey } from '../jobs/maintenance-store';
import { randomUUID } from 'node:crypto';
import { Transaction } from 'firebase-admin/firestore';
import { AckState, parseAckState } from './acknowledgment-state';
import { AckFailure, AcknowledgmentError } from './play-acknowledgment-api';
import { RetryPolicy, beginAttempt, retryAt, newRecoveryGeneration } from './retry-policy';
export type AckResult = { readonly status: 'acknowledged' | 'busy' | 'deferred' | 'acknowledgmentRetry' | 'acknowledgmentFailed' | 'acknowledgmentExhausted' | 'stale'; readonly failure?: AckFailure; readonly reason?: string };
export interface AckClaim { readonly hash: string; readonly uid: string; readonly token: string; readonly leaseId: string; readonly recoveryGeneration: number; readonly accountGeneration: number; readonly lifecycleRevision: number; }
import { Firestore, Timestamp } from 'firebase-admin/firestore';
import { AuthContext, authenticatedUid } from './account-binding';
import { readAccount } from '../accounts/account-lifecycle';
import { readBinding, bindingVersion } from '../accounts/binding-registry';
import { LifecycleError } from './lifecycle-error';
import { readPurchase, readEffective, PurchaseV2 } from './schema-v2';
import { decideTransition } from './purchase-lifecycle';
import { PACKAGE_NAME, PRODUCT_ID, parsePlayPurchase } from './play-purchase-api';
import { tokenHash, playGrantId } from './purchase-identity';
import { effectiveUpdate } from './effective-update';
import { parseVoidedObservation, RevokeResult } from './voided-purchase-api';
import { readInbox } from './rtdn/inbox-store';
import { compareTime, parseGrant } from '../models';

export interface CommitObservation {
  /** Trusted adapter observation, never client purchase JSON. */
  readonly purchase: unknown;
  /** Server-resolved local binding for an already recovered ledger only. */
  readonly recoveredBinding?: string;
  readonly expectedLifecycleRevision: number;
  readonly expectedAccountGeneration: number;
  readonly ackRecovery?: { readonly maxGenerations: number; readonly cooldownMs: number; readonly policy: RetryPolicy };
}
export type CommitResult = { readonly outcome: 'stale' | 'rejected'; readonly reason: string } |
  { readonly outcome: 'committed'; readonly lifecycleRevision: number; readonly granted: boolean };

/** Single purchase writer for verification and acknowledgment.
 * All future grant writers must read the account marker and use this contract. */
export class LifecycleStore {
  constructor(private readonly db: Firestore, private readonly clock: () => Timestamp = Timestamp.now,
    private readonly writeGuard?: (tx: Transaction) => Promise<void>) {}
  async commit(context: AuthContext, input: CommitObservation): Promise<CommitResult> {
    const uid = authenticatedUid(context);
    if (!Number.isSafeInteger(input.expectedLifecycleRevision) || input.expectedLifecycleRevision < 0 ||
      !Number.isSafeInteger(input.expectedAccountGeneration) || input.expectedAccountGeneration < 1) throw new LifecycleError('invalidTransition');
    const play = parsePlayPurchase(input.purchase);
    if (play.packageName !== PACKAGE_NAME || play.productId !== PRODUCT_ID || (!play.obfuscatedExternalAccountId && !input.recoveredBinding)) throw new LifecycleError('bindingConflict');
    const opaque = input.recoveredBinding ?? play.obfuscatedExternalAccountId!, keyVersion = bindingVersion(opaque);
    const hash = tokenHash(play.purchaseToken), ledgerRef = this.db.doc(`billingPurchases/${hash}`);
    const grantsRef = this.db.collection(`users/${uid}/entitlementGrants`), grantRef = grantsRef.doc(playGrantId(hash));
    const effectiveRef = this.db.doc(`users/${uid}/entitlements/pro`);
    try {
      return await this.db.runTransaction(async tx => {
        await this.writeGuard?.(tx);
        const marker = await tx.get(this.db.doc(`accountLifecycle/${uid}`));
        if (!marker.exists) throw new LifecycleError('accountInactive');
        const account = readAccount(marker.data());
        const ledgerDoc = await tx.get(ledgerRef), bindingDoc = await tx.get(this.db.doc(`billingAccountBindings/${opaque}`));
        const current = ledgerDoc.exists ? readPurchase(ledgerDoc.data()) : null;
        if (input.recoveredBinding && (current?.bindingState !== 'BOUND' || !current.recoveredFromDeletion || current.accountBinding !== input.recoveredBinding)) throw new LifecycleError('bindingConflict');
        // Terminal/stale decision precedes owner resolution: retired rows omit UID.
        const observation = play.purchaseState === 'CANCELED' ? 'terminalInvalid' : play.purchaseState === 'PENDING' ? 'pending' :
          play.acknowledgementState === 'ACKNOWLEDGED' ? 'acknowledged' : 'purchased';
        const decision = decideTransition(current, observation, account, input.expectedLifecycleRevision, input.expectedAccountGeneration);
        if ('reason' in decision) return decision;
        if (!bindingDoc.exists) throw new LifecycleError('bindingConflict');
        const binding = readBinding(bindingDoc.data());
        if (binding.state !== 'ACTIVE' || binding.uid !== uid || binding.keyVersion !== keyVersion) throw new LifecycleError('bindingConflict');
        if (current && (current.bindingState !== 'BOUND' || current.boundUid !== uid || current.accountBinding !== opaque ||
          current.purchaseToken !== play.purchaseToken || current.packageName !== PACKAGE_NAME || current.productId !== PRODUCT_ID ||
          current.testPurchase !== play.testPurchase || current.accountGeneration !== null && current.accountGeneration !== account.generation ||
          current.bindingKeyVersion !== null && current.bindingKeyVersion !== keyVersion)) throw new LifecycleError('bindingConflict');
        const now = this.clock();
        const ledger = readPurchase(current ? { ...current, schemaVersion: 2, lifecycleRevision: decision.lifecycleRevision,
          purchaseState: decision.purchaseState, acknowledgementState: decision.acknowledgementState,
          accountGeneration: account.generation, bindingKeyVersion: keyVersion, lastCheckedAt: now,
          operationalError: null, verifiedAt: now, updatedAt: now } : {
          schemaVersion: 2, lifecycleRevision: decision.lifecycleRevision, packageName: PACKAGE_NAME, productId: PRODUCT_ID,
          purchaseToken: play.purchaseToken, boundUid: uid, accountBinding: opaque, bindingState: 'BOUND',
          purchaseState: decision.purchaseState, acknowledgementState: decision.acknowledgementState,
          verifiedAt: now, updatedAt: now, revokedAt: null, revokeReason: null, testPurchase: play.testPurchase,
          lastCheckedAt: now, nextCheckAt: null, operationalError: null, accountGeneration: account.generation, bindingKeyVersion: keyVersion });
        if (decision.grantRequired) {
          const grantDocs = await tx.get(grantsRef), effectiveDoc = await tx.get(effectiveRef);
          const grants = grantDocs.docs.map(d => parseGrant(d.data()));
          const index = grantDocs.docs.findIndex(d => d.id === grantRef.id), priorGrant = index < 0 ? undefined : grants[index];
          if (priorGrant && (priorGrant.source !== 'PLAY_PURCHASE' || priorGrant.sourceRef !== hash || priorGrant.status !== 'ACTIVE' ||
            priorGrant.revokedAt !== null || priorGrant.expiresAt !== null || compareTime(priorGrant.startsAt, now) > 0)) throw new LifecycleError('internalConflict');
          const grant = priorGrant ?? parseGrant({ source: 'PLAY_PURCHASE', sourceRef: hash, status: 'ACTIVE', startsAt: now,
            createdAt: now, expiresAt: null, revokedAt: null });
          if (!priorGrant) grants.push(grant);
          const prior = effectiveDoc.exists ? readEffective(effectiveDoc.data()) : null;
          const next = effectiveUpdate(grants, now, prior);
          const ackRef = ledgerRef.collection('acknowledgment').doc('state');
          const ackDoc = input.ackRecovery ? await tx.get(ackRef) : null;
          const ack = ackDoc?.exists ? parseAckState(ackDoc.data()) : null;
          if (ack?.status === 'acknowledgmentExhausted' && input.ackRecovery &&
            play.acknowledgementState === 'PENDING' && ack.recoveryGeneration < input.ackRecovery.maxGenerations &&
            ack.lastAttemptAt.toMillis() + input.ackRecovery.cooldownMs <= now.toMillis()) {
            // Fresh verified purchase and recovery are committed together. Legacy
            // exhausted budgets may differ from the current configured budget.
            const progress = newRecoveryGeneration({ generation: ack.recoveryGeneration,
              generationAttempts: ack.attemptCount, totalAttempts: ack.totalAttempts }, ack.recoveryGeneration,
              { ...input.ackRecovery.policy, attemptsPerGeneration: ack.attemptCount });
            tx.set(ackRef, parseAckState({ ...ack,status:'acknowledgmentReady',attemptCount:0,
              recoveryGeneration:progress.generation,totalAttempts:progress.totalAttempts,leaseId:null,leaseUntil:null,
              nextRetryAt:null,failure:null,accountGeneration:account.generation,lifecycleRevision:ledger.lifecycleRevision }));
          }
          if (!priorGrant) tx.create(grantRef, grant);
          if (next) {
            if (effectiveDoc.exists) tx.update(effectiveRef, next); else tx.create(effectiveRef, next);
          }
        }
        // Validated full known schema, field update preserves delivery subdocuments.
        if (ledgerDoc.exists) tx.update(ledgerRef, { ...ledger }); else tx.create(ledgerRef, ledger);
        return { outcome: 'committed', lifecycleRevision: ledger.lifecycleRevision, granted: decision.grantRequired };
      });
    } catch (e) { if (e instanceof LifecycleError) throw e; throw new LifecycleError('internalConflict'); }
  }
  /** Explicit Restore only. Fresh Play evidence is mandatory; transaction CAS
   * elects one new owner. The original Play opaque ID is never rebound. */
  async recoverDeleted(context: AuthContext, input: CommitObservation, localBinding: string): Promise<CommitResult> {
    const uid = authenticatedUid(context), play = parsePlayPurchase(input.purchase);
    if (play.packageName !== PACKAGE_NAME || play.productId !== PRODUCT_ID || play.purchaseState !== 'PURCHASED') throw new LifecycleError('verificationRejected');
    const hash = tokenHash(play.purchaseToken), keyVersion = bindingVersion(localBinding);
    return this.db.runTransaction(async tx => {
      await this.writeGuard?.(tx);
      const ref = this.db.doc(`billingPurchases/${hash}`), marker = this.db.doc(`accountLifecycle/${uid}`);
      const ledgerDoc = await tx.get(ref), markerDoc = await tx.get(marker);
      const registry = await tx.get(this.db.doc(`billingAccountBindings/${localBinding}`));
      if (!ledgerDoc.exists || !markerDoc.exists || !registry.exists) throw new LifecycleError('bindingConflict');
      const old = readPurchase(ledgerDoc.data()), account = readAccount(markerDoc.data()), binding = readBinding(registry.data());
      if (old.bindingState !== 'ACCOUNT_DELETED' || old.lifecycleRevision !== input.expectedLifecycleRevision ||
          old.revokedAt !== null || old.purchaseState === 'CANCELED' || old.packageName !== PACKAGE_NAME || old.productId !== PRODUCT_ID || old.testPurchase !== play.testPurchase ||
          account.state !== 'ACTIVE' || account.generation !== input.expectedAccountGeneration ||
          binding.state !== 'ACTIVE' || binding.uid !== uid || binding.keyVersion !== keyVersion) throw new LifecycleError('bindingConflict');
      if (old.acknowledgementState === 'ACKNOWLEDGED' && play.acknowledgementState !== 'ACKNOWLEDGED') throw new LifecycleError('verificationRejected');
      const grantsRef = this.db.collection(`users/${uid}/entitlementGrants`), effectiveRef = this.db.doc(`users/${uid}/entitlements/pro`);
      const grantsDoc = await tx.get(grantsRef), effectiveDoc = await tx.get(effectiveRef);
      const grantRef = grantsRef.doc(playGrantId(hash));
      if (grantsDoc.docs.some(d => d.id === grantRef.id)) throw new LifecycleError('bindingConflict');
      const now = this.clock();
      const grant = parseGrant({source:'PLAY_PURCHASE',sourceRef:hash,status:'ACTIVE',startsAt:now,createdAt:now,expiresAt:null,revokedAt:null});
      const next = effectiveUpdate([...grantsDoc.docs.map(d => parseGrant(d.data())),grant],now,effectiveDoc.exists ? readEffective(effectiveDoc.data()) : null);
      const {reconciliationRequired: unusedReconciliation, ...base} = old;
      const ledger = readPurchase({...base,bindingState:'BOUND',recoveredFromDeletion:true,purchaseToken:play.purchaseToken,boundUid:uid,accountBinding:localBinding,
        purchaseState:'PURCHASED',acknowledgementState:play.acknowledgementState,lifecycleRevision:old.lifecycleRevision+1,
        accountGeneration:account.generation,bindingKeyVersion:keyVersion,lastCheckedAt:now,nextCheckAt:null,operationalError:null,verifiedAt:now,updatedAt:now});
      // Full replacement drops retired-only state; never reuse the old UID.
      tx.set(ref, ledger);
      tx.create(grantRef,grant);
      if(next) tx.set(effectiveRef,next);
      return {outcome:'committed',lifecycleRevision:ledger.lifecycleRevision,granted:true};
    });
  }
  /** Server-only trusted observation. All terminal purchase/grant/effective writes
   * share this transaction with the existing verification/ack writer. */
  async commitVoided(uid: string, input: CommitObservation): Promise<RevokeResult> {
    const play = parseVoidedObservation(input.purchase);
    if (!uid || uid.includes('/') || !play.authoritative ||
      !['entitlementRevoked','pendingCanceled'].includes(play.state) ||
      play.packageName !== PACKAGE_NAME || play.productId !== PRODUCT_ID ||
      !Number.isSafeInteger(input.expectedLifecycleRevision) || input.expectedLifecycleRevision < 1 ||
      !Number.isSafeInteger(input.expectedAccountGeneration) || input.expectedAccountGeneration < 1) {
      return { outcome: 'lifecycleConflict' };
    }
    const hash = tokenHash(play.purchaseToken), ref = this.db.doc(`billingPurchases/${hash}`);
    try {
      return await this.db.runTransaction(async tx => {
        await this.writeGuard?.(tx);
        const doc = await tx.get(ref), marker = await tx.get(this.db.doc(`accountLifecycle/${uid}`));
        if (!doc.exists || !marker.exists) return { outcome: 'lifecycleConflict' };
        const current = readPurchase(doc.data()), account = readAccount(marker.data());
        if (current.bindingState !== 'BOUND' || current.boundUid !== uid || current.purchaseToken !== play.purchaseToken ||
          current.packageName !== PACKAGE_NAME || current.productId !== PRODUCT_ID || current.testPurchase !== play.testPurchase) {
          return { outcome: 'lifecycleConflict' };
        }
        const decision = decideTransition(current, play.state === 'entitlementRevoked' ? 'entitlementRevoked' : 'pendingCanceled',
          account, input.expectedLifecycleRevision, input.expectedAccountGeneration);
        if ('reason' in decision) return { outcome: decision.outcome === 'stale' ? 'staleObservation' : 'lifecycleConflict', reason: decision.reason };
        if (decision.outcome === 'noop') return { outcome: 'revokeAlreadyApplied' };
        const grantsRef = this.db.collection(`users/${uid}/entitlementGrants`), grantRef = grantsRef.doc(playGrantId(hash));
        const effectiveRef = this.db.doc(`users/${uid}/entitlements/pro`), ackRef = ref.collection('acknowledgment').doc('state');
        const grantsDoc = await tx.get(grantsRef), effectiveDoc = await tx.get(effectiveRef), ackDoc = await tx.get(ackRef);
        const grants = grantsDoc.docs.map(d => parseGrant(d.data()));
        const index = grantsDoc.docs.findIndex(d => d.id === grantRef.id), priorGrant = index < 0 ? null : grants[index]!;
        if (priorGrant && (priorGrant.source !== 'PLAY_PURCHASE' || priorGrant.sourceRef !== hash || play.state === 'pendingCanceled')) {
          return { outcome: 'lifecycleConflict' };
        }
        const now = this.clock(), reason = play.state === 'entitlementRevoked' ? 'ENTITLEMENT_REVOKED' : 'PENDING_CANCELED';
        const revoked = priorGrant ? parseGrant({ ...priorGrant, status: 'REVOKED', revokedAt: priorGrant.revokedAt ?? now, reasonCode: reason }) : null;
        if (revoked) grants[index] = revoked;
        // A never-purchased cancellation must not create an artificial entitlement.
        const next = play.state === 'pendingCanceled' ? null : effectiveUpdate(grants, now,
          effectiveDoc.exists ? readEffective(effectiveDoc.data()) : null, account.state === 'ACTIVE');
        const ack = ackDoc.exists ? parseAckState(ackDoc.data()) : null;
        const ledger = readPurchase({ ...current, purchaseState: decision.purchaseState,
          lifecycleRevision: decision.lifecycleRevision, revokedAt: play.state === 'entitlementRevoked' ? now : null,
          revokeReason: reason, updatedAt: now, lastCheckedAt: now, nextCheckAt: null, operationalError: null,
          accountGeneration: account.generation, bindingKeyVersion: bindingVersion(current.accountBinding) });
        // Owner/token retained for later retention coordination; no user data cleanup.
        tx.update(ref, { ...ledger });
        if (revoked) tx.update(grantRef, { ...revoked });
        if (next) { if (effectiveDoc.exists) tx.update(effectiveRef, { ...next }); else tx.create(effectiveRef, next); }
        if (ack && ack.status !== 'acknowledged' && ack.status !== 'acknowledgmentCanceled') {
          tx.set(ackRef, parseAckState({ ...ack, status: 'acknowledgmentCanceled', leaseId: null,
            leaseUntil: null, nextRetryAt: null, failure: null }));
        }
        return { outcome: play.state === 'entitlementRevoked' ? 'purchaseRevoked' : 'pendingCanceled' };
      });
    } catch { return { outcome: 'lifecycleConflict' }; }
  }
  /** Operative timestamps/errors do not change the purchase lifecycle revision.
   * CAS on account + lifecycle is required even for future worker metadata writes. */
  async recordCheck(context: AuthContext, hash: string, expectedRevision: number, expectedGeneration: number,
    nextCheckAt: Timestamp | null, error: PurchaseV2['operationalError']): Promise<boolean> {
    const uid = authenticatedUid(context); if (!/^[a-f0-9]{64}$/.test(hash)) throw new LifecycleError('invalidTransition');
    return this.db.runTransaction(async tx => {
      await this.writeGuard?.(tx);
      const marker = await tx.get(this.db.doc(`accountLifecycle/${uid}`)), ref = this.db.doc(`billingPurchases/${hash}`), doc = await tx.get(ref);
      if (!marker.exists || !doc.exists) return false;
      const account = readAccount(marker.data()), ledger = readPurchase(doc.data());
      if (ledger.revokedAt !== null || ledger.purchaseState === 'CANCELED' || account.state !== 'ACTIVE' || account.generation !== expectedGeneration || ledger.lifecycleRevision !== expectedRevision ||
        ledger.bindingState !== 'BOUND' || ledger.boundUid !== uid) return false;
      const now = this.clock();
      readPurchase({ ...ledger, lastCheckedAt: now, nextCheckAt, operationalError: error });
      // Explicit v1-to-v2 normalization only when this operation is requested.
      tx.update(ref, { ...ledger, lastCheckedAt: now, nextCheckAt, operationalError: error }); return true;
    });
  }

  /** Boundary maintenance uses the same effective writer, with account fencing.
   * Bounded grant read fails closed rather than partially aggregating large sets. */
  async recomputeGrants(uid: string, expectedGeneration: number): Promise<number | null> {
    authenticatedUid({uid});
    return this.db.runTransaction(async tx => {
      await this.writeGuard?.(tx);
      const marker = await tx.get(this.db.doc(`accountLifecycle/${uid}`));
      if (!marker.exists) throw new LifecycleError('accountInactive');
      const account = readAccount(marker.data());
      if (account.state !== 'ACTIVE' || account.generation !== expectedGeneration) throw new LifecycleError('staleAccountGeneration');
      const docs = await tx.get(this.db.collection(`users/${uid}/entitlementGrants`).limit(501));
      if (docs.size > 500) throw new LifecycleError('internalConflict');
      const ref = this.db.doc(`users/${uid}/entitlements/pro`), doc = await tx.get(ref), now = this.clock();
      const grants = docs.docs.map(d => parseGrant(d.data()));
      const next = effectiveUpdate(grants,now,doc.exists ? readEffective(doc.data()) : null);
      const boundaries = grants.filter(g => g.status === 'ACTIVE' && !g.revokedAt)
        .flatMap(g => [g.startsAt,g.expiresAt]).filter((t): t is Timestamp => t !== null && compareTime(t,now) > 0);
      if (next) { if (doc.exists) tx.update(ref,{...next}); else tx.create(ref,next); }
      return boundaries.length ? Math.min(...boundaries.map(t => t.seconds * 1000 + Math.ceil(t.nanoseconds / 1000000))) : null;
    });
  }
  private async ackContext(tx: Transaction, hash: string) {
    const ref = this.db.doc(`billingPurchases/${hash}`), doc = await tx.get(ref);
    if (!doc.exists) throw new AcknowledgmentError('invalidLifecycleTransition');
    const ledger = readPurchase(doc.data());
    if (ledger.bindingState !== 'BOUND' || ledger.purchaseState !== 'PURCHASED' || ledger.revokedAt !== null ||
      ledger.packageName !== PACKAGE_NAME || ledger.productId !== PRODUCT_ID || tokenHash(ledger.purchaseToken) !== hash) throw new AcknowledgmentError('invalidLifecycleTransition');
    const marker = await tx.get(this.db.doc(`accountLifecycle/${ledger.boundUid}`));
    if (!marker.exists) throw new AcknowledgmentError('invalidLifecycleTransition');
    const account = readAccount(marker.data());
    if (account.state !== 'ACTIVE') throw new LifecycleError(account.state === 'DELETING' ? 'accountDeleting' : 'accountDeleted');
    if (ledger.accountGeneration !== null && ledger.accountGeneration !== account.generation) throw new LifecycleError('staleAccountGeneration');
    const bindingDoc = await tx.get(this.db.doc(`billingAccountBindings/${ledger.accountBinding}`));
    if (!bindingDoc.exists) throw new LifecycleError('bindingConflict');
    const binding = readBinding(bindingDoc.data());
    if (binding.state !== 'ACTIVE' || binding.uid !== ledger.boundUid || binding.keyVersion !== bindingVersion(ledger.accountBinding) ||
      ledger.bindingKeyVersion !== null && ledger.bindingKeyVersion !== binding.keyVersion) throw new LifecycleError('bindingConflict');
    const grantDoc = await tx.get(this.db.doc(`users/${ledger.boundUid}/entitlementGrants/${playGrantId(hash)}`));
    const effectiveDoc = await tx.get(this.db.doc(`users/${ledger.boundUid}/entitlements/pro`));
    if (!grantDoc.exists || !effectiveDoc.exists) throw new AcknowledgmentError('invalidLifecycleTransition');
    const grant = parseGrant(grantDoc.data()), effective = readEffective(effectiveDoc.data());
    if (grant.source !== 'PLAY_PURCHASE' || grant.sourceRef !== hash || grant.status !== 'ACTIVE' || grant.revokedAt !== null ||
      grant.expiresAt !== null || compareTime(grant.startsAt, this.clock()) > 0 || !effective.active || effective.validUntil !== null ||
      !effective.sources.includes('PLAY_PURCHASE')) throw new AcknowledgmentError('invalidLifecycleTransition');
    return { ref, ledger, account, binding };
  }

  async claimAck(hash: string, policy: RetryPolicy): Promise<{ result: AckResult } | { claim: AckClaim }> {
    if (!/^[a-f0-9]{64}$/.test(hash)) throw new AcknowledgmentError('invalidLifecycleTransition');
    const leaseId = randomUUID();
    return this.db.runTransaction(async tx => {
      await this.writeGuard?.(tx);
      const { ref, ledger, account, binding } = await this.ackContext(tx, hash);
      const stateRef = ref.collection('acknowledgment').doc('state'), stateDoc = await tx.get(stateRef);
      const state = stateDoc.exists ? parseAckState(stateDoc.data()) : null, now = this.clock();
      const completed = (s: AckState) => parseAckState({ ...s, status: 'acknowledged', leaseId: null, leaseUntil: null, nextRetryAt: null, failure: null });
      if (ledger.acknowledgementState === 'ACKNOWLEDGED') {
        if (state && state.status !== 'acknowledged') tx.set(stateRef, completed(state));
        return { result: { status: 'acknowledged' } };
      }
      if (state?.status === 'acknowledged' || state?.status === 'acknowledgmentCanceled') throw new AcknowledgmentError('internalConflict');
      if (state?.status === 'acknowledgmentFailed' || state?.status === 'acknowledgmentExhausted') return { result: { status: state.status, failure: state.failure! } };
      if (state?.leaseUntil && compareTime(now, state.leaseUntil) < 0) return { result: { status: 'busy' } };
      if (state?.nextRetryAt && compareTime(now, state.nextRetryAt) < 0) return { result: { status: 'deferred' } };
      const progress = { generation: state?.recoveryGeneration ?? 1, generationAttempts: state?.attemptCount ?? 0, totalAttempts: state?.totalAttempts ?? 0 };
      // Old records may already exceed a newly configured generation budget.
      const attempt = progress.generationAttempts >= policy.attemptsPerGeneration ? null : beginAttempt(progress, policy);
      if (!attempt) {
        tx.set(stateRef, parseAckState({ ...state!, status: 'acknowledgmentExhausted', leaseId: null, leaseUntil: null, nextRetryAt: null,
          failure: state!.failure ?? 'acknowledgmentTemporaryFailure' }));
        return { result: { status: 'acknowledgmentExhausted', failure: state!.failure ?? 'acknowledgmentTemporaryFailure' } };
      }
      const next = parseAckState({ schemaVersion: 2, status: 'acknowledgmentPending', attemptCount: attempt.generationAttempts,
        totalAttempts: attempt.totalAttempts, recoveryGeneration: attempt.generation,
        accountGeneration: account.generation, lifecycleRevision: ledger.lifecycleRevision,
        lastAttemptAt: now, leaseId, leaseUntil: Timestamp.fromMillis(now.toMillis() + policy.leaseMs), nextRetryAt: null, failure: null });
      const normalized = readPurchase({ ...ledger, accountGeneration: account.generation, bindingKeyVersion: binding.keyVersion });
      // Explicit legacy adoption; operational claim does not increment lifecycleRevision.
      tx.update(ref, { ...normalized }); tx.set(stateRef, next);
      return { claim: { hash, uid: ledger.boundUid, token: ledger.purchaseToken, leaseId,
        recoveryGeneration: next.recoveryGeneration, accountGeneration: account.generation, lifecycleRevision: ledger.lifecycleRevision } };
    });
  }

  async completeAck(claim: AckClaim, failure: AckFailure | null, policy: RetryPolicy, random: () => number): Promise<AckResult> {
    // Sample once per logical completion, not again on Firestore transaction retry.
    const sample = random();
    return this.db.runTransaction(async tx => {
      await this.writeGuard?.(tx);
      const ref = this.db.doc(`billingPurchases/${claim.hash}`), stateRef = ref.collection('acknowledgment').doc('state');
      const stateDoc = await tx.get(stateRef);
      if (!stateDoc.exists) throw new AcknowledgmentError('internalConflict');
      const state = parseAckState(stateDoc.data());
      if (state.status !== 'acknowledgmentPending' || state.leaseId !== claim.leaseId || state.recoveryGeneration !== claim.recoveryGeneration ||
        state.accountGeneration !== claim.accountGeneration || state.lifecycleRevision !== claim.lifecycleRevision) return { status: 'stale', reason: 'claimChanged' };
      const marker = await tx.get(this.db.doc(`accountLifecycle/${claim.uid}`));
      if (!marker.exists) return { status: 'stale', reason: 'staleAccountGeneration' };
      const account = readAccount(marker.data());
      if (account.state !== 'ACTIVE' || account.generation !== claim.accountGeneration) return { status: 'stale', reason: 'staleAccountGeneration' };
      const doc = await tx.get(ref); if (!doc.exists) return { status: 'stale', reason: 'staleLifecycleRevision' };
      const ledger = readPurchase(doc.data());
      if (ledger.lifecycleRevision !== claim.lifecycleRevision || ledger.bindingState !== 'BOUND' || ledger.boundUid !== claim.uid ||
        ledger.revokedAt !== null || ledger.purchaseState !== 'PURCHASED' || ledger.acknowledgementState !== 'PENDING') return { status: 'stale', reason: 'staleLifecycleRevision' };
      // Validate current durable grant/effective/registry again, not only the lease.
      await this.ackContext(tx, claim.hash);
      const now = this.clock();
      if (!state.leaseUntil || compareTime(state.leaseUntil, now) <= 0) return { status: 'stale', reason: 'leaseExpired' };
      if (failure === null) {
        const decision = decideTransition(ledger, 'acknowledged', account, claim.lifecycleRevision, claim.accountGeneration);
        if ('reason' in decision) return { status: 'stale', reason: decision.reason };
        tx.update(ref, { acknowledgementState: decision.acknowledgementState, lifecycleRevision: decision.lifecycleRevision, updatedAt: now });
        tx.set(stateRef, parseAckState({ ...state, status: 'acknowledged', leaseId: null, leaseUntil: null, nextRetryAt: null, failure: null }));
        return { status: 'acknowledged' };
      }
      const exhausted = state.attemptCount >= policy.attemptsPerGeneration;
      const permanent = failure === 'acknowledgmentPermanentFailure';
      const nextMs = permanent || exhausted ? null : retryAt({ generation: state.recoveryGeneration,
        generationAttempts: state.attemptCount, totalAttempts: state.totalAttempts }, now.seconds * 1000 + Math.ceil(now.nanoseconds / 1000000), () => sample, policy);
      const status = permanent ? 'acknowledgmentFailed' : exhausted ? 'acknowledgmentExhausted' : 'acknowledgmentRetry';
      tx.set(stateRef, parseAckState({ ...state, status, leaseId: null, leaseUntil: null,
        nextRetryAt: nextMs === null ? null : Timestamp.fromMillis(nextMs), failure }));
      return { status, failure };
    });
  }

  async advanceAccountMarker(context: AuthContext, expectedGeneration: number, target: 'ACTIVE'|'DELETING'|'DELETED') {
    const uid = authenticatedUid(context);
    return this.db.runTransaction(async tx => {
      const ref = this.db.doc(`accountLifecycle/${uid}`), effectiveRef = this.db.doc(`users/${uid}/entitlements/pro`);
      const doc = await tx.get(ref), effectiveDoc = await tx.get(effectiveRef);
      if (!doc.exists) throw new LifecycleError('accountInactive');
      const current = readAccount(doc.data()), now = this.clock();
      if(target!=='ACTIVE')await assertNoCommittedJoin(this.db,tx,uid);
      const next = advanceAccount(current, target, expectedGeneration, now);
      const effective = next.state === 'ACTIVE' ? null : effectiveUpdate([], now, effectiveDoc.exists ? readEffective(effectiveDoc.data()) : null, false);
      if(next !== current) tx.update(ref, {...next});
      if(effective) tx.set(effectiveRef, effective);
      return next;
    });
  }

  /** Durable account barrier and immediate access shutdown in one transaction. */
  async beginDeletion(uid:string,authGone=false) {
    authenticatedUid({uid});
    return this.db.runTransaction(async tx=>{
      const markerRef=this.db.doc(`accountLifecycle/${uid}`),jobRef=this.db.doc(`accountDeletions/${uid}`),effectiveRef=this.db.doc(`users/${uid}/entitlements/pro`);
      const markerDoc=await tx.get(markerRef),jobDoc=await tx.get(jobRef),effectiveDoc=await tx.get(effectiveRef),now=this.clock();
      const blocking=await blockingJoin(this.db,tx,uid);
      if(!blocking&&!authGone)await assertNoActiveFamilyDeletion(this.db,tx,uid);
      if(blocking){
        if(!authGone)throw new Error('JOIN_COMMITTED_IN_PROGRESS');
        tx.update(this.db.doc(`familyOperations/${blocking}`),{status:'OPERATOR',nextAt:null,leaseId:null,leaseUntil:null,lastOutcome:'externalAuthDeletion',updatedAt:now});
        // Auth is already gone: retain the JOIN lock, but preserve the existing
        // DELETING access barrier/job below. Shared cleanup still fails closed.
      }
      const old=markerDoc.exists?readAccount(markerDoc.data()):null;
      if(old?.state==='DELETED' && jobDoc.exists && readDeletion(jobDoc.data()).stage==='DONE')return {outcome:'alreadyDeleted' as const};
      const account=old && old.state!=='ACTIVE'?old:old?advanceAccount(old,'DELETING',old.generation,now):readAccount({schemaVersion:1,state:'DELETING',generation:1,updatedAt:now,deletionStartedAt:now,deletedAt:null});
      const prior=jobDoc.exists?readDeletion(jobDoc.data()):null;
      if(prior && (prior.generation!==account.generation||prior.stage==='DONE'))throw new LifecycleError('internalConflict');
      const job=prior?readDeletion({...prior,authGone:prior.authGone||authGone}):readDeletion({schemaVersion:2,cleanupState:'PENDING',operationId:randomUUID(),generation:account.generation,stage:'BINDINGS_MARK',authGone,leaseId:null,leaseUntil:null,nextAt:null,lastOutcome:null,updatedAt:now});
      const effective=effectiveUpdate([],now,effectiveDoc.exists?readEffective(effectiveDoc.data()):null,false);
      if(!old||old.state==='ACTIVE')tx.set(markerRef,account);
      if(!prior||authGone&&!prior.authGone)tx.set(jobRef,job);
      if(effective)tx.set(effectiveRef,effective);
      return {outcome:prior?'deletionAlreadyInProgress' as const:'deletionStarted' as const,operationId:job.operationId};
    });
  }

  /** Admin reads, never client evidence. Root absence alone is insufficient. */
  async verifyDeletionContent(context:AuthContext):Promise<'VERIFIED'|'cleanupIncomplete'|'alreadyDeleted'> {
    const uid=authenticatedUid(context);
    return this.db.runTransaction(async tx=>{
      const marker=await tx.get(this.db.doc(`accountLifecycle/${uid}`));
      const ref=this.db.doc(`accountDeletions/${uid}`),doc=await tx.get(ref);
      if(!marker.exists||!doc.exists)throw new LifecycleError('internalConflict');
      const a=readAccount(marker.data()),j=readDeletion(doc.data());
      if(a.state==='DELETED'&&j.stage==='DONE')return 'alreadyDeleted';
      if(a.state!=='DELETING'||a.generation!==j.generation||j.authGone)throw new LifecycleError('invalidTransition');
      const root=await tx.get(this.db.doc(`users/${uid}`));
      const recipes=await tx.get(this.db.collection(`users/${uid}/recipes`).limit(1));
      const shopping=await tx.get(this.db.collection(`users/${uid}/shopping`).limit(1));
      const mutations=await tx.get(this.db.collection(`users/${uid}/shoppingMutations`).limit(1));
      const mutationWork=await tx.get(this.db.collection('shoppingMutationWork').where('uid','==',uid).limit(1));
      const homes=await tx.get(this.db.collection('households').where('ownerUid','==',uid).limit(1));
      const family=await tx.get(this.db.doc(`familyMemberships/${uid}`));
      const cleanupState=root.exists||!recipes.empty||!shopping.empty||!mutations.empty||!mutationWork.empty||!homes.empty||family.exists?'PENDING':'VERIFIED';
      if(j.cleanupState!==cleanupState||doc.data()!.schemaVersion!==2)
        tx.set(ref,readDeletion({...j,cleanupState,updatedAt:this.clock()}));
      return cleanupState==='VERIFIED'?'VERIFIED':'cleanupIncomplete';
    });
  }

  /** One bounded atomic cleanup page. First remaining page prevents deletion
   * cursor skips. Account generation and stage are checked in every transaction. */
  async deletionStep(uid:string,limit:number,policy:DeletionPolicy=defaultDeletionPolicy):Promise<{kind:'continue'|'done'|'busy'|'operator'|'cleanupIncomplete'}|{kind:'auth';operationId:string;generation:number;leaseId:string}> {
    authenticatedUid({uid});validateDeletionPolicy(policy);if(!Number.isSafeInteger(limit)||limit<1||limit>100)throw new LifecycleError('invalidTransition');
    return this.db.runTransaction(async tx=>{
      const markerRef=this.db.doc(`accountLifecycle/${uid}`),jobRef=this.db.doc(`accountDeletions/${uid}`);
      const markerDoc=await tx.get(markerRef),jobDoc=await tx.get(jobRef);
      if(!markerDoc.exists||!jobDoc.exists)throw new LifecycleError('internalConflict');
      const account=readAccount(markerDoc.data()),job=readDeletion(jobDoc.data()),now=this.clock();
      if(account.state==='DELETED'&&job.stage==='DONE')return {kind:'done'};
      if(account.state==='ACTIVE'||account.generation!==job.generation)throw new LifecycleError('staleAccountGeneration');
      if (await cleanupPrivateHousehold(this.db,tx,uid,limit)) return {kind:'continue'};
      // Schema-owned content registry: extend here when new personal collections
      // are introduced. Bounded first-page deletes avoid unbounded recursiveDelete.
      const rootRef=this.db.doc(`users/${uid}`), root=await tx.get(rootRef);
      const content=[];
      for(const name of ['recipes','shopping','shoppingMutations']) {
        if(content.length===limit)break;
        content.push(...(await tx.get(rootRef.collection(name).limit(limit-content.length))).docs);
      }
      if(content.length<limit)content.push(...(await tx.get(this.db.collection('shoppingMutationWork').where('uid','==',uid).limit(limit-content.length))).docs);
      if(content.length || root.exists){
        for(const d of content){tx.delete(d.ref);if(d.ref.parent.id==='shoppingMutations')tx.delete(this.db.doc(`shoppingMutationWork/${shoppingWorkId(d.ref.path)}`));}
        if(root.exists)tx.delete(rootRef);
        tx.set(jobRef,readDeletion({...job,cleanupState:'PENDING',updatedAt:now}));
        return {kind:'continue'};
      }
      const advance=(stage:typeof job.stage)=>tx.set(jobRef,readDeletion({...job,stage,updatedAt:now,lastOutcome:null}));
      if(job.stage==='BINDINGS_MARK'){
        const page=await tx.get(this.db.collection('billingAccountBindings').where('uid','==',uid).where('state','==','ACTIVE').limit(limit));
        const rows=page.docs.map(d=>({ref:d.ref,b:readBinding(d.data()),keyVersion:bindingVersion(d.id)}));
        for(const {ref,b,keyVersion} of rows){if(keyVersion!==b.keyVersion)throw new LifecycleError('bindingConflict');if(b.state!=='ACTIVE'||b.uid!==uid)throw new LifecycleError('bindingConflict');tx.set(ref,readBinding({...b,state:'DELETING',updatedAt:now}));}
        if(page.empty)advance('GRANTS');return {kind:'continue'};
      }
      if(job.stage==='GRANTS'){
        const page=await tx.get(this.db.collection(`users/${uid}/entitlementGrants`).limit(limit));
        for(const d of page.docs) parseGrant(d.data());
        for(const d of page.docs){tx.delete(d.ref);tx.delete(this.db.doc(`billingMaintenance/${workKey('grant',d.ref.path)}`));}
        if(page.empty)advance('PURCHASES');return {kind:'continue'};
      }
      if(job.stage==='PURCHASES'){
        const page=await tx.get(this.db.collection('billingPurchases').where('boundUid','==',uid).limit(1));
        if(page.empty){advance('BINDINGS');return {kind:'continue'};}
        const doc=page.docs[0]!,p=readPurchase(doc.data());
        if(p.bindingState!=='BOUND'||p.boundUid!==uid||tokenHash(p.purchaseToken)!==doc.id||p.packageName!==PACKAGE_NAME||p.productId!==PRODUCT_ID)throw new LifecycleError('internalConflict');
        const inbox=await tx.get(this.db.collection('rtdnInbox').where('tokenHash','==',doc.id).limit(limit));
        for(const d of inbox.docs) readInbox(d.data());
        for(const d of inbox.docs)tx.delete(d.ref);
        if(!inbox.empty)return {kind:'continue'};
        const ackRef=doc.ref.collection('acknowledgment').doc('state');
        const ackDoc=await tx.get(ackRef);if(ackDoc.exists)parseAckState(ackDoc.data());
        const {purchaseToken:unusedToken,boundUid:unusedUid,accountBinding:unusedBinding,...base}=p;
        const tombstone=readPurchase({...base,schemaVersion:2,bindingState:'ACCOUNT_DELETED',reconciliationRequired:false,
          lifecycleRevision:p.lifecycleRevision+1,accountGeneration:null,bindingKeyVersion:null,lastCheckedAt:null,nextCheckAt:null,operationalError:null,updatedAt:now});
        // Intentional strict tombstone replacement purges identity/token. It never
        // fabricates a financial refund or authoritative Play revocation.
        tx.set(doc.ref,tombstone);
        tx.delete(doc.ref.collection('acknowledgment').doc('state'));
        tx.delete(this.db.doc(`billingMaintenance/${workKey('purchase',doc.id)}`));
        return {kind:'continue'};
      }
      if(job.stage==='BINDINGS'){
        const page=await tx.get(this.db.collection('billingAccountBindings').where('uid','==',uid).limit(limit));
        const rows=page.docs.map(d=>({ref:d.ref,b:readBinding(d.data()),keyVersion:bindingVersion(d.id)}));
        for(const {ref,b,keyVersion} of rows){if(keyVersion!==b.keyVersion)throw new LifecycleError('bindingConflict');if(b.state==='TOMBSTONED'||b.uid!==uid)throw new LifecycleError('bindingConflict');
          tx.set(ref,readBinding({schemaVersion:1,state:'TOMBSTONED',keyVersion:b.keyVersion,createdAt:b.createdAt,updatedAt:now}));}
        if(page.empty)advance('AUTH');return {kind:'continue'};
      }
      if(job.stage!=='AUTH')throw new LifecycleError('internalConflict');
      const remainingGrants=await tx.get(this.db.collection(`users/${uid}/entitlementGrants`).limit(1));
      if(!remainingGrants.empty){advance('GRANTS');return {kind:'continue'};}
      const entitlements=await tx.get(this.db.collection(`users/${uid}/entitlements`).limit(limit));
      const removable=entitlements.docs.filter(d=>job.authGone || d.id!=='pro');
      if(removable.length){for(const d of removable)tx.delete(d.ref);return {kind:'continue'};}
      if(job.authGone){
        tx.delete(this.db.doc(`users/${uid}/entitlements/pro`));
        const completed=account.state==='DELETED'?account:advanceAccount(account,'DELETED',account.generation,now);
        if(completed!==account)tx.set(markerRef,completed);
        tx.set(jobRef,readDeletion({...job,cleanupState:'VERIFIED',stage:'DONE',generation:completed.generation,leaseId:null,leaseUntil:null,nextAt:null,lastOutcome:null,updatedAt:now}));
        return {kind:'done'};
      }
      if(job.lastOutcome==='supportRequired')return {kind:'operator'};
      if(job.leaseUntil&&compareTime(job.leaseUntil, now) > 0||job.nextAt&&compareTime(job.nextAt, now) > 0)return {kind:'busy'};
      const leaseId=randomUUID();tx.set(jobRef,readDeletion({...job,cleanupState:'VERIFIED',leaseId,leaseUntil:Timestamp.fromMillis(now.toMillis()+policy.leaseMs),nextAt:null,updatedAt:now}));
      return {kind:'auth',operationId:job.operationId,generation:job.generation,leaseId};
    });
  }
  async completeDeletionAuth(uid:string,operationId:string,generation:number,leaseId:string,status:Awaited<ReturnType<AuthUserDeletionApi['deleteUser']>>,policy:DeletionPolicy=defaultDeletionPolicy):Promise<boolean>{
    authenticatedUid({uid});validateDeletionPolicy(policy);return this.db.runTransaction(async tx=>{
      const ref=this.db.doc(`accountDeletions/${uid}`),doc=await tx.get(ref),marker=await tx.get(this.db.doc(`accountLifecycle/${uid}`));
      if(!doc.exists||!marker.exists)return false;
      const j=readDeletion(doc.data()),a=readAccount(marker.data()),now=this.clock();
      if((!j.authGone&&j.cleanupState!=='VERIFIED')||a.state==='ACTIVE'||a.generation!==generation||j.stage!=='AUTH'||j.operationId!==operationId||j.leaseId!==leaseId||!j.leaseUntil||compareTime(j.leaseUntil, now) <= 0)return false;
      const success=status==='deleted'||status==='notFound';
      tx.set(ref,readDeletion({...j,authGone:j.authGone||success,leaseId:null,leaseUntil:null,nextAt:status==='temporaryFailure'?Timestamp.fromMillis(now.toMillis()+policy.retryMs):null,
        lastOutcome:success?null:status==='temporaryFailure'?'authDeleteRetryRequired':'supportRequired',updatedAt:now}));return true;
    });
  }
}
