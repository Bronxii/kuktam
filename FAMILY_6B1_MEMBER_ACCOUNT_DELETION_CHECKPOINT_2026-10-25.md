# Family Phase 6B1 — ACTIVE non-owner member account deletion

Date: 2026-10-25. Local/demo execution only. Acceptance: PASS � 50 PASS / 0 FAIL / 0 SKIP.

## Scope and ordering

An authenticated account-deletion request for a stable ACTIVE non-owner member
now uses the existing deletion entry point with a Family preparation stage:

`WAITING_EXIT → EXIT_COMPLETE → HANDED_OFF`

1. The existing DeletionGateway still requires recent authenticated login and an
   empty request body. UID, lifecycle state and Family routing are never accepted
   from client fields.
2. `MemberAccountDeletionStore.admit` transactionally binds the ACTIVE account
   generation, ACTIVE member index/version, server-authoritative JOIN incarnation,
   Family/owner identity and exact private fallback identity into durable intent.
3. The existing Phase 5A member-exit implementation performs the exit, or existing
   owner-remove/dissolution evidence proves that another winner already did so.
4. Only after stable private state and durable exit evidence are verified does
   `LifecycleStore.beginDeletion` admit the original private deletion job.
5. Existing AccountDeletionService / maintenance performs private data cleanup,
   Auth deletion and DELETED/DONE. No second deletion engine exists.

The existing raw LifecycleStore admission remains guarded for ACTIVE Family
members. The supported authenticated service entry adds the lifecycle wrapper;
no low-level Family guard was removed. Auth-deletion fallback is unchanged.

## Durable intent and identity

`familyMemberDeletions/{uid}` is server-only under existing deny-by-default rules.
Fields: version=1, uid, accountGeneration, householdId, ownerUid,
privateHouseholdId, joinOperationId, inviteId, membershipUpdateTime,
reason=`ACCOUNT_DELETION_MEMBER_EXIT`, phase, exitEvidence,
deletionOperationId, createdAt, updatedAt, nextAt, lastOutcome.

One UID has one irreversible deletion intent. Its original account generation
and JOIN invite identity prevent a retry from targeting a different membership.
OPERATOR and HANDED_OFF are terminal for this preparation worker. HANDED_OFF
binds the existing private deletion job ID; it does not claim that Auth has
already been deleted. Audit metadata is retained like existing Family operations.

The existing one-minute local Family scheduler pattern is reused by
`familyMemberDeletionMaintenance`: at most 20 due intents per invocation. A
failure remains retryable and rotates to a later due time. The existing private
deletion maintenance takes over once the original job exists. No new Auth API
call appears in the Family lifecycle worker.

The current local/demo Family gate remains. Production execution of this new
lifecycle is not enabled. Cloud scheduler delivery/IAM is not deployed or tested
against production in this task.

## Shared exit, atomicity and evidence

`MemberLeaveStore.leaveForAccountDeletion` invokes the SAME validated exit
transaction as self-leave. It additionally binds the durable deletion intent and
account/membership generation. The existing `commitMemberExit` removes the
member row and reverse index, switches user routing to the existing private
fallback and advances the private epoch. It changes no shopping items.

The same MEMBER_LEAVE operation identity is shared with a concurrent self-leave.
The intent's reason records deletion origin without creating a competing success
operation. Successful lifecycle exit writes EXIT_COMPLETE and the receipt path
in the same transaction as the membership/routing transition.

Existing receipt validation was factored into `readMemberExitCompletion` and
reused unchanged for self-leave/owner-remove recovery. Existing dissolution
release-journal validation was factored into `readParticipantReleaseProgress`;
it verifies bounded cursor/receipt-chain evidence without requiring the owner
still to be in its previous live state. The released participant must match the
intent's membership version and exact fallback.

Missing membership alone is NOT exit evidence. Reconciliation also requires:

- no remaining original Family member row;
- current user routing/private ownership valid before private deletion admission;
- either valid self-leave, owner-remove, or dissolution release evidence;
- account generation consistent with the original intent;
- if deletion already started, the existing parsed job/marker and generation
  instead of private content that the legitimate deletion engine may have removed.

Private fallback contents stay unchanged until the original deletion engine
cleans them. Family shopping, owner and other participants are never copied,
removed or edited by this lifecycle. Active capacity is the member set, so the
shared atomic removal releases exactly one slot; there is no extra decrement.

## Structural conflicts and recovery

- Owner-remove/self-leave wins: use its original receipt, no second exit, epoch or
  capacity change. Deletion continues from private state.
- Deletion exit wins: competing exit sees the existing completed receipt or
  deterministic non-member result; no contradictory successful exit is created.
- Dissolution owns structuralOperationId: keep WAITING_EXIT, account ACTIVE and
  no deletion job. After the existing engine releases this participant, its
  durable receipt allows private deletion. The owner can then finish dissolution
  even if this member's private account is already DELETED.
