## S1D2A atomic ADD blocks - PASS, 2026-10-22

Baseline: 261d5602d02bd091b9ac8c84dcfc89d47e8575ac (committed S1D1).
ADD-only BULK now executes up to 10 ordered children per atomic transaction,
within the existing worker child budget. Command/hash read once; full authority
and epoch revalidated in every block and SDK retry. Repeated normalized products
share transaction-local working state. Per-child revisions/results/created proof
remain; canonical final target, household sequence, receipt/cursor and work state
commit together. Mixed parents and standalone CRUD retain the original path.
Legacy/custom or oversized targets conservatively use one-child granularity.
No whole-parent authorization cache, client change, rules change or new protocol.

Final targeted result: 175 PASS / 0 FAIL / 0 SKIP (27 new block, 29 small cost,
15 contract, 45 executor, 59 rules). Functions build and diff-check PASS.
Actual emulator-meter 1/10 costs, including command write, not billing truth:
private 1: 7 R / 5 W; private 10: 16 R / 14 W (was 70 / 41);
family 1: 9 R / 5 W; family 10: 18 R / 14 W (was 90 / 41).
No retry in baseline measurements; explicit retry/atomicity/fresh-authority and
lost-ACK recovery tests PASS. Historical S1D1 artifact is unchanged.

Details: [S1D2A_CHECKPOINT_2026-10-22.md](S1D2A_CHECKPOINT_2026-10-22.md).
Raw counts: [S1D2A_COST_MEASUREMENT.json](S1D2A_COST_MEASUREMENT.json).
S1B remains COMPLETE / ACCEPTED. S1C remains COMPLETE LOCALLY. S1D1 PASS.
S1D2A PASS; S1D NOT COMPLETE; Family Phase4B NOT READY. Next separate S1D2B
50/200 measured cost acceptance, NOT started. No production access/deploy,
commit or push. Historical sections below describe their own checkpoint dates.

## S1D1 cost measurement / design - PASS, 2026-10-22

Baseline: committed S1C 6891ceabeef90d8dd4efc34bcbcb5b18d9bbfa8d; clean worktree.
S1B remains accepted and S1C complete locally. No production business code/rules/
Dart/config changes. S1D2 optimization is NOT implemented.

Real Admin SDK/ShoppingMutationStore/Maintenance instrumentation on the guarded
local demo emulator: 35 measurement/calibration +15 contract tests PASS. Final
40 raw records in [S1D1_COST_BASELINE.json](S1D1_COST_BASELINE.json); 34 shared records
are identical across two runs. Baseline retries zero (calibration deliberately one).
Functions build/diff checks PASS. No production access/deploy/commit/push.

Read equivalent R = measured document gets + query documents + empty-query floors;
not a Firebase billed-read counter. Server processing + required continuations:
private ADD bulk 10/50/200 = R70/358/1438; family = R90/458/1838.
Writes including one request = 41/201/801. Client listeners and rules-dependent
reads are excluded, context/admission/cleanup overheads measured separately.

Recommended design ONLY: <=10 ADD children share full fresh authority inside one
atomic transaction, with sequential semantic results and atomic receipt/work;
revision/mixed paths initially unchanged. Whole-parent authority caching or an
epoch-only authorization guard is unsafe and rejected. Derived 200-child targets:
private R1438 -> <=358, family R1838 -> <=398, W801 -> <=261. Not measured optimized
performance. Exact categories, constraints, targets and S1D2 test plan:
[S1D1_CHECKPOINT_2026-10-22.md](S1D1_CHECKPOINT_2026-10-22.md).

S1D1 PASS; S1D NOT COMPLETE. Family Phase4B NOT READY. Next separate S1D2 only.
Older dated entries below preserve historical evidence, not current gate status.

## S1C local rules cutoff � PASS / COMPLETE, 2026-10-22

Baseline: accepted S1B commit d4dfe76723f1029fb6e11fda59044a84dff8bad2.
Canonical client create/update/delete now deny unconditionally; authorized reads
and the immutable mutation protocol remain unchanged. No business Dart/backend
changes. See the checkpoint's S1C entry for the exact inventory, attack cases and
rules-mediated SDK -> actual Admin processor integration coverage.

Shopping Flutter 263/263, analyzer, Functions build and S1A contract 15/15 PASS.
Full Firestore emulator regression: 662/662 PASS (includes 45 S1A executor tests).
Final focused rules/protocol validation: 59/59 PASS, overlapping the full suite.
Private/family reads preserved; direct CRUD/batches denied; client-command/Admin
CRUD, semantic merge and representative clear work. Stale direct ADD and +500
stale edit/delete are blocked with canonical data preserved. Lifecycle/migration,
source zero-bypass and diff checks PASS. No blockers.
S1B remains ACCEPTED. S1C locally COMPLETE; S1D READY but not started/complete.
Family Phase4B remains NOT READY. No production access,
deploy, gate change, commit or push. Older dated sections below are historical;
local prepared rules must not be confused with deployed production rules.

## Current implemented status — S1B ACCEPTED, H3B PASS, 2026-10-21

This section and the implemented S1A contract below describe current source.
Older dated checkpoints/design proposals are historical, not current failures
or implementation gaps. Baseline: committed H3A 79d62ee75ffd873985c55a1c09341e42856889a9.
H1/H2/H3A/H3B all PASS; S1B client migration COMPLETE / ACCEPTED.

Final full regression after the narrow AuthGate Future.sync initialization-error
fix: Flutter 1527 PASS / 0 FAIL / 1 intentional opt-in performance SKIP (1528
total); included shopping group 263 PASS. Analyze/no issues, Functions build,
backend unit 237, full Firestore emulator 653, Android debug/native test APK and
diff checks PASS. All six native H2 groups rerun on demo-kuktam-local, each exit
0: ten completed phases and seven real force-stops with successful recovery.
No backend/rules/harness contract change. Exact commands and evidence in the
checkpoint H3B section. No unexplained flaky shopping tests.

Client: SQLite schema 6, FULL synchronous, immutable UID/household/epoch/action
identity; durable backward dependencies materialize from actual receipts, never
predicted revisions. APPLIED ADD hands off immediately to canonical state, with
receipt evidence retained for dependencies. Merged/ambiguous destructive retarget
fails closed. All UI writers, clear pages and import/recipe bulk routes use the
same facade, without canonical writes or fallback. Revision-bound actions retain
the user's observed context. UID deletion markers prevent late recreation;
normal sign-out keeps accepted work. v1-v5 upgrades/reopen remain proven.

Observation: one canonical list, shared UID-root routing, one household epoch
observer; at most one receipt observer with ten parent IDs. No polling/permanent
per-mutation listeners. Indexed projection: 100 unresolved/held plus 100 terminal-
unretired parents, max 200 children per parent. Client read paths and server costs
remain as H3A documented; no cost optimization was performed.

