## H2C2B2 update — PASS; H2 COMPLETE, 2026-10-21

Baseline e2df8eda0a6ddf587241e0aa3c65c227bfe9b275 (committed H2C2B1).
Two real force-stops kill BOTH independent native clients in the shared Android
process. Both restart offline with original SQLite requests and separate cached
projections. Existing server-APPLIED/local-unobserved command recovers without
replay or manual refresh; B's pending work independently completes. Two Milk
scenarios each finish at 3300 ml in one row. Stale EDIT/DELETE/CHECK after restart
are rejected; newer 510 quantities remain, B-only notices survive the next kill.
Final comparison proves all 15 original requests/IDs and server child receipts.
One completed native phase PASS plus two verified kills/successful resumes;
harness exit 0. Targeted Flutter 85 PASS; analyzer, native APK and diff check PASS.
No business code changes. Initial test-only cache/projection event ordering barrier
was corrected before final acceptance. Details and exact evidence in checkpoint.

Previous H2A/H2B/H2C1/H2C2A/H2C2B1 evidence audited and unchanged; all PASS.
H2 COMPLETE: YES. Next separate phase H3 final audit/full regression, NOT STARTED.
S1B accepted/S1C ready/Family Phase4B ready: NO. Production/deploy/commit/push: NONE.

## H2C2B1 update — PASS, 2026-10-21

Baseline f4141f4d97986687797dbe8d73f7e435b9431eb8 (committed H2C2A).
Real two-client offline/reconnect native evidence now covers A->B, B->A and
simultaneous reconnect ADD, plus one receipt-uncertainty network flap: initial
1000 ml +300 ml +2 l always yields one 3300 ml canonical row. Offline EDIT,
DELETE and CHECK conflicts reject stale revisions; B-winning/A-stale DELETE
also passes. Own optimistic state and cached canonical data stay separate.
Both clients converge without manual refresh/recover; loser-only notices,
24 unchanged immutable requests/IDs, server/local receipt equality, no duplicates.
No production or business-code change needed; same H2C2A topology reused.
Final native: 1 PASS, eight scenario checks (21s), harness exit 0.
Direct Flutter: 85 PASS / 0 FAIL. Analyzer/debug APK/harness syntax/diff check PASS.
Backend business source untouched, no broad regressions run. Exact evidence and
limits are in S1B_CHECKPOINT_2026-10-19.md. Test emulators stopped.
Next H2C2B2 ONLY, not started. H2 complete/S1B accepted/S1C ready/Phase4B ready: NO.
Production changes/deploy/commit/push: NONE.

## H2C2A update — PASS, 2026-10-21

Baseline 4860b58139108db81e79d8030fba9aac72fd8698 (committed H2C1).
Two independent native Firebase/Auth/Firestore/SQLite/coordinator clients in one
dedicated AVD now prove basic ONLINE shared-household concurrency. Same-product
ADD sums to 2300 ml in concurrent and both explicit processing orders; optional
three-command case sums to 2800 ml. Distinct products/incompatible units survive,
replayed terminal commands do not change quantity or shoppingRevision. Stale
EDIT/DELETE/CHECK are rejected, optimistic projections reconcile, +500 increments
survive. Identical concurrent CHECK intents yield one APPLIED and one STALE.
Both clients converge automatically to server data; UID-local receipts/notices
stay isolated. No polling or listener multiplication. No production-code fix.
Final evidence: 1 native test PASS (11 focused checks, 31s), harness exit 0;
85 directly affected Flutter tests PASS; analyzer/native APK/diff check PASS.
Backend business source untouched. Only local harness/new native test/docs change.
Full details and topology limitations in S1B_CHECKPOINT_2026-10-19.md.
Next H2C2B only; not started. H2/S1B/S1C/Family4B remain incomplete/not ready.
Production changes/deploy/commit/push: NONE.

## H2C1 update — PASS, 2026-10-21

