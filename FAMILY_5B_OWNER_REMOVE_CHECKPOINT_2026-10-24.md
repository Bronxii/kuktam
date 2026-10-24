# Family Phase 5B — owner removes ACTIVE non-owner member

Date: 2026-10-24. Baseline: `12a5a7f7f4341bee8fd2685c6bd04f99eccd0e0e`.
Initial worktree clean; committed Phase 5A. No reset, staging, commit or push.

## API and authority

New lazy CORE callable `removeFamilyMember({targetUid, inviteId})` uses existing
Family callable options. Authenticated caller UID is never accepted in payload.
Household and role overrides are rejected. Target UID is only a selector; all
routing and membership authority comes from server documents. inviteId binds the
request to the target's completed JOIN incarnation, preventing a delayed request
from removing a future membership.

The 5A local rollout barrier remains: demo-kuktam-local + loopback Firestore
emulator, with no deployed K_SERVICE/FUNCTION_NAME runtime. No production gates,
App Check configuration, client UI or rules were changed.

## Shared atomic exit

`MemberLeaveStore.leave` (5A) and `.remove` (5B) enter one private transaction
primitive. The existing leave receipt and API remain compatible. Removal adds:
- Authenticated caller differs from target (OWNER_CANNOT_REMOVE_SELF otherwise).
- Fresh existing FamilyInviteStore.owner validation on every transaction attempt:
  ACTIVE lifecycle, ACTIVE owner reverse membership, matching user routing,
  structurally ACTIVE family root, actual owner member document, own fallback.
- No caller deletion job; no Pro entitlement or dissolution implementation.
- Target ACTIVE member and owner belong to the same authoritative family.

Both paths retain existing target checks: ACTIVE lifecycle/no deletion job,
strict reverse index and actual member role, active/family/private pointers,
valid existing own fallback, no foreign structuralOperationId, valid bounded
capacity and original ACTIVE/DONE JOIN + USED invite evidence.

All validation precedes the same five atomic writes:
1. Delete target household member document.
2. Delete target reverse familyMemberships document.
3. Set target activeHouseholdId=own private fallback and familyHouseholdId=null.
4. Advance target private shopping epoch with existing helper.
5. Create immutable terminal operation evidence.

No shopping collection writes or copies. No owner/other member change. Private
contents, family root/items, original JOIN/invite audit evidence and unrelated
reservations remain unchanged. Missing/corrupt fallback is never manufactured.

## Durable identity and race behavior

Removal ID: `remove_` + SHA256(JSON.stringify([actorUid,targetUid,inviteId])).
Receipt at familyOperations/{id}, schemaVersion=1:
`kind=OWNER_REMOVE_MEMBER`, actorUid=owner, targetUid=removed member,
householdId, privateHouseholdId, joinOperationId, inviteId,
`phase=PRIVATE`, `status=DONE`, equal createdAt/updatedAt timestamps,
nextAt=null, leaseId=null, leaseUntil=null.

Strict receipt verification binds all identity fields. Same authenticated actor
can retrieve historical DONE after lost ACK with no writes, no second epoch
advance and no effect on any later membership. This is historical completion,
not a current membership claim. Other actors cannot reuse that receipt.

5A and 5B have distinct audit identities but share transactional membership and
routing read/write dependencies. In a self-leave/remove race exactly one commits.
The losing transaction retries against missing membership and returns
NOT_ACTIVE_MEMBER without creating a second audit receipt or changing epoch.
The winner's retries return its DONE. Both winner orders and concurrent requests
are tested. No compensating shopping operation is performed.

## Structural serialization and capacity

Read the existing familyJoinCapacity guard inside the transaction. A non-null
structuralOperationId yields IN_PROGRESS and is never stolen/expired/cleared.
There is no externally visible intermediate removal state or temporary lease.
Transaction dependencies serialize removal against structural guard writers and
the bounded membership query. Active capacity is actual member count: deleting
one member frees one slot. Reserved operationIds are untouched; no numeric
counter is decremented. Full-capacity tests verify a subsequent new reservation
can occupy the freed place, including after duplicate requests.

## Shopping and deletion admission

Previously accepted family commands retain their immutable family context; after
removal the unchanged authority validation rejects REJECTED_CONTEXT_CHANGED.
They are never retargeted. Fresh ensureContext and ADD use own private fallback.
Private epoch renewal is atomic with routing; family epoch/sequence is unchanged.
Before removal account deletion is FAMILY_LIFECYCLE_NOT_READY; afterward the
unchanged private admission creates its normal deletion job. No Phase 6 logic.
Owner invalid lifecycle/deletion jobs fail safely; Pro-loss lifecycle is absent.

## Failure semantics

NOT_OWNER: ordinary member/non-owner caller.
OWNER_CANNOT_REMOVE_SELF: caller targets self; never dissolution.
WRONG_FAMILY: target reverse binding is not caller's verified family.
NOT_ACTIVE_MEMBER: target has no current reverse membership and no matching receipt.
IN_PROGRESS: target RESERVED or foreign structural operation.
STALE_MEMBERSHIP: wrong expected JOIN invite incarnation.
ACCOUNT_UNAVAILABLE: target/caller lifecycle or deletion job disallows operation.
INTEGRITY_REQUIRES_OPERATOR: malformed binding/fallback/audit/capacity evidence;
no partial writes or automatic repair. Existing OWNER_CANNOT_LEAVE also rejects
an owner as target in the common exit primitive. Infrastructure errors remain
retryable and sanitized by the callable.

## Validation

Development focused run: 43 tests, 42 PASS / 1 FAIL / 0 SKIP (221537.6879 ms).
The failure was an assertion inherited from 5A expecting generic integrity error
for a target reverse index pointing at another family. Owner authorization now
rejects this earlier with WRONG_FAMILY, correctly before writes. The assertion
was corrected to require that exact error; production behavior was unchanged.
Final build: PASS. Final regression: 92 PASS / 0 FAIL / 0 SKIP, exit 0,
429604.3492 ms. 43 Phase 5B tests + 34 Phase 5A tests + 15 affected regressions
(3 Phase 4B2, 5 reservation/capacity, 5 shopping context/authority, 2 runtime).
Final source was built before this run; no production code changed afterward.
Emulator stopped successfully. Final git diff --check: PASS.
Commands:
- npm --prefix functions run build
- node functions/scripts/emulator-tests.cjs --remove
- node functions/scripts/emulator-tests.cjs --remove-regression
- git diff --check

The final targeted selection includes all new 5B tests, complete 5A regression,
relevant 4B2 active/routing/reentry tests, Phase 4A capacity/reservation tests,
shopping authority/context tests, and callable export/runtime checks.
No broad shared shopping, account deletion, reservation or rules implementation
was changed; full historical regression is not required. No Flutter/native H2,
Android builds, transfer scale matrices or shopping performance suites run.

Logs: C:/Users/gabor/AppData/Local/Temp/family-5b-focused.log and family-5b-final.log.

## Boundaries

Owner dissolution (5C), Pro-loss and Family-aware account deletion (6), UI and
production rollout are NOT STARTED. No ownership transfer or family shopping
copy/disposition. The historical per-UID JOIN slot/re-JOIN admission limitation
from Phase 5A is unchanged; freeing capacity for a new reservation is tested.

No production access, deploy, Flutter/rules changes, commit or push.

## Final gates

Phase 4B COMPLETE; Phase 5A PASS; Phase 5B PASS locally.
Phase 5C owner dissolution and Phase 6 NOT STARTED. No required Phase 5B targeted
validation remains outstanding. Next separate milestone: Phase 5C design and
subdivision, not started automatically. No deploy, commit or push.