S1C READY: YES; S1C COMPLETE: NO. Direct-write rules cutoff NOT YET APPLIED.
S1D bulk cost optimization NOT STARTED / NOT COMPLETE (known cost release gate).
Family Phase 4B NOT READY. Required next order: S1C -> S1D -> Family Phase 4B.
Do not claim S1 overall or the production flaw fully closed: older clients can
still bypass the new protocol under pre-S1C rules. Production gate remains OFF.
No production access/change/deploy, rule/App Check/Play change, commit or push.

## H3A production source / read architecture — PASS, 2026-10-21

At committed H2 baseline 52b15be967e0a4723f09cafb40cded2b26d135b3, all normal
Flutter shopping business writes exclusively use the semantic mutation protocol.
Canonical shoppingItems direct-write count = 0. Its only two lib references are
the common list subscription and bounded server absence GET. CRUD, clear pages,
text import, recipe 1x/multiplier and scaled recipe reach atomic SQLite intent
acceptance; transport writes only immutable users/{uid}/shoppingMutations IDs.
Observed revisions/context remain bound to user intent; no legacy error fallback.
Android incoming share imports recipes; it cannot auto-write shopping items.

Client read architecture (separate from server cost): one canonical list listener,
one shared users/{uid} routing listener, one household epoch listener, <=1 receipt
observer with <=10 parent IDs. UI list/notice streams only subscribe to local
coordinator events. Additional event-driven reads are ensure-context callables,
receipt/context checks after permission rejection and terminal EDIT/CHECK missing
target proofs in <=10-ID queries. ADD receipt handoff needs no absence read.
Proof attempts are once per candidate/session, reset by explicit resume recovery;
timeouts preserve uncertainty, never establish correctness. No polling/permanent
per-item listeners. Projection queries use indexed independent 100 unresolved/
held and 100 terminal-unretired parent windows, each parent <=200 children.

Server child transactions read immutable command, lifecycle/user/household/member/
reverse-index authority (family adds fallback checks), source item for revision
operations, and <=3 normalized matches for ADD/EDIT. Existing due-work maintenance
and bounded retry remain unchanged. Bulk cost optimization is deliberately later.
Legacy account cleanup of users/{uid}/shopping is distinct from canonical data;
UID-local outbox cleanup is deletion-only, not normal sign-out. Old local-submission
helper has no production callers; test/emulator wiring remains outside release.

No implementation change required. Exact source inventory and read-path exceptions
are recorded in the checkpoint. Shopping tests 263 PASS, analyze/diff PASS.
H3B full regression remains required; S1B NOT accepted, S1C/Family4B NOT ready.
Firestore rules unchanged: legacy direct-write permission is still technically
present until separate S1C. Production bug is not declared fully closed by H3A.

## H2C2B2 multi-client process-death evidence — PASS, 2026-10-21

H2 is now complete; S1B acceptance still awaits separate H3 audit/regression.
Two independent named Firebase/native Auth/Firestore/SQLite/coordinator clients
survive two abrupt whole-application force-stops in the dedicated demo AVD.
Offline restart reconstructs both original UID/context-bound requests and local
projections before reconnect. Server-existing APPLIED receipt, unobserved locally
at death, resolves with the same identity and no semantic replay. Both independent
Milk cases preserve exactly 1000+300+2000=3300 ml in one canonical row. Restarted
stale EDIT/DELETE/CHECK reject newer-state overwrite; isolated durable conflicts
and automatic canonical convergence are verified. Fifteen immutable requests and
their server results are compared, with no IDs regenerated or local UID leakage.

Protocol/product unchanged. Only the guarded local harness and new native test
were added/extended. One completed native phase PASS, two verified kills plus
successful recovery assertions, targeted Flutter 85 PASS, analyzer/native APK/
diff PASS. Prior H2 evidence audited, not rerun; see checkpoint for exact scope.
One canonical listener and at most one <=10-parent receipt observer per client;
no polling or permanent per-mutation listener. H3, S1C hardened rules and Family
Phase4B remain separate and unstarted. Production unchanged; S1 overall incomplete.

## H2C2B1 offline multi-client evidence — PASS, 2026-10-21

The same two independent native clients now prove offline semantic ADD/reconnect
safety against actual local S1A: A-first, B-first, simultaneous and receipt-flap
cases each preserve 1000+300+2000 = 3300 ml in one canonical row. Separate SQLite
intents and optimistic views do not modify the SDK's cached canonical documents.
Offline revision-bound EDIT/DELETE/CHECK reject the later stale client; reversed
winner direction is also covered. Both views converge automatically, with isolated
durable notices, original IDs/payloads and no refresh/recover/manual replay.
Final comparison covers 24 original server/local commands and receipts. No product
or protocol change. Native 1 PASS (eight checks), direct Flutter 85 PASS, analyzer/
native APK/diff PASS. See checkpoint for network controls, topology and boundaries.
H2C2B2 process-death/complex recovery, H3 and S1C remain. S1B not accepted;
Family Phase 4B not ready. Production unchanged.

## H2C2A online multi-client evidence — PASS, 2026-10-21

Two independent named native Firebase apps with separate Auth/Firestore state,
SQLite files and coordinator/dispatcher instances now exercise concurrent online
S1A execution in the guarded demo shared-household fixture. ADD deltas accumulate
exactly once, both forced creator/merge orders preserve 2300 ml, three contributions
preserve 2800 ml, and terminal command replay leaves canonical revision unchanged.
Revision-bound stale EDIT/DELETE/CHECK reject newer-state overwrite; real delivery
gates prove optimistic rollback without disabling networking. Same-state concurrent
CHECK still uses strict revision matching: one APPLIED, one STALE. Canonical views
converge on both clients without refresh. No protocol or product code change.
Native 1 PASS (11 focused checks), targeted Flutter 85 PASS, analyzer/APK/diff PASS.
This is online two-client evidence on one dedicated AVD, not offline multi-client
or lifecycle acceptance. See checkpoint for guards, orchestration and exact results.
H2C2B, H3 and S1C remain; S1B not accepted. Production unchanged.

## H2C1 native session isolation evidence — PASS, 2026-10-21

The current protocol/coordinator now has real demo-stack evidence for pending
A->B->A recovery, same-UID session-generation fencing, H1->H2 and E1->E2 binding,
persistent notice isolation and invalid write-authority cache removal across
relaunch. Abrupt process death while B is active preserves inactive A's original
SQLite request without resurrecting A subscriptions. No protocol/business-code
change was required. Actual ensure results are delayed by event gates; all
Firestore reads/writes and S1A execution remain real local emulator operations.
One coordinator, one canonical listener and <=1 receipt observer (<=10 parents)
were measured at the native session boundaries. No polling added. This is not
H3's full source/read audit. Exact phases and evidence: S1B_CHECKPOINT_2026-10-19.md.
Shopping 263 PASS, analyzer/native APK/diff check PASS; two completed native phases
and one verified abrupt termination with passing recovery, harness exit 0.
H2C2/H3/S1C remain; S1B is NOT accepted. Production unchanged.

