## H3B final regression — PASS; S1B ACCEPTED, 2026-10-21

Authoritative latest status: S1B COMPLETE / ACCEPTED. H1, H2, H3A and H3B PASS.
All older dated sections below are historical evidence, not current gate status.
Baseline: clean committed H3A `79d62ee75ffd873985c55a1c09341e42856889a9`.
No pre-existing unrelated modifications. Final worktree has four unstaged files:
this checkpoint, S1B_PROGRESS_REPORT.md, SHOPPING_MUTATION_SAFETY.md, and
lib/features/auth/presentation/widgets/auth_gate.dart. No commit or push.

### Regression found and narrow fix

The initial full Flutter run exposed three deterministic startup failures:
`Kuktám alkalmazás elindul`, and the walkthrough `KuktamApp skip/finish reaches
AuthGate and restart retains preference` cases. With injected authentication and
no default Firebase app, productionShoppingCoordinator could throw synchronously
before its existing Future.catchError boundary. AuthGate now invokes that lookup
through Future.sync; both synchronous and asynchronous initialization failures
use the existing error boundary. Production startup still opens the coordinator
with the same condition and registry; no shopping-screen dependency or fallback
was introduced. No business backend, shopping protocol, rule or harness changes.
The existing failing tests are now green; no diagnostics/tests were suppressed.

All final acceptance suites below ran after the last application-code change.

### Final local results and exact commands

| Validation | Final result |
| --- | --- |
| `flutter test --reporter json` | 1528 total: 1527 PASS, 0 FAIL, 1 intentional SKIP |
| Shopping subset of that full run | 263 PASS, 0 FAIL; not additional unique tests |
| Auth / household / recipe subsets | 73 / 31 / 506 PASS; recipe group also contains the one skip |
| Account-deletion-named subset | 45 PASS (overlaps auth); UID cleanup also covered by shopping H1C |
| `flutter analyze` | PASS, no issues (5.3s) |
| `npm run test:unit` in functions | Functions TypeScript build PASS; 237 PASS, 0 FAIL, 0 SKIP |
| `npm run test:rules` in functions | Full demo Firestore suite: 653 PASS, 0 FAIL, 0 SKIP; exit 0 |
| `flutter build apk --debug` | PASS (final assembleDebug 10.7s) |
| `android/gradlew.bat app:assembleDebugAndroidTest` | PASS, BUILD SUCCESSFUL; native test APK |
| `git diff --check` | PASS |

The skipped test is `perf: focus and inset sweep do not scale or format` in
test/recipes/recipe_scaling_dialog_test.dart. It is guarded by
`skip: !scalingPerfEnabled`; SCALING_PERF is an opt-in non-release diagnostic,
not enabled by the normal suite. No other tests were excluded.
Builds retain existing FlutterFire Kotlin-plugin / Gradle deprecation warnings;
builds pass and analyzer has no warnings/errors. No dependency upgrade here.

Full backend coverage includes S1A contract/executor/rules, exact-once ADD,
strict EDIT/DELETE/SET_CHECKED revisions, epoch/retention, bulk 200, CREATE,
invite/email identity, JOIN reservation, household authorization, maintenance,
billing and local account deletion. All PASS. The first full emulator run also
passed 653 tests; an overlapping second launch was rejected before running tests
because its local port was occupied. It was replaced by the complete sequential
final run above (686382ms). This was runner scheduling, not a flaky test.
No unexplained intermittent shopping failure remains.

### Native H2 final rerun (unchanged committed scenarios)

Dedicated Android 35 x86_64 AVD Kuktam_H2A_Local, serial emulator-5580.
Only demo-kuktam-local: Firestore 127.0.0.1:8088, Auth 127.0.0.1:9098,
fixture HTTP 127.0.0.1:8099; Android uses emulator host 10.0.2.2.
Real SQLite, native Firebase SDKs, production client coordinator/dispatcher/
projection and actual S1A ShoppingMutationStore. Two-client groups use separate
FirebaseApp/Auth/Firestore/UID/SQLite/client state in the same Android process.

Each group ran `firebase emulators:exec --only firestore,auth --project
demo-kuktam-local --config firebase.shopping-e2e.json` with the committed
`node functions/scripts/shopping-client-e2e.cjs` and KUKTAM_E2E_SCOPE below.
Harness internally runs the corresponding integration_test/shopping_h2*.dart
with `flutter test -d emulator-5580 --no-uninstall` and its phase define.
Only dedicated com.bronxii.kuktam test-package data was cleared BETWEEN groups.
Within each group every restart/kill retained data. No real user data touched.

| Group | Completed native phases | Verified abrupt kills | Harness exit |
| --- | ---: | ---: | ---: |
| H2A | 3 PASS | 2 | 0 |
| H2B | 2 PASS | 2 | 0 |
| H2C1 | 2 PASS | 1 | 0 |
| H2C2A | 1 PASS | 0 | 0 |
| H2C2B1 | 1 PASS | 0 | 0 |
| H2C2B2 | 1 PASS | 2 | 0 |

Total: 10 completed phases PASS, 7 intentional kills with successful recovery,
all six harness exits 0. Killed intermediate runners are not ordinary passing
tests or unexplained failures. Actual mechanism: `adb -s emulator-5580 shell am
force-stop com.bronxii.kuktam`, prior PID verified and absent afterward, while
coordinator/SQLite remained open. H2C2B2 kills BOTH clients, never one-only.
All native APK builds passed. Dedicated AVD and Firebase services stopped;
ports 8088/9098/8099/4408/4508 confirmed released after completion.

Final logs: C:/Users/gabor/AppData/Local/Temp/kuktam-h3b-flutter-final.jsonl,
kuktam-h3b-analyze-final.log, kuktam-h3b-unit-final.log,
kuktam-h3b-emulator-final.log, kuktam-h3b-debug-final.log,
kuktam-h3b-android-test-build.log, kuktam-h3b-H2A.log through the six scope logs,
and kuktam-h3b-native-summary.log. Temp logs are local evidence, not committed.

### Final implementation / acceptance recheck

SQLite schema 6: FULL synchronous; upgrades v1-v5 and reopen preserve accepted
requests, IDs, bindings, prerequisites and notices. Deleted-UID tombstone blocks
late recreation; ordinary sign-out retains accepted work. Projection uses indexed
100 unresolved/held +100 terminal-unretired PARENTS, each at most 200 children.
No history scan on widget rebuild, no pending starvation regression.