Baseline `9db148a3bb5eed116c3c6c36de21ad10cdc5f8d3` (committed H2B).
Actual native demo stack now proves A->B->A, pending sign-out/same-UID relogin,
late ensure callback fencing across sessions and household/epoch changes,
UID-bound SQLite recovery, isolated durable notices and invalid authority cache
rejection after offline relaunch. One real abrupt am force-stop with B active
and A pending; restart restores B without activating A, then A recovers its ID.
One coordinator/canonical listener and <=1 bounded receipt observer observed;
inactive UID subscriptions detach. No production-code change was needed.

Final validation: 2 completed native phases PASS plus 1 verified intentional
process death and passing recovery, harness exit 0; shopping 263 PASS / 0 FAIL;
analyzer PASS; native debug APK PASS; harness syntax/diff check PASS.
Backend business source untouched. Only native test/harness/docs modified.
See checkpoint for exact measurement boundaries and local-only fixture design.
Next H2C2, not started. H2 complete/S1B accepted/S1C ready/Phase 4B ready: NO.
Production changes/deploy/commit/push: NONE.

## H2B update — PASS, 2026-10-20

Baseline 33ad58347ebea3de81bc2c5febe5094e4e873bac. Real native demo stack proves
50/200 offline bulk acceptance, unchanged parent/payload-index identities after
offline process restart, partial 17/73-child progress, a second abrupt force-stop,
resume, one event-gated network flap, exact quantities and no repeated effects.
Mixed APPLIED/STALE/NOT_FOUND/pending then CONTEXT_CHANGED yields correct PARTIAL
completion and aggregate notice. Completed-parent reopen does not replay work.
Two completed native phases PASS; two independently verified deliberate process
terminations followed by passing checks; harness exit 0. Debug APK PASS.
Final shopping Flutter: 263 PASS / 0 FAIL. Analyzer PASS (no issues),
JavaScript harness syntax PASS, git diff --check PASS including new test file.
Only test/harness/docs changed; backend business source untouched. See checkpoint
for exact fixture, revisions, sequential receipt contract and limitations.
Next H2C only. H2 complete/S1B accepted/S1C ready/Phase 4B ready: NO.
Production changes/deploy/commit/push: NONE.

## H2A update — PASS, 2026-10-20

Starting committed H1: `05310fecb28eb91b45179f11b49001b8b9c1c846`.
Current native demo-stack validation passes: offline CRUD/check-uncheck,
single-client rapid dependencies, stale +500 EDIT/DELETE, old-epoch rejection,
event-gated network flap and H1A receipt/canonical handoff. Two actual Android
force-stops (no graceful SQLite close) prove offline restart and original
request/ID/dependency retention for ADD→EDIT→CHECK and EDIT/CHECK/UNCHECK/DELETE.
Merged-ADD dependent destructive retarget also fails closed in native E2E.

Final evidence: 3 completed native phases PASS, 2 independently verified intentional
process terminations plus passing resumes; harness exit 0. Shopping 263 PASS;
analyzer/debug APK builds/diff-check PASS. Backend business code unchanged.
Only test harness/tests/docs changed. Local emulators stopped. Exact environment,
mechanism, limitations and reproduction command are in S1B_CHECKPOINT_2026-10-19.md.

Next H2B (50/200 bulk/restart) only, then H2C, H3 and S1C separately.
H2 COMPLETE: NO. S1B ACCEPTED: NO. S1C READY: NO. PHASE 4B READY: NO.
Production changes/deploy/commit/push: NONE.

## H1C update — PASS, 2026-10-20

SQLite v6 backfills old accepted work, uses indexed bounded projection states, and adds UID-specific deletion tombstones/cleanup after backend acceptance. Normal sign-out retains work. Upgrade, history/starvation, dependency, overlay, partial bulk/clear and cleanup tests pass. Shopping: 263 PASS; combined targeted shopping/deletion: 297 PASS; final deletion callback recheck: 13 PASS (overlapping). Analyzer/diff-check PASS. See S1B_CHECKPOINT_2026-10-19.md for exact semantics and evidence. H1 complete; H2 is next and was NOT run. S1B acceptance/S1C/Phase 4B remain NO.

## H1B update — PASS, 2026-10-19