## H2B bulk native evidence — PASS, 2026-10-20

Real SQLite/FlutterFire/S1A validation now covers 50 and 200 children through
offline acceptance, two abrupt process deaths, partial 17/73-child progress,
reconnect, mixed terminal outcomes and completed-parent reopen. No protocol or
application change was required. Child identity is immutable parent ID plus array
index; server receipts are an ordered prefix, not independently delivered child
documents. Exact quantities, unchanged prefix receipts and household-global
revision checks prove no repeated logical effects in the tested scenarios.
See S1B_CHECKPOINT_2026-10-19.md for complete evidence and test boundaries.
H2C/H3/S1C remain unperformed; S1B is NOT accepted. No production changes.

## H2A native evidence — PASS, 2026-10-20

Current H1 client protocol now has real single-client native evidence using
SQLite, local Auth/Firestore and actual S1A execution: offline CRUD, dependent
ADD operations, abrupt Android process death/restart with unchanged IDs and
requests, stale +500 protections, old epoch rejection, network flap and receipt
handoff. Three completed native phases PASS and two verified force-stops with
passing offline resumes. Shopping 263 PASS; analyzer/debug APK/diff-check PASS.
No protocol/application/backend/rules changes required. See
S1B_CHECKPOINT_2026-10-19.md for exact delivery control, failure interpretation,
environment and test scope. This does not establish H2B bulk, H2C multi-client,
H3 full acceptance or S1C hardened rules. S1B remains NOT ACCEPTED; production
direct-write rule cutoff and Family Phase 4B remain separate and unimplemented.

## H1C update — PASS, 2026-10-20

SQLite v6 backfills old accepted work, uses indexed bounded projection states, and adds UID-specific deletion tombstones/cleanup after backend acceptance. Normal sign-out retains work. Upgrade, history/starvation, dependency, overlay, partial bulk/clear and cleanup tests pass. Shopping: 263 PASS; combined targeted shopping/deletion: 297 PASS; final deletion callback recheck: 13 PASS (overlapping). Analyzer/diff-check PASS. See S1B_CHECKPOINT_2026-10-19.md for exact semantics and evidence. H1 complete; H2 is next and was NOT run. S1B acceptance/S1C/Phase 4B remain NO.

## H1B update — PASS, 2026-10-19

Session/household/observer fencing, serialized authority persistence, fail-closed ensure classification, offline invalidation persistence and live-send-safe dispatcher recovery are hardened. A testable production session registry preserves rebuild independence. Shopping 245 PASS / 0 FAIL; analyzer/diff-check PASS. No backend or production changes. See S1B_CHECKPOINT_2026-10-19.md for exact model/evidence. H1C remains; H1/S1B are not complete, H2/S1C/Phase 4B not started.

## H1A update — PASS, 2026-10-19

APPLIED ADD receipts now end the optimistic contribution immediately, independent of target query observation. ADD requires no absence lookup. Canonical state takes over (temporarily old/empty snapshots are allowed); no fake canonical state, replay, polling or backend/schema change. Created/merged ordering, delete/update, reopen and dependencies passed in 227 shopping tests; analyzer/diff-check PASS. See S1B_CHECKPOINT_2026-10-19.md for evidence. Earlier ghost-blocker statements below are historical. Remaining H1 is incomplete; H2/S1C/Phase 4B remain blocked.

## H1 status update — 2026-10-19

H1 is NOT accepted: a positive absence lookup followed by deletion before canonical observation can leave a ghost pending row. The deterministic STOP characterization reproduces it. Read S1B_CHECKPOINT_2026-10-19.md for partial fixes, validation and remaining H1 work. Actual baseline is 8b6255ce0ff6d604ff70c85c74ac2e6ac170cdc2; SQLite is now v5 in the uncommitted H1 worktree. Earlier status below is historical. H2/S1C/Phase 4B are not ready.

# Historical S1B worktree checkpoint — 2026-10-19 (superseded above)

The uncommitted client cutover is paused, not accepted. Read
[S1B_CHECKPOINT_2026-10-19.md](S1B_CHECKPOINT_2026-10-19.md) for implemented
changes, exact validation scope and remaining work. S1C direct-write rule cutoff
and Phase 4B are NOT implemented. Earlier status statements below remain
historical unless explicitly superseded by that checkpoint.

# Shopping Mutation Safety — S1 architecture

## S1B continuation, 2026-10-19 — dependency layer only

Starting HEAD: `367ec48 feat(shopping): add mutation client foundation`;
starting worktree clean. The existing contract, SQLite outbox and bounded receipt
observer were preserved. **S1B is still incomplete: no application writer cutover.**

SQLite schema version 2 adds `shoppingIntents(sequence, uid, id, draft,
dependencies, materialized)`. Version-1 journals upgrade in place. A draft has a
stable preallocated mutation ID but is NOT a submitted immutable command.
Dependencies identify an earlier action ID and child index, scoped to the same
UID, household and epoch. References must already be durable, making cycles and
forward references impossible. The shared limit of 100 pending actions includes
both held intents and materialized nonterminal requests.

For EDIT/CHECK/DELETE on an established canonical identity, the intent queue
waits for the predecessor's terminal child result. Only APPLIED with the same
item ID and a valid server revision can materialize the dependent request.
Its revision is taken from that receipt, never predicted. Inserting the final
immutable request and marking the draft materialized share one SQLite transaction.
An EDIT merge into a different canonical row fails the dependent intent safely
instead of retargeting a destructive action to unseen quantities. An unsuccessful
predecessor causes a durable conflict notice; descendants cannot silently rebase.
A successful child of a PARTIAL bulk receipt can satisfy its own dependency.
Malformed prerequisite results fail closed.

The dispatcher resolves held work after receipts and on UID binding, with no new
listener or polling. The ordinary enqueue API cannot bypass a held dependency.
Pruning retains prerequisite receipts while held intents exist, and removes
materialized intent payloads with their acknowledged, retention-expired journal
entries afterward. UID A/B isolation, reopen, duplicate enqueue, chains, schema
upgrade and retention protection have focused tests.

Still REQUIRED: ADD-to-edit resolution for a not-yet-canonical item (currently
rejected before local acceptance), application coordinator, UI-observed dependency
selection, optimistic overlay/reconciliation, Hungarian aggregate conflict UX,
all repository writers, deletion-time local queue cleanup, and genuine Flutter /
Firebase emulator E2E. No production app path calls the new intent API yet.
This dependency layer therefore does NOT establish complete rapid-action or
offline application behavior. The eight direct canonical write sites remain.
S1C and Phase 4B remain blocked on completion of S1B.

Current validation and remaining acceptance matrix: `S1B_PROGRESS_REPORT.md`.
The older sections below retain the prior baseline and approved architecture.

