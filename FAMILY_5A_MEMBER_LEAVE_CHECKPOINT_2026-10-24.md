# Family Phase 5A — ACTIVE non-owner member self-leave

Date: 2026-10-24. Baseline: `46d0e52d8bfe055b871879908e7841c6cc8a05f6`
(`feat(family): complete join activation and finalization`). Initial worktree clean.
No reset, production access, deploy, Flutter/rules modification, staging, commit or push.

## Scope and API

`leaveFamilyShare({inviteId})` is an authenticated, lazy CORE callable using the
existing Family runtime options. No client UID, source/destination household or
role is accepted. The invite ID is the expected completed JOIN incarnation; routing
comes exclusively from the authenticated user's current backend relationship and
its completed JOIN evidence. This prevents a delayed request for a previous
relationship from targeting a later one.

The store remains explicitly LOCAL ONLY: GCLOUD_PROJECT=demo-kuktam-local,
loopback Firestore emulator endpoint, no K_SERVICE/FUNCTION_NAME deployed runtime.
No production runtime gate or UI is enabled. The future UI must retain/read the
expected JOIN incarnation before requesting leave; no Flutter change is made here.

## One atomic transaction

No multi-phase workflow, worker lease or persisted leave lock is required.
Every attempt reads the completion receipt first. If valid DONE evidence already
exists, return that historical result without mutating current membership/routing.

For a new operation freshly validate:
- Authenticated actor, ACTIVE lifecycle, no deletion job.
- Strict ACTIVE reverse membership with member role; owner denied deterministically.
- User active/family/private pointers and migration version.
- Deterministically derived private fallback, schema v2, correct owner/member,
  ACTIVE and unfenced. A missing/damaged fallback is never recreated.
- Shared capacity guard exists, has no structuralOperationId and contains no stale
  reservation for this already-active JOIN.
- Valid family root/owner context and bounded membership list, actor member doc,
  active member count plus reservation count <=8. No Pro or invite-expiry admission.
- Exact ACTIVE/DONE JOIN with matching actor/source/target/owner and invite identity.
- Exact USED invite with matching joining UID, JOIN operation and target.

Then atomically perform five writes:
1. Delete only `households/{family}/members/{actorUid}`.
2. Delete only `familyMemberships/{actorUid}` (no new membership state).
3. Set user activeHouseholdId to own private fallback, familyHouseholdId=null;
   retain privateHouseholdId and other fields.
4. Advance the private fallback epoch using the existing shopping helper.
5. Create immutable completed leave evidence.

No canonical shopping document is read for transfer, copied, created, edited or
deleted by leave. Existing private items, if any, are preserved. The family root,
its shopping epoch/sequence/items, owner/other members, invitation inventory,
reservations and original JOIN/invite/journal evidence remain unchanged.

## Structural serialization and capacity

The existing familyJoinCapacity guard is read INSIDE the same transaction as
membership/pointer changes. A foreign structuralOperationId returns IN_PROGRESS;
no expiry takeover or clearing/replacing foreign ownership is possible. Conflicting
JOIN/structural writers must change that same guard and are serialized by Firestore
transaction dependencies. The bounded membership query also participates in the
capacity transaction. A one-commit leave has no intermediate external lock state.

Active capacity is the actual membership collection count, not a numeric counter.
Deleting the actor member doc releases exactly one active seat. operationIds holds
other users' RESERVED seats and is not rewritten/decremented. Reentry only reads
its DONE receipt. A full eight-person family falls to seven, allowing a new user's
reservation to use the free seat without double release.

## Identity and durable evidence

ID: `leave_` + SHA256(JSON.stringify([authenticatedUid, inviteId])).
Path: `familyOperations/{leaveId}`. Terminal-only schema v1:
`{schemaVersion,kind:'MEMBER_LEAVE',actorUid,householdId,privateHouseholdId,
joinOperationId,inviteId,phase:'PRIVATE',status:'DONE',createdAt,updatedAt,
nextAt:null,leaseId:null,leaseUntil:null}`.
createdAt=updatedAt=server transaction time. No READY leave job is created;
nextAt=null keeps the receipt out of maintenance's due-work query. Existing rules
already deny direct client reads/writes to familyOperations. No rules change.

