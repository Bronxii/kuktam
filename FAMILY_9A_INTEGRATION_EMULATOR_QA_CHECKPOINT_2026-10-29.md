# Family 9A integration / emulator QA

## Bounded matrix (defined before implementation)
| Journey | Planned strongest proof |
|---|---|
| A Create | Production Dart repository -> actual callable handler -> Firestore emulator |
| B Invite | Same bridge; canonical URL/token/expiry |
| C Manual preview/JOIN | Same bridge, real owner-created credential |
| D App Link equivalence | Strict Dart parser feeds same repository preview |
| E Signed-out continuation | Real Auth emulator email/password sign-in and continuation coordinator; existing auth gate widget tests |
| F ADD | Real transfer, representative compatible and unique shopping |
| G DELETE | Real consent contract and cleanup; existing widget second-confirmation proof |
| H Leave | Current immutable binding, real callable and private read |
| I Remove | Owner target binding, real callable and private read |
| J Rejoin | Real A->exit->B, stale A rejected, B current |
| K Dissolution | One start, authoritative progress, server worker, private reads |
| L Shopping | Real routing context before/after transitions |
| M Pro loss | Selected existing real emulator lifecycle test |
| N Member deletion | Selected existing simulated-Auth deletion handoff test |
| O Owner deletion | Selected existing full simulated-Auth deletion chain |
| P Historical audit | Completed dissolution read plus selected deletion regression |

## Evidence boundary
The stdio bridge replaces FlutterFire native transport. Production Dart CallableFamilyRepository calls actual callable handler factories with real Firestore emulator stores. Local Auth emulator accounts sign in through signInWithPassword REST; Admin verifies their emulator ID tokens before handler invocation. A test User adapter represents that verified session to Dart. This is NOT a Functions emulator HTTP/IAM/App Check test, native Firebase Auth UI test or device E2E. It is the closest economical repository/callable layer: existing SDK injection and local fixture-runner patterns are reused without native plugins or production gates.

Server scheduler dispatch, synthetic clock and fixture seeding are test-only. CREATE/JOIN resume uses unchanged engines as scheduled maintenance does; dissolution uses OwnerProLossStore.sweep. The clock avoids real five-minute waits. No client lifecycle logic is added. The bridge has no listening socket, is not a Functions export, refuses non-demo/non-loopback targets, and never echoes request/token/URL/SDK diagnostics. Auth port is 9098, Firestore 8088; emulator config otherwise preserves the existing configuration.

The continuation proof receives duplicate links signed out, retains one pending token, performs zero preview calls, signs in through local email/password Auth, creates the session-bound repository after authentication, resumes once and clears pending state. Google, registration, verification, failure and process recreation rely on existing targeted 8C/auth regression. There is no claim of live Google authentication.


Status: PASS within the explicitly documented repository/callable integration boundary. No production access/deploy. Browser fallback and Play-signed device verification remain 9B release items.

## Integration observations and harness corrections
No production Family defect has been found. Initial test-development failures were fixture/adapter issues: canonical stored shopping name needed lowercase `milk`; a fenced DELETE source must be inspected through test fixture data rather than normal shopping routing; repository must be instantiated after usable auth (it intentionally captures UID); asynchronous route handoff must be awaited before another stdio request. These were corrected only in new test code. No Family, JOIN, shopping, auth or lifecycle production source changed.

The ADD proof merges 1000 ml + 2 l into 3000 ml and preserves one distinct bread item; private source is emptied by backend. DELETE starts with two private items, waits for the exact second consent, and leaves Family shopping unchanged. Current B binding replaces A; stale A owner removal rejects STALE_MEMBERSHIP. A completed self-leave replay may return historical DONE by existing contract; the selected four rejoin regressions cover the alternate fresh stale-request paths and current-generation exits. No stale operation hijacks B.