Status: S1A SERVER IMPLEMENTED LOCALLY; full S1 remains incomplete.
Implementation baseline: cfd3630 (approved design), containing Phase 4A 321a700.
No production changes. No Flutter writer migration. No Phase 4B transfer.

## Historical S1B foundation checkpoint — not yet cut over at that date

Baseline checked: `965318d feat(shopping): add safe mutation backend protocol`.
The worktree was clean before S1B. The following new components are not yet wired
into ShoppingRepository or the application lifecycle and MUST NOT be described
as a completed migration:

* Typed Dart requests/children/context/status/result contracts. Secure random
  256-bit mutation suffix; exact persisted payload bytes; S1A request SHA-256;
  strict field allowlists; BULK uses the S1A parent ID + child cursor, not invented
  child Firestore documents.
* SQLite outbox (`sqflite` on mobile, FFI adapter for desktop tests), FULL
  synchronous commits. UID + mutation ID unique key, immutable envelope,
  transactionally bounded 100 nonterminal parent actions per UID, no eviction of
  accepted work, UID-scoped verified-context storage, durable terminal notices.
  This is additional local storage because Firestore rollback cannot be the sole
  record of a rejected offline intention. No token or Firebase credential is
  stored in the outbox.
* A dispatcher/Firestore transport prototype: at most ten parent IDs in one
  result query, no polling, no canonical writes. Authoritative absence precedes
  first transport creation; cache absence is insufficient. Remote acknowledgement
  is not awaited by enqueue. UID/generation guards fence old callbacks. Receipts
  are matched to the original envelope/hash. Duplicate-create permission denial
  checks the existing receipt before classifying the outcome. Expired absent
  receipt is RESULT_EXPIRED, never an automatic replacement ID.

Actual process-kill/mobile crash durability, native transport integration,
dependent-action scheduling and complete reconciliation still need verification.
Reopening a SQLite file in a unit test alone is not claimed as a device kill test.
The current dispatcher also needs lifecycle/network-resume integration; its
existence does not yet prove unattended recovery in the running application.

### Re-audited production write inventory

All canonical writes are currently in `shopping_repository.dart`; **they have
NOT yet been migrated**. The table specifies the required next implementation:

| Current path | Required protocol | Offline acceptance / result |
| --- | --- | --- |
| shopping item dialog -> addOrMergeItem | ADD | durable enqueue, pending delta, receipt |
| shopping item dialog -> updateItem | EDIT | captured dialog revision/context, conflict rollback |
| shopping screen -> setItemChecked | SET_CHECKED | explicit boolean + observed revision |
| shopping screen -> deleteItem | DELETE | capture before confirmation; stale brings row back |
| shopping screen -> clearShoppingList | BULK DELETE | capture displayed IDs/revisions before confirmation; never fresh destructive scan |
| shopping text import dialog -> addOrMergeItems | BULK ADD | stable parent/cursor, one aggregate result |
| recipe details -> addOrMergeItems | BULK ADD | preserve ingredient semantics |
| recipe scaling dialog -> addOrMergeItems | BULK ADD | preserve exact scaled quantities |

Android share routes recipe input and has no additional direct shopping writer.
The old ShoppingLocalSubmission helper is still used by the old repository and
must be removed from the normal write flow during cutover, not kept as fallback.

### Remaining S1B completion gates

1. Shared authenticated session/context/canonical-list coordinator and authoritative
   epoch initialization/cache. A late context response must not bind a new UID.
2. Durable dependent-intent scheduling without guessed revisions. In particular,
   an EDIT that merges into a different canonical row must not cause a queued
   DELETE to silently delete that different row or unseen contributions.
3. Pending overlay, persisted aggregate conflict notices and acknowledgement;
   canonical-before-receipt and receipt-before-canonical ordering tests.
4. Cut over ALL inventory paths, including destructive confirmations and lists
   larger than one bounded parent, without a direct-write fallback.
5. Actual local Flutter/Firestore/backend E2E, original stale races, process death,
   offline/reconnect and full required regression/build validation.

S1B: INCOMPLETE. S1C: NOT READY. S1 overall: NOT COMPLETE. Phase 4B: NOT READY.
No production change, deploy, gate enablement, rule cutoff, commit or push.

## Implemented S1A contract (takes precedence over the historical design below)

Source: `functions/src/shopping/mutation-contract.ts` and `mutation-store.ts`.

* `users/{uid}/shoppingMutations/{mutationId}`: immutable client request containing
  exactly schemaVersion=1, mutationId, actorUid, householdId, epoch, kind,
  payloadJson and submittedAt. submittedAt is a server timestamp in Firestore
  rules. Only the authenticated path UID can create/read; no client update/delete.
* `kind`: ADD, EDIT, DELETE, SET_CHECKED or BULK. payloadJson is one strict child
  object (including type), or `{items:[...]}` for BULK. 1-200 children; names at
  most 200 Unicode scalars; payload at most 256 KiB UTF-8; whitelisted units;
  finite positive normalized quantity no greater than MAX_SAFE_INTEGER. All
  children validate before any effect. Unknown child fields are rejected.
* ADD payload: type/name/quantity/unit. EDIT additionally itemId/expectedRevision.
  DELETE: type/itemId/expectedRevision. SET_CHECKED additionally isChecked boolean.
* Epoch: `13-digit-expiryMillis-32-lowercase-hex-random`. Server creates 128 random
  bits and expiry exactly 30 days ahead. Household stores shoppingEpoch and
  shoppingEpochExpiresAt. Request ID is `epoch_64-lowercase-hex-random` (256-bit
  client-generated random suffix). Actor is also bound to document path.
* Missing legacy epoch is NOT a writable command context. ensureShoppingContext
  lazily creates one after authoritative checks; legacy item revision is zero.
  Existing shopping data stays readable. No bulk migration occurs.
* Household shoppingRevision is the shared transaction contention point and
  sequence. New item revisions use the next sequence, including deleted/recreated
  items. Lazy context initialization reads the maximum existing item revision so
  CREATE-copied revisioned items cannot reset the sequence.
* Request hash is SHA-256 of fixed envelope identity/context fields and EXACT
  payloadJson bytes, excluding submittedAt. Same ID with changed payload, even
  equivalent reformatting, is ID_CONFLICT through the authenticated submit helper;
  direct Firestore replacement is denied. Terminal receipt retains hash.
* Each child commits canonical effects, sequence, cursor, bounded results and
  continuation work atomically. No independent child ID is needed: parent ID and
  persisted child cursor identify the effect. Maximum 10 child transactions per
  normal invocation; explicit internal bound 1-20. No lease is necessary because
  every effect and progress change is a single contended Firestore transaction.
* Concurrent ADD reads current normalized target INSIDE that transaction. Every
  successful writer changes the common household sequence. Missing-target races
  retry discovery rather than create a second row. Existing duplicate rows fail
  closed. ADD preserves checked/createdAt/unknown fields; EDIT preserves current
  merge-into-another-row semantics. No arbitrary patch API.