Direct production canonical shopping writes: 0. The two lib shoppingItems
references remain read-only list subscription and bounded absence lookup.
Manual ADD/EDIT/CHECK/UNCHECK/DELETE, clear pages, text import, normal/scaled
recipe-to-shopping all use semantic intents; observed revision/context retained.
No legacy direct-write fallback, no new canonical writer from this fix.

Per active client: 1 canonical shopping listener, 1 shared UID-root routing
observer, 1 household epoch observer, at most 1 receipt observer over at most
10 parent IDs. No permanent per-mutation listener or polling. Normal AuthGate
startup/registry ownership is unchanged by Future.sync. Test/emulator fixtures
remain outside release code; main/release config unchanged. H3A audit retained.

S1B ACCEPTED / COMPLETE: YES. S1C READY: YES, not started or complete.
S1D bulk cost optimization: NOT STARTED / NOT COMPLETE. Family Phase 4B: NOT READY.
Next separate sequence: S1C hard rule cutoff -> S1D bulk cost optimization ->
Family Phase 4B. Existing rules STILL permit legacy canonical writes; original
production risk is not declared fully closed. Keep production gates OFF.
Production project accessed: NO. Production changes/deploy/rules/App Check/Play:
NONE. No production deletion E2E. No Image Import changes. Blockers: NONE for
S1B acceptance. Commit/push: NO. STOP; do not automatically start S1C.

## H3A final source / listener / read-path audit — PASS, 2026-10-21

Baseline: clean committed H2 `52b15be967e0a4723f09cafb40cded2b26d135b3`.
Audit scope: complete production lib/ Firestore references and set/update/delete/
commit/add/batch/transaction calls, shopping method callers, injected callbacks,
offline/catch branches, timer/delay paths, Android main/debug source separation.
No application, backend, rule or release-config modification was necessary.

### Zero-bypass inventory

Production direct canonical shoppingItems writes: **0**. Both literal canonical
references are in production_shopping_coordinator.dart:
- line 35: absentItems server-only GET, IDs grouped by 10; read-only.
- line 99: items ordered canonical query + snapshots; read-only.
No alternate dynamic shopping collection writer or native Android Firestore
writer was found. No Flutter WriteBatch/runTransaction shopping implementation.

Other write-shaped search hits are classified explicitly:
- shopping_mutation_transport.dart:98 set creates only
  users/{authenticatedUid}/shoppingMutations/{stableId}; immutable command path.
- shopping_outbox.dart and shopping_intent_queue.dart tx.update/delete/insert,
  rawDelete and database.transaction are local SQLite, not Firestore.
- ShoppingMutationChild.delete is a typed intent factory, not a document delete.
- recipe_repository.dart add/update/delete target users/{uid}/recipes.
- ingredient_repository.dart set targets ingredients/{normalizedName}, the
  ingredient-name catalog; it never changes shopping quantity/list contents.
- account_deletion_repository.dart:88-111 deletes legacy users/{uid}/shopping,
  recipes and user root AFTER coordinated deletion begin. This is explicit
  legacy-domain account cleanup, NOT a canonical household shoppingItems bypass.
- export, sharing, image preparation delete calls remove local files/directories;
  secure entitlement/household storage delete calls remove local keys. Unrelated
  domains were inspected only, not modified (including Image Import).
- list/set .add, widget setState, stream sinks and SQL helpers are not remote
  document writes. Recipe export/ingredient catalog reads are unrelated reads.
- integration_test fixtures and functions/scripts use local-only Admin setup;
  functions/src/shopping/mutation-store.ts is the authorized SERVER writer.
- shopping_local_submission.dart is an unreferenced legacy callback helper:
  no production import/caller and no Firestore reference inside it. Its generic
  commit/listener seam does not provide a reachable business-write fallback.

### Complete production entry-point trace

All routes below: mutation protocol YES; direct canonical write NO.

| Entry | Repository / intent |
| --- | --- |
| shopping_item_dialog.dart:104 EDIT | updateItem(observed: widget.item) -> EDIT with captured revision |
| shopping_item_dialog.dart:112 manual ADD | addOrMergeItem -> addOrMergeItems -> semantic ADD delta |
| shopping_screen.dart:292 checkbox | setItemChecked(observed: item, desired !item.isChecked) -> SET_CHECKED |
| shopping_screen.dart:277 confirmed delete | deleteItem(observed: captured item) -> DELETE |
| shopping_screen.dart:139 finish/clear | clearShoppingList(observed: captured List.of(items)) -> revision-bound DELETE children |
| main_screen.dart:296 text import -> shopping_import_dialog.dart:75 | confirmed parser snapshot -> addOrMergeItems -> ADD/BULK |
| recipe_details_screen.dart:468 recipe/multiplier (1x included) | normalized ingredient snapshot -> addOrMergeItems -> ADD/BULK |
| recipe_scaling_dialog.dart:89 scaled recipe | calculated normalized quantities -> addOrMergeItems -> ADD/BULK |

Common suffix: ShoppingCoordinator.add/mutate -> dispatcher.enqueueIntent(s) ->
ShoppingIntentQueue.enqueueMany SQLite transaction (FULL synchronous durability)
-> held dependency materialization and immutable outbox insertion -> bounded
receipt observer proves server absence -> transport.create immutable command.
No user-facing API accepts a presentation-supplied UID. Context comes from the
authenticated session; mutation request retains UID/household/epoch/random stable
ID. Item operations use their captured ShoppingItem.context and revision, not a
fresh item query. Pending dependencies use actual predecessor result identity/
revision; ambiguous merged-ADD destructive retarget fails closed.

Clear snapshots the observed list before confirmation resolves. Coordinator splits
into <=200-child commands; enqueueMany accepts all pages atomically or none when
the 100-action capacity is exhausted. No canonical batch.delete loop exists.
ADD never calculates a final remote quantity from a client query: local canonical
matching only records projection observations. Server owns transactional merge.
Bulk callers may normalize units/scaled quantities; no client server-list merge.
All optional injected widget callbacks default to this facade; production call
sites do not inject a competing writer.

Android SEND text -> TextShareController -> MainScreen._scheduleShare -> recipe
import; recipe files -> RecipeFileReceiver -> AddRecipeScreen. Neither directly
adds shopping. Later explicit recipe-to-shopping uses the table above. Shopping
text import is the separate confirmed main-screen dialog. Shopping share/export
uses getShoppingItems (local composed view), not a fresh canonical subscription.

### Listener ownership / client read map

- AuthGate.initState opens the production registry once per FirebaseAuth object.
  The registry memoizes the Future; repository/widget rebuilds reuse it. Auth
  changes bind the app-lifetime coordinator; resume triggers explicit recovery.