JOIN submission response is deliberately dropped after server acceptance; authoritative read reports inProgress and same-token retry resumes the same logical JOIN. Dissolution start response is similarly dropped; read reports inProgress without a second start; server worker reaches privateOnly. Owner-only Family stays activeOwner after removal until explicit dissolution. Final private owner shopping contains preserved Family contents; historical dissolution is not active in read model.

## Validation commands
Run from repository root unless noted:
- `node functions/scripts/emulator-tests.cjs --integration-qa` — guarded demo project, local Auth + Firestore; new Dart integration then bounded existing backend selectors.
- `flutter test test/family/family_mutation_test.dart test/family/family_join_test.dart test/family/family_exit_test.dart test/family/family_dissolution_test.dart test/family/family_dissolution_progress_test.dart test/family/family_app_links_test.dart test/family/family_continuation_test.dart test/auth/auth_qa_test.dart test/auth/email_verification_test.dart --reporter expanded`
- `npm.cmd run build` from functions.
- `flutter analyze`
- `flutter build apk --debug` — one final build; no installation.

Functions build initially hit local output write permissions; rerun with required filesystem permission succeeded. No TypeScript source correction was needed. Android emits existing non-fatal Kotlin migration warnings for plugins; APK builds successfully.

## Files modified
- `firebase.family-qa.emulators.json` (new, local Auth+Firestore config)
- `functions/scripts/emulator-tests.cjs` (two bounded 9A selectors)
- `functions/scripts/family-qa-bridge.cjs` (new test-only verified-auth transport/fixture)
- `functions/scripts/family-qa-runner.cjs` (new bounded runner)
- `test/family/family_emulator_qa_test.dart` (new cross-language journey)
- this checkpoint.

## Boundaries / handoff
No backend business or Flutter production code changes; no Firestore rules changes, gate changes, production data/account deletion, Hosting/Functions deployment, commit or push. Auth account deletion remains simulated in the selected existing deletion tests. Local Auth emulator account fixture creation/deletion is not production Auth.

Browser invite fallback: OPEN RELEASE TODO (known 404, untouched).
Play-signed App Links device verification: DEFERRED TO 9B / RELEASE READINESS.
Functions emulator HTTP/IAM/App Check and native device auth transport are outside this substitute-transport proof; do not present this run as native end-to-end. Manual/Google/registration UI safety is bounded widget evidence.
9B security/read-cost/release review is NOT STARTED. No rollout authorization is implied.

## Final results
- Matrix A–P: PASS, using the distinct evidence levels above; no native/device E2E claim.
- New 9A cross-language Dart repository/Auth/Firestore journey: 1/1 PASS (32 seconds).
- Selected backend emulator regressions: 13/13 PASS (158.5 seconds): two max-size/capacity reads; four real leave/remove x ADD/DELETE A->B->C chains; one three-participant owner full deletion; one member full deletion; one member deletion owner/history guard; owner-only dissolution; duplicate/lost-ACK dissolution; Pro-loss read/reuse; Pro-loss complete lifecycle.
- Bounded Flutter widget/domain/repository/auth regression: 221/221 PASS. New integration plus regression total: 222 Flutter tests.
- Functions TypeScript build: PASS.
- flutter analyze: PASS, no issues (20.9 seconds).
- Android debug build: PASS (31.7 seconds); build/app/outputs/flutter-apk/app-debug.apk.
- Functional product bugs found/fixed: NONE. Only new harness corrections listed above.
- Unresolved functional Family blockers within 9A scope: NONE.

Final validation logs (local temporary artifacts): family9a-final-emulator.log, family9a-flutter-regression.log, family9a-functions-build.log, family9a-analyze.log, family9a-android.log under C:/Users/gabor/AppData/Local/Temp. Logs contain test labels/results, not invite credentials. Preliminary harness runs are not counted as passing evidence.

FINAL GATES: Family core COMPLETE; 8A PASS; 8B LOCAL + HOSTING PASS (device deferred); 8C PASS; 9A PASS; 9B NOT STARTED; production rollout NO; commit NO; push NO. STOP. Next separately authorized milestone: 9B release readiness/security/read-cost review and outstanding release items.