* EDIT/DELETE/SET_CHECKED compare observed revision before any write. CHECK is an
  explicit desired boolean. Bulk children may have granular conflicts; completed
  children never replay. A context/account failure rejects remaining children.
* Results: APPLIED, PARTIAL, REJECTED_STALE, REJECTED_CONTEXT_CHANGED,
  REJECTED_NOT_FOUND, REJECTED_UNAUTHORIZED, FAILED_TERMINAL. Missing status is
  PENDING, intermediate status PROCESSING. Infrastructure failure records
  FAILED_RETRYABLE with exponential 5-minute to 1-hour backoff, up to eight failures.
  Exhaustion becomes FAILED_TERMINAL while preserving prior appliedCount/results.
  Request payload is removed on terminal completion/exhaustion.
* New exports: ensureShoppingContext (authenticated empty callable, CORE,
  europe-west1, GEN2, no secrets, App Check false) and processShoppingMutation
  (GEN2 document-create trigger, CORE, retry enabled, no secrets). Both lazy-init
  Admin. Trigger errors are sanitized, never include payload.
* `shoppingRuntime/config.enabled` must be exactly true for context issuance and
  request creation. Missing/false is OFF. No production gate changed. Already
  accepted requests can finish after gate closes. KEEP OFF during legacy cutover.
* `shoppingMutationWork/{sha256(commandPath)}` contains uid, mutationId, nextAt.
  Existing maintenance has a bounded shopping category (at most five due rows,
  at most ten children per row), isolated from billing/deletion/family. Failed
  jobs back off; no full user scan, new scheduler or polling.
* Terminal work is scheduled for epoch expiry + seven days. Payload disappears
  immediately; compact receipt/work disappear only after the ID's encoded epoch
  expiry too. Extremely delayed replay cannot pass executor expiry even before
  household rotation. Changing the payload epoch cannot preserve the old ID.
  Missing receipt after retention means RESULT_EXPIRED/unknown historical outcome
  to a future client, NEVER an instruction to automatically generate a new ID.
* Ordinary account deletion now verifies/removes shoppingMutations and orphaned
  shoppingMutationWork in bounded pages. Late trigger does not recreate absent
  request or user. Family deletion still fails closed as before.
* CREATE source reservation advances shopping epoch with its fence. New family
  context is lazily initialized after activation. Phase 4A remains unchanged.

### Current S1C rules boundary and production rollout risk

S1A originally retained direct canonical CRUD for the later client migration.
S1B has completed that migration. The local S1C rules now unconditionally deny
client create/update/delete on households/{hid}/shoppingItems/{itemId}; authorized
reads retain the existing householdWritable predicate. There are no client flags,
role exceptions or migration write exceptions. Immutable command CREATE and owner
receipt reads remain unchanged; command update/delete and technical state writes
remain denied. The production Admin processor performs canonical transactions.

HouseholdStore legacy migration and private-household account-deletion cleanup use
Admin transactions and require no client canonical permission. The separate legacy
users/{uid}/shopping compatibility/cleanup rules are unchanged; the server-owned
migration pointer already closes legacy create/update for migrated accounts.

This is LOCAL source/test preparation only. Production rules have NOT been
changed, and production gates remain OFF. No claim that the deployed production
flaw is closed. S1D cost optimization and a separately authorized rollout remain.

Rules validate the envelope and current context, not arbitrary nested JSON. The
executor strictly validates nested payload before effects; invalid JSON becomes
a sanitized terminal receipt. Family and RESERVED-private rule access-budget
paths are covered by dedicated emulator tests.

### Exact Phase 4B primitive

`advanceShoppingEpoch(now)` returns the fresh server epoch/expiry patch. A future
structural transaction must finish ALL reads first, apply this patch to source
AND destination alongside their fence/pointer changes, and never restore/reuse
old epochs. All transfer canonical writes must also use the common revision
authority. This primitive implements no transfer, JOIN activation or invite USED.

### Cost of implemented executor

Historical S1A estimates below exclude continuation overhead. The measured S1D1
baseline and SDK-versus-billing distinctions are in S1D1_CHECKPOINT_2026-10-22.md.

Per child, authorization is five document reads for ordinary private context,
seven for active family, plus one command read and one target query/item read.
RESERVED-private adds an operation read. EDIT also reads its source separately.
Firestore query minimum charges, contention retries, trigger delivery and result
listeners are additional. Values below assume ordinary private / active family,
no retries, no existing duplicates, one command and no cleanup yet:

| Action | Request writes | Processor reads | Canonical writes | Receipt writes | Work writes |
| --- | ---: | ---: | ---: | ---: | ---: |
| ADD | 1 | 7 / 9 | 2 | 1 | 1 |
| EDIT | 1 | 8 / 10 | 2 (3 when merging) | 1 | 1 |
| DELETE | 1 | 7 / 9 | 2 | 1 | 1 |
| SET_CHECKED | 1 | 7 / 9 | 2 | 1 | 1 |
| 10 ADD bulk | 1 | 70 / 90 | 20 | 10 | 10 |
| 50 ADD bulk | 1 | 350 / 450 | 100 | 50 | 50 |
| 200 ADD bulk | 1 | 1400 / 1800 | 400 | 200 | 200 |

Canonical writes include household sequence. Each maintenance continuation adds
one work-query document read and one receipt read before processing; eventual
cleanup adds work-query + receipt reads and two deletes. Submission helper adds
gate/authority/receipt reads when used instead of rules-mediated command creation.
These are estimates, not measured billing. No realtime listener is added in S1A.
Rules-mediated creation additionally incurs dependent authorization document
reads (approximately 6-9 unique documents, with rules caching), separate from
the executor reads above. Future receipt listeners can observe intermediate
cursor updates; their reads are not included in these server-only estimates.

### Exact S1B handoff

Implement UID-bound durable outbox and immutable ID/payload retry; call authenticated
empty ensureShoppingContext when context needs authoritative initialization or
refresh; observe cached household epoch. Capture item revision/context at the UI
intent boundary. Submit request with serverTimestamp and never set result fields.
Reconcile receipts by stable ID/hash with canonical stream, keep failures durable,
and do not interpret local acceptance as server ACK. Map CHECK to SET_CHECKED;
clear-list becomes BULK DELETE of observed IDs/revisions, not a fresh list scan.
Migrate manual, edit, check, delete, clear, import, recipe and scaled-recipe paths.
Then close canonical/legacy direct writes and validate offline device behavior.
S1 overall and Phase 4B remain NOT READY until that cutover is proved.

### Local validation — 2026-10-18

S1A SERVER FOUNDATION: PASS. No production execution.

* Backend unit: 237 passed, 0 failed.
* Full backend/Firestore emulator suite: 651 passed, 0 failed.
* Final affected shopping/rules/deletion/maintenance rerun after final hardening:
  197 passed, 0 failed. These overlap the full suite; do not sum them as unique tests.