- One shared users/{uid} root listener via productionHouseholdContext and
  CachedHouseholdGateway._remoteFor, shared with HouseholdGate; last consumer
  releases it. Cached gateway deduplicates ensure calls, no polling.
- One household root snapshots observer for shopping epoch, server-confirmed
  snapshots only. It is separate from the UID/root routing observer.
- Exactly ONE canonical shoppingItems ordered snapshots listener per active
  bound client; zero while signed out. Coordinator cancels old subscriptions
  before replacements and fences auth/household/authority generations.
- At most ONE receipt query observer, WHERE documentId IN <=10 parent IDs.
  refresh chooses oldest unresolved outbox entries, cancels old query before
  replacing, and fences observation generations. Terminal receipts leave the
  pending set; rotation admits subsequent parents. Empty queue means no observer.
- watchShoppingItems/watchNotices observe only coordinator.changes locally.
  Navigation/rebuilds do not create canonical/receipt subscriptions.
- ensureShoppingContext callable on household bind validates current authority;
  ensureHouseholdContext comes through the shared household gateway. No UI poll.
- Exceptional reads: permission-denied submission first looks up <=10 receipt
  IDs (currently one), then user/root epoch if needed to classify rejection.
  Terminal EDIT/CHECK missing-target proof queries canonical IDs in groups of 10.
  ADD receipt handoff does NOT require that proof; DELETE also excluded.
  Proof candidates are bounded by the 100 terminal projection parents and <=200
  children each, not by one item per parent. One attempt per candidate/session;
  app resume explicitly permits another bounded recovery attempt. 15s timeout
  preserves uncertainty; it never proves absence or retries a semantic mutation.
  No periodic reads or permanent per-command/per-row listeners.

SQLite projection: indexed (uid,projectionState,sequence), separate LIMIT 100
unresolved/held + LIMIT 100 terminal-unretired branches, joined by UID/ID, ordered
by sequence. Retired historical parents excluded. Bound is PARENTS, each up to
200 children. Ordinary widget builds consume memory; DB projections run on
canonical/receipt/acceptance/context/recovery events. No full-history UI scan.
Notice query <=100; pending outbox <=100. H1C starvation/reopen and H2 bulk proof
remain applicable, implementation unchanged.

### Server read map (separate from client listeners)

Each mutation child transaction reads command receipt, lifecycle, user root,
household, membership and family reverse index. Family adds private fallback
root/member reads; reserved JOIN private authority may read its operation.
ADD: normalized name+unit query limit 3. EDIT: source item + same bounded query.
DELETE/CHECK: source item only. Household shoppingRevision write serializes
concurrent ADD destinations. Receipt/canonical writes commit atomically.
ensureContext additionally reads runtime gate and may query highest revision
limit 1 for lazy initialization. Maintenance queries due shoppingMutationWork
with limit min(5,pageSize), no user scan. Rules may also charge authorization
document reads; these are separate from SDK listeners. No cost optimization or
new cost claim: existing ~1400 private/~1800 family reads per 200 ADD estimate
remains a later optimization concern, not H3A scope.

Retry: original persisted request/ID only. Authoritative missing receipt precedes
create; permission denial is checked against existing receipt before terminal
classification. Network uncertainty retains work, resumes via network snapshots,
session bind or app resume; no retry timer or new ID. Expired missing receipt is
terminal resultExpired. Server deferred failures use bounded backoff (5min to
1h, at most 8 failures), maintenance keeps original identity. Stale/context/
unauthorized/terminal results never blindly rebase. No Timer.periodic or
Future.delayed in lib; recipe scaling's one-shot 500ms input debounce is local
calculation, not Firestore/status polling.

### Local cleanup / release isolation

Settings passes deletion-accepted UID to coordinator.deleteLocalAccount only
after backend begin acknowledgment. It unbinds matching active session, waits
authority writes, deletes only that UID's SQLite technical rows and retains a
deleted-UID tombstone to block late recreation. Normal sign-out only unbinds;
accepted queue remains recoverable. Existing server deletion safety unchanged.

No emulator host/config/test import in production lib. Debug-only Android
network-security XML allows cleartext solely 10.0.2.2/127.0.0.1/localhost, denies
other cleartext; main/release manifest does not reference it. Harness lives
outside release lib, guards exact demo project + loopback Firestore/Auth ports
and dedicated AVD. functions package entry is lib/src/index.js, not scripts.
No test fixture hook is reachable through normal production flows.

Validation: shopping-focused Flutter 263 PASS / 0 FAIL; H1 lifecycle, projection,
dispatcher and repository coverage included. Native H2 matrices NOT rerun.
Backend NOT TOUCHED. Flutter analyze PASS/no issues (62.9s); git diff --check PASS.
Audit found no bypass or lifecycle fix requiring code changes. H3B full regression
and final S1B acceptance remain separate. S1B ACCEPTED / S1C READY / PHASE4B READY:
NO. Production/deploy/rule cutoff/commit/push: NONE.

## H2C2B2 two-client process death — PASS; H2 COMPLETE, 2026-10-21

Baseline: clean committed H2C2B1 `e2df8eda0a6ddf587241e0aa3c65c227bfe9b275`.
No production/business/backend/rules change. Only new native test, existing local
harness scope routing and these evidence documents changed. Previous H2 test files
remain unchanged. No H3, S1C, cost optimization or Family Phase 4B work.

Topology: dedicated Android 35 x86_64 Kuktam_H2A_Local / emulator-5580,
demo-kuktam-local, Auth 127.0.0.1:9098, Firestore 127.0.0.1:8088,
fixture HTTP 127.0.0.1:8099 (Android uses 10.0.2.2). Two named FirebaseApps,
separate native Auth/Firestore instances, UIDs client-a/client-b, SQLite files,
coordinators, dispatchers and projections share only the guarded test-family
fixture and Android OS process. Actual S1A ShoppingMutationStore executes requests;
the harness replaces event delivery, not mutation business logic. Production
Family gates are untouched. Only dedicated test-package data was reset before
the entire run; all three phases use --no-uninstall and preserve app data.

Final three-phase evidence:
1. death-offline: seed Milk 1000 ml and three revision-conflict targets. Both
   clients disable Firestore networking, durably accept Milk +300 ml / +2 l,
   and three A EDIT versus B EDIT/DELETE/CHECK pairs. Eight pending requests,
   separate optimistic quantities 1300/3000, complete original request maps and
   IDs are recorded in a flushed local manifest. Both coordinators/DBs stay open.
   Host runs `adb -s emulator-5580 shell am force-stop com.bronxii.kuktam` and
   verifies PID 3915 disappeared. This kills BOTH clients, not just one.
