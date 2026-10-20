## H1C local hardening — PASS, 2026-10-20

H1A and H1B remain green. H1 local hardening is complete; H2 native E2E is next,
not executed here. S1B acceptance, S1C and Family Phase 4B remain blocked.

SQLite v6 preserves accepted IDs, UID/household/epoch, receipts and notices. The
upgrade repairs orphan accepted requests (including v5) with materialized intent
and observation rows, never generates new IDs, and retains existing dependency
metadata. Legacy requests without observations remain executable/recoverable;
projection does not invent an observed revision for an ambiguous existing item.
Representative v1/v2/v3/v4/v5 -> v6 and v6 reopen tests pass.

Projection now uses indexed shoppingIntents.projectionState:
0 unresolved/held, 1 terminal awaiting projection reconciliation, 2 retired.
Insert/result triggers maintain state; retirement updates state and observation
atomically. Two indexed bounded selections return at most 100 unresolved + 100
terminal rows, restored to action sequence order. The existing shared 100-action
acceptance cap ensures current pending/held work fits independently of history.
Tests with 250 historical receipts prove newer work remains visible. Retired
history is excluded by the index, not sorted on each projection. Notice queries
also have a (uid,terminal,noticeAcknowledged,sequence) index. No widget polling.
This is local query verification, not the final H3 listener/read-cost audit.

Retention remains conservative: held dependencies prevent premature receipt
pruning. Acknowledged terminal payloads may be pruned only beyond retention;
late result callbacks update existing rows only and cannot recreate cleaned rows.
Existing retention/dependency regression passes.

Local account deletion differs from sign-out. Normal sign-out keeps UID-bound
accepted work for return. After backend begin is accepted, the repository supplies
its checked actual UID to the production local shopping cleanup callback. The
coordinator fences that UID's session, drains authority writes, then one SQLite
transaction removes only its mutations/intents/observations/context and stores a
minimal deletedShoppingUids UID tombstone. Stale enqueue/intent/context writes are
rejected transactionally. B data is untouched. The marker survives reopen; it
contains no shopping payload. No server receipt or canonical document is modified
by this cleanup. It is not final Family account-deletion integration.

Tests additionally cover multiple ADD receipt orderings, authoritative merge
handoff with destructive dependency rejection, ADD→EDIT→CHECK/DELETE across reopen,
terminal predecessor failure propagation, mixed applied/conflict/pending bulk,
250-item clear partial-page reopen, existing clear capacity rollback and rename
collision regressions. Pending quantities are conservative when a canonical
revision changed without disambiguating receipts; canonical state stays authoritative.

Validation:
- Shopping Flutter: 263 PASS / 0 FAIL (245 prior + 18 H1C cases).
- Combined shopping + three account-deletion suites: 297 PASS / 0 FAIL.
- Final UID callback integration recheck: 13 PASS / 0 FAIL (overlaps above).
- Final analyzer: PASS, no issues. Diff-check: PASS.
- Backend/rules untouched; no full Flutter/backend/emulator or native matrix run.

H1C-only modified files:
- lib/shopping/data/mutations/shopping_outbox.dart
- lib/shopping/data/mutations/shopping_intent_queue.dart
- lib/shopping/data/mutations/shopping_coordinator.dart
- lib/features/auth/data/repositories/account_deletion_repository.dart
- lib/settings/settings_screen.dart (only local shopping cleanup wiring)
- test/shopping/shopping_h1c_test.dart (new)
- test/shopping/shopping_intent_queue_test.dart
- test/shopping/shopping_client_fixture.dart
- test/auth/account_deletion_coordination_test.dart
- S1B_CHECKPOINT_2026-10-19.md
- S1B_PROGRESS_REPORT.md
- SHOPPING_MUTATION_SAFETY.md

H1 COMPLETE: YES. S1B ACCEPTED: NO. S1C READY: NO. PHASE 4B READY: NO.
Next: H2 expanded real native/emulator E2E, then separate H3 full validation.
Production changes/deploy/commit/push: NONE. Image Import work unchanged.
## H1B coordinator/dispatcher hardening — PASS, 2026-10-19