* Flutter shopping repository/read compatibility: 21 passed.
* Full Flutter: 1387 passed, 0 failed, 1 intentional skip.
* Flutter analyzer, Functions TypeScript build and diff whitespace checks: PASS.
* No application Dart or native Android changes. Only a Dart read-compatibility
  test fixture was added. No Android build was needed for this backend phase.

The new executor tests prove semantic exact-once ADD, two-UID/owner-member ADD,
single logical target, stale EDIT/DELETE/SET_CHECKED rejection, old epoch rejection,
same-ID altered payload denial, post-retention replay safety, legacy item revision
zero, bulk 10/50/200 interruption/resume, atomic commit followed by lost response,
bounded retry exhaustion, granular conflicts, deleted-user cleanup and late trigger
safety. Family CREATE/invite/JOIN-reservation, billing and deletion regressions pass.

The old direct-write races are intentionally NOT claimed fixed in S1A. S1B client
migration can start; full S1 and Phase 4B remain blocked on client/rules cutover.

## Historical approved whole-S1 architecture (future client/cutover sections)

The original task's section 38 permitted a design-only stop when a larger intentional
migration is required. That condition applies: the proposed command transport
replaces the entire current client-write contract, introduces durable local
storage and asynchronous results, and requires a coordinated rules/client
cutover. Keeping any old writer enabled would invalidate the safety claim.
The original sections below described the full migration, not S1A completion.
The implemented S1A contract above supersedes conflicting proposed field names,
cost estimates and historical validation status. Phase 4B remains blocked.

## Write-path inventory (source audit)

All canonical writes currently originate in ShoppingRepository:
manual add/dialog -> addOrMergeItem; shopping text import -> addOrMergeItems;
recipe details and scaled recipe dialog -> addOrMergeItems; item dialog ->
updateItem; ShoppingListScreen -> setItemChecked/deleteItem/clearShoppingList.
Android share paths do not write shoppingItems directly. The spinner fix waits
for local pending snapshots or server acknowledgement; its error callback does
not survive process death. The shared household gateway caches verified UID-scoped
routing, not authority or item versions.

## Selected protocol

One immutable mutation request per logical action, transported through Firestore.
Canonical shoppingItems become backend-only. A durable UID-scoped local outbox
accepts actions offline before networking and retains failures across process
death. Firestore persistence alone cannot retain a request that rules reject on
reconnect, so it is insufficient as the only outbox.

ADD is a semantic delta. EDIT, DELETE and CHECK require the version observed by
the user, captured before dialog/confirmation, not reread optimistically at submit.
Bulk actions share one stable parent ID and durable cursor/results. Processing
an item and advancing its cursor commit in one transaction.

The server validates active UID/lifecycle, household membership, active pointer,
unlocked household and observed shopping epoch. A household sequence serializes
logical target resolution and becomes the revision assigned to changed items.
Legacy items start at revision zero. Recreating a deleted logical row gets a new
sequence revision, preventing ABA/stale-delete problems.

## Retention proof required before implementation is complete

Mutation IDs must be bound to their immutable shopping epoch. Deleting a receipt
is safe only when that epoch is irrevocably invalid for CREATE and processing.
A time-based TTL alone is not idempotency. The final design must specify an
explicit epoch lifetime/rotation and receipt cleanup policy, with tests proving
that arbitrarily delayed offline duplicates cannot recreate an applicable request.

## Phase 4B integration

No JOIN transfer is implemented here. Future structural operations must change
the authoritative epoch as part of acquiring source/destination fences and pointer
transitions, and use the same serialized shopping writer/revision authority.
Old-context commands must be rejected even after the fence is released.

No deploy, production mutation, commit or push.

## Exact current failure and alternatives

`shopping_repository.dart` resolves ADD targets with a query before a batch.
Two clients can both observe no target and allocate different random IDs.
Its merge-on-edit branch increments a destination and unconditionally deletes
the source. A newer increment on that source is lost when the delayed delete
commits. CHECK and ordinary DELETE similarly have no observed-item precondition.
The rules only check authorization/fence state at commit time: after unlocking,
the delayed write is authorized again. A fence is not a historical precondition.

The existing offline helper accepts a local pending snapshot and retains an
in-memory failure callback. Its own contract states that callback disappears
after restart. Bulk writes, edit and delete also still await remote completion.

Rejected approaches:

* A longer fence or delay: no upper bound on offline replay; still unsafe after
  unlocking. No arbitrary sleeps.
* A field-only epoch patch: direct DELETE carries no observed epoch; direct
  writes also lack durable idempotency receipts and atomic ADD target discovery.
* Client Firestore transactions alone: they do not supply the required durable
  offline command queue or post-restart rejection presentation.
* An in-memory outbox or snackbar callback: loses accepted actions/results at
  process death.
* Two simultaneous authoritative writer models: the old one remains a bypass.
* Receipt TTL alone: deletion allows the same old action to execute again.

## Required implementation boundary

Implement and validate these together before calling S1 complete:

1. Strict command codec and server transactional executor.
2. Server-owned context epochs, revisions and all structural-writer integration.
3. Immutable request transport, bounded continuation and safe receipt cleanup.
4. Durable UID-scoped client outbox, pending overlay and persistent outcomes.
5. Every repository/UI writer converted, including clear-list confirmation.
6. Rules deny both direct canonical writes and legacy shopping mutation bypass.
7. Existing account deletion removes new command payloads and continuation work.
8. Full race, offline, bulk, rules and regression matrix.

Nothing in this document enables JOIN transfer or changes Phase 4A.

## Proposed schema (not implemented)

### Household authority

`households/{hid}` adds server-owned fields:

* `shoppingEpoch`: random 128-bit hexadecimal identifier, never reused.
* `shoppingEpochExpiresAt`: server-established validity deadline.
* `shoppingRevision`: monotonically increasing safe integer for this household.

Existing item documents without `revision` have baseline revision zero. The
first new-protocol write assigns the next household sequence, never resets an
item to zero, and preserves unrelated fields. Household sequence initialization
must exceed any existing item revision, including items copied by CREATE.
Deleting/recreating an item therefore cannot make an old revision valid again.
Context initialization is lazy and authoritative; no bulk user migration.
Missing epoch is a read-only legacy context until initialized, not permission
to invent client authority. Offline startup may still open cached content.

### Immutable request

Path: `users/{uid}/shoppingMutations/{epoch}_{random256bitHex}`.
The client generates the random suffix once per logical action, persists it,
and never regenerates it on retry. Epoch is part of the ID as well as payload.

Client-create fields only:

* `schemaVersion: 1`
* `actorUid`: must equal authenticated UID and path UID
* `householdId`, `epoch`: observed authoritative context
* `kind`: ADD / EDIT / DELETE / CHECK / DELETE_MANY
* `payloadJson`: strict versioned payload, at most 256 KiB UTF-8
* `submittedAt`: Firestore server timestamp, not concurrency authority