Session/household/observer fencing, serialized authority persistence, fail-closed ensure classification, offline invalidation persistence and live-send-safe dispatcher recovery are hardened. A testable production session registry preserves rebuild independence. Shopping 245 PASS / 0 FAIL; analyzer/diff-check PASS. No backend or production changes. See S1B_CHECKPOINT_2026-10-19.md for exact model/evidence. H1C remains; H1/S1B are not complete, H2/S1C/Phase 4B not started.

## H1A update — PASS, 2026-10-19

APPLIED ADD receipts now end the optimistic contribution immediately, independent of target query observation. ADD requires no absence lookup. Canonical state takes over (temporarily old/empty snapshots are allowed); no fake canonical state, replay, polling or backend/schema change. Created/merged ordering, delete/update, reopen and dependencies passed in 227 shopping tests; analyzer/diff-check PASS. See S1B_CHECKPOINT_2026-10-19.md for evidence. Earlier ghost-blocker statements below are historical. Remaining H1 is incomplete; H2/S1C/Phase 4B remain blocked.

## H1 status update — 2026-10-19

H1 is NOT accepted: a positive absence lookup followed by deletion before canonical observation can leave a ghost pending row. The deterministic STOP characterization reproduces it. Read S1B_CHECKPOINT_2026-10-19.md for partial fixes, validation and remaining H1 work. Actual baseline is 8b6255ce0ff6d604ff70c85c74ac2e6ac170cdc2; SQLite is now v5 in the uncommitted H1 worktree. Earlier status below is historical. H2/S1C/Phase 4B are not ready.

# S1B continuation report — 2026-10-19

> **Latest checkpoint:** read [S1B_CHECKPOINT_2026-10-19.md](S1B_CHECKPOINT_2026-10-19.md)
> first. The final continuation added repository cutover, coordinator, overlay,
> ADD dependencies and two passing native emulator scenarios, but was paused at
> the user's request before full acceptance. The text below is historical
> sequencing-phase evidence, not the current implementation inventory.

**PHASE S1B: FAIL / INCOMPLETE. The requested full client migration was not
completed in this continuation. No external blocker has been established.**

Baseline: `367ec48 feat(shopping): add mutation client foundation`, clean worktree.
The previous foundation remains intact. This continuation implements and tests
durable dependent intent sequencing for already-identified canonical items.
It does not switch the application to the mutation protocol.

## Completed in this continuation

- SQLite v1 -> v2 upgrade preserving accepted immutable requests and contexts.
- Separate durable drafts and backward dependency references (action + child).
- Same UID / household / epoch required. No cycles or forward references.
- EDIT -> CHECK / EDIT / DELETE and CHECK -> CHECK materialize only from the
  predecessor's actual APPLIED child revision, retaining the allocated action ID.
- Atomic materialization + immutable outbox insertion. No predicted revisions.
- Changed merge destination, failed predecessor or malformed receipt resolves
  fail-closed with a persistent notice, rather than deleting unseen quantities.
- PARTIAL bulk predecessors resolve dependencies per child.
- Dispatcher resumes after receipts and session binding. No additional listeners.
- Shared 100-action limit includes held work; direct enqueue cannot bypass it.
- Retention preserves prerequisite receipts, then cleans intent payloads alongside
  eligible journal rows. Schema upgrade, reopen and concurrency tests cover this.

## Acceptance matrix — current state, not historical test claims

PHASE S1B FLUTTER CLIENT MIGRATION: FAIL / INCOMPLETE
FOUNDATION PRESERVED: YES
DEPENDENT MUTATION ORDERING: durable backwards action/child dependencies;
  existing-item paths tested; ADD-before-canonical-identity remains unimplemented.