H1A is preserved. H1 overall is still incomplete; next scope is H1C, not H2.

Authority: auth generation, household generation and authority-write version are
separate from the opaque server epoch. Old session callbacks do not become valid
on same-UID relogin. Context saves/clears are serialized; rebind waits for prior
writes before reading cache. A server epoch stream alone cannot authorize a fresh
or definitively invalidated context. It may refresh an already verified context;
a successful ensure establishes eligibility. A delayed ensure cannot replace a
newer context received on the ordered server stream. Wrong UID/household ensure
results fail closed. Commands retain their captured household/epoch unchanged.

Definitive ensure/stream failures invalidate write authority and delete the UID's
cached context. Gate-off (failed-precondition), permission-denied, invalid account,
not-found and unknown/internal errors fail closed. Only timeout/unavailable,
deadline-exceeded/network-request-failed/resource-exhausted/aborted retain already
verified offline cache. With no cache, transient failure cannot invent authority.
After invalidation and offline SQLite reopen, raw epoch events cannot resurrect
write eligibility. Read-only canonical display is separate from write eligibility.

Dispatcher: observer generations reject queued events from replaced observers.
Session guards run after local receipt writes and dependency materialization.
Live create futures have separate guards retained across session/recovery changes;
recovery never clears a live send guard. Completed uncertain submissions can resume
bounded server observation with the same immutable ID. Only authoritative server
absence permits sending; existing PENDING commands are observed, not overwritten.
Permission-denied checks the authoritative command first; cache-only results cannot
prove rejection. Verified absence yields UNAUTHORIZED unless the existing context
inspector proves CONTEXT_CHANGED. No timer, polling or new mutation ID is used.
An outstanding SDK write stays protected until completion/receipt/process restart;
restart observes server state from the durable journal before any submission.

Production session coordinator registry is now directly testable and reused by the
production factory. Ordinary widget rebuilds reuse the same instance. Active model:
1 canonical shopping listener, 1 context/epoch listener, household-context stream,
and at most 1 receipt observer over up to 10 parent IDs. Zero per-command listeners.
No H3 read-budget audit claimed.

Validation: shopping Flutter 245 PASS / 0 FAIL (18 more than H1A); analyzer PASS;
diff-check PASS. Deterministic cases cover A→B→A, signout/relogin, delayed ensure,
late create rejection, SQLite-blocked old receipt, queued canonical callback,
household switch, delayed E1 ensure after E2 stream, gate/permission/unknown errors,
true SQLite reopen after invalidation, live-send recovery, existing PENDING command,
observer startup/error recovery, cache-only rejection lookup and widget rebuilds.
No backend changes/builds, native E2E, full Flutter/backend regression or production
operations. H1A's shopping regression remains green.

H1B-only modified files:
- lib/shopping/data/mutations/shopping_coordinator.dart
- lib/shopping/data/mutations/shopping_mutation_dispatcher.dart
- lib/shopping/data/mutations/production_shopping_coordinator.dart
- lib/shopping/data/mutations/shopping_coordinator_registry.dart (new)
- test/shopping/shopping_h1b_test.dart (new)
- test/shopping/shopping_mutation_dispatcher_test.dart
- test/shopping/shopping_client_fixture.dart
- S1B_CHECKPOINT_2026-10-19.md
- S1B_PROGRESS_REPORT.md
- SHOPPING_MUTATION_SAFETY.md

Next H1C: older outbox compatibility, projection bounds/starvation, local account
cleanup and remaining focused overlay/bulk hardening. H1 COMPLETE: NO. S1B ACCEPTED:
NO. S1C READY: NO. FAMILY PHASE 4B READY: NO. Deploy/production/commit/push: NONE.
## H1A ADD receipt handoff — PASS, 2026-10-19

This supersedes the H1 ghost-row blocker below; other H1 work remains incomplete.