JSON transport allows one bounded immutable envelope without pretending rules
can recursively validate 200 arbitrary array entries. Rules validate the
envelope, size, actor, kind, timestamp, ID/epoch relationship and current
authorization. The backend strictly validates ALL payload fields and children
before the first effect. Unknown keys, invalid types, units, non-finite or
overflowed quantities and invalid revisions fail closed. Limit ADD and
DELETE_MANY to 200 entries. Limit names to 200 Unicode scalar values and validate
the encoded envelope size separately. No arbitrary canonical field injection.

Backend fields only:

* `requestHash`: SHA-256 of canonical semantic request (excluding transport time)
* `status`, `cursor`, `appliedCount`, bounded per-child outcome list
* `createdAt`, `updatedAt`, `epochExpiresAt`, `purgeAfter`

Status is absent on client creation; the server interprets that as PENDING.
Terminal receipt retains requestHash, context, outcome and minimal affected
IDs/revisions, removing shopping names/quantities/payload. No permanent shopping
snapshot journal. Client cannot update/delete the request or receipt.
Same ID with different requestHash is a terminal integrity error. Retrying a
create against an existing document uses the existing receipt; it does not
replace it. Firestore permission-denied alone is not evidence of a failed effect.

### Continuation

`shoppingMutationWork/{hash(commandPath)}` is backend-only and contains only
command path plus `nextAt`. Initial document-create trigger processes a bounded
page; it atomically creates/updates work when more children remain. Existing
maintenance queries due work with a small limit, not users or shopping lists.
One work error cannot abort billing/deletion/family categories.

The same executor handles trigger and maintenance. Transactional cursor and
receipt contention provide mutual exclusion for effects, so a separate lease
framework is unnecessary for single-transaction pages. Crash before commit has
no effect; crash after commit resumes at the persisted cursor. No unawaited
server continuation after a response. A retrying initial trigger covers crashes
before the first continuation document is committed.

## Transaction semantics

For each child, read command/cursor, current lifecycle, user pointers, household,
membership and required reverse-index/private-fallback authority. Validate the
same standalone/family/Phase-4A RESERVED-private eligibility as current rules.
Validate ACTIVE lifecycle, unlocked context, epoch equality and server expiry.
Do not trust the command's actor merely because an Admin SDK read returned it;
the path/actor relationship and immutable rules-mediated creation are mandatory.

Read all necessary item/query data before writes. Write the household sequence
on EVERY successful mutation together with item effects and command progress.
Concurrent commands targeting an absent logical row contend on this common
household document: the retry repeats target discovery, preventing phantom
duplicate creation. Never suppress transaction retries or reuse old query data.

* ADD: trim/lowercase name; existing unit whitelist; kg -> g and l -> ml;
  positive finite quantities; group identical normalized keys. Find current
  matching row and add delta. Preserve existing isChecked/createdAt and unknown
  fields. New row is unchecked with server createdAt. Distinct action IDs each
  contribute once; repeated action ID contributes once total.
* EDIT: compare observed source ID/revision first. If renamed into an existing
  logical row, transactionally add requested quantity there and delete source,
  preserving current repository behavior. Both effects share one receipt.
  Concurrent source change causes REJECTED_STALE, never a merge/delete anyway.
* DELETE: exact observed ID/revision required; missing target is NOT_FOUND.
* CHECK: desired boolean, exact observed revision; no blind toggle.
* DELETE_MANY: explicit IDs/revisions captured when confirmation is shown.
  Never query a fresh whole list after confirmation and delete unseen new items.

Existing duplicate logical rows require fail-closed handling or a separately
specified deterministic consolidation; do not silently choose a random row and
claim the no-duplicates invariant. Detect at least two matching rows and report
a terminal repair-required result without touching data. New-protocol concurrent
ADD must never create that condition. Do not run a production repair in S1.

For bulk requests, validate the whole payload first, normalize/group ADD keys
deterministically and freeze that order. Cursor indexes normalized children.
Execute bounded pages (initial target: ten children) with atomic per-child
effects/receipt advancement. Mid-bulk context invalidation preserves prior
effects and marks remaining children rejected, reporting PARTIAL explicitly.
No rollback by issuing inverse quantities; no retry of completed children.

Result codes: APPLIED, PARTIAL, REJECTED_STALE, REJECTED_CONTEXT_CHANGED,
REJECTED_NOT_FOUND, REJECTED_UNAUTHORIZED, FAILED_TERMINAL. Infrastructure
failures preserve progress and retry the same ID; conflicts never auto-rebase.

## Offline outbox and reconciliation

Use a storage interface with real atomic durable transactions, implemented for
mobile with a suitable local database. Do not use ordinary preferences as a
critical mutation journal without proving its crash-durability contract.
Dependency selection and process-kill durability tests are implementation work
still required. Keep domain interfaces platform-neutral; no Android-only model.

Persist UID, immutable context, action ID, exact payload and pending result
before reporting local acceptance. Local storage failure remains an immediate
submission error. At most ten pending parent actions are actively dispatched
and observed; additional durable actions can wait locally with bounded storage
limits and an explicit queue-full error before acceptance. No accepted action
may be silently evicted. App startup/auth restoration and network/SDK events
resume dispatch; no polling or timeout-based duplicate submission.

One canonical active shoppingItems listener remains authoritative. Add one
active household authority listener and at most one bounded query listener for
the active pending command IDs. Rebind that query when the pending set changes;
detach it when empty. Do not create a permanent listener per command. Reuse
services across repository instances to avoid duplicate subscriptions.

Overlay is a separate pending projection, never a fake canonical snapshot:

* New-key ADD can show a pending row. Existing-key ADD shows a pending delta
  separately from confirmed quantity, avoiding double addition if canonical
  change arrives before the receipt.
* Coalesce pending actions for display only; immutable action IDs stay distinct.
* EDIT/CHECK/DELETE projections apply only to the matching observed revision.
  If canonical state advances, display that state and pending/conflict status.
* A newly pending row is not destructively editable until its authoritative ID
  and revision arrive, unless a separately proven dependency protocol is added.
* APPLIED removes the pending projection; canonical stream owns confirmed data.
* Rejection removes the projection and persists a concise conflict message until
  shown/acknowledged. Restart must not erase that message.

The edit dialog captures the original revision/context when opened. Delete and
clear confirmations capture them before awaiting user confirmation. It is unsafe
to fetch a newer revision at submit and attach it to the user's older intent.
ADD/import captures household context and session before asynchronous work.

On A -> B switch, detach A's subscriptions/overlay and stop dispatching A. A's
durable records remain namespaced under A. An already queued Firestore request
cannot execute as B because rules require actor/path/auth equality. Returning
to A resumes only A's original commands, never rewrites their actor/context.

## Retention and arbitrarily late replay proof

