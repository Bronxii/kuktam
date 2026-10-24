# Family Phase 5C1 - owner dissolution preparation

Date: 2026-10-24. Baseline: e87b9f34db85a606a4989b44c435f05e182c1794.
Committed Phase 5B; initial worktree clean. No reset/staging/commit/push.

## Scope and admission

New local-only CORE callable: prepareFamilyDissolution({householdId}). Caller UID
comes exclusively from authentication. householdId is an expected-family selector,
not routing authority. Existing FamilyInviteStore.owner validates ACTIVE lifecycle,
ACTIVE owner reverse binding, current pointers, actual member role, root owner,
ACTIVE family structure and own fallback. Non-owner receives NOT_OWNER; a different
expected family receives WRONG_FAMILY. Deletion jobs block preparation. No Pro
entitlement check or Pro-loss lifecycle implementation is introduced.

Runtime guard requires demo-kuktam-local + loopback Firestore emulator and no
K_SERVICE/FUNCTION_NAME. Production gates, rules, UI and App Check are unchanged.

## One bounded atomic preparation

Operation identity: dissolve_ + SHA256(JSON.stringify([authenticated owner UID,
family householdId])). Path: familyOperations/{id}. The family household creation
timestamp is bound into the record; an inconsistent generation cannot reuse it.
There is one preparation per household lifetime, no automatic cancellation/reset.

Fresh transactional validation:
- Existing capacity lock is free. No lease-expiry takeover.
- Actual members query bounded at 9 detects overflow beyond maximum 8.
- Reverse indexes queried by householdId with limit 9 must match the actual ACTIVE
  members exactly; RESERVED indexes match existing capacity claims exactly.
- Every participant has ACTIVE lifecycle and no deletion job, matching family/
  active pointers, expected derived privateHouseholdId and migration version 1.
- Every fallback exists, is schema-v2 private/ACTIVE/unfenced, has correct owner,
  creation timestamp and owner membership. No fallback is manufactured.
- All bounded reserved JOINs have valid pre-commit READY evidence, matching RESERVED
  reverse index and matching inventoried invite. No committed JOIN may lack its lock.
- Bounded invite inventory documents are valid and belong to this owner/family.

Only two documents are written: create the complete operation and write the shared
capacity guard with its dissolution lock. No participant/user/fallback/family root,
shopping collection, JOIN evidence, invite or reserved index is modified.

## Immutable participant snapshot

Family maximum 8 makes an inline bounded snapshot sufficient; no paging workflow.
Participant order is ascending UTF-8 byte order by UID. Exact count is 1..8.
Each entry stores:
uid, role, privateHouseholdId, activeHouseholdId,
memberUpdateTime, reverseUpdateTime, privateCreatedAt.
The two membership updateTimes bind their existing document incarnations (which
have no explicit version field). Fallback identity is the deterministic household
ID plus owner validation and creation timestamp. Existing private contents are not
read/copied/cleared. A canonical framed-by-JSON array of those explicit fields,
including seconds/nanoseconds for timestamps, produces snapshotHash (SHA256).
Strict parser verifies exact fields, ordering, uniqueness, count, owner identity,
derived fallback identity, timestamp types and hash before returning evidence.

Operation schemaVersion=1, kind=FAMILY_DISSOLUTION, actorUid=ownerUid,
householdId, householdCreatedAt, structuralOperationId=id,
phase=PREPARED, status=READY, createdAt=updatedAt,
nextAt=null, leaseId=null, leaseUntil=null, cursor=null,
participantCount, participants, snapshotHash,
reservedJoinOperationIds (max 7), inviteIds (max 8).

nextAt=null is deliberate: existing maintenance must NOT dispatch this record to
CREATE/JOIN executors. 5C2 needs an explicit dissolution dispatcher/contract before
work may become due. Cursor is empty; no transfer/cleanup/exit progress is implied.

## Structural lock compatibility

familyJoinCapacity schemaVersion 3 is a narrow additive variant with the same keys:
operationIds remains only reserved join_ IDs; structuralOperationId must be a
non-null dissolve_ hash ID. Dissolution does not consume a reservation seat.
Legacy v1 and v2 validation is unchanged: v2 JOIN lock still must name a reserved
JOIN ID. No generic arbitrary lock string is accepted.

5A and 5B already reject a non-null lock; their business code is unchanged.
JOIN commit already checks structural ownership. Minimal additional v3 guards
prevent new reservation admission, v1 READY_FOR_TRANSFER progress, transfer
prepare, snapshot steps and DELETE confirmation from advancing under dissolution.
Existing pre-commit cancellation may release its own reservation/fence/invite while
preserving the dissolution lock. No mass cancellation is performed by 5C1.

Participant set is frozen; inviteIds/reservedJoinOperationIds are bounded observed
inventory evidence, NOT permission to assume later invite/reservation status is
unchanged. Pending invites may expire/be revoked and pre-commit claims can cancel.
Later phases must re-read and reconcile that inventory under the retained lock.
New active membership cannot appear while the lock is held.