- Lost exit ACK: atomic EXIT_COMPLETE/receipt and private routing survive.
- Crash between exit and deletion: durable nextAt resumes admission, never rejoins.
- Lost private admission ACK: existing accountDeletions job and generation are
  recognized, and HANDED_OFF is recorded without creating another job.
- Failed exit transaction: all membership/routing/epoch/progress writes roll back;
  no DELETING marker, deletion job or Auth call.
- Corrupt/missing fallback, index mismatch or invalid exit receipt: OPERATOR;
  no replacement home and no private deletion admission.

New JOIN/CREATE admission checks for an existing member-deletion intent. This
closes the temporary private handoff gap: a pending delete cannot become a new
Family owner/member and strand the already-authorized deletion. It is not a
change to existing shopping or account-deletion semantics.

## Unsupported cases retained safely

ACTIVE owner: FAMILY_LIFECYCLE_NOT_READY; no owner exit/dissolution is implemented.
Historical DISSOLVED owner: same guard, including a historical owner who is now a
member elsewhere. No historical audit cleanup is added.
RESERVED/transitional JOIN: JOIN_COMMITTED_IN_PROGRESS and no deletion job/intent;
the existing JOIN completes forward. A subsequent authenticated request after
ACTIVE can use 6B1. No JOIN rollback or transfer compensation occurs.

Family structural conflicts with a stable ACTIVE member may admit only the
waiting intent alone; they do not admit irreversible private deletion.
Public response while deferred is `familyExitPending`; integrity-blocked response
is `supportRequired`. Normal completion returns existing private deletion outcomes.
No Flutter/UI handling or production rollout was added.

## Validation

Development focused run: 22 PASS / 0 FAIL / 0 SKIP, 158109.1127 ms, exit 0.
Two additional admission-boundary tests were added for the final run.
Final selected regression after the last backend code change: **50 PASS / 0 FAIL /
0 SKIP**, exit 0, duration 285833.9996 ms. Emulator shutdown confirmed.

- 24 new Phase 6B1 lifecycle tests.
- 7 Phase 5A member-exit regressions.
- 7 Phase 5B owner-remove/shared-exit regressions.
- 2 Phase 5C4A release/deletion-evidence regressions.
- 6 existing private-deletion/authentication regressions.
- 3 directly affected JOIN/CREATE admission regressions.
- 1 lazy runtime/export discovery regression.

Command: `node functions/scripts/emulator-tests.cjs --member-deletion-regression`
after `npm --prefix functions run build`.
Log: `C:/Users/gabor/AppData/Local/Temp/family-6b1-final.log`.
Runner syntax check: PASS. The new suite is registered in the default emulator
harness, but the full historical suite was not run.

Observed final result: no guest Family index or member row; private routing was
established before DELETING. Intent HANDED_OFF references one private deletion
job. The original engine then reached account DELETED / job DONE with one fake
Auth delete call. Family shopping, owner/other participants and JOIN audit evidence
remained unchanged. The member's own private home/data were then removed by the
normal private deletion engine, not by the Family exit.

Both ACK-loss boundaries, crash recovery, competing workers, self-leave/remove
races and dissolution ordering passed. The dissolution test finishes the owner's
original dissolution after the released member's account has reached DELETED.
No 6B1 acceptance blocker or required test remains.
Functions build/typecheck: PASS after the final backend changes.

The local end-to-end test uses real Firestore emulator writes and the EXISTING
private deletion engine with the repository's FakeAuthDeletionApi. The fake Auth
boundary asserts both Family membership indexes are absent before deletion. It
proves normal DELETED marker / DONE job and user-private cleanup; no real Auth
account or production deletion E2E was performed.

Routine git checks, full historical regression, transfer-scale/performance suites,
Flutter, Android/native H2 and production deletion E2E were not run.

## Files changed

- functions/src/households/member-account-deletion.ts (new)
- functions/src/households/member-leave.ts
- functions/src/households/dissolution-member-release.ts
- functions/src/households/family-join.ts
- functions/src/households/family-create.ts
- functions/src/accounts/account-deletion.ts
- functions/src/index.ts
- functions/test/member-account-deletion.test.ts (new)
- functions/test/runtime.test.ts
- functions/scripts/emulator-tests.cjs
- FAMILY_JOIN_RESERVATION.md
- FAMILY_6B1_MEMBER_ACCOUNT_DELETION_CHECKPOINT_2026-10-25.md (new)

## Remaining separate work

6B2: ACTIVE owner account deletion, dissolution before private deletion.
6C: historical DISSOLVED Family owner audit/deletion policy.
UI and production rollout remain separate. Existing owner/historical-owner guards
are deliberately retained. No deploy, commit or push. No next phase started.

## Final gates

Phase 4B COMPLETE; Phase 5 COMPLETE; Phase 6A PASS (accepted inputs).
Phase 6B1 PASS / COMPLETE LOCALLY.
Phase 6B2 NOT STARTED; Phase 6C NOT STARTED.
Flutter changed NO; Firestore rules changed NO; production accessed NO;
production deletion E2E NO; deploy NO; commit NO; push NO.
Next separate milestone: 6B2 ACTIVE owner account deletion. STOP.