DURABLE: YES for the implemented intent queue
RESTART SAFE: YES for SQLite close/reopen; native process-kill E2E NOT VERIFIED
APP COORDINATOR: NOT IMPLEMENTED
UID SCOPED: YES for queue/dispatcher; application-level cutover NOT COMPLETE
OUTBOX: SQLite v2, FULL synchronous, transactional intent materialization
OFFLINE DURABLE: local journal tested; complete application flow NOT VERIFIED
APP RESTART SAFE: complete application flow NOT VERIFIED
PENDING OVERLAY: NOT READY
CANONICAL DATA FAKED: NO
RESULT OBSERVATION: one bounded query of at most 10 materialized parent IDs
POLLING: NO
PER-MUTATION PERMANENT LISTENER: NO
CANONICAL SHOPPING LISTENER COUNT: shared application-level model NOT IMPLEMENTED

MANUAL ADD MIGRATED: NO
EDIT MIGRATED: NO
DELETE MIGRATED: NO
CHECK/UNCHECK MIGRATED: NO
SHOPPING TEXT IMPORT MIGRATED: NO
RECIPE -> SHOPPING MIGRATED: NO
SCALED RECIPE -> SHOPPING MIGRATED: NO
OTHER PATHS: clearShoppingList remains direct batch delete
NORMAL FLUTTER DIRECT CANONICAL WRITES: 8, all in
  lib/shopping/data/repositories/shopping_repository.dart:
  line 162 batch.update; 168 batch.set; 234 batch.update;
  237 batch.delete; 243 item.update; 254 checked.update;
  260 item.delete; 269 clear batch.delete.
LEGACY FALLBACK: no new fallback introduced; original direct writer still active

STALE ADD FULL E2E: NOT RUN / NOT PROVEN BLOCKED
+500 STALE EDIT FULL E2E: NOT RUN / NOT PROVEN BLOCKED
+500 STALE DELETE FULL E2E: NOT RUN / NOT PROVEN BLOCKED
OFFLINE ADD/EDIT/DELETE/CHECK/BULK APPLICATION FLOW: NOT VERIFIED
RESTART/RECONNECT APPLICATION FLOW: NOT VERIFIED
ACCOUNT SWITCH: queue/dispatcher tests PASS; complete app E2E NOT RUN
MULTI-CLIENT: full client E2E NOT RUN
BULK 10/50/200 FULL CLIENT FLOW: NOT RUN
LISTENER / READ AUDIT: no listener added by sequencing; full app model incomplete

S1A / CREATE / INVITE / JOIN / ACCOUNT DELETION / BILLING:
  backend and rules unchanged. Backend unit regression rerun: PASS.
  Full emulator regression NOT RERUN in this continuation.

## Validation actually run on this continuation

- Targeted mutation foundation + sequencing: **62 PASS, 0 FAIL**.
  This includes the original 39 tests and 23 additional tests.
- Full Flutter: **1449 PASS, 0 FAIL, 1 intentional SKIP**.
- Backend unit: **237 PASS, 0 FAIL**.
- Backend/Firestore emulator: **NOT RERUN**; previously reported baseline 651 PASS
  is historical, not new execution evidence.
- Flutter analyzer: **PASS**, no issues.
- Android debug APK build: **PASS**, no install or upload. Existing FlutterFire
  Kotlin migration warnings remain; no dependency upgrades made here.
- Functions TypeScript build: **PASS** (executed by test:unit).
- Diff check: **PASS** (tracked diff and new source/test files checked).
- Real Flutter/Firebase emulator E2E: **NOT RUN**.

## Files modified by this continuation only

- SHOPPING_MUTATION_SAFETY.md
- S1B_PROGRESS_REPORT.md
- lib/shopping/data/mutations/shopping_outbox.dart
- lib/shopping/data/mutations/shopping_mutation_dispatcher.dart
- lib/shopping/data/mutations/shopping_intent_queue.dart (new)
- test/shopping/shopping_mutation_dispatcher_test.dart
- test/shopping/shopping_intent_queue_test.dart (new)

## Work still required to finish the user's request

1. Safely resolve ADD -> EDIT for a newly pending logical item; connect observed
   UI references to dependency selection. Do not silently retarget merged data.
2. Wire one application/session-owned coordinator, context authority and canonical
   listener; resume without the shopping screen; complete deletion-time local cleanup.