## Shopping and lifecycle boundary

Family root remains ACTIVE, operationId and shopping epoch unchanged. No shopping
item snapshot or count is needed in 5C1. householdId/householdCreatedAt identify the
source, but do NOT claim a stable shopping snapshot. Owner and members can continue
normal semantic ADD through the accepted shopping protocol after PREPARED.
5C2 must separately define/fence the shopping source before preservation execution.

Existing deletion admission sees the retained structural lock and returns existing
JOIN_COMMITTED_IN_PROGRESS (legacy name). No lifecycle redesign. Losing owner Pro
does not clear the lock or abandon the preparation. Pro-loss processing is absent.

## Idempotency and races

Retry verifies owner authority, strict stored operation, family generation and same
retained v3 lock; returns the exact existing operation/hash/count with no writes.
Lost ACK and competing requests yield one operation, one snapshot and one lock.
Corrupt prepared evidence/lock/generation fails INTEGRITY_REQUIRES_OPERATOR without
rewriting, guessing, compensation or lock release.

All member queries, reverse indexes and guard reads participate in the same
transaction as operation creation/lock acquisition. If self-leave/remove commits
first, preparation retries and snapshots the new stable participant set. If
preparation wins, exit returns IN_PROGRESS. No stale participant set is accepted.
If JOIN commit wins first, preparation defers until its normal activation releases
the JOIN lock; a later prepare includes the newly active member. If preparation
wins, JOIN remains pre-commit and cannot activate. Forced transaction abort leaves
neither an orphan lock nor a partial snapshot.

## Validation

Development run: 40 PASS / 0 FAIL / 0 SKIP, exit 0, 228602.7033 ms
(36 preparation tests + 4 existing/new contract tests). A duplicate no-op v3 guard
line found in source review was removed before the final build. Two focused tests
were added for pre-commit cancellation preserving the v3 lock and v1 worker deferral.
Final Functions build: PASS. Complete targeted regression attempt: 55 tests,
54 PASS / 1 FAIL / 0 SKIP, 304446.9822 ms. All 38 preparation tests and all 15
non-runtime affected regressions passed. The failing shared runtime assertion
assumed householdId was forbidden at every endpoint. This new endpoint accepts
it as an expected-family selector (verified by owner authority, not trusted routing).
The test was corrected for this endpoint to reject an ownerUid override alongside
householdId; old endpoints' expectations remain unchanged.

Only the affected runtime checks were rerun after that TEST-ONLY correction:
2 PASS / 0 FAIL / 0 SKIP, exit 0, 690.2808 ms. Functions build rerun: PASS.
Command: node --test --test-name-pattern="^root discovery|^invite/state exports" functions/lib/test/runtime.test.js
No production source changed after the complete targeted run. Therefore all 55
unique selected tests are verified on final production code: 38 new preparation,
2 capacity contracts, 5 existing 5A/5B structural/race, 3 JOIN foundation guards,
5 reservation/capacity, 2 runtime. No unresolved failure or unexplained flake.
Emulator stopped after the complete run. Final git diff --check: PASS.
Commands:
- npm --prefix functions run build
- node functions/scripts/emulator-tests.cjs --dissolution-preparation
- node functions/scripts/emulator-tests.cjs --dissolution-preparation-regression
- git diff --check

Final targeted regression includes new preparation tests, strict capacity schema
compatibility, 5A/5B structural/race tests, JOIN commit lock/lifecycle/shopping guard
checks, capacity races and callable discovery. Changes to shared code are limited
to the additive capacity variant and explicit v3 early guards; no broad historical
suite is required. No transfer scale, performance, Flutter or native/Android runs.

Logs: C:/Users/gabor/AppData/Local/Temp/family-5c1-focused.log and family-5c1-final.log.

## Prerequisites for 5C2

Verify PREPARED evidence and lock ownership. Define the Family shopping source
fence/snapshot while preserving normal-operation safety, owner fallback merge
identity and exact-once progress. Reconcile current pending reservations/invites
under the retained lock. Do not interpret the participant snapshot as a shopping
snapshot. Add an explicit dissolution worker dispatch only in its own phase.
No transfer, member release, pointer switch, household dissolution, lock release,
Pro-loss or account-deletion dissolution is implemented here.

Production untouched; no deploy, commit or push. Phase 5C2 and Phase 6 NOT STARTED.

## Final gates

Phase 4B COMPLETE; Phase 5A PASS; Phase 5B PASS; Phase 5C1 PASS locally.
Phase 5C2 NOT STARTED; Phase 6 NOT STARTED. Required targeted validation complete.
No data transfer, membership removal, pointer switch or household dissolution.
No production access/deploy, commit or push. STOP at preparation boundary.