Root cause: APPLIED ADD projection previously waited for target revision observation
or a separate absence proof. A positive lookup followed by deletion before query
observation supplied neither signal, leaving a completed ADD projected indefinitely.

Fix: each APPLIED ADD child immediately stops contributing optimistic state.
The existing authenticated, validated, persisted receipt is sufficient completion
proof. Canonical shopping query data takes over, even if temporarily older/empty.
A brief old quantity or absent row before the next snapshot is intentional; no
receipt payload is turned into canonical data. Created and merged ADD use the same
handoff. Other child outcomes retain their existing behavior. Partial bulk retires
only completed ADD children; unresolved children remain projected.

ADD is excluded from coordinator absence lookups: zero extra ADD network reads,
zero timers/retries/listeners for handoff, no polling, no replay. Existing absence
support for non-ADD mutations is unchanged and outside this narrow task.

Projection retirement does not delete the immutable receipt: dependencies still
use its actual itemId/revision and created=true proof. Merged/missing creation
proof remains fail-closed. A deleted target produces normal dependent NOT_FOUND
or stale rejection, never another ADD. Persisted APPLIED receipts resolve on
SQLite reopen even if projection retirement had not run; unresolved requests
retain their original IDs and pending display. No schema/backend contract change.

Validation: shopping Flutter 227 PASS / 0 FAIL; analyzer PASS; diff-check PASS.
Tests include created/merged receipt-first and snapshot-first ordering, update
then delete, deletion without any observation, positive old lookup result with
no query observation, unavailable lookup irrelevance, persisted-receipt reopen,
unresolved reopen, and ADD→EDIT/CHECK/DELETE NOT_FOUND after actual-target binding.
Existing merge fail-closed and projection/dependency tests remain green.
No native/emulator or full Flutter/backend suite run (H1A scope).

H1A files only:
- lib/shopping/data/mutations/shopping_projection.dart
- lib/shopping/data/mutations/shopping_coordinator.dart
- test/shopping/shopping_h1_test.dart
- test/shopping/shopping_coordinator_test.dart
- S1B_CHECKPOINT_2026-10-19.md
- S1B_PROGRESS_REPORT.md
- SHOPPING_MUTATION_SAFETY.md

Next: remaining H1 hardening (lifecycle/authority races, dispatcher recovery,
old outbox/bounds, local cleanup, remaining overlay cases). Do not start H2 yet.
H1 COMPLETE: NO. S1B ACCEPTED: NO. S1C READY: NO. PHASE 4B READY: NO.
Production changes/deploy/commit/push: NONE.
## H1 hardening checkpoint — 2026-10-19 (NOT ACCEPTED)

Actual H1 starting HEAD: `8b6255ce0ff6d604ff70c85c74ac2e6ac170cdc2`
(`feat(shopping): wire safe mutation client cutover`), clean at H1 start.
This section supersedes the historical uncommitted/baseline status below.

**H1 FAIL / STOP CONDITION REPRODUCED. H2 NOT READY. S1B NOT ACCEPTED.**

A deterministic test demonstrates an unresolved ghost-row race: ADD is APPLIED;
its target is absent from the canonical listener; the one-off server lookup
finds the target (returns no absent IDs); a remote deletion occurs before the
listener ever observes that item. Subsequent empty canonical snapshots do not
repeat the lookup because the action is already marked checked. The pending ADD
remains visible until explicit recovery/rebind. No mutation is replayed, but the
no-ghost guarantee is NOT satisfied. The passing characterization test named
`STOP CONDITION` proves this defect, not acceptance.

Partial H1 changes preserved in the worktree:
- UID-fenced public state and definitive ensure failures invalidate cached write
  authority; selected network/timeout failures retain recoverable cached state.
- Absence lookup has a 15-second bound, in-flight guard and explicit foreground
  recovery; proven absence persists a notice without changing the APPLIED receipt.
