# P0C.2B – Functions runtime / production composition

Verdict: READY TO PAUSE PRODUCTION INFRA. Local source and emulator validation complete; NO DEPLOY.

## Runtime and region
- Installed versions retained: firebase-functions 7.4.0, firebase-admin 14.5.0, google-auth-library 11.1.0. No dependency install/upgrade.
- Declared Node runtime: 22; TypeScript ES2022/CommonJS, strict mode. Local tests use the existing Node 24.18.0 toolchain; Node 22 cloud-runtime smoke validation remains a later deployment gate.
- Central region: europe-west1, Firebase's recommended Functions region for Firestore eur3. [Official location guidance](https://firebase.google.com/docs/functions/locations).
- Callables, Pub/Sub and Scheduler use 2nd gen.
- Installed SDK exposes v2 onUserDeleted, but marks it beta. Only Auth deletion uses stable v1.auth.user().onDelete; this is a deliberate isolated generation split, not a claim that no v2 API exists. [Auth API reference](https://firebase.google.com/docs/reference/functions/2nd-gen/node/firebase-functions.identity).

## Composition
- One lazy factory in runtime/composition.ts assembles Admin, LifecycleStore, account/binding store, verifier, acknowledger, production Play adapters, deletion service/gateway, RTDN processor and maintenance dispatcher.
- Existing RTDN/maintenance internals construct lease-fenced service instances as before; no parallel purchase writer introduced.
- Import/discovery only declares functions and parameters. No Admin initialization, secret value read, credential acquisition, HTTP or Firestore access on import.
- Admin default app initialized once or reused; service graph cached per runtime process. Failed initialization is not cached.
- compose() accepts Firestore, Play transport, Auth deletion adapter and key provider for offline/local testing.

## Exports
| Export | Trigger | Behavior |
|---|---|---|
| prepareProPurchase | v2 authenticated callable | Strict empty body; ACTIVE account; registers generation-fenced opaque binding |
| verifyProPurchase | v2 authenticated callable | Strict productId/purchaseToken DTO; authoritative lookup; common lifecycle writer; backend ack |
| getEntitlementProof | v2 authenticated callable | Own UID; existing minimal trusted online proof |
| beginAccountDeletion | v2 authenticated callable | Strict empty body; trusted auth_time <=5 minutes; DELETING barrier |
| finalizeAccountDeletion | v2 authenticated callable | Strict empty body; trusted content verification; resumable completion |
| authUserDeleted | v1 trusted Auth deletion event | Existing idempotent legacy fallback; not callable/HTTP |
| playRtdn | v2 Pub/Sub | Existing strict parser/inbox/processor; fresh authoritative lifecycle path |
| billingMaintenance | v2 scheduled | Bounded existing core, durable cursor/category checkpoint and lease |

## Callable contract/security
- UID is constructed from request.auth.uid only. No body UID or mass assignment.
- Existing N5.3 {schemaVersion:1,error:...} envelopes are preserved instead of replacing them with incompatible client error strings.
- Existing errors include unauthenticated, accountDeleting/accountDeleted, tokenBindingConflict, configuration, retryableUnavailable and internalMalformed; rejected purchase remains outcome=rejected.
- Recent-auth failures use recentAuthRequired for the new deletion surface; raw exceptions never leave wrappers.
- Missing runtime secret/config fails closed as configuration. No fallback key/credential.
- Product/package authority stays backend constants; client productId is only an exact validated context field.
- Verification commits grant before ack. Ack failures do not undo verified grants; existing maintenance recovery continues. No fire-and-forget ack work.
- verified remains a verification result, never a client entitlement grant.
- Proof keeps proofIssuedAt as the online trust boundary; cached verifiedAt is not used to renew offline grace.
- Deletion outputs expose only schemaVersion/outcome, not private operation IDs. Finalize ignores no evidence: extra cleanupComplete/UID fields are rejected.
- Flutter's deletion gateway remains injectable; its future live transport wiring is not implemented here. No existing Dart DTO mismatch found.

## Deletion/fallback
- Modern flow: recent reauth -> begin DELETING -> client content cleanup -> backend VERIFIED -> cleanup/Auth claim -> Auth delete -> DONE.
- AccountDeletionService is still the only coordinator calling the Auth adapter. Maintenance cannot bypass content verification.
- Auth fallback receives UID only from the trusted Auth event. Duplicate events use existing idempotency; malformed UID is ignored; transient continuation throws a sanitized retry error.
- Auth fallback is not exported as a callable. Its exception/retry path does not expose SDK details.
- Bulk Admin deleteUsers does not produce individual Auth deletion events; future operator tooling must not assume it does.

## RTDN
- Official Pub/Sub message.messageId/publishTime/data are mapped to the existing envelope; source is the configured topic, not a payload assertion.
- No duplicate JSON/base64 decoder or dedupe engine. Domain parser owns validation, inbox owns durable dedupe and lease/retry state.
- retryablePlayFailure/internalConflict/busyLease throw sanitized errors for transport redelivery.
- Malformed/unsupported/terminal outcomes complete without poison-message retry loops. Durable RETRY/UNRESOLVED/retryDeferred work remains maintenance-owned.
- Topic declaration: kuktam-play-rtdn. No topic, subscription or publisher permission was created.

## Maintenance
- Single schedule declaration: every 5 minutes, UTC. Actual job was not created.
- Existing policy controls hourly exhausted recovery, ~30-minute unresolved delay, daily active checks with jitter, ~6-hour voided catch-up and per-item due times.
- Existing pageSize=50/runBudget=60 seconds; no full database scan or unbounded loop added.
- billingRuntime/maintenance contains only schemaVersion, nextCategory, cursors, leaseId, leaseUntil.
- Strict metadata parsing; 360-second lease exceeds 300-second function timeout. Transactional claim and completion identity check prevent cursor regression on overlap/stale completion.
- Global checkpoint crash is recovered after lease expiry; existing per-item leases and lifecycle fencing remain the durable mutation guards.
- Scheduler maxInstances=1, concurrency=1, retryCount=0; next invocation handles failure. Durable lease is the correctness mechanism, not maxInstances alone.
- New operational path is already denied by local catch-all rules; rules source unchanged. Added explicit client denial tests.

## Secrets / credentials / config
- Official defineSecret declares KUKTAM_BINDING_KEYS without reading or creating a secret.
- Runtime payload: JSON object mapping known vN versions to canonical base64 >=32-byte keys (max 128 bytes/key, 16 versions, 16 KiB document).
- Current keyVersion=v1 in central config; previous keys may coexist. Missing current/unknown versions fail closed. No hardcoded secret or env/file fallback.
- Keys are copied into the existing private in-memory provider; temporary decoded buffers are zeroed.
- ADC uses the deployed service identity. Required defineString parameter KUKTAM_RUNTIME_SERVICE_ACCOUNT has no default and is bound to both generations' serviceAccount options.
- Central config also owns package/product references, region, topic, secret name, recent-auth age, schedule and runtime limits.
- No service-account JSON, OAuth refresh token, secret persistence or credential logging.
- App Check explicitly non-enforced. Future rollout: configure -> monitor -> investigate failures -> enforce separately.

## Deploy config audit
- functions/package.json main=lib/src/index.js, engines.node=22; strict build script unchanged.
- firebase.json adds only local Functions source/codebase/runtime/predeploy/ignore configuration; existing Flutter Firebase registration values preserved.
- Predeploy compiles local TypeScript; source remains packaged for standard cloud build behavior, tests/generated test output and local scripts/logs/env/key-file patterns excluded.
- No project alias added/changed. Existing emulator config remains explicit demo-kuktam-local.
- No Rules deploy configuration/change added. Hardened rules must precede any live entitlement population because current live broad rules are unsafe for billing data.
- Deploy-readiness is source readiness, not permission or live-runtime verification. No deploy command was executed.

## Privacy/writer audit
- No request/event dumps, token/UID pairs, ID tokens, HMAC values, raw SDK exception logging or full response logging added.
- Runtime wrappers write no ledger, grant or entitlement directly.
- Only new direct writes are technical dispatcher checkpoint transactions in billingRuntime/maintenance.
- No consume, Flutter completePurchase, public fallback shortcut, or client-trusted cleanup evidence.
- Existing onlineEnabled:false is unchanged. No Flutter source was edited.

## Validation
- TypeScript strict build: PASS.
- Unit suite: 198 PASS (30 new runtime tests, existing 56 adapter tests included).
- Targeted new composition/dispatcher emulator suite: 12 PASS.
- Full backend emulator/rules/Admin/concurrency/transport suite: 366 PASS, 0 failures. Combined backend total: 564 PASS.
- Root import test blocks HTTP/HTTPS/fetch, supplies no key/ADC, verifies no Admin initialization and checks the exact export set/generation metadata. Demo project ID is used only for SDK trigger metadata inspection.
- Emulator tests use explicit demo project guards and injected fake Play HTTP/Auth clients; no live API call.
- New integration coverage: prepare/verify/ack/proof replay, strict request schema, DELETING/DELETED, verified cleanup barrier, fallback replay, RTDN dedupe, durable pagination/rotation, overlapping scheduler claims, stale completion and crash lease recovery.
- Existing N3/N4A/N4B/P0C.1 regression covers lifecycle, deletion, retry and rules invariants.
- Flutter not rerun because no Flutter source changed.
- Final diff-check: PASS, including explicit checks of all newly created/untracked phase files.

## Files
New: functions/src/index.ts; functions/src/runtime/{config,keys,composition,handlers,maintenance-dispatcher}.ts; functions/test/{runtime,runtime-integration}.test.ts; P0C_2B_REPORT.md.
Modified: firebase.json; functions/package.json; functions/package-lock.json; functions/scripts/emulator-tests.cjs; functions/src/transport/monetization.ts (structural verifier injection); functions/src/accounts/deletion-gateway.ts (injectable recent-auth maximum); functions/test/rules.test.ts.
Inherited dirty working-tree changes from earlier phases were preserved.

## Known limitations / pause boundary
- Live project/permission state was not queried. Spark, absent APIs/identity/secrets/products remain as supplied by the user.
- Production adapter limits from P0C.2A remain: bounded voided lookup/30-day technical window, conservative unknown-state handling; real Play QA is still mandatory.
- Synchronous verify+ack can outlast the client's 25-second timeout under dependency latency. Server processing/replay is idempotent and maintenance recovers ack; verify UI retry/timeout behavior needs real-device QA before activation.
- Modern Flutter live deletion transport/online composition remains disabled; existing gateway injection is ready, activation is a separately authorized integration step.
- Auth fallback and all functions need the configured key secret/identity; missing configuration retries/fails closed, so monitor configuration failures before release.
- Dispatcher poison/corrupt metadata fails closed and requires operator repair; no unsafe automatic cursor reset.
- No paid production release claim. The complete backend validation is green; infrastructure can safely pause until EV/Blaze and explicit authorization for live changes. No known P0/P1 identified in this local phase.

## FUTURE LIVE WIRING CHECKLIST — do not execute now
- Blaze and budget/cost alerts.
- Required Cloud Functions/Run/build/artifact, Android Publisher, Secret Manager, Pub/Sub, Scheduler APIs.
- Dedicated runtime service identity, least-privilege Firestore/Auth/Play access, secret access and invocation permissions; set KUKTAM_RUNTIME_SERVICE_ACCOUNT.
- Create/version KUKTAM_BINDING_KEYS values; preserve previous required keys.
- Hardened Rules deploy and legacy CRUD/deletion compatibility smoke test before billing writes.
- Functions deploy with explicit project and Node 22 runtime smoke verification.
- Pub/Sub topic/subscription plus Google Play publisher permission.
- Play RTDN configuration and test delivery; monitor inbox/retry/operator outcomes.
- Scheduler creation via separately approved deployment; verify bounded cursors/lease recovery.
- Merchant/payments profile and one-time kuktam_pro_lifetime product, country/price setup.
- License testers and internal/closed track.
- Real purchase/restore/pending/cancel/refund/revoke/account deletion QA; monitor ack deadlines and stuck deletion.
- App Check configure/monitor, only later enforce.
- Flutter live transport/region wiring and online activation only after smoke gates, in a separate authorized phase.

PRODUCTION FIREBASE CHANGES: NONE
GOOGLE CLOUD CHANGES: NONE
PLAY CONSOLE CHANGES: NONE
IAM/API CHANGES: NONE
PRODUCTION DEPLOY: NONE
LIVE GOOGLE API CALLS: NONE
REAL PLAY PURCHASE TEST: NOT PERFORMED
BLAZE UPGRADE: NOT PERFORMED
FLUTTER CHANGES: NONE
COMMIT: NONE
PUSH: NONE
