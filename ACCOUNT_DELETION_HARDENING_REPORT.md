# Account deletion hardening and lifetime recovery

Local implementation only. No production requests, deploy, live account deletion, Play purchase, commit or push performed in this task.

## Coordinated client

Settings uses AccountDeletionRepository with its production CallableAccountDeletionGateway by default. There is no direct User.delete fallback. Reauthentication precedes begin; both callables use empty bodies, authenticated Firebase SDK transport and europe-west1. Session changes fence requests and completions, including logout/relogin to the same UID. Successful begin clears cached Pro access before client content cleanup. Backend completion may end the session; replacement-account sessions are never signed out by completion. Failures remain retryable and the durable backend job can finish independently of the client.

## Authoritative cleanup

Every durable cleanup step checks the account generation and deletes a bounded first page of recipes/shopping plus the user root. At most 2 * pageSize content documents plus root/job are written in a content step (pageSize <= 100). Grant cleanup retains its separate bounded stage and removes corresponding technical maintenance records. At AUTH, remaining grants route back to GRANTS; all entitlement documents are removed before DONE. The backend rechecks content even when a prior client check said VERIFIED. authGone does not bypass content removal.

Covered current user schema: users/{uid}, recipes, shopping, entitlementGrants, entitlements. No currently defined additional personal Firestore subcollection was found in the client audit. The approach deliberately does not invoke unbounded recursiveDelete: it has no durable per-job pagination checkpoint and would obscure the billing retirement stages. Future collections/nested subcollections must be added explicitly to the schema-owned cleanup plan; this is not a promise to erase arbitrary future paths. Household data is out of scope. Root absence alone is never evidence of child absence. Unsupported/corrupt billing state fails closed rather than declaring DONE.

accountLifecycle and accountDeletions remain UID-indexed deletion tombstones. Billing ledgers keep non-personal historical state/hash; raw token, old UID and personal binding are removed on deletion. Old binding registry entries remain UID-free TOMBSTONED records. No Play refund, revoke or consume is performed.

## Explicit purchase recovery

verifyProPurchase accepts the existing two fields, or exactly those fields plus intent: "restore". Only the explicit Restore action sends this intent. Startup callbacks and automatic already-owned handling do not opt in.

Only ACCOUNT_DELETED is eligible. The backend checks the current token against Google Play, correct package/product, PURCHASED, and local non-revoked/non-canceled state. No old UID or Google email is supplied/required. Missing, invalid, wrong-package/product, pending, canceled and locally revoked observations are rejected. A currently BOUND purchase remains non-transferable even with intent:restore.

After verified recovery, a new active account marker and local HMAC binding are provisioned (never reopening an existing DELETING/DELETED marker). An atomic ledger revision/account-generation transaction elects one owner and creates its deterministic play_<hash> grant. Concurrent losing attempts can initialize their own empty account marker/binding, but cannot acquire the ledger or a grant. Original Play obfuscated account metadata is not rewritten/reassigned. The old registry stays tombstoned.

The ledger gains optional recoveredFromDeletion:true. Subsequent verification uses the server-stored new local binding, because Play still returns the original obfuscated metadata. This exception applies only to an already recovered, same-UID BOUND ledger. Late RTDN while tombstoned stays ignored; after rebind RTDN/maintenance resolve the new ledger owner. Repeated Restore preserves semantic revisions and grant identity.

Recovery requires current Firebase authentication and a fresh verified Play token; no additional recent-auth challenge is introduced for Restore. Deletion begin still requires recent reauthentication. The purchase token is a sensitive possession proof and is never logged. ACKNOWLEDGED purchases are not acknowledged again. If a verified recovered purchase is still PENDING acknowledgement, the existing server acknowledgement mechanism remains responsible. No client ACK/consume is introduced.

## Validation

- TypeScript build: PASS (`npm --prefix functions run build`; also executed by test:unit).
- Backend unit tests: 208/208 PASS (`npm --prefix functions run test:unit`).
- Full relevant backend emulator suite: 381/381 PASS (`node functions/scripts/emulator-tests.cjs`). Includes security rules, verification, acknowledgement, lifecycle, revoke, RTDN, maintenance, deletion, callable transport and production runtime composition with fake upstream adapters.
- Flutter auth/billing/monetization/Pro tests: 324/324 PASS (`flutter test --no-pub test/auth test/billing test/monetization test/pro`).
- Full analyzer: PASS, no issues (`flutter analyze --no-pub`).
- Tracked diff whitespace check: PASS (`git diff --check`). New task files checked separately for trailing whitespace.
- Initial emulator startup needed local sandbox elevation to bind loopback. An intermediate runtime test expected legacy cleanupIncomplete and was updated to assert actual server cleanup. Final suite above has zero failures/skips.
- No AAB build or production E2E performed.

