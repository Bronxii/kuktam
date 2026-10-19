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