- Dispatcher releases uncertain sending guards; explicit recovery resets its
  observer. Live-send versus recovery ordering still needs dedicated proof.
- SQLite v5 backfills projection intents for older accepted requests, preserving
  IDs. Projection selects pending work before historical terminal rows, then
  preserves action order. Full terminal-backlog starvation proof remains open.
- Optimistic rename collisions do not invent a merged destination.

Validation: shopping-focused Flutter suite 224 PASS / 0 FAIL, including 13 new
H1 cases (one deliberately characterizes the blocker). No native/emulator test
was run in H1. Backend and rules were not touched. Final analyzer: PASS (no issues). Diff-check: PASS. Two initial brace-style
issues were fixed before the final analyzer run. No full Flutter/backend regression was run.

Next H1 work, before H2:
1. Replace the positive-lookup/canonical-list reconciliation gap with a bounded,
   authoritative resolution contract; do not solve it with polling or replay.
   Convert the STOP characterization into a no-ghost acceptance test.
2. Complete A→B→A, household/epoch and stale same-household authority races;
   test delayed SQLite writes and old in-flight proof completion after rebinding.
3. Prove dispatcher uncertainty/live-send recovery and server-existence checks;
   preserve immutable IDs, with no permanently stuck sending guard.
4. Test v1–v4 upgrade/reopen, orphan accepted requests and >200 historical
   terminal projections; prove no starvation or hidden dependency prerequisites.
5. Complete local account-deletion cleanup audit; do not conflate sign-out
   isolation with actual UID-scoped deletion cleanup.
6. Complete multiple-ADD/order matrix, ADD→EDIT→CHECK reopen, unrelated canonical
   updates and mixed partial-bulk/held-dependency cases.
7. Rerun focused shopping tests/analyzer/diff-check after those fixes.

H2 expanded native E2E and H3 full regression remain separate. S1C rules cutoff
and Family Phase 4B remain blocked. No production changes, deploy, commit or push.
# S1B safe worktree checkpoint — 2026-10-19

**PAUSED AT THE USER'S REQUEST. S1B acceptance is NOT complete.**

Continue this worktree; do not reset or recreate the implemented foundation.
Git baseline: `f53833d91ecab32ba73120a76d2ff139eb019370`
(`feat(shopping): add durable mutation sequencing`). No checkpoint commit or push
was made. This document supersedes the older acceptance state in the progress
report, not its historical test evidence.

## Implemented in this uncommitted continuation

- S1A ADD receipts now return `created` to distinguish new canonical identity
  from merging somebody else's pre-existing quantity. Two backend emulator
  tests cover the distinction, concurrency and replay.
- Pending ADD dependencies bind only to the actual APPLIED target/revision when
  `created == true`. A merge or missing proof resolves fail-closed with a durable
  conflict; no guessed target/revision. Existing sequencing is retained.
- UID-scoped coordinator, production session composition, one canonical list
  stream, persistent notices, pending projection and repository cutover exist.
- Repository business writes now enqueue typed semantic intents. Manual CRUD,
  existing text/recipe/scaled-recipe bulk callers and clear-list route through
  that facade. No automatic canonical-write fallback was introduced.
- Dialog closes after SQLite acceptance; pending rows have a sync indicator.
  Screen actions carry their observed item/context/revision.
- SQLite schema now v4: v2 intent foundation retained, v3 projection observations,
  v4 server absence proof. Multi-page clear is accepted in one local transaction
  and emits bounded commands of at most 200 children. Capacity failure rolls
  the entire local acceptance back.
- A receipt-triggered, bounded server absence lookup was added for a canonical
  item deleted again before its ADD receipt was observed. It is asynchronous
  and must not block local UI acceptance. **This latest path still needs focused
  regression/E2E coverage and review.**
- Native Android FlutterFire + real SQLite + local Firestore/Auth + actual S1A
  processor harness exists. Debug cleartext is restricted to emulator/loopback
  hosts; release configuration is unchanged. `integration_test` SDK dependency
  and its lockfile dependencies were added.
