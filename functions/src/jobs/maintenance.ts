import { FamilyJoinStore } from '../households/family-join';
import { ShoppingMutationStore } from '../shopping/mutation-store';
import { compareTime } from '../models';
import { FamilyCreateStore } from '../households/family-create';
import { readDeletion } from '../accounts/deletion-contract';
import { Firestore, Timestamp, FieldPath, Query, QueryDocumentSnapshot } from 'firebase-admin/firestore';
import { createHash } from 'node:crypto';
import { AccountBinding } from '../billing/account-binding';
import { PlayPurchaseApi, PlayLookupError, PACKAGE_NAME } from '../billing/play-purchase-api';
import { VoidedPurchaseApi, VoidedLookupError } from '../billing/voided-purchase-api';
import { PlayAcknowledgmentApi } from '../billing/play-acknowledgment-api';
import { PurchaseVerifier } from '../billing/verify-purchase';
import { PurchaseRevoker } from '../billing/revoke-purchase';
import { PurchaseAcknowledger } from '../billing/acknowledge-purchase';
import { LifecycleStore } from '../billing/lifecycle-store';
import { LifecycleError } from '../billing/lifecycle-error';
import { VerificationError } from '../billing/errors';
import { readPurchase } from '../billing/schema-v2';
import { parseAckState } from '../billing/acknowledgment-state';
import { readAccount } from '../accounts/account-lifecycle';
import { parseGrant } from '../models';
import { RtdnInboxStore, readInbox } from '../billing/rtdn/inbox-store';
import { RtdnProcessor } from '../billing/rtdn/processor';
import { dedupeKey, ParsedDelivery } from '../billing/rtdn/notification';
import { tokenHash } from '../billing/purchase-identity';
import { MaintenancePolicy, defaultMaintenancePolicy, categories, Category, validatePolicy, bounded, nextActiveCheck, nextFailure, voidedWindow } from './maintenance-policy';
import { MaintenanceStore, WorkClaim, workKey } from './maintenance-store';
import { VoidedPurchaseFeed, parseFeed } from './voided-feed';
export interface MaintenanceDependencies { readonly play: PlayPurchaseApi; readonly voided: VoidedPurchaseApi; readonly ack: PlayAcknowledgmentApi; readonly feed: VoidedPurchaseFeed; readonly binding: AccountBinding; readonly deletion?: { resume(uid:string,maxSteps:number,pageSize:number):Promise<string> }; }
export interface MaintenanceRun { readonly now: Timestamp; readonly nextCategory?: Category; readonly cursors?: Partial<Record<Category, string | null>>; readonly only?: readonly Category[]; }
export interface MaintenanceReport { readonly nextCategory: Category; readonly cursors: Partial<Record<Category, string | null>>; readonly items: readonly { category: Category; key: string; outcome: string }[]; readonly budgetReached: boolean; }
/** Local/scheduler-neutral orchestrator. It owns NO purchase/grant/access writes.
 * Bounded ID pages include legacy missing scheduling fields, so no mass migration
 * or composite index is needed. The caller must persist/rotate returned cursors. */
