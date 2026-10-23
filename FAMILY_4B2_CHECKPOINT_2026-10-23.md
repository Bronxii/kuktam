# Family 4B2 — JOIN activation / finalization

Date: 2026-10-23. Baseline: `ede97f8bcaaf9824449ff36be91bc68177abc5ce`.
Initial worktree clean; committed 4B1B2. No reset, production access, deploy,
gate enablement, Flutter/rules change, staging, commit or push.

## Transaction boundary

The existing leased JOIN worker dispatches READY / TRANSFER_COMPLETE to activation.
No new callable, client routing, operation phase or membership/invite schema is
introduced. Existing strict schema v2 already supports ACTIVE / DONE.

Every transaction attempt freshly checks the operation/lease, committedAt,
actor lifecycle and private pointers, source ownership/fence/epoch, reverse
RESERVED membership, owned capacity seat and structuralOperationId, RESERVED
invite and inventory, target owner/context/membership and absence of deletion
jobs. It does not recheck Pro, invite expiry or admission gates.

The activation evidence reader validates ALL expected ten-child journal pages,
the exact manifest hash chain and source-ID order, per-child transfer identities,
ADD APPLIED target/revision/created evidence or DELETE NO_TRANSFER evidence,
complete DELETED cleanup identities/hashes/times, monotonic ADD revisions and
null completion cursor. A transactional limit(1) source query proves emptiness.
The target sequence must cover all recorded successful transfer revisions.
Journal reads scale with snapshot pages; each page remains bounded, the verifier
keeps only hash/order/revision accumulators, and no new root results array exists.
The 201-item ADD and DELETE cases exercise 21 journal pages. This is not an
unbounded-scale performance claim; transaction failures leave the old state intact
and use existing retry/repair behavior.

After every read/validation succeeds, eight documents are written atomically:

1. Create target `members/{actorUid}` with existing `{role:'member'}` schema.
2. Replace the owned reverse index with ACTIVE/member/target/operationId=null.
3. Update user's familyHouseholdId and activeHouseholdId to target; retain private ID.
4. Clear source operationId and apply a fresh `advanceShoppingEpoch(now)`.
5. Mark invite USED, preserving operationId and recording usedByUid/usedAt.
6. Remove only this capacity operation ID and clear its structuralOperationId.
7. Remove only this invite from the bounded invite inventory.
8. Set operation ACTIVE/DONE, nextAt/leaseId/leaseUntil=null, updatedAt=activation
   timestamp, lastOutcome=joinActivated. Retain committed snapshot/consent/journal.

A valid live family epoch is preserved. A missing/expired family epoch is renewed
with the existing helper in the same transaction (one optional ninth root write).
Malformed epoch evidence is an integrity error. No canonical item or shopping
sequence is written by activation. There is no source cleanup or ADD replay.

Membership state and both user routing pointers become visible with fence/lock
release in the same commit. The private fallback and its owner member survive,
empty and hidden. Source epoch is advanced exactly once; the old private pointer
and old epochs cannot authorize stale requests. Fresh ensureContext and ordinary
ShoppingMutationStore requests use the family via existing authority checks.

## Recovery and post-commit events

Same-operation competing workers serialize transactionally. Worker lease expiry
is separate from the durable structural lock. An aborted activation writes nothing.
Lost acknowledgement recovers ACTIVE/DONE; resume returns DONE on terminal reentry
without reacquiring a lease, advancing epochs, consuming capacity or editing items.

Postcommit revoke/cancel returns IN_PROGRESS before activation. Natural expiry,
Pro loss and disabled admission gates do not abort. USED invite returns USED to
owner revoke afterward and cannot be reserved/reused. Cancel cannot undo the
committed JOIN. No lifecycle dissolution or removal is implemented.

Structural mismatch, foreign lock/reservation, incomplete/corrupt journal, wrong
snapshot digest/cursor, nonempty source, target inconsistency or invalid sequence/
epoch parks OPERATOR in TRANSFER_COMPLETE. No activation write is queued before
all proof reads finish; locks/fences/evidence are retained without compensation.
A malformed operation root that cannot pass the existing strict parser is rejected
before dispatch rather than repaired or guessed; it cannot partially activate.

## Account deletion boundary

Before activation, the existing JOIN_COMMITTED_IN_PROGRESS admission guard remains.
After ACTIVE, normal deletion admission and explicit non-ACTIVE marker transitions
return FAMILY_LIFECYCLE_NOT_READY for an ACTIVE Family index (owner or member),
before marker/job/Auth/private-data changes. This narrowly scoped fail-closed guard
is temporary pending the separate Family lifecycle implementation, not Phase 6.
Unexpected external Auth deletion still records the existing access barrier/job;
shared-household cleanup remains fail-closed. No automatic active Family deletion,
member removal, dissolution, rollback or account resurrection is introduced.