3. Implement pending overlay, canonical/receipt ordering and persistent aggregated
   Hungarian conflict feedback without double counting.
4. Capture observed context/revision at dialog/confirmation boundaries and migrate
   every repository/UI write, including clear, text import, recipe and scaling.
5. Run genuine local Flutter-to-Firebase emulator CRUD/bulk, offline/restart,
   account-switch/multi-client and both original corruption reproductions.
6. Run all final regressions and update this report to acceptance only after all
   criteria are proven. Do not treat these green foundation tests as cutover evidence.

BLOCKERS: no external blocker established; implementation requirements above remain.
S1C READY: NO
S1 OVERALL COMPLETE: NO
PHASE 4B READY: NO
PRODUCTION CHANGES: NONE
DEPLOY: NO
DIRECT-WRITE RULE CUTOFF: NO
PHASE 4B IMPLEMENTED: NO
COMMIT: NO
PUSH: NO

---

## Historical foundation report (2026-10-18, superseded status above)

DEPLOY: NO

DIRECT-WRITE RULE CUTOFF: NO

PHASE 4B IMPLEMENTED: NO

COMMIT: NO

PUSH: NO
S1B local implementation status — 2026-10-18

**S1B IS NOT COMPLETE. This is a progress report, not acceptance of the client migration.**

Baseline: `965318d feat(shopping): add safe mutation backend protocol`.
Starting worktree: clean. Backend, rules, Image Import and Android native source
were not edited. No deployment or production access was performed.

## Implemented and locally tested

* Typed request, child, context, status and result domain contracts matching S1A.
* Stable epoch-prefixed 256-bit cryptographic action IDs; immutable persisted
  payload; SHA-256 parity fixture generated with Node/S1A hashing.
* SQLite durable local journal with FULL synchronous commits, unique UID/action
  keys, transactionally enforced queue limit, durable outcomes/notices, UID-bound
  context storage and conservative retention cleanup.
* Bounded dispatcher and Firestore transport foundation. At most ten active parent
  IDs in one query; cache absence cannot cause blind replay; authoritative receipt
  identity/hash checked; no polling and no canonical writes in this transport.
* Old UID callbacks fenced; immutable commands are not rebound to another UID or
  household. Expired missing receipts are unknown historical outcomes, not new
  actions. A duplicate-create rejection checks for an existing server receipt.
* Locally committed actions remain accepted if result observation fails to start.
  Explicit observation recovery reuses existing IDs.

These components **are not yet composed into the running application**.
SQLite reopen tests do not substitute for native process-kill/device evidence.

## Required remaining work

1. Shared session/household/epoch coordinator and one canonical shopping listener.
2. Durable dependent-action scheduling. Never guess the next item revision or
   silently retarget a dependent DELETE when an EDIT merges into a different row.
3. Pending overlay, canonical/receipt ordering reconciliation, durable aggregated
   Hungarian conflict feedback and its acknowledgement.
4. Capture context/revision at dialog/confirmation boundaries; switch every
   ShoppingRepository writer and all calling UI flows to the mutation client.
5. Wire dispatcher recovery at startup/session changes and appropriate network/SDK
   events; handle local outbox cleanup in coordinated account deletion.
6. Real local Flutter-to-Firestore-to-backend E2E, offline/process-death/reconnect,
   multiple clients and original stale ADD / +500 EDIT/DELETE reproductions.
7. Repeat final validation after integration. Green tests of the unused foundation
   do not prove the new application write path.

No external blocker has been established. These are unfinished implementation and
validation requirements; they are not waived or replaced by the foundation tests.

## Requested acceptance report

PHASE S1B FLUTTER CLIENT MIGRATION: FAIL — INCOMPLETE, not a failing-test claim

MUTATION CLIENT: NOT READY for application cutover

OUTBOX IMPLEMENTATION: SQLite/sqflite, UID-keyed immutable request journal

DURABLE OFFLINE: local SQLite commit/reopen tested; complete app/device flow NOT VERIFIED

APP RESTART SAFE: journal reopen PASS; complete application restart NOT VERIFIED