Only demo-kuktam-local Firestore emulator data and fake Play/Auth adapters were used. Emulator commands remove live credential environment overrides and target loopback. No real account was deleted.

## Proposed production sequence (NOT EXECUTED)

1. Review diff and a fresh read-only production inventory, IAM/secret access and deletion-job state. Separately authorize each deploy. Keep current important account/purchase intact.
2. Update playRtdn and billingMaintenance readers/workers before allowing recovered-ledger writes. Use only their selectors; --force is only for the existing intentional RTDN retry policy.
3. Deploy verifyProPurchase with explicit recovery intent support. Existing prepareProPurchase/getEntitlementProof behavior requires no redeploy for these changes.
4. Deploy authUserDeleted (GEN1 retry policy), then finalizeAccountDeletion, then beginAccountDeletion. Verify each configuration; no live deletion smoke without separate account-specific authorization.
5. Release an Internal-only test build after all backend prerequisites. Default monetization flag remains unchanged/default-OFF. Do not ship this coordinated client before its callables exist.
6. Start with a new disposable Free account containing recipes/shopping; verify interrupted client and server continuation, terminal cleanup, Auth absence and unrelated-user isolation.
7. Separately authorize an active-lifetime purchase test on a sacrificial profile/Play setup. Delete that Kuktam account, create a different UID, explicitly Restore the still-owned purchase, repeat Restore and inspect ledger/grant/ACK/RTDN idempotency. Do not refund/revoke or repurchase as part of recovery.

Example narrowly scoped commands from repository root, only after separate authorization:

```powershell
node .\functions\node_modules\firebase-tools\lib\bin\firebase.js deploy --only "functions:monetization:playRtdn,functions:monetization:billingMaintenance" --project kuktam-67768 --force
node .\functions\node_modules\firebase-tools\lib\bin\firebase.js deploy --only "functions:monetization:verifyProPurchase" --project kuktam-67768
node .\functions\node_modules\firebase-tools\lib\bin\firebase.js deploy --only "functions:monetization:authUserDeleted" --project kuktam-67768 --force
node .\functions\node_modules\firebase-tools\lib\bin\firebase.js deploy --only "functions:monetization:finalizeAccountDeletion" --project kuktam-67768
node .\functions\node_modules\firebase-tools\lib\bin\firebase.js deploy --only "functions:monetization:beginAccountDeletion" --project kuktam-67768
```

The optional ledger field is rejected by older strict readers. Do not roll those readers back after the first recovered record without a deliberate compatibility plan. The old inactive UID and data are never restored; recovery restores the purchase entitlement only. Real Play E2E is still required; local tests prove the implementation, not production operation.

## Task-owned files

- functions/src/accounts/account-deletion.ts
- functions/src/billing/lifecycle-store.ts
- functions/src/billing/schema-v2.ts
- functions/src/billing/verify-purchase.ts
- functions/src/transport/monetization.ts
- functions/test/deletion.test.ts
- functions/test/runtime-integration.test.ts
- lib/billing/billing_contracts.dart
- lib/billing/purchase_orchestrator.dart
- lib/features/auth/data/repositories/account_deletion_repository.dart
- lib/features/auth/data/repositories/callable_account_deletion_gateway.dart (NEW)
- lib/monetization/callable_gateways.dart
- lib/pro/pro_screen.dart
- lib/settings/settings_screen.dart
- test/auth/account_deletion_coordination_test.dart
- test/auth/account_deletion_test.dart
- test/auth/callable_account_deletion_gateway_test.dart (NEW)
- test/billing/fakes.dart
- test/billing/purchase_orchestrator_test.dart
- test/monetization/callable_adapter_test.dart
- test/pro/pro_integration_test.dart
- ACCOUNT_DELETION_HARDENING_REPORT.md (NEW)

Pre-existing Image Import code, Android edits and dependency edits were left in place; no dependency added or upgraded for this task.