- Existing repository regression tests were adapted individually, retaining
  normalization, offline dialog, validation, scaling, identity and routing
  coverage. No wholesale removal of the old suite was performed.

## Verified evidence versus remaining validation

Completed earlier in this continuation:

- Backend unit: **237 PASS / 0 FAIL**, including Functions TypeScript build.
- Targeted backend emulator (shopping/rules/deletion/maintenance):
  **199 PASS / 0 FAIL**, including the two new ADD receipt tests.
- Native Android E2E: **2 scenario tests PASS / 0 FAIL** (`main`, `restart`).
  Main exercised real repository -> SQLite -> immutable Firestore command ->
  actual S1A processor -> canonical stream/receipt: ADD, EDIT, CHECK, DELETE,
  10-item bulk, clear, old-epoch rejection, stale EDIT and DELETE preserving
  +500, same-UID concurrent ADD, and two-UID family concurrent ADD. Restart
  retained queued ADD IDs and context across separate native test runs, started
  with Firestore networking disabled, then resynchronized without duplicate ADD.
  This was **before the final multi-page-clear/absence-proof changes**.
- Native harness delivers command snapshots to the real S1A store; it does not
  emulate the deployed Cloud Functions trigger platform. Context setup uses a
  guarded local fixture calling the real store helper. No production calls.
- Old epoch denied at command-creation rules is classified from a server context
  recheck into a local durable rejection; it is not presented as a fabricated
  server receipt.
- Full backend/emulator regression was started but **interrupted at user stop**;
  no full-suite PASS or final count may be claimed.
- Full Flutter suite has **not** been rerun after this cutover. The historical
  1449 PASS / 1 SKIP is baseline evidence only.
- Final Android debug build has not been rerun after the latest changes; the
  successful native E2E builds prove only the earlier tested revision.

Local logs are under `C:/Users/gabor/AppData/Local/Temp/`:
`s1b-final-backend-unit.log`, `s1b-final-shopping-emulator.log`,
`s1b-final-device-e2e.log`, `s1b-final-full-emulator.log`.
Final checkpoint short checks (latest worktree, including schema v4 and absence
proof implementation): **shopping suite 211 PASS / 0 FAIL; flutter analyze PASS
(no issues); git diff --check PASS**. These do not substitute for the missing
focused absence-proof coverage or final full regression/E2E rerun.

The dedicated Android emulator was stopped. No listeners remained on test ports
8088, 9098, 4408, 4508 or 8099 at shutdown verification. Automatic approval had
initially been unavailable due to usage limits; the user authorized retry and
cleanup subsequently succeeded. No remaining approval blocker.

## Required next work, in order

1. Review/test the latest absence-proof path: receipt-before-snapshot, ADD then
   remote DELETE before observation, bulk mixed results, unavailable lookup,
   account switch during lookup, schema upgrade/restart. Ensure no ghost rows,
   indefinite UI wait, accidental double count or unbounded repeated reads.
2. Complete coordinator lifecycle hardening tests: overlapping A -> B -> A binds,
   household/epoch change while SQLite or server callbacks are pending, same
   household authority races, widget rebuild independence. Distinguish definitive
   ensure-context rejection/gate OFF from transient offline fallback; current
   catch-all cache retention requires review.
3. Review dispatcher uncertain permission/context lookup recovery (`_sending`
   and observer recovery), no blind retries, and persistent user notice mapping.
4. Handle/verify older outbox requests without a shoppingIntent row in projection;
   accepted old foundation work must not disappear from pending UI. Review
   200-row projection bounds and retention so old unretired receipts cannot mask
   newer pending actions. Audit local account-deletion cleanup integration.
5. Add focused overlay tests for rename/merge collisions, multiple pending ADDs,
   ADD -> EDIT/CHECK/DELETE and chains, unrelated canonical updates, terminal
   missing rows and partial bulk. Fail closed on ambiguous destructive retargets.