## Validation

Final acceptance: PASS. All required targeted groups pass on the final production code.
Local runner: demo-kuktam-local, loopback Firestore 127.0.0.1:8088; credentials
stripped by the existing guarded runner. Real production backend primitives used.

Commands:
- `npm --prefix functions run build`
- `node functions/scripts/emulator-tests.cjs --activation-regression`
- `git diff --check`

The development activation run passed 31/31; two additional epoch-integrity cases
are included in the final 33-case activation suite. Final selection also includes
complete 4B1A, 4B1B1, 4B1B2, Phase4A reservation/capacity, invite/revoke, shopping
executor/context and account-deletion regressions. The previous cleanup test checks
its retained TRANSFER_COMPLETE boundary first; subsequent worker steps now check
ACTIVE/DONE with unchanged cleanup evidence instead of the historical parked state.

No full backend/emulator matrix: existing shared lease, mutation executor, rules,
contract parsers and deletion engine are unchanged; targeted deletion coverage
exercises the small admission addition. No Flutter/native H2/Android/performance run.

## Remaining scope

4B2 PASS; Family Phase4B COMPLETE locally. Phase5 leave/
remove/dissolution, Phase6 lifecycle/account deletion/Pro-loss handling, Family UI,
operator repair/monitoring and production rollout remain separate work. No Family
runtime gate has been enabled. No deployment, commit or push was performed.

### Regression expectation adjustment

The first final selection exposed one historical invite test expecting ACTIVE
Family deletion to start and fail later in shared-household cleanup. 4B2 explicitly
requires the safer admission boundary. That test now asserts
FAMILY_LIFECYCLE_NOT_READY, no deletion job, unchanged ACTIVE marker and retained
invite. This is an intentional contract-expectation update, not a flaky failure
or an application-code fix. Its complete invite/rules suite was rerun successfully; other final suites passed on the same production code.

## Final measured validation and closure

| Suite | Final passing tests |
|---|---:|
| 4B2 activation | 33 |
| 4B1A foundation | 36 |
| 4B1B1 transfer | 28 |
| 4B1B2 source disposition | 27 |
| Phase4A reservation/capacity | 51 |
| Invite/revoke | 67 |
| Shopping executor/context | 45 |
| Account deletion | 79 |
| Household rules | 33 |
| Distinct tests with final passing evidence | 399 |

The first final selection was 366 tests: 365 PASS / 1 FAIL / 0 SKIP, exit 1,
1182233.1738 ms. Its sole failure was the historical deletion expectation detailed
above. Only that test expectation changed afterward; no production code changed.
The complete invite + household-rules rerun was 100 PASS / 0 FAIL / 0 SKIP, exit 0,
55140.0867 ms. The 67 invite tests overlap the first selection; 33 rules tests are
additional. Thus 399 distinct tests have passing final-state evidence; this is not
a claim of a single 399-test invocation. No unresolved failure or unexplained flake.
Functions build PASS, final diff check PASS. Emulators shut down normally; no local
8088 listener remains. User requested closure; no further test was started.

Logs (local only):
- C:/Users/gabor/AppData/Local/Temp/family-4b2-focused.log
- C:/Users/gabor/AppData/Local/Temp/family-4b2-final.log
- C:/Users/gabor/AppData/Local/Temp/family-4b2-invites-final.log

No mandatory 4B2 targeted test remains unfinished. A single all-green combined
rerun, full backend/emulator regression and later UI/device E2E were not performed;
they are not required by this phase's targeted policy. Full regression may be a
later release gate. No Flutter/native/Android suite is missing from 4B2 scope.
Phase5/6 implementation and its tests, UI and its tests, operator repair/monitoring
and explicit production rollout remain future milestones, not completed features.

Modified files: this checkpoint; FAMILY_JOIN_RESERVATION.md;
functions/scripts/emulator-tests.cjs; functions/src/billing/lifecycle-store.ts;
functions/src/households/family-join.ts; functions/src/households/join-capacity.ts;
functions/src/households/join-source-disposition.ts;
functions/src/households/join-transfer.ts; functions/src/households/join-activation.ts;
functions/test/family-invites.test.ts; functions/test/family-source-disposition.test.ts;
functions/test/family-join-activation.test.ts.

Final gates: 4B0 PASS (prior evidence); 4B1 COMPLETE; 4B2 PASS; Family4B COMPLETE.
Phase5 NOT STARTED; Phase6 NOT STARTED; Family UI NOT STARTED.
Production accessed NO; production rollout NO; rules/client changes NO.
DEPLOY NO; COMMIT NO; PUSH NO. Next separate milestone: Phase5. STOP.
