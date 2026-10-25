# Family Phase 6A â€” owner Pro-loss lifecycle

Date: 2026-10-25. Local implementation; no production access or deployment.
Acceptance: PASS — 38 PASS / 0 FAIL / 0 SKIP; Phase 6A complete locally.

## Authoritative source and admission

`familyOwnerEntitlementChanged` watches server-owned
`users/{uid}/entitlementGrants/{grantId}` writes/deletions. Event bodies are not
entitlement decisions. `OwnerProLossStore.observe` reads the current membership
and recomputes all grants through the existing `hasPro` / `aggregateGrants`
contract. Expiry, revoked grants and alternate active grant sources retain their
existing semantics. A stale effective entitlement cache is not authoritative.
The existing 500-grant safety bound remains; overflow fails closed.

A bounded rotating scan of `familyMemberships` (20 documents per invocation,
durable document-ID cursor at `familyLifecycleMaintenance/ownerScan`) also finds
timed expiry without a grant-write event. The scheduled entry point is declared
once per minute; it processes at most 20 due intents, one existing engine step
per intent. Failures do not prevent other entries in that batch from processing.
Transient failures rotate to a later retry. No external Play call is made by the
Family worker.

Both new entry points retain the accepted local/demo Family rollout barrier.
They do not initialize Admin or run lifecycle work in deployed environments.
This task does not enable production Family gates or claim a deployed scheduler.
Tests run the real exported handler and the real sweep against local Firestore;
Cloud Scheduler/Eventarc delivery infrastructure is not deployed/tested here.

## Minimal durable intent

`familyProLoss/{dissolutionId(ownerUid,householdId)}`:

- version 1; ownerUid; householdId; reason `OWNER_PRO_LOSS`;
- status `PENDING`, `IN_PROGRESS`, `DONE`, `SUPERSEDED`, or `OPERATOR`;
- operationId null before admission, deterministic dissolution ID afterwards;
- createdAt, updatedAt, nextAt for nonterminal continuation, lastOutcome.

Server only; existing catch-all Firestore rules deny client access. No new rules.
Repeated notifications reuse this identity and do not churn existing pending or
in-progress evidence. SUPERSEDED means Pro was restored before a new dissolution
was admitted. A later real loss may requeue the same still-active Family intent.
Terminal entries have no nextAt and leave the due-work query.

`DissolutionPreparationStore.prepareForProLoss` uses the same preparation
transaction as owner-requested dissolution. It checks the current grant set
again IN that transaction, alongside fresh owner/topology/lifecycle/fallback
validation. It creates PREPARED plus the durable structural lock and associates
the intent atomically. Restoration that wins before this commit prevents new
admission. The proof at
`familyOperations/{id}/lifecycleAdmission/state` records version, reason,
ownerUid, householdId, intentId, checkedAt and entitled=false. The complete grant
query participates in transaction conflict detection. No parallel entitlement
revision/model is introduced. Existing dissolution root schema is unchanged.

## Structural ordering and forward completion

- No active Family / historical dissolved owner only: no new operation.
- Non-owner: no dissolution; members can remain Free.
- Precommit JOIN: cannot cross the commit point once dissolution owns the lock;
  Phase 5 finalization uses the existing abort path, preserving private items.
- Committed JOIN: retain its lock. Resume `FamilyJoinStore.resume` using its
  existing lease/due-time rules until ACTIVE/DONE. Never abort or compensate it.
  Then preparation re-reads topology and includes the new member.
- Self-leave / owner-remove: existing atomic transactions and shared capacity
  read serialize against preparation. The winner defines the participant set.
- Existing owner-requested or lifecycle dissolution: reuse the deterministic
  operation, never create a second one. Pro restoration after admission does not
  roll it back, including at PREPARED.
- Impossible structural evidence: safe failure / OPERATOR; no lock stealing,
  quantity compensation or invented memberships. Existing engine OPERATOR is
  propagated to the intent. A malformed intent cannot authorize work.

The worker dispatches only these existing engine implementations:

| Operation phase | Existing worker |
| --- | --- |
| PREPARED / SNAPSHOT_SHOPPING / VERIFY_SHOPPING | DissolutionPreservationStore |
| PRESERVATION_COMMITTED | DissolutionMergeStore |
| PRESERVATION_MERGE_COMPLETE | DissolutionSourceDispositionStore |
| PRESERVATION_SOURCE_CLEANED / RELEASING_NON_OWNERS | DissolutionMemberReleaseStore |
| NON_OWNER_RELEASE_COMPLETE / DONE | DissolutionFinalizationStore |