UID ISOLATION: outbox/dispatcher tests PASS; application cutover NOT VERIFIED

MUTATION ID STABLE ACROSS RETRY: YES in implemented foundation

PENDING OVERLAY IMPLEMENTED: NO

CANONICAL DATA FAKED: NO

RESULT OBSERVATION: bounded query dispatcher prototype, not application-wired

PER-MUTATION PERMANENT LISTENER: NO

POLLING: NO

CANONICAL SHOPPING LISTENERS: existing implementation unchanged; shared new coordinator pending

MANUAL ADD MIGRATED: NO

EDIT MIGRATED: NO

DELETE MIGRATED: NO

CHECK/UNCHECK MIGRATED: NO

SHOPPING TEXT IMPORT MIGRATED: NO

RECIPE → SHOPPING MIGRATED: NO

SCALED RECIPE → SHOPPING MIGRATED: NO

OTHER WRITE PATHS: full-list clear also remains to migrate

NORMAL FLUTTER DIRECT canonical shoppingItems WRITES: 8 existing write call sites in ShoppingRepository; target zero NOT achieved

AUTOMATIC LEGACY FALLBACK ADDED: NO; existing repository is not yet switched

ORIGINAL STALE ADD CLIENT E2E: NOT RUN

ORIGINAL +500 LOSS CLIENT E2E: NOT RUN

OFFLINE ADD / EDIT / DELETE / CHECK / IMPORT / RESTART / RECONNECT: new application path NOT VERIFIED

ACCOUNT SWITCH: foundation PASS; complete migrated application NOT VERIFIED

MULTI-CLIENT: new Flutter E2E NOT RUN

BULK 10 / 50 / 200: request serialization PASS; application E2E NOT RUN

FEATURE GATE: existing shoppingRuntime/config.enabled, missing/false OFF; unchanged

PRODUCTION CONFIG CHANGED: NO

## Validation

New foundation tests: 39 PASS. Full Flutter: 1426 PASS, 0 FAIL, 1 intentional SKIP.
Backend unit: 237 PASS, 0 FAIL. Functions TypeScript build: PASS.
Android debug build: PASS; no installation/upload. Native Android source unchanged.
Analyzer: PASS (no issues). Full backend/Firestore emulator: 651 PASS, 0 FAIL.
This includes the S1A mutation/rules, CREATE, invite/email, JOIN reservation,
maintenance, billing and deletion regressions. Diff whitespace check: PASS,
including new untracked source/test files.

These regression results do not substitute for the missing new Flutter E2E.

Read/listener audit: production reads are unchanged because the new dispatcher
is not wired. Its design uses one query over at most ten pending parent IDs,
rebound when that set changes, and detaches when empty. Permission-denied transport
reconciliation adds one bounded server lookup. Each child progress update can
produce a receipt read; BULK therefore is not assumed to cost only one read.
Global session sharing, the authority listener and the canonical-list coordinator
are still pending, so the final application read budget is NOT VERIFIED.

## Files belonging to this work

* SHOPPING_MUTATION_SAFETY.md
* S1B_PROGRESS_REPORT.md
* pubspec.yaml
* pubspec.lock
* macos/Flutter/GeneratedPluginRegistrant.swift (sqflite generated registration)
* lib/shopping/domain/shopping_mutation.dart
* lib/shopping/data/mutations/shopping_outbox.dart
* lib/shopping/data/mutations/shopping_mutation_transport.dart
* lib/shopping/data/mutations/shopping_mutation_dispatcher.dart
* test/shopping/shopping_mutation_contract_test.dart
* test/shopping/shopping_outbox_test.dart
* test/shopping/shopping_mutation_dispatcher_test.dart

S1C FINAL CUTOVER READY: NO

S1 OVERALL COMPLETE: NO

PHASE 4B READY: NO

Reason: application migration/reconciliation/E2E remain unfinished; direct canonical
client writes are still present and rules-permitted. S1C must subsequently close
the rule bypass and validate rollout/rollback before Phase 4B resumes.

PRODUCTION CHANGES: NONE