2. death-uncertain: restart BOTH offline, using persisted native Auth, real
   SQLite and cached Firestore snapshots; ensure-context deliberately reports
   offline, never substitutes fresh server authority. Restore all original IDs,
   payloads, UID/household/epoch bindings and separate pending views before any
   reconnect. A reconnects/applies first; B's three revision operations become
   REJECTED_STALE. Both automatically converge: Milk 3300 ml in one row, each
   conflict target quantity 510 and unchecked. Three durable notices belong only
   to B. Then seed another Milk 1000 ml; accept A+300/B+2000 offline. Let A's
   immutable command reach the server, disable A networking before processing,
   execute actual S1A to APPLIED while its local result remains nonterminal.
   B stays offline/unresolved. Persist this receipt and original requests, then
   host force-stops BOTH open clients again; PID 4163 disappearance verified.
3. complete: restart BOTH offline again. Original pending quantities and complete
   requests reconstruct without server results; one unresolved request per UID.
   Reconnect A: existing server receipt resolves automatically, with NO process
   replay call or manual recovery. Reconnect/process B. Both Milk cases remain
   exactly 3300 ml, one logical row each. Compare all 15 original IDs/full local
   requests, server ID sets, originating UIDs and exact child result arrays.
   All terminal; B's three notices survive restart without A leakage. Both
   canonical views equal authoritative Firestore, no optimistic ghosts.

Deterministic control: server processing paused; one-shot command-arrival barriers
precede bounded process-selected calls. Firestore network toggles prevent receipt
delivery before the second kill. No arbitrary sleep decides correctness. The host
15s watchdog only cleans a killed Flutter runner, never retries application work.
Restart tests wait for both SQLite projection AND cached canonical snapshot events;
neither arrival is assumed first. Initial development run exposed a test barrier
that checked pending presence too early (delta-only row before cached baseline).
The final barrier also requires the correct composed quantity; no product fix or
timeout-based correctness was introduced. Initial failed run is not acceptance.

Observed per client: exactly one canonical subscription, at most one receipt
observer with <=10 parent IDs. Maximum active counts are asserted across the
run; disposal leaves zero. No permanent per-command listener, polling, ID
replacement, cross-UID local rows/notices, semantic replay or manual refresh.
Safety claims apply to the tested scenarios, not a proof against all possible bugs.

Validation:
- Native: one normally completed phase PASS (4s), two independently verified
  abrupt force-stops with successful subsequent recovery assertions; harness exit 0.
  Interrupted runners' expected "did not complete" / temp-listener cleanup errors
  are NOT counted as passed tests. All three debug/native APK builds PASS.
- Direct Flutter: 85 PASS / 0 FAIL (coordinator, dispatcher, repository, H1 tests).
- Final flutter analyze: PASS, no issues (6.7s).
- Harness JS syntax and git diff --check including new test: PASS.
- Backend business source NOT TOUCHED; no backend suite/Functions build required.
- No broad regression or old H2 matrix rerun.
- Local Firebase services and dedicated Android AVD stopped; test ports
  8088/9098/8099/4408/4508 have no remaining listeners.

Reproduce with KUKTAM_E2E_SCOPE=H2C2B2 and the existing project-local
emulators:exec command/config. Final log:
`%TEMP%\kuktam-h2c2b2-acceptance-final.log`; unit log:
`%TEMP%\kuktam-h2c2b2-flutter.log`.

H2 closing evidence audit (prior documented results retained, not rerun):
- H2A PASS: three completed phases + two abrupt stops; single-client offline CRUD,
  restart, dependencies, stale +500, old epoch, network flap and ghost sanity.
- H2B PASS: two completed phases + two abrupt stops; 50/200 bulk, partial recovery,
  stable children, mixed outcomes and completed reopen.
- H2C1 PASS: two completed phases + one abrupt stop; account/session/household/
  epoch isolation, durable notice isolation and invalid cached authority rejection.
- H2C2A PASS: one native test, 11 checks; online multi-client concurrency,
  normalization, reversed order, duplicate delivery, revision conflicts/convergence.
- H2C2B1 PASS: one native test, eight checks; offline ADD reconnect orders,
  stale EDIT/DELETE/CHECK, reversed winner, network uncertainty and convergence.
- H2C2B2 PASS: current dual-client process-death and uncertain receipt recovery.
Application/backend/rules and all previous H2 test files match this committed
baseline. Together these establish H2's durability, isolation, exact-once identity,
strict stale-revision protection, automatic convergence and bounded observations.

H2 COMPLETE: YES. STOP here. Next separate task: S1B-H3 final audit/full regression.
S1B ACCEPTED / S1C READY / PHASE 4B READY: NO.
Production changes / deploy / commit / push: NONE.

## H2C2B1 two-client offline/reconnect — PASS, 2026-10-21

Baseline: clean committed H2C2A `f4141f4d97986687797dbe8d73f7e435b9431eb8`.
Only new native test, narrow harness scope routing and evidence docs changed.
Production Dart, S1A business source, rules, release config and Image Import unchanged.
No process-death/account-switch scenarios, H2C2B2, H3, S1C or Family lifecycle work.

Topology reuses H2C2A: dedicated Android 35 x86_64 Kuktam_H2A_Local,
emulator-5580, two named native FirebaseApp instances h2c2b1-a / h2c2b1-b,
independent Auth/Firestore, UID client-a / client-b, SQLite files, coordinators,
dispatchers and projections. Distinct identities/DB paths are asserted. This is
one AVD with independent client instances, not two physical devices. Both are
members of the existing guarded local test-family fixture (owner A/member B).
No production Family gate or lifecycle operation is used.

Demo project demo-kuktam-local only; host loopback Firestore :8088, Auth :9098,
fixture :8099, hub :4408, logging :4508; Android host alias 10.0.2.2. Dedicated AVD
identity checked before whole-run app-data reset; no real user/device data touched.
Real SQLite, production repository/coordinator/dispatcher/projection/transport,
local Auth/Firestore and actual ShoppingMutationStore execute the protocol.
The new ReconnectClient only changes the TEST acceptance helper: it returns after
real repository/SQLite acceptance rather than awaiting server command arrival.
No mocked receipt or canonical payload, no replacement business implementation.

Eight native scenario checks:
1. Both observe Milk 1000 ml at the same canonical revision, then BOTH Firestore
   networks are disabled. A accepts +300 ml, B accepts +2 l. A projects 1300 ml,
   B projects 3000 ml, each pending; each Firestore cache still has original
   1000 ml/revision/check state. Verified UID-bound SQLite contexts are unchanged.
   Reconnect A, process its actual command, await its receipt/canonical 1300 ml.
   B remains offline with only its own projection and old canonical cache.
   Reconnect/process B: one canonical 3300 ml row, both clients converge.
