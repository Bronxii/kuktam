# Family Phase 6B2 — ACTIVE owner account-deletion orchestration

Checkpoint label: 2026-10-25. Implemented and locally validated: 2026-10-26.
Acceptance: PASS locally — final 58 PASS / 0 FAIL / 0 SKIP.

## Scope and irreversible deletion barrier

The existing recent-authenticated, empty-body deletion gateway classifies owners
server-side. An ACTIVE owner request now records a durable preparation intent,
then invokes the SAME Phase 5 dissolution engine. No account DELETING marker,
accountDeletions job, private-data cleanup or Auth deletion is performed by 6B2.

`WAITING_DISSOLUTION -> DISSOLUTION_IN_PROGRESS -> WAITING_HISTORICAL_AUDIT`

WAITING_HISTORICAL_AUDIT is the successful terminal state for this phase. It is
not an error and does not mean the account is deleted. The account remains ACTIVE
and private-only, with its preserved shopping available under normal private
routing. The existing historical DISSOLVED-family owner admission guard remains
unchanged. Phase 6C must define audit compatibility before final deletion.

Non-owner requests continue through 6B1. Private-only requests without historical
ownership continue through the existing private deletion admission. A historical
owner without an admitted 6B2 intent remains blocked by the original guard; 6B2
does not create a retrospective dissolution or edit historical ownership.

## Durable owner intent

Server-only document: `familyOwnerDeletions/{uid}`. Existing default-deny rules
protect it; no client/rules changes.

- version=1, uid, role=owner, reason=OWNER_ACCOUNT_DELETION;
- accountGeneration binds the original ACTIVE account incarnation;
- householdId, householdCreatedAt, exact privateHouseholdId;
- operationId = existing dissolutionId(uid, householdId);
- phase, createdAt, updatedAt, nextAt, lastOutcome;
- completionEvidence = null until historical handoff, then the existing
  familyOperations/{operationId}/finalization/state path.

UID + account generation identifies the one durable deletion request. Repeated
requests reuse the intent and deterministic dissolution identity. OPERATOR is a
safe stopped state; it never compensates shopping or removes locks/memberships.
Terminal handoff removes nextAt and reentry performs no writes.

A new local/demo-only familyOwnerDeletionMaintenance follows the 6A/6B1 minute
scheduler convention: at most 20 due intents, one bounded engine step per intent,
retryable failures retain work and rotate nextAt by 60 seconds. No deployed
execution or production gate is enabled. Cloud delivery/IAM is not validated by
these local tests.

## Admission and shared engine

OwnerAccountDeletionStore.admit checks authenticated UID, exact ACTIVE owner
membership, owner member row, account generation/state/no deletion job, ACTIVE
Family identity/owner/creation time, and current Family/private user routing.
It can bind an already-running dissolution whose source/target are fenced.

DissolutionPreparationStore.prepareForAccountDeletion reuses the original
bounded participant/topology validation transaction. For a new dissolution it
also reads the matching durable owner intent and original ACTIVE account
version. Its commit creates the existing PREPARED operation and structural lock,
updates the intent to DISSOLUTION_IN_PROGRESS, and writes
lifecycleAdmission/state with reason OWNER_ACCOUNT_DELETION. Existing dissolution
provenance is never overwritten when a different request wins first.

DissolutionLifecycleDriver factors the previously accepted 6A phase dispatch and
committed-JOIN ordering; both 6A and 6B2 call it. The Phase 5 engines are unchanged
apart from factoring the original terminal receipt parser for reuse:

PREPARED -> shopping fence/snapshot -> PRESERVATION_COMMITTED ->
PRESERVATION_MERGE_COMPLETE -> PRESERVATION_SOURCE_CLEANED ->
NON_OWNER_RELEASE_COMPLETE -> DONE.

No preservation, cleanup, membership exit, invite finalization, capacity or
fence-release algorithm is copied into the owner deletion orchestrator.

## Races, locks and retry

- Pro-loss and deletion: one deterministic dissolution, independent durable
  intents referencing it. Either admission reason may win. Restoration of Pro
  does not cancel an admitted owner deletion or dissolution.
- Existing owner-requested/Pro-loss dissolution: resume the same operation.
- Self-leave/owner-remove: the original atomic structural winner determines
  current topology; preparation revalidates and snapshots that topology.
- Pre-commit JOIN: original structural rules apply. Dissolution finalization
  aborts uncommitted reservations and revokes usable invites using Phase 5.
- Committed JOIN: the shared driver forward-completes JOIN to ACTIVE/DONE before
  dissolution admission; the newly active member is included in the snapshot.
- Unknown/corrupt structural ownership or OPERATOR dissolution: no takeover;
  intent is safely blocked for operator action.
- Lost intent ACK: retry reads existing intent.
- Lost admission ACK: existing operation is recognized immediately/on retry.
- Crash/lost ACK during Phase 5: original journal/receipts drive forward recovery.
- DONE before handoff ACK: validate existing terminal receipt, never start a new
  dissolution or replay merge/cleanup.
- Lost handoff ACK: return WAITING_HISTORICAL_AUDIT with no repeated epochs/effects.

New CREATE/JOIN admissions reject a user with a pending owner-deletion intent,
including the private-only interval after dissolution and the 6C handoff. This
prevents creation of a new Family dependency while deletion remains requested.
Ordinary private shopping is not blocked after Phase 5 finalization.

## Handoff evidence and live validation

The original Phase 5 finalization receipt validator verifies the operation,
participant snapshot, owner/private identities, completion timestamp, terminal
source/target epoch evidence, invite/reservation IDs and receipt hash.

One transaction binds that receipt into the intent only after verifying:

- dissolution phase/status DONE, original Family incarnation;
- account still ACTIVE at original generation, no deletion job;
- Family DISSOLVED, source operation fence cleared, source empty;
- no Family member rows or reverse indexes (ACTIVE or RESERVED), no owner index;
- owner routes to exact original valid private fallback with its owner row;
- source terminal epoch correct, target remains valid and not on pre-release
  fence epoch; legitimate later private epoch renewal is allowed;
- capacity has no reservations/structural lock, invite slots empty;
- no RESERVED or currently usable PENDING invite remains.

Shopping quantities are not rewritten or re-derived by handoff. Phase 5 receipt
proves preservation; later legitimate private shopping is not rolled back.
Inconsistent evidence yields OPERATOR, without audit editing or deletion.

## Phase 6C contract

6C may consume WAITING_HISTORICAL_AUDIT only after defining and validating how
historical DISSOLVED Family ownership/audit records coexist with account cleanup.
It must preserve idempotent identity and historical evidence, revalidate the
private-only account incarnation, and then reuse the existing private deletion
engine. This task does not define or implement that audit policy, admit a deletion
job, clean owner data, or call Auth deletion. It does not auto-start 6C.

## Local validation

Final backend build/typecheck: PASS (`npm run build`, exit 0).
Runner syntax: PASS (`node --check scripts/emulator-tests.cjs`).

Final selected run, ONCE after the final backend code change:
`node scripts/emulator-tests.cjs --owner-deletion-regression`

- 30 new 6B2 cases: PASS.
- 12 relevant 6A orchestration/JOIN/race/recovery cases: PASS.
- 7 Phase 5 terminal/invite/reservation/context/receipt cases: PASS.
- 5 relevant 6B1 member/deletion classification cases: PASS.
- 3 existing private deletion admission/gateway cases: PASS.
- 1 root export/discovery test: PASS.
- Total: 58 PASS / 0 FAIL / 0 SKIP; exit 0; 633938.7976 ms.
- Firestore demo emulator stopped normally after the run.
- Final log: C:/Users/gabor/AppData/Local/Temp/family-6b2-final.log.

Earlier implementation-only focused run: 28 PASS / 0 FAIL / 0 SKIP,
357974.258 ms, exit 0. Two additional crash/handoff cases and stronger private
content assertions were added before the final build/run. Focused log:
C:/Users/gabor/AppData/Local/Temp/family-6b2-focused.log.

The emulator reported retryable transaction lock contention in concurrent-worker
cases; SDK retry completed them successfully. No test was skipped or weakened,
and no second merge/exit/dissolution was observed.

No mandatory 6B2 test remains unexecuted. No unresolved 6B2 blocker remains.
Phase 6C is NOT STARTED. Historical audit policy and final owner account/Auth
deletion remain intentionally unimplemented. Production scheduling/delivery and
real Auth deletion are outside this local-only phase.
No full historical regression, transfer scale/performance, Flutter, native H2,
Android build, production access/deletion E2E, deploy, commit or push performed.

## Focused evidence covered by the final suite

The 30 new 6B2 cases cover:

- 1, 3 and maximum 8 participants, authenticated gateway classification;
- preserved owner milk: 1000 ml private + 300 ml + 2 l Family = 3300 ml;
- committed guest JOIN adds 200 ml before dissolution = 3500 ml;
- non-owner private item data AND document updateTime unchanged;
- duplicate requests/reentry with identical operation, receipt and epoch times;
- existing fenced owner-requested dissolution, existing Pro-loss dissolution;
- concurrent Pro-loss/deletion workers sharing the same operation;
- self-leave and owner-remove races against snapshot preparation;
- pre-commit JOIN abort/revoked pending invites through existing finalization;
- committed JOIN reaches ACTIVE/DONE before inclusion in dissolution snapshot;
- lost ACK at intent creation, admission, DONE and historical handoff;
- competing workers, durable queue/crash recovery, no repeated merge;
- transaction failure before intent, before dissolution and during handoff;
- missing fallback, wrong Family owner/structural lock, OPERATOR engine;
- corrupt terminal receipt and unexpected post-DONE source item safe blocking;
- historical-only owner still rejected by original admission guard;
- unaffected private-only account deletion admission;
- no new CREATE/JOIN while the owner deletion intent is pending;
- legitimate post-DONE private epoch refresh before handoff.

Every full owner orchestration checks accountLifecycle remains ACTIVE,
accountDeletions/owner does not exist, and finalizeContent cannot reach Auth.
FakeAuthDeletionApi.calls remains zero before, during and after dissolution.
No real Auth user is created/deleted by these tests.

## Files modified in this phase

Backend:
- functions/src/households/owner-account-deletion.ts (new intent/orchestrator)
- functions/src/households/dissolution-lifecycle-driver.ts (shared extracted driver)
- functions/src/households/owner-pro-loss.ts (uses shared driver)
- functions/src/households/dissolution-preparation.ts (trusted deletion admission)
- functions/src/households/dissolution-finalization.ts (shared receipt validator)
- functions/src/accounts/account-deletion.ts (owner classification before 6B1)
- functions/src/households/family-create.ts (pending owner deletion guard)
- functions/src/households/family-join.ts (pending owner deletion guard)
- functions/src/index.ts (local-only owner deletion maintenance)

Tests/harness:
- functions/test/owner-account-deletion.test.ts (new)
- functions/test/member-account-deletion.test.ts (owner guard assertion now checks
  the still-guarded 6B1 member path; the higher service supports owners via 6B2)
- functions/test/runtime.test.ts (export discovery)
- functions/scripts/emulator-tests.cjs (focused/final selections)

Docs:
- FAMILY_6B2_OWNER_ACCOUNT_DELETION_CHECKPOINT_2026-10-25.md (new)
- FAMILY_JOIN_RESERVATION.md (additive progress pointer)