Proposed policy: an epoch is valid at most 30 days from SERVER initialization.
Structural transitions invalidate it earlier. No client extends its deadline.
Expired epochs are never accepted even if a maintenance/rotation job is late.
Online context refresh can create a new epoch atomically; offline users can
still open cached lists and queue intents, which may later be rejected as old
context rather than silently rewritten. This is an explicit stale-context
policy, not an online-only startup gate.

Keep terminal receipts through original epoch expiry plus seven days. A bounded
cleanup query may delete them only after checking server-owned epoch expiry;
do not trust a client purgeAfter. Incomplete work is finalized/rejected before
payload cleanup. Structural invalidation does not shorten the receipt window.

Proof obligations:

1. An original command ID includes its original epoch E.
2. Rules and executor require ID prefix == request epoch == current valid epoch.
3. After expiry, E can NEVER become valid again, even if household ID is reused.
4. Recreating the old ID after receipt cleanup therefore cannot apply.
5. Changing epoch in payload while preserving ID fails validation. A new random
   ID represents a new explicit action, never an automatic retry.

If a device returns AFTER receipt retention, it may no longer distinguish an
old applied request from an old request never received. Expose RESULT_EXPIRED /
outcome unavailable, stop automatic retry and refresh the canonical list. Never
claim confirmed success or confirmed failure in that case. This limitation and
the 30-day/7-day policy must be made explicit in the implemented client contract.
Exactly-once effect safety is distinct from indefinite historical observability.

## Account deletion and existing structural writers

Current lifecycle-store explicitly verifies recipes, legacy shopping, household
and family state. It does not know the proposed shoppingMutations subtree or
shoppingMutationWork collection. Add both to bounded cleanup/verification before
introducing them. DONE must not leave shopping payloads behind. A late trigger
must not recreate users/{uid} or reapply a deleted user's request. Lifecycle
barriers and deletion transaction conflicts must serialize against processing.
This extends ordinary owned-content cleanup, not final Family deletion semantics.

CREATE currently copies full item documents. Its source fence/pointer changes
must invalidate old epochs transactionally and its destination revision allocator
must account for copied revisions. Do not let a newly created family start a
sequence lower than copied items. Keep Phase 2 lossless-copy behavior and tests.
Phase 4A remains READY_FOR_TRANSFER, private list writable through the new common
protocol, with no JOIN item changes or pointer activation.

## Rules and rollout boundary

New rules deny canonical shoppingItems create/update/delete to ALL clients.
Legacy shopping writes must not remain a mutation bypass. Keep only the precise
read/deletion compatibility needed by coordinated account cleanup, or route that
cleanup wholly through its authoritative backend before denying legacy deletes.
Commands are owner-readable, create-only with strict envelope/context validation.
Results, work, epoch, revisions, member/index/pointer fields remain backend-only.

A coordinated cutover is necessary. Deploying deny-write rules before replacing
old clients breaks their writes; leaving direct-write rules enabled after new
client rollout does not provide S1 safety. Offline old direct batches cannot be
converted into commands retroactively. They must be rejected after cutover.
Do not enable Family JOIN until that denial is active and proven.

Proposed later rollout (not authorized here): prepare complete backend and client;
validate emulator matrix; deploy processors without public activation; distribute
controlled compatible Internal build; perform explicit rules/client cutover;
observe queued/rejected outcomes; only later resume Phase 4B development/rollout.
Rollback must not reopen direct writes while any family transfer can occur.

## Cost model (design estimates, not measured)

Let A be authorization reads per transaction: approximately 4-9 documents,
depending on standalone/family/RESERVED-private state. One-child transactions
read one receipt plus A authority documents and 0-2 item documents/queries.
Empty queries still incur a minimum read. Transaction retries add reads.
Writes include one receipt progress update, one household sequence update,
one or two canonical mutations; command creation is one additional client write.

| Operation | Approximate executor reads | Base writes incl. command creation |
| --- | ---: | ---: |
| ADD | A + 2 | 4 |
| EDIT without merge | A + 3 | 4 |
| EDIT merging another row | A + 3 | 5 |
| DELETE | A + 2 | 4 |
| CHECK | A + 2 | 4 |
| 10 distinct ADD children | 10(A + 2) | 31 |
| 50 distinct ADD children | 50(A + 2) | 151 |
| 200 distinct ADD children | 200(A + 2) | 601 |

Bulk figures assume one atomic child effect per transaction and one parent
creation, without transaction retry, continuation, terminal payload compaction
or later cleanup. Continuation scheduling and finalization add O(pages) writes
and reads; terminal receipt query/listener delivery adds client reads. These are
not quota promises. No O(n squared) whole-list discovery per child. Optimizing
multi-child transactions is permitted only after proving unchanged semantics.
Idle: no polling; an unchanged household listener adds no periodic read. Canonical
stream costs remain, plus authority changes and bounded pending-result updates.

## Required tests and current evidence

The two original counterexamples were rerun locally on this baseline using
the real Firestore rules emulator, project demo-kuktam-local:

* Fence denied writes while held; delayed ADD after release produced two rows
  with quantities 500 and 1000 instead of one row 1500.
* Delayed edit/merge/delete after a newer +500 produced 1001 instead of 1501.

Those are successful reproductions of UNSAFE current behavior, not passing
protection tests. Runner/test artifacts remain outside the repository.

Implementation release blockers: both races become blocked; all mutation types
duplicate/concurrent delivery; changed-payload replay; post-GC replay; epoch
expiry/rotation; ABA deletion/recreation; two-device and two-member ADD; 10/50/200
bulk interruption; strict malformed-envelope/payload rules; offline process kill;
outcome persistence; A -> B -> A; no spinner; every repository entry path; deletion
cleanup; CREATE/invites/Phase 4A/billing regressions. Full required Flutter/backend/
emulator/analyzer/build validation has NOT been run for an implementation,
because no implementation is present.

## Phase 4B readiness A-G

| Required proof | Current result |
| --- | --- |
| A old-context ADD blocked | NOT PROVEN / current reproduction succeeds |
| B stale EDIT cannot lose merged quantity | NOT PROVEN / current reproduction succeeds |
| C stale DELETE blocked | NOT PROVEN / direct unconditional delete remains |
| D durable offline commands/results | NOT IMPLEMENTED |
| E exactly-once effects including post-retention replay | DESIGN ONLY |
| F multi-user semantic ADD cannot lose/duplicate effects | NOT IMPLEMENTED |
| G canonical direct-write bypass denied | NO; currently allowed |

PHASE 4B READY TO RESUME: NO.

Future integration contract: acquire source AND destination structural fences
and replace their epochs transactionally before transfer. Every server shopping
writer, including transfer, uses the same sequence/item revision authority.
Old commands fail even after unlock. Pointer/member activation is atomic with
the final context change. Transfer journals remain necessary for transfer
idempotency but are not a replacement for this mutation protocol. No transfer,
activation or invite USED implementation is included in this document.