6. Expand native E2E: offline EDIT/DELETE/CHECK/bulk restart, partial 50/200-item
   processing, rapid ADD dependencies, same application A -> signout -> B -> A,
   multi-client EDIT/DELETE/CHECK conflicts and stale offline reconnection.
   Existing two native scenarios do NOT prove this entire requested matrix.
   Prove forced process death explicitly; the current two-run harness closes its
   coordinator/database before ending the first native test process.
7. Final production-source bypass inventory (including imports, recipes, scaled
   recipes, clear, helper references) and exact listener/read-budget audit.
   Inspect clear confirmation capture and every UI boundary. No S1C rule cutoff.
8. Run final shopping/household/auth/recipe tests, full Flutter, analyzer, Android
   debug build, full backend unit + full backend/emulator, Functions build and
   diff-check. Run emulator suites sequentially: existing runners share ports.
9. Update SHOPPING_MUTATION_SAFETY.md and S1B_PROGRESS_REPORT.md to actual final
   acceptance only after all evidence is green. Do not claim S1B PASS early.

## Native test runner notes

- Test project is exclusively `demo-kuktam-local`; fixture checks emulator env.
- Harness: `functions/scripts/shopping-client-e2e.cjs`, config:
  `firebase.shopping-e2e.json`; native device expected `emulator-5580`.
- Flutter integration tests default to uninstall after each run. Harness now
  uses `--no-uninstall`; otherwise restart erases SQLite and cannot be tested.
- A new independent run should start from an isolated clean test device/data;
  never clear a real user's app. Within main -> restart preserve all app data.
- Restart backend uses persisted context to supply the same offline household
  bootstrap as production's cached household gateway.
- Native Firebase apps used for multiple clients must not be deleted while
  another new Auth client is being initialized (SDK lifecycle failure observed).
- Test widget SQLite work must execute in `tester.runAsync`; do not await a
  fake-zone Future from that real zone. Fixture uses real SQLite FFI without an
  isolate. No production arbitrary sleeps were added.

## Files belonging to this continuation

```text
android/app/src/debug/AndroidManifest.xml
android/app/src/debug/res/xml/emulator_network_security.xml
firebase.shopping-e2e.json
functions/scripts/shopping-client-e2e.cjs
functions/src/shopping/mutation-store.ts
functions/test/shopping-mutation.test.ts
integration_test/shopping_mutation_e2e_test.dart
lib/features/auth/presentation/widgets/auth_gate.dart
lib/shopping/data/mutations/production_shopping_coordinator.dart
lib/shopping/data/mutations/shopping_coordinator.dart
lib/shopping/data/mutations/shopping_projection.dart
lib/shopping/data/mutations/shopping_intent_queue.dart
lib/shopping/data/mutations/shopping_mutation_dispatcher.dart
lib/shopping/data/mutations/shopping_mutation_transport.dart
lib/shopping/data/mutations/shopping_outbox.dart
lib/shopping/data/repositories/shopping_repository.dart
lib/shopping/domain/models/shopping_item.dart
lib/shopping/presentation/screens/shopping_screen.dart
lib/shopping/presentation/widgets/shopping_item_dialog.dart
lib/shopping/presentation/widgets/shopping_item_tile.dart
pubspec.yaml
pubspec.lock
test/shopping/shopping_client_fixture.dart
test/shopping/shopping_coordinator_test.dart
test/shopping/shopping_core_qa_test.dart
test/shopping/shopping_intent_queue_test.dart
test/shopping/shopping_repository_test.dart
S1B_CHECKPOINT_2026-10-19.md
S1B_PROGRESS_REPORT.md
SHOPPING_MUTATION_SAFETY.md
```

## Release status

S1B: INCOMPLETE / NOT ACCEPTED. S1C READY: NO.
S1 OVERALL COMPLETE: NO. PHASE 4B READY: NO.
Production changes NONE. Deploy NO. Feature gates unchanged. Rules cutoff NO.
Image Import untouched. Commit NO. Push NO.
