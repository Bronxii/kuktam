# Family Phase 6C2 - final account deletion handoff

Date: 2026-10-26. Local/demo only. Acceptance: PASS. All 47 selected cases verified; see run accounting below.

## Boundary and engine reuse

HISTORICAL_AUDIT_READY -> DELETION_IN_PROGRESS -> DELETED on
familyOwnerDeletions/{uid}. The account uses the existing ACTIVE -> DELETING ->
DELETED marker; accountDeletions/{uid} uses the existing stages through DONE.
There is no Family-specific cleanup/Auth engine, new public endpoint or scheduler.
The existing local Family feature gate remains. Production deployment/rollout is
not part of this checkpoint.

AccountDeletionService recognizes a ready owner intent and requests the explicit
server-only historical handoff in LifecycleStore.beginDeletion. Unadmitted raw
beginDeletion, marker advancement and Auth-event fallback retain the 6C1 barrier.
Once admitted, retries must match the durable owner intent, account marker and job.

## Atomic admission

HistoricalFamilyAuditStore.verifyDeletionHandoff runs inside the SAME Firestore
transaction as the existing private DELETING marker/job creation. It is read-only.
It reuses the 6C1 audit validator and original Phase 5 completion parsers.

Required proof:

- strict owner intent, phase HISTORICAL_AUDIT_READY and current ACTIVE generation;
- exact private fallback ownership, private routing, no existing deletion job;
- complete 6C1 progress, count and receipt hash chain, primary dissolution identity;
- every receipt's UID/generation, root pointer, household incarnation and final receipt;
- each root DISSOLVED with ownerUid null and auditOwnerUid matching historical UID;
- no members/indexes/source items, no structural lock or reservation/usable invite;
- no in-progress/OPERATOR Family operation, no active Pro-loss lifecycle;
- no additional live owner Family, membership, actor/owner work or detached root
  missing from the receipt set.

Receipt queries use pages of ten, without a first-match or fixed-history-count
shortcut. All pages participate in the final admission transaction for freshness.
Very large histories remain subject to Firestore transaction/time limits: failure
rolls back and does not admit deletion; there is no truncation or unsafe fallback.

Failure is a safe deterministic block with no marker/job/intent handoff write.
The transaction atomically records deletionOperationId, deletionGeneration,
handedOffAt and phase DELETION_IN_PROGRESS alongside the original engine writes.
A crash cannot produce a handoff without its job or a job without its handoff.

## Account generation and structural guards

For original generation g, existing engine admission creates DELETING generation
g+1, and terminal completion creates DELETED generation g+2. The owner intent keeps
its original g and explicitly binds the admitted job ID and g+1. Each cleanup step
validates that binding. Terminal replay requires DELETED/g+2 and the same DONE job.
A recreated ACTIVE account or mismatched generation is blocked before cleanup/Auth.

Existing CREATE/JOIN admission rejects a familyOwnerDeletions document, including
pending, ready, handed-off and terminal records. These guards were not removed.
The final transaction also independently checks live dependencies.

## Cleanup and audit survival

The original cleanupPrivateHousehold implementation still discovers live resources
through ownerUid. Detached Family roots have ownerUid null, so they are excluded.
The owner private household, including the shopping quantities preserved by Phase
5, is ordinary private data and is deleted by that unchanged cleanup path.

Family roots, auditOwnerUid, operations and subcollections, historical invites,
capacity/finalization records, 6C1 progress and detachment receipts remain intact.
No email, display name, profile or entitlement data is copied into audit history.
Historical UID retention is exactly the 6C1 contract, not anonymization.
Former members' routing, households and shopping remain unchanged.

## Recovery and terminal completion

The existing deletion worker, lease, Auth adapter and retry policy are reused.
The private terminal transaction also marks owner intent DELETED with deletedAt
and lastOutcome privateDeletionCompleted. Thus the account, job and owner intent
finish atomically; replay does not churn versions or restart dissolution/detachment.

Normal, duplicate and competing requests cause one simulated Auth call. The user
explicitly accepted the existing lost-ACK contract: if Auth succeeds before durable
acknowledgement, retry calls the adapter again, receives notFound, and records ONE
logical deletion. This case has two calls, one effective delete; it is not an
exactly-once network-call guarantee and no second deletion engine was introduced.

## Full local sequence and scope

Focused tests assemble real existing components:
ACTIVE owner -> 6B2 dissolution DONE -> 6C1 audit-ready -> 6C2 admission -> existing
private cleanup -> FakeAuthDeletionApi -> DELETED/DONE. Already-historical owners
reuse the same 6C1 primitive then the same handoff, without new dissolution.
No automatic orchestration of earlier phases/new production trigger was added.

Tests use only demo-kuktam-local Firestore and the existing fake Auth adapter.
No real Auth API, production account deletion E2E, production access, Flutter or
rules change, deployment, commit or push is part of this work.

## Validation

Functions build/typecheck: PASS (including the corrected test fixture). Runner
syntax check: PASS. No production backend change followed the final suite.

- Development focused run: 24 PASS / 0 FAIL / 0 SKIP, 347487.0875 ms.
- Final selected regression ran ONCE after final backend changes:
  47 cases, 46 PASS / 1 FAIL / 0 SKIP, 539642.6008 ms.
- The sole failure was a new test fixture using a non-canonical base64url token.
  It received INVALID_ARGUMENT before reaching the intended ACCOUNT_UNAVAILABLE
  assertion. The token was corrected with Buffer.alloc(32,1).toString('base64url');
  the specific error assertion was retained. No backend change or test weakening.
- Only that affected test was rerun: 1 PASS / 0 FAIL / 0 SKIP, 13323.9806 ms.
- Combined final coverage: all 47 unique selected cases verified, no unresolved
  failures. This is NOT represented as a single 47/0 run.

Coverage: 26 new 6C2 cases (25 final-run passes + corrected case), 5 relevant 6C1,
3 relevant 6B2, 3 relevant 6B1, 10 private deletion/generation/recovery cases.
The new audit-survival cases cover both real self-leave and owner-remove history.

Logs in C:/Users/gabor/AppData/Local/Temp/:
family-6c2-focused.log, family-6c2-final.log, family-6c2-guard-recheck.log.
All emulator runs stopped normally. No mandatory 6C2 case remains untested.
No full historical backend, shopping scale/performance, Flutter, native/Android,
or production deletion E2E run was performed. The narrowly scoped admission and
completion hooks reuse the engine and its targeted recovery regression; a full
historical regression was not justified.

## Remaining work

Family Flutter UI/integration and separately authorized production rollout remain.
No next milestone is started. Operational end-to-end UI/authentication scheduling
and production rollout checks are not claimed by this local backend checkpoint.

## Files

- functions/src/households/historical-family-audit.ts
- functions/src/households/owner-deletion-handoff.ts (new)
- functions/src/households/owner-account-deletion.ts
- functions/src/households/join-capacity.ts
- functions/src/billing/lifecycle-store.ts
- functions/src/accounts/account-deletion.ts
- functions/test/final-family-deletion.test.ts (new)
- functions/test/historical-family-audit.test.ts
- functions/scripts/emulator-tests.cjs
- FAMILY_JOIN_RESERVATION.md
- this checkpoint