Lost ACK and competing requests reobserve the same receipt and cannot delete a
later membership or renew the source epoch twice. A historical DONE response is
not a statement that the user is still private now. Original JOIN ACTIVE/DONE is
historical audit evidence; resuming that JOIN does not reactivate the departed user.

## Shopping and deletion safety

A pending immutable Family request still names its original household/epoch.
After leave, the existing shopping authority sees the changed active pointer and
missing memberships, rejects it as REJECTED_CONTEXT_CHANGED, and never retargets it.
Fresh normal ensureContext routes to private; semantic ADD uses the existing S1
processor. The private epoch is renewed atomically with the pointer switch, so
old private contexts are not reopened. Other family members retain their context.

Before leave, normal account deletion is blocked by FAMILY_LIFECYCLE_NOT_READY.
After membership deletion and family pointer clearing, the unchanged private
admission path accepts beginDeletion and establishes its normal DELETING/job state.
No Family-aware deletion, removal, dissolution, Pro-loss or compensation was added.

## Failure contract

OWNER_CANNOT_LEAVE: member endpoint cannot dissolve or remove an owner.
NOT_ACTIVE_MEMBER: no active relationship and no matching historical receipt.
IN_PROGRESS: RESERVED actor or owned foreign structural transition.
STALE_MEMBERSHIP: supplied invite differs from current completed JOIN.
ACCOUNT_UNAVAILABLE: non-ACTIVE lifecycle or deletion job.
INTEGRITY_REQUIRES_OPERATOR: structural/binding/evidence/fallback inconsistency;
no partial mutation, no automatic repair, no new fallback or compensation.
Transient infrastructure failure remains retryable; callable sanitizes internal
errors as RETRYABLE_UNAVAILABLE. All domain checks finish before any write.

## Validation

Development focused run: 32 PASS / 0 FAIL / 0 SKIP, exit 0, 161672.4348 ms.
Two additional focused eligibility/audit cases are included in final validation.
Final Functions build: PASS. Final local emulator regression: 49 PASS / 0 FAIL / 0 SKIP, exit 0, 211727.2911 ms. Breakdown: 34 Phase 5A tests, 3 relevant 4B2 tests, 5 Phase 4A reservation/capacity tests, 5 shopping authority/context tests, 2 callable/runtime tests. Emulator stopped successfully. Final git diff --check: PASS.

Commands:
- `npm --prefix functions run build`
- `node functions/scripts/emulator-tests.cjs --leave`
- `node functions/scripts/emulator-tests.cjs --leave-regression`
- `git diff --check`

The final runner's explicit name filter selects all `5A` tests plus relevant 4B2
ACTIVE/reentry/routing/deletion guards, reservation/capacity races, shopping stale
context/authority tests and callable discovery/identity tests. It does not run
Phase4B transfer scale matrices, Flutter, Android/native H2, shopping performance,
or unrelated full backend/emulator suites. Core shopping/deletion/lease/rules
implementations are unchanged; no broad infrastructure change justifies those runs.

Local logs:
- C:/Users/gabor/AppData/Local/Temp/family-5a-focused.log
- C:/Users/gabor/AppData/Local/Temp/family-5a-final.log

## Boundary and remaining work

This is self-leave only. Owner removal (5B), owner dissolution (5C), Pro-loss and
Family-aware account deletion (6), UI and production rollout remain NOT STARTED.
No JOIN admission/re-JOIN redesign is included: the historical per-UID DONE JOIN
slot remains as implemented in Phase4A/4B. The freed seat is proven usable by a
new user's reservation; reopening the departed user's JOIN slot is not claimed.
The old-leave-versus-future-membership test is an isolated future-state fixture,
not an implementation of re-JOIN.

No production deploy/access, rule changes, Flutter changes, commit or push.

## Final gates

Phase 4B: COMPLETE (committed baseline). Phase 5A: PASS locally.
Phase 5B owner remove, Phase 5C owner dissolution and Phase 6: NOT STARTED.
No outstanding required Phase 5A test. Full historical backend/emulator, Flutter,
Android/native and performance suites were intentionally not run under this scope.
Next separate milestone: Phase 5B. No commit or push.