2. Repeat with B reconnecting/committing first, then A: same one-row 3300 ml result.
3. Both reconnect together; actual S1A processing starts concurrently after both
   immutable commands arrive: same one-row 3300 ml result.
4. Focused receipt-uncertainty network flap: both queue offline; A reconnects and
   its original command reaches server. Disable A networking BEFORE processing.
   Actual server processes A while A cannot observe its receipt. Local A remains
   nonterminal/pending, immutable request unchanged. Restore A networking; receipt
   observation automatically completes. B reconnects later and adds its delta.
   Final one-row quantity 3300 ml. No coordinator recover/refresh or new ID used.
   This proves receipt-observation uncertainty, not every possible lost-ACK timing.
5-7. Separate EDIT/DELETE/CHECK fixtures: both see revision N/quantity 10, then
   both go offline. A queues EDIT to 510; B queues EDIT to 12, DELETE, or explicit
   CHECK true using N. Assert separate optimistic views (including hidden DELETE)
   and unchanged canonical caches. A reconnects/commits first. B still retains N
   and its original pending request, then reconnects: REJECTED_STALE. A's 510 and
   checked=false survive; B's projection resolves to the exact canonical item.
8. Reverse direction: B wins EDIT to 510, A's offline DELETE becomes stale.
   Same preservation/convergence and notice isolation, without A-specific logic.

After every scenario both full client views equal Source.server data by ID/name/
quantity/unit/check/revision, with no pending rows and no manual refresh/recover.
Conflict notices appear only in the losing client's UID-scoped outbox/UX and are
explicitly acknowledged. Final reconciliation proves exactly 24 distinct original
command IDs across both clients, unchanged complete local request payloads,
terminal results matching actual server receipts, equal server/local ID sets,
and zero other-UID rows in either SQLite outbox. No semantic replay, duplicate
quantity, lost contribution or stuck optimistic state in the tested paths.

Determinism: existing /process-selected is enabled for the new guarded scope,
keeps automatic worker delivery paused and processes at most three actual commands.
One-shot test arrival barriers precede processing; SDK network enable/disable
completions and receipt/canonical stream events define reconnect order. No sleep,
polling, periodic retry or manual app refresh is used. Offline here means each
real Firestore SDK's disableNetwork(), not airplane mode or Auth sign-out.
Per-client application model remains one canonical listener and <=1 receipt query
(max 10 parent IDs); maximum subscription counts and zero counts after disposal
are asserted. Two independent canonical listeners total. Test-only one-shot
command-arrival subscriptions end automatically; no permanent per-command listener.

Final validation:
- Native: 1 PASS / 0 FAIL, eight scenario checks, 21s, entire harness exit 0.
- Direct Flutter: 85 PASS / 0 FAIL (shopping_coordinator_test,
  shopping_mutation_dispatcher_test, shopping_repository_test, shopping_h1_test).
- Flutter analyze: PASS / no issues (42.1s).
- Native Android debug APK: PASS, built and installed (46.0s build).
- JavaScript harness syntax and git diff --check including new file: PASS.
- Backend business source untouched; no backend suite/Functions build rerun.
No product fix was needed. Firebase/Android test emulators stopped after completion.

Reproduce using KUKTAM_E2E_SCOPE=H2C2B1 with existing project-local Firebase CLI:
emulators:exec --only firestore,auth --project demo-kuktam-local
--config firebase.shopping-e2e.json 'node functions/scripts/shopping-client-e2e.cjs'.
Logs: %TEMP%/kuktam-h2c2b1-acceptance.log, kuktam-h2c2b1-targeted.log,
kuktam-h2c2b1-analyze.log.
Next: H2C2B2 process-death/reconnect complex recovery and H2 closing evidence ONLY.
H2 COMPLETE / S1B ACCEPTED / S1C READY / PHASE 4B READY: NO.
Production changes/deploy/commit/push: NONE.

## H2C2A basic online multi-client concurrency — PASS, 2026-10-21

Baseline: clean committed H2C1 `4860b58139108db81e79d8030fba9aac72fd8698`.
Scope strictly online concurrency. No offline/restart/account-switch matrix,
H2C2B, H3, S1C, Family lifecycle implementation or production work performed.
Application Dart, S1A business source and rules unchanged; no product bug/fix.

Topology: one dedicated Android 35 x86_64 AVD Kuktam_H2A_Local, emulator-5580,
running two named native FirebaseApp instances h2c2a-a / h2c2a-b. Each has its
own Auth/Firestore SDK instance, authenticated client-a / client-b, SQLite file,
coordinator, dispatcher, projection and receipt observer. Independence is asserted
(including different DB paths and no shared coordinator). It is NOT two devices
and NOT two coordinators sharing one Auth or outbox. Normal production repository,
coordinator, dispatcher, outbox and projection classes execute all business work.
Existing test-only callable delivery invokes the actual S1A store via loopback.

Project demo-kuktam-local only. Firestore 127.0.0.1:8088, Auth :9098, fixture :8099,
hub :4408/logging :4508; Android accesses host via 10.0.2.2. Existing guards reject
non-demo/non-emulator configuration and require the dedicated AVD. Only dedicated
AVD app data is cleared at whole-run start. Release configuration is unchanged.
The existing local fixture provisions both private fallbacks and test-family,
with A owner, B member, ACTIVE member/reverse-index records and authoritative
pointers. No Family create/invite/join feature gate is enabled; no JOIN executes.

Concurrency control: H2C2A starts automatic processor delivery paused. Both real
client immutable commands must be server-observed before the bounded fixture
accepts /process-selected (1..3 commands, local A/B UIDs only). It verifies every
command exists, then invokes actual ShoppingMutationStore.process concurrently
with Promise.all, or in explicit A->B / B->A order. No mutation logic is replaced.
No arbitrary sleep controls correctness. The one-shot test command-arrival
subscriptions terminate on server observation; they are not application listeners.

Final native acceptance covers 11 focused checks in one native test:
- Empty logical product + concurrent 300 ml and 2 l: exactly one 2300 ml row.
- Two additional pairs explicitly processed A-first and B-first: each 2300 ml,
  one row; first receipt created=true, second created=false. Concurrent winner
  is not assumed, but exactly one created and one merged receipt is required.
- Same successful immutable IDs redelivered to actual processor: canonical view
  AND household shoppingRevision unchanged; no new semantic effect.