export class Maintenance {
  private readonly work: MaintenanceStore;
  private readonly inbox: RtdnInboxStore;
  private readonly processor: RtdnProcessor;
  private readonly play: PlayPurchaseApi;
  private readonly voided: VoidedPurchaseApi;
  constructor(private readonly db: Firestore, private readonly deps: MaintenanceDependencies,
    private readonly clock: () => Timestamp = Timestamp.now, private readonly policy: MaintenancePolicy = defaultMaintenancePolicy,
    private readonly rng: () => number = Math.random, work?: MaintenanceStore,
    private readonly monotonic: () => number = () => performance.now()) {
    validatePolicy(policy); this.work = work ?? new MaintenanceStore(db, clock, policy.leaseMs);
    this.play = { lookup: q => bounded(signal => deps.play.lookup(q, { signal }), policy.ioTimeoutMs) };
    this.voided = { lookup: q => bounded(signal => deps.voided.lookup(q, { signal }), policy.ioTimeoutMs) };
    this.inbox = new RtdnInboxStore(db, clock, policy.retry, rng, { ...policy.retry, baseDelayMs: policy.unresolvedDelayMs, capDelayMs: policy.unresolvedCapMs });
    this.processor = new RtdnProcessor(db, 'maintenance-internal', this.play, this.voided, deps.binding, clock, this.inbox);
  }
  async run(input: MaintenanceRun): Promise<MaintenanceReport> {
    const started = this.monotonic(), items: { category: Category; key: string; outcome: string }[] = [], cursors: Partial<Record<Category, string | null>> = { ...input.cursors };
    const timeLeft = () => this.monotonic() - started < this.policy.runBudgetMs;
    const start = input.nextCategory ? categories.indexOf(input.nextCategory) : 0;
    if(start < 0) throw new Error('invalidMaintenanceCategory');
    let nextCategory: Category = categories[start]!;
    for (const category of [...categories.slice(start), ...categories.slice(0,start)]) {
      if (input.only && !input.only.includes(category)) continue;
      if (category === 'deletion' && !this.deps.deletion) continue;
      if (!timeLeft()) return { items, cursors, nextCategory, budgetReached: true };
      nextCategory = categories[(categories.indexOf(category)+1)%categories.length]!;
      if(category==='shopping'){
        try{
          const page=await this.db.collection('shoppingMutationWork').where('nextAt','<=',input.now).orderBy('nextAt').limit(Math.min(5,this.policy.pageSize)).get();
          for(const doc of page.docs){if(!timeLeft())break;
            try{items.push({category,key:doc.id,outcome:await new ShoppingMutationStore(this.db,this.clock).continueWork(doc.get('uid'),doc.get('mutationId'))});}
            catch{
              // A malformed job must not monopolize every due-page forever.
              // Preserve a processor's longer backoff/terminal cleanup deadline.
              try{await this.db.runTransaction(async tx=>{const current=await tx.get(doc.ref);const due=current.get('nextAt');
                if(current.exists&&due instanceof Timestamp&&due.toMillis()<=input.now.toMillis())tx.update(doc.ref,{nextAt:Timestamp.fromMillis(this.clock().toMillis()+300000)});
              });}catch{/* The independent next work item must still run. */}
              items.push({category,key:doc.id,outcome:'retryable'});
            }
          }
        }catch{items.push({category,key:'due',outcome:'queryFailure'});}continue;
      }
      if (category === 'family') {
        // Single-field due query excludes terminal rows (nextAt=null). No user
        // scan, no new scheduler; isolate failures and use one bounded page/job.
        try {
          const page=await this.db.collection('familyOperations').where('nextAt','<=',input.now).orderBy('nextAt').limit(Math.min(5,this.policy.pageSize)).get();
          for(const doc of page.docs) {
            if(!timeLeft())break;
            try { items.push({category,key:doc.id,outcome:doc.get('kind')==='JOIN'?await new FamilyJoinStore(this.db,this.clock).resume(doc.id):await new FamilyCreateStore(this.db,this.clock,this.policy.pageSize>50?50:this.policy.pageSize).resume(doc.id,1)}); }
            catch {items.push({category,key:doc.id,outcome:'internalConflict'});}
          }
        } catch {items.push({category,key:'due',outcome:'queryFailure'});}
        continue;
      }
      if (category === 'voided') {
        try { items.push({ category, key: workKey('feed', 'voided'), outcome: await this.catchUp(timeLeft) }); }
        catch { items.push({ category, key: workKey('feed', 'voided'), outcome: 'internalConflict' }); } continue;
      }
      const base: Query = category === 'deletion' ? this.db.collection('accountDeletions') : category === 'active' ? this.db.collection('billingPurchases') : category === 'ack' ? this.db.collectionGroup('acknowledgment') :
        category === 'grants' ? this.db.collectionGroup('entitlementGrants') : this.db.collection('rtdnInbox');
      let query = base.orderBy(FieldPath.documentId()).limit(this.policy.pageSize);
      const cursor = input.cursors?.[category];
      try {
        if (cursor) query = query.startAfter(this.db.doc(cursor));
        const page = await query.get(); let last = cursor ?? null, visited = 0;
        for (const doc of page.docs) {
          if (!timeLeft()) break;
          last = doc.ref.path; visited++;
          try { const outcome = await this.visit(category, doc, input.now); items.push({ category, key: workKey(category, doc.ref.path), outcome }); }
          catch { items.push({ category, key: workKey(category, doc.ref.path), outcome: 'internalConflict' }); }
        }
        cursors[category] = visited === page.size && page.size < this.policy.pageSize ? null : last;
      } catch { items.push({ category, key: workKey('query', category), outcome: 'queryFailure' }); cursors[category] = cursor ?? null; }
    }
    return { items, cursors, nextCategory, budgetReached: !timeLeft() };
  }
  private async visit(category: Category, doc: QueryDocumentSnapshot, now: Timestamp): Promise<string> {
    if (category === 'deletion') {
      const job=readDeletion(doc.data());
      if(job.stage==='DONE'||job.lastOutcome==='supportRequired')return 'terminalOrOperator';
      if(job.nextAt && compareTime(job.nextAt, now) > 0)return 'notDue';
      return this.deps.deletion!.resume(doc.id,1,this.policy.pageSize);
    }
    if (category === 'active') {
      const p = readPurchase(doc.data());
      if (p.bindingState !== 'BOUND' || p.revokedAt || p.purchaseState === 'CANCELED') return 'terminal';
      if (p.nextCheckAt && compareTime(p.nextCheckAt, now) > 0) return 'notDue';
      return this.purchase(doc.id);
    }
    if (category === 'ack') {
      if (!/^billingPurchases\/[a-f0-9]{64}\/acknowledgment\/state$/.test(doc.ref.path)) return 'unsupportedPath';
      const a = parseAckState(doc.data());
      if (['acknowledged', 'acknowledgmentCanceled', 'acknowledgmentFailed'].includes(a.status)) return 'terminal';
      if (a.leaseUntil && compareTime(a.leaseUntil, now) > 0 || a.nextRetryAt && compareTime(a.nextRetryAt, now) > 0) return 'notDue';
      if (a.status === 'acknowledgmentExhausted' && a.lastAttemptAt.toMillis() + this.policy.recoveryRoundMs > now.toMillis()) return 'notDue';
      return this.purchase(doc.ref.parent.parent!.id);
    }
    if (category === 'grants') {
      if (!/^users\/[^/]+\/entitlementGrants\/[^/]+$/.test(doc.ref.path)) return 'unsupportedPath';
      const g = parseGrant(doc.data());
      if (compareTime(g.startsAt, now) > 0) return 'notDue';
      const fingerprint = createHash('sha256').update(JSON.stringify(doc.data())).digest('hex');
      const c = await this.work.claim(workKey('grant', doc.ref.path), fingerprint); if (!c) return 'notDueOrBusy';
      try {
        const uid = doc.ref.parent.parent!.id, marker = await this.db.doc(`accountLifecycle/${uid}`).get();
        if (!marker.exists || readAccount(marker.data()).state !== 'ACTIVE') { await this.work.finish(c, 'inactive', null); return 'inactive'; }
        const account = readAccount(marker.data());
        const next = await new LifecycleStore(this.db, this.clock, tx => this.work.guard(tx, c)).recomputeGrants(uid, account.generation);
        await this.work.finish(c, 'success', next); return 'recomputed';
      } catch (e) { return this.failure(c, e); }
    }
    const r = readInbox(doc.data());
    if (category === 'tokens') return await this.inbox.minimizeToken(doc.id) ? 'tokenMinimized' : 'noTokenChange';
    if (category === 'expiredInbox' && !(r.status === 'PROCESSING' && compareTime(r.leaseUntil!, now) <= 0) ||
      category === 'retryInbox' && !(r.status === 'RECEIVED' || r.status === 'RETRY' && (!r.nextRetryAt || compareTime(r.nextRetryAt, now) <= 0)) ||
      category === 'unresolvedInbox' && !(r.status === 'UNRESOLVED' && (!r.nextRetryAt || compareTime(r.nextRetryAt, now) <= 0))) return 'notDue';
    if (r.operatorRequired || r.lastOutcome === 'permanentConfigurationFailure') return 'operatorRequired';
    if (r.attemptCount >= this.policy.retry.attemptsPerGeneration) {
      if (!await this.inbox.recover(doc.id, this.policy.recoveryRoundMs, this.policy.maxRecoveryGenerations)) return 'recoveryDeferred';
    }
    return (await this.processor.process(doc.id)).outcome;
  }
  private async failure(c: WorkClaim, e: unknown): Promise<string> {
    const config = e instanceof PlayLookupError && e.code === 'configuration' || e instanceof VoidedLookupError && e.code === 'configuration' || e instanceof VerificationError && e.code === 'playConfigurationError';
    const inactive = e instanceof LifecycleError && ['accountDeleted', 'accountDeleting', 'accountInactive'].includes(e.code);
    const exhausted = c.record.failures + 1 >= this.policy.maxFailures;
    try {
      await this.work.finish(c, config ? 'configuration' : inactive ? 'inactive' : exhausted ? 'exhausted' : 'retry',
        inactive ? null : nextFailure(this.clock().toMillis(), c.record.failures + 1, this.policy), config || exhausted);
    } catch { return 'staleOrCrashed'; }
    return config || exhausted ? 'operatorRequired' : inactive ? 'inactive' : 'retry';
  }
  private async purchase(hash: string): Promise<string> {
    const c = await this.work.claim(workKey('purchase', hash)); if (!c) return 'notDueOrBusy';
    const store = new LifecycleStore(this.db, this.clock, tx => this.work.guard(tx, c));
    try {
      const doc = await this.db.doc(`billingPurchases/${hash}`).get();
      if (!doc.exists) throw new Error('missingPurchase');
      const p = readPurchase(doc.data());
      if (p.bindingState !== 'BOUND' || p.revokedAt || p.purchaseState === 'CANCELED') { await this.work.finish(c, 'success', null); return 'terminal'; }
      let verified;
      try {
        verified = await new PurchaseVerifier(this.db, this.play, this.deps.binding, this.clock, store).verify({ uid: p.boundUid }, { purchaseToken: p.purchaseToken },
          { maxGenerations: this.policy.maxRecoveryGenerations, cooldownMs: this.policy.recoveryRoundMs, policy: this.policy.retry });
      }
      catch (e) {
        if (e instanceof VerificationError && e.code === 'purchaseNotOwned') {
          const result = await new PurchaseRevoker(this.db, this.voided, store).run(p.purchaseToken);
          if (['purchaseRevoked', 'pendingCanceled', 'revokeAlreadyApplied'].includes(result.outcome)) { await this.work.finish(c, 'success', null); return result.outcome; }
          if (result.outcome === 'voidedLookupConfigError') throw new VoidedLookupError('configuration');
        }
        throw e;
      }
      if (verified.status === 'purchasePending') { await this.work.finish(c, 'success', this.clock().toMillis() + this.policy.unresolvedDelayMs); return 'pending'; }
      const next = nextActiveCheck(this.clock().toMillis(), this.rng, this.policy);
      if (!await store.recordCheck({ uid: p.boundUid }, hash, verified.fence.revision, verified.fence.generation, Timestamp.fromMillis(next), null)) throw new LifecycleError('staleLifecycleRevision');
      const ack = await new PurchaseAcknowledger(this.db, this.deps.ack, this.clock, this.policy.retry, this.rng, store).run(hash);
      const stateDoc = await this.db.doc(`billingPurchases/${hash}/acknowledgment/state`).get(), a = stateDoc.exists ? parseAckState(stateDoc.data()) : null;
      const operator = ack.status === 'acknowledgmentFailed' || a?.status === 'acknowledgmentExhausted' && a.recoveryGeneration >= this.policy.maxRecoveryGenerations;
      const scheduled = ack.status === 'acknowledged' ? next : a?.nextRetryAt?.toMillis() ?? this.clock().toMillis() + this.policy.recoveryRoundMs;
      await this.work.finish(c, operator ? 'exhausted' : 'success', scheduled, operator); return operator ? 'operatorRequired' : ack.status;
    } catch (e) { return this.failure(c, e); }
  }
  private async catchUp(timeLeft: () => boolean): Promise<string> {
    const c = await this.work.claim(workKey('feed', 'voided')); if (!c) return 'notDueOrBusy';
    try {
      const window = c.record.progress ?? { ...voidedWindow(this.clock().toMillis(), this.policy), pageToken: null };
      const raw = await bounded(signal => this.deps.feed.list({ packageName: PACKAGE_NAME, ...window, limit: this.policy.pageSize }, { signal }), this.policy.ioTimeoutMs);
      const page = parseFeed(raw, this.policy.pageSize);
      if (page.nextPageToken !== null && page.nextPageToken === window.pageToken) throw new VoidedLookupError('configuration');
      const keys: string[] = [];
      for (const item of page.items) {
        // Google's window filters when it observed the void, not returned voidedTimeMillis.
        // The timestamp is validated by parseFeed; discovery still cannot authorize a revoke.
        const hash = tokenHash(item.purchaseToken), source = 'maintenance:voided', messageId = workKey('voided', [hash, item.voidedTimeMs, window.endMs].join(':'));
        const d: ParsedDelivery = {
          key: dedupeKey(source, messageId), source, messageId, publishTimeMillis: window.endMs, fingerprint: messageId,
          notification: { category: 'voided', notificationType: 1, eventTimeMillis: item.voidedTimeMs, token: item.purchaseToken, tokenHash: hash, rejection: null }
        };
        await this.inbox.receive(d); keys.push(d.key);
      }
      // Commit page checkpoint only AFTER every item has a durable inbox. Crash
      // before checkpoint safely rediscovers them; unresolved tokens remain there.
      await this.work.finish(c, 'success', page.nextPageToken ? this.clock().toMillis() : this.clock().toMillis() + this.policy.voidedIntervalMs,
        false, page.nextPageToken ? { ...window, pageToken: page.nextPageToken } : null);
      for (const key of keys) { if (!timeLeft()) break; await this.processor.process(key); }
      return page.nextPageToken ? 'pageContinues' : 'pageComplete';
    } catch (e) { return this.failure(c, e); }
  }
}