There is no new merge, cleanup, membership-exit or fence-release implementation.
The operation's atomic blocks remain the effect/idempotency authority. The
orchestrator needs no independent structural lease. A missed acknowledgement
between an engine commit and intent update is recovered from operation state.
Concurrent phase advancement is retried without regressing terminal evidence.
The intent becomes DONE only after the existing finalizer verifies durable DONE.

## Final state / lifecycle boundary

The original Phase 5 final state applies: Family DISSOLVED audit record retained,
zero ACTIVE Family memberships, source empty, owner and members route to their
own private homes, shopping preserved for owner only, both fences safely released,
structural lock null, pending usable invites revoked, precommit reservations
aborted, USED history preserved, dissolution DONE and intent DONE.

No account-deletion implementation or guard was changed. Former-owner deletion
still returns FAMILY_LIFECYCLE_NOT_READY because historical Family audit-root
cleanup belongs to 6C. Active/committed Family protections remain in force.

## Validation

Development run exposed two issues: the synthetic existing private item used an
unnormalized name instead of the canonical stored lowercase name (14 repeated
assertion failures), and malformed capacity parsing escaped without recording
intent OPERATOR (1 failure). The fixture and the narrow orchestration error
handling were corrected; shopping semantics were not modified. Read ordering
between operation and intent was aligned for competing workers. Additional
billing-writer and forward-completion tests were then included.

Final acceptance run after the last backend change: **38 PASS / 0 FAIL / 0 SKIP**,
exit 0, duration 274572.6394 ms. Emulator shut down successfully.

- 20 new Phase 6A tests (including 1/3/8 participants, committed JOIN ordering,
  billing revoke through the real writer, expiry sweep, stale events, restoration,
  duplicate/lost ACK/concurrent workers, 5A/5B races and integrity handling).
- 4 Phase 5C4B final-state/routing/reservation/deletion-guard regressions.
- 6 JOIN precommit/postcommit cancellation/Pro/lifecycle regressions.
- 2 entitlement/lifecycle contract regressions.
- 5 authoritative billing revoke / alternate-source regressions.
- 1 lazy runtime/export discovery regression.

Reproduce: `node functions/scripts/emulator-tests.cjs --pro-loss-regression`
after `npm --prefix functions run build`.
Final log: `C:/Users/gabor/AppData/Local/Temp/family-6a-final.log`.
The new suite is also registered in the default emulator harness for future use;
that broader suite was not run. Runner syntax check: PASS.

Observed terminal shopping result: existing owner milk 1000 ml plus Family
300 ml + 2 l = **3300 ml, one canonical row**. In the committed JOIN case,
its additional 200 ml survives exactly once, giving **3500 ml**, and the
newly ACTIVE guest is present in the dissolution participant snapshot.
Final Family ACTIVE memberships: 0. Source items: 0. Dissolution and intent: DONE.
Member private contents preserved. Account-deletion guard remains unchanged.
Functions build/typecheck: PASS on final backend code.
Routine git checks, full historical backend/emulator suites, transfer scale and
performance suites, Flutter, Android/native H2: NOT RUN as requested.

## Files changed

- functions/src/households/owner-pro-loss.ts (new)
- functions/src/households/dissolution-preparation.ts
- functions/src/index.ts
- functions/test/owner-pro-loss.test.ts (new)
- functions/test/runtime.test.ts
- functions/scripts/emulator-tests.cjs
- FAMILY_JOIN_RESERVATION.md
- FAMILY_6A_OWNER_PRO_LOSS_CHECKPOINT_2026-10-25.md (new)

## Remaining separate work

6B: ACTIVE Family account-deletion lifecycle.
6C: historical DISSOLVED Family audit-root/deletion retention policy.
Production rollout, scheduler delivery/IAM and UI remain separately gated; none
was started here. No Flutter/rules/account-deletion edits, deploy, commit or push.

## Final gates

Phase 4B: COMPLETE (accepted input). Phase 5: COMPLETE (accepted input).
Phase 6A: PASS / COMPLETE LOCALLY. No unresolved 6A blocker or required test.
Phase 6B: NOT STARTED. Phase 6C: NOT STARTED.
Production accessed: NO. Flutter changed: NO. Firestore rules changed: NO.
Account deletion code changed: NO. Deploy: NO. Commit: NO. Push: NO.
Next separate milestone: 6B ACTIVE Family account-deletion lifecycle. STOP.