- Optional three-command case across two independent clients (A/B/A):
  300 ml + 2 l + 500 ml = one 2800 ml row. No third client was necessary.
- Distinct Milk/Flour deltas both survive (2000 ml and 500 g).
- Same-name incompatible units remain two rows: 2000 ml and 1 db.
- Stale EDIT, DELETE and SET_CHECKED: both clients first see revision N; A adds
  +500 and commits a higher revision. A real B canonical snapshot is held by a
  Completer delivery gate while B remains ONLINE. B submits observed revision N;
  optimistic quantity=12 / hidden row / checked=true is asserted BEFORE processing.
  Actual server receipt is REJECTED_STALE. After receipt and gate release, B
  automatically returns to A's newer exact row/revision/quantity. Every +500
  survives (final conflict quantity 1501). Durable conflict belongs to B only;
  A has no notice. Acknowledgement is explicit, not auto-retry/rebase.
- Both clients request checked=true at the same revision: exactly one APPLIED,
  one REJECTED_STALE under existing revision semantics; final checked=true.

After every scenario, BOTH client views must equal a Source.server query across
all item IDs/names/quantities/units/check state/revisions, with no pending flags.
No manual refresh/recover call is used. Final local requests and server receipts
are compared by ID/actor/result; all terminal, no ID collision, no other UID rows
in either SQLite database and server/local command ID sets match exactly.
Observed application listener model per client: one canonical subscription,
at most one receipt query with 1..10 parent IDs, no per-command permanent listener,
no polling. Two clients therefore have two canonical listeners total. Subscription
maximum is asserted and disposal returns counts to zero. This is targeted sanity,
NOT the final H3 listener/cost/source audit.

Validation on final source:
- Native: 1 PASS / 0 FAIL, all 11 scenario checks; 31s; harness exit 0.
- Targeted Flutter: 85 PASS / 0 FAIL (shopping_coordinator_test,
  shopping_mutation_dispatcher_test, shopping_repository_test, shopping_h1_test).
- Flutter analyze: PASS / no issues (6.2s).
- Android debug/native APK: PASS (built/installed for acceptance).
- JavaScript syntax and git diff --check including new test: PASS.
- Backend business source untouched; no backend test/build rerun required.
- First native version also passed; final version adds explicit optimistic
  hide/edit/check evidence using delivery gates, without changing business code.

Run: KUKTAM_E2E_SCOPE=H2C2A with the existing project-local Firebase CLI
emulators:exec --only firestore,auth --project demo-kuktam-local
--config firebase.shopping-e2e.json 'node functions/scripts/shopping-client-e2e.cjs'.
Local logs: %TEMP%/kuktam-h2c2a-acceptance.log, kuktam-h2c2a-targeted.log,
kuktam-h2c2a-analyze.log. Firebase and dedicated Android emulators stopped.
Next: H2C2B offline/reconnect multi-client + remaining complex conflict recovery.
H2 COMPLETE / S1B ACCEPTED / S1C READY / PHASE 4B READY: NO.
Production changes/deploy/commit/push: NONE.

## H2C1 account/session native isolation — PASS, 2026-10-21

Baseline: clean committed H2B `9db148a3bb5eed116c3c6c36de21ad10cdc5f8d3`.
Only the local harness, new native test and evidence documentation changed.
Production Dart, S1A business backend, rules and Image Import remain unchanged.

Environment: Kuktam_H2A_Local / emulator-5580 / Android 35 x86_64;
demo-kuktam-local, Firestore 127.0.0.1:8088, Auth :9098, fixture :8099,
hub :4408, logging :4508. Android uses host loopback alias 10.0.2.2.
AVD identity is checked before resetting dedicated test app data at run start.
No uninstall/data reset between phases. Real user device/data is not used.
Firebase emulators and dedicated Android emulator were stopped after acceptance.

Native test uses one real Firebase Auth instance, real SQLite file and the actual
ShoppingCoordinatorRegistry, ShoppingCoordinator, dispatcher, intent queue,
projection, repository and Firestore transport. Auth state changes bind that same
coordinator; registry opener count remains one per process despite repeated gets.
Test bootstrap supplies demo Firebase instances instead of the production singleton
factory. Callable delivery is the existing local fixture invoking the actual
ShoppingMutationStore.ensureContext; mutation processing uses actual S1A store.
No fabricated context, mutation result, canonical item or receipt is substituted.

Three native phases:
1. death-transition: A accepts offline ADD in SQLite and displays it pending.
   Sign-out clears active projection/notice/authority and all A subscriptions,
   but preserves original request and mutation ID. B signs in, accepts its own
   pending ADD, then completes it using the real processor. A remains pending
   and unchanged in SQLite, invisible to B. A/B IDs differ. Host runs
   `adb -s emulator-5580 shell am force-stop com.bronxii.kuktam` while B is active
   and coordinator/SQLite are open. PID 4132 existed before and none afterward;
   no graceful close. A manifest was flushed before the signal.
2. resume-transition: restart restores Auth B, B canonical state and invisible A
   request with byte-equivalent decoded payload/ID. Return to A processes its
   original ADD exactly once: one row, quantity 3, unchanged request; B row is
   absent from A's private list. Delayed real ensure completions are released
   across A->B, B->A, and A->sign-out->A. For same-UID relogin the new session's
   epoch is advanced before old completion, proving it cannot downgrade authority.
   Pending same-UID work keeps its ID and receives CONTEXT_CHANGED, never rebases.
   Separate same-session E1->E2 test retains old request epoch, rejects it and
   accepts a new E2 action. Durable rejection notices are hidden from B and
   restored to A without duplicate IDs. Local family fixture switches A from
   private H1 to H2; delayed H1 completion cannot overwrite H2, old request stays
   H1/E1 and is rejected, new action targets H2. Server H2 contains only its new
   item. This is a structural test fixture, NOT JOIN or multi-client execution.
   Actual local runtime gate denial clears SQLite authority; new submission fails.
3. invalid-reopen: a separate app launch starts with Firestore networking disabled,
   Auth A retained and previously invalidated authority absent. It cannot create a
   new mutation from old cache. A and B UID-scoped persistent mutation rows remain
   intact and correctly bound. This last cache test uses a normal close/relaunch;
   abrupt process-death proof is specifically phase 1 followed by phase 2.

Deterministic delayed callback injection covers actual ensure-context Future
completion (one of the requested callback types), not every SDK callback type
individually. Canonical/household/authority/receipt subscriptions are real and
instrumented at subscribe/cancel boundaries; inactive UID counts are zero.
At active checkpoints: one coordinator/dispatcher, one canonical listener,
one household and one authority listener, at most one receipt observer with
1..10 parent IDs. Maximum simultaneous canonical/receipt subscriptions <=1.
Signed out: zero listeners/observers. No polling or per-mutation listener added.
No new logical mutation ID, context rebinding or duplicate effect in tested flows.
These are targeted H2C1 observations, not H3's final source/read-budget audit.

Validation on final test source:
- Native: 2 completed phases PASS (9s and 1s), 1 independently verified intentional
  process termination with passing resume; entire harness exit 0.
- The killed Flutter test deliberately reports did-not-complete; it is not counted
  as a normally completed passing test. Host PID verification and resume assertions
  are its durability evidence. Runner cleanup warning after force-stop is expected.
- Shopping Flutter: 263 PASS / 0 FAIL (`flutter test test/shopping --reporter expanded`).
- Flutter analyze: PASS / no issues (6.9s).
- Android debug/native APK: PASS, built and installed for all three phases.
- JavaScript harness syntax and git diff --check (including new native file): PASS.
- Backend business source untouched; backend suites/build not rerun.
- Initial harness-only failure tried reusing a deleted FirebaseApp in the same
  process. Moving cache proof to a separate app launch resolved it; no product fix.

Reproduce after dedicated AVD boot and fresh dedicated test app data:
`$env:KUKTAM_E2E_SCOPE='H2C1'`
`node .\functions\node_modules\firebase-tools\lib\bin\firebase.js emulators:exec --only firestore,auth --project demo-kuktam-local --config firebase.shopping-e2e.json 'node functions/scripts/shopping-client-e2e.cjs'`
Local evidence logs: `%TEMP%\kuktam-h2c1-acceptance.log`,
`%TEMP%\kuktam-h2c1-shopping.log`, `%TEMP%\kuktam-h2c1-analyze.log`.

Next: H2C2 multi-client concurrent conflicts ONLY, then H3 and S1C separately.
H2 COMPLETE: NO. S1B ACCEPTED: NO. S1C READY: NO. PHASE 4B READY: NO.
Production changes/deploy/commit/push: NONE. No production gate or IAM changes.

## H2B bulk native durability — PASS, 2026-10-20

Baseline: clean committed H2A `33ad58347ebea3de81bc2c5febe5094e4e873bac`.
Only the local native harness, new H2B integration test and evidence docs change.
Application/backend business source, rules, Image Import and production unchanged.

Environment reused safely: Kuktam_H2A_Local / emulator-5580 / Android 35 x86_64;
demo-kuktam-local only, Firestore :8088, Auth :9098, fixture :8099, hub :4408,
logging :4508 on host loopback (Android reaches host at 10.0.2.2). Fresh Firebase
emulator state and dedicated test app data at whole-run start; never clear data
or uninstall between phases. No real device/user data touched.

Native acceptance run has four phases:
1. death-queued: production addOrMergeItems accepts two independent offline BULK
   parents, exactly 50 and 200 children, each atomically in real SQLite. The
   projected rows/normalized quantities are verified, complete original requests
   and IDs persisted, then abrupt am force-stop (PID 4712). No graceful close.
2. death-partial: restart STILL offline verifies identical requests/IDs and both
   reconstructed projections. Reconnect with automatic processing paused. Actual
   ShoppingMutationStore processes exactly 17/50 and 73/200 children through
   calls bounded to at most 20 steps each. SQLite records PROCESSING and the
   result prefix; applied rows are canonical and unresolved suffix remains pending.
   Disable networking and force-stop again with SQLite/coordinator open (PID 4887).
3. complete: restart offline verifies exact persisted partial SQLite rows, original
   requests/IDs, nonterminal parents and reconstructed rows. One deterministic
   network flap advances child 18 of the 50 parent while client networking is off.
   Receipt observation resumes, then normal harness dispatch finishes both parents.
   All 250 results complete; no accepted child is lost. Original result prefixes
   are byte-equivalent after JSON decoding. Household shoppingRevision is exactly
   250 before any later fixtures, and every canonical item's revision equals its
   last actual receipt revision. This uses the existing household-global sequence,
   NOT an incorrect assumption that each new item's revision starts at 1.
4. reopen: another native launch after completion proves both parents remain
   APPLIED, outbox has no unresolved entries, IDs unchanged, canonical counts,
   quantities and receipt-matching revisions unchanged. No child is resubmitted.

Each bulk includes 300 ml + 2 l + 500 ml of the same normalized product and a
separate 1 db item. Result: one 2800 ml row plus one db row. Therefore 50 children
produce 48 canonical rows and 200 produce 198, intentionally; all other quantities
are checked individually. No truncation/phantom child, duplicate logical effect
or projection starvation observed. Child identity in the actual protocol is
(immutable parent mutationId, immutable payload array index), not a separate
client-generated ID per child. Exact persisted payload equality preserves it.

Mixed-state native test uses the real clearShoppingList facade with four observed
items. First three results: APPLIED, REJECTED_STALE (authoritative +500 survives),
REJECTED_NOT_FOUND; fourth still pending and parent nonterminal. Advance epoch,
process final child -> REJECTED_CONTEXT_CHANGED; parent PARTIAL/terminal, successful
sibling stays deleted and one aggregate notice is available. No receipt is forged.
No held child is manufactured: dependency behavior is already covered by H1/H2A.
Within one parent the server's cursor/results contract is a sequential prefix;
child 40-before-child 3 delivery is not naturally supported and was NOT simulated
by violating that contract. Different parent continuation can interleave normally.

Parent completion remains the existing server criterion: results cover all children,
including explicit context-rejected suffixes. Client nonterminal requests remain
in the outbox; terminal results remove pending contributions, and held intents
would still prevent the existing done check from succeeding. No polling added.
Observation architecture unchanged: 1 canonical listener, at most 1 bounded
receipt observer (max 10 parent IDs, 2 bulk parents here), no per-child listener.
Test-only firstWhere server-command barriers terminate on their matching event.
This is a scoped sanity check, not H3's final listener/source audit. Firestore
read/write counts were not instrumented; no cost optimization performed.

Evidence: 2 completed native test phases PASS / 0 unexpected failures in final run;
2 separately verified intentional force-stops with successful subsequent assertions;
harness exit 0. Killed Flutter runners report expected "did not complete" and
temporary listener finalization errors; those are not counted as passed tests.
Debug/native APK builds PASS. Shopping/analyzer/diff results are recorded in the
progress report. Backend business code untouched; no backend suites/build rerun.
Local Firebase processes and dedicated AVD stopped; test ports released.

Reproduce with the H2A safety setup but KUKTAM_E2E_SCOPE=H2B and the same local
emulators:exec command. Final log: %TEMP%\kuktam-h2b-acceptance.log. Earlier harness
development failures (missing test extension import and incorrect revision assertion)
were corrected without application changes and do not count as acceptance evidence.

Files: functions/scripts/shopping-client-e2e.cjs;
integration_test/shopping_h2b_e2e_test.dart (new); this checkpoint;
S1B_PROGRESS_REPORT.md; SHOPPING_MUTATION_SAFETY.md.
Next ONLY H2C account/session switch + multi-client conflicts. H3 full validation
and S1C cutoff remain separate. H2 COMPLETE: NO. S1B ACCEPTED: NO.
S1C READY: NO. PHASE 4B READY: NO. Production/deploy/commit/push: NONE.

## H2A single-client native durability — PASS, 2026-10-20

Baseline: clean committed H1, `05310fecb28eb91b45179f11b49001b8b9c1c846`
(`feat(shopping): complete S1B local hardening`). No application/backend business
logic, rules, release network configuration or Image Import changes were needed.
Only native test/harness code and these evidence documents changed.

Environment: dedicated new AVD `Kuktam_H2A_Local`, Android 35 x86_64,
`emulator-5580`. Existing Pixel_8 and real device data were untouched.
Project `demo-kuktam-local`; Firestore 127.0.0.1:8088, Auth :9098, fixture
:8099, hub :4408, logging :4508. Android uses 10.0.2.2 to reach the host.
Real FlutterFire, real SQLite v6/FULL durability, actual repository/coordinator/
dispatcher/projection and actual ShoppingMutationStore execute the operations.
The local fixture substitutes callable/event delivery, not mutation execution.
Offline means Firestore disableNetwork; offline restart ensure explicitly throws
unavailable so a network fixture cannot silently establish fresh authority.

Fresh environment: no Firebase emulator import/export; the new dedicated AVD
starts with no user data. Before the final complete run only that AVD's
com.bronxii.kuktam test data was cleared. No data clearing/uninstall occurs
between phases (`--no-uninstall`). No production credentials/config changes.
Admin metadata probing is disabled; project/emulator guards remain mandatory.

Final run: three completed native test phases PASS, two deliberate interrupted
process phases independently verified; harness exit 0.

1. `single`: real add dialog closes after offline SQLite acceptance; pending ADD
   appears and reconnect creates exactly one item. Offline EDIT, CHECK, UNCHECK,
   DELETE reconcile correctly. ADD→EDIT, ADD→CHECK, ADD→DELETE and
   ADD→EDIT→CHECK complete without new IDs. Offline stale EDIT/DELETE preserve
   authoritative +500 (quantity 501), reject STALE and produce a notice.
   Old-epoch ADD is rejected CONTEXT_CHANGED, no item is created or replayed.
   In this scenario stale epoch is denied at rules admission and classified by
   the client's authoritative context check, not manufactured as a server receipt.
   A paused processor + observed server command gates the online/offline/online
   flap; same ID completes once. No timing sleep determines correctness.
2. `death-add` / `resume-add`: ADD→EDIT→CHECK is durably queued offline.
   Host executes `adb -s emulator-5580 shell am force-stop com.bronxii.kuktam`
   with coordinator/SQLite open, checks previous PID 6185 then absence of process.
   Separate APK launch remains offline initially: exact IDs, immutable requests,
   dependency rows and pending quantity survive. Reconnect produces one item,
   quantity 9 and checked true.
3. `death-edit` / `resume-edit`: offline EDIT, CHECK, UNCHECK and DELETE are
   accepted together; same abrupt mechanism kills PID 6515. Restart while offline
   verifies all four exact requests (including observed revisions), original IDs,
   and projected state. Reconnect applies them once. A further local second-actor
   merge case proves a new pending ADD's dependent DELETE fails closed instead
   of deleting the authoritative merged quantity 502.

The two force-stopped Flutter runners intentionally report "did not complete"
and may print a temporary listener-directory finalization error. Those are NOT
counted as passed tests. Success requires the host's crash-ready/PID evidence
AND the separate passing resume assertions. Neither coordinator.close nor
SQLite.close is called before force-stop. A 15s host-runner reap watchdog is
only test-process cleanup, never application mutation recovery.

H1A native sanity: a test-only delivery barrier suppresses real Firestore query
snapshots containing `ghost` before they reach the coordinator. Actual S1A ADD
completes; its APPLIED receipt retires the optimistic row without query observation.
Actual S1A DELETE then removes the server target. Canonical server query is empty,
no pending mutation/ghost/replay remains. This deterministically controls delivery,
not Firestore network packet scheduling; no fake canonical data is injected.

Validation on final H2A code:
- Native: 3 completed phases PASS / 0 unexpected failures; 2 verified abrupt
  terminations plus successful resumes. Final harness exit 0.
- Shopping Flutter: 263 PASS / 0 FAIL (H1A/B/C included).
- Analyzer PASS, no issues; Android debug test APK builds PASS.
- Harness JavaScript syntax check PASS; git diff --check PASS.
- Backend business source untouched: no backend suite/Functions build required.
- Firebase processes and dedicated AVD stopped; test ports no longer listening.

Reproduction: start ONLY Kuktam_H2A_Local on port 5580, use fresh local Firebase
state and fresh test app data at the start of the WHOLE run, then:

```powershell
$env:KUKTAM_E2E_SCOPE='H2A'
node .\functions\node_modules\firebase-tools\lib\bin\firebase.js emulators:exec --only firestore,auth --project demo-kuktam-local --config firebase.shopping-e2e.json "node functions/scripts/shopping-client-e2e.cjs"
```

Do not clear app data between death/resume phases. Harness refuses a different
AVD in H2A mode. Local evidence logs: `%TEMP%\kuktam-h2a-final.log` and
`%TEMP%\kuktam-h2a-shopping.log` (not committed).

H2A modified files:
- functions/scripts/shopping-client-e2e.cjs
- integration_test/shopping_mutation_e2e_test.dart (shared native fixture only)
- integration_test/shopping_h2a_e2e_test.dart (new)
- S1B_CHECKPOINT_2026-10-19.md
- S1B_PROGRESS_REPORT.md
- SHOPPING_MUTATION_SAFETY.md

Next: H2B 50/200 bulk partial progress/process-death only; then separate H2C
multi-client/family/account-switch coverage, H3 full regression/audits, and S1C
rules cutoff/hardened validation. None executed here.
H2 COMPLETE: NO. S1B ACCEPTED: NO. S1C READY: NO. PHASE 4B READY: NO.
Production changes/deploy/commit/push: NONE.

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
