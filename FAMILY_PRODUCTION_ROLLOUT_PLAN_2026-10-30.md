# Family production rollout plan — 2026-10-30

**PLAN READY — IMPLEMENTATION BLOCKER FOUND**

This is a blocked planning checkpoint, NOT an execution-ready production runbook or deployment approval. Inspection reached the request's explicit STOP condition: critical Family runtime paths are intentionally restricted to local emulators. No safe end-to-end deployment sequence can be signed off by treating these guards as ordinary configuration switches. Implementation must be a separately authorized phase; then this plan must be completed and revalidated.

## 1. State and evidence boundary

9A PASS, 9B0 PASS, 9B delta CONDITIONAL PASS are retained for their tested local scope. The former-owner CREATE/JOIN defect remains closed. Production deployment readiness is a different claim.

The supplied planning brief reports browser fallback DEPLOYED/LIVE PASS and DAL LIVE PASS. These are accepted as supplied status, not reverified in this task. The prior chat's fallback work ended at local PASS; no intervening deployment is attributed to this assistant. No new Hosting deploy is needed by the inspected local configuration. Play-signed device verification remains DEFERRED.

Project: `kuktam-67768`; Firestore region `eur3` per brief. Functions source region: `europe-west1`. Codebase: `monetization`, Node 22. No `.firebaserc`. Runtime/gate/rules/index/IAM values in production were not queried. Family OFF and App Check OFF are supplied rollout policy; local endpoint declarations have `enforceAppCheck:false`.

Only repository source/config and existing checkpoints were inspected. No live data/config access, tests, builds, deployments, gate changes, Play changes or account deletion occurred.

## 2. Confirmed implementation blocker — STOP

Evidence:

- `functions/src/households/family-join.ts:79`: JOIN admission rejects `K_SERVICE`, `FUNCTION_NAME`, or a non-demo/non-loopback emulator runtime.
- `functions/src/households/join-transfer.ts:23`: transfer entry checks use the same local-only restriction.
- `functions/src/households/member-leave.ts:65`: leave/remove require exact demo project and loopback emulator, rejecting deployed runtime variables.
- `functions/src/households/owner-pro-loss.ts:10`: `familyLifecycleEnabled()` requires no K_SERVICE/FUNCTION_NAME, project `demo-kuktam-local`, and loopback Firestore emulator.
- `functions/src/index.ts`: `familyOwnerEntitlementChanged`, `familyOwnerProLossMaintenance`, `familyMemberDeletionMaintenance`, `familyOwnerDeletionMaintenance` return immediately when that predicate is false. They therefore do not run the Family lifecycle in Cloud Functions.
- Each dissolution store also independently enforces the demo restriction: preparation, preservation, merge, source disposition, member release and finalization.
- Owner/member account-deletion stores use that predicate. `AccountDeletionService.beginAccountDeletion` takes the private deletion path when it is false, instead of orchestrating Family handoff.

These are intentional previous-phase safety boundaries, not evidence that the local lifecycle engine is defective. Setting `familyRuntime/config` fields to true would not enable the missing deployed behavior. Removing environment guards blindly is not an acceptable rollout step.

Required separate work: a reviewed production admission/continuation policy for these stores and exports, production-enabled durable dissolution/Pro-loss/deletion handoff, and targeted proof that emergency admission shutdown never disables committed forward completion. No such implementation was made here.

## 3. Exact source export inventory

Names below come from `functions/src/index.ts`. They are source exports, NOT a list confirmed deployed in production. Each name has exact selector `functions:<name>` under the sole configured codebase. All Family callables use the core runtime identity, region europe-west1, and App Check enforcement false.

| Group / exact exported names | Type and purpose | Required / current limitation |
|---|---|---|
| `getFamilyShareState`, `previewFamilyInvite`, `getFamilyJoinTransferState` | Authenticated callables; state, invite preview, transfer recovery | Required. State/preview rely on server records; transfer path local restriction. Reads are not controlled by a universal Family switch. |
| `createFamilyShare`, `createFamilyInvite`, `revokeFamilyInvite`, `acceptFamilyInvite` | Authenticated mutation callables | Required. CREATE/invite starts have server config gates; JOIN additionally hard-local. Pro grant aggregation and capacity remain server authority. |
| `prepareFamilyJoinTransfer`, `confirmFamilyJoinDelete`, `cancelFamilyJoin` | Authenticated JOIN lifecycle/consent callables | Required by existing client flow; local restrictions require production integration. |
| `leaveFamilyShare`, `removeFamilyMember` | Authenticated member/owner mutations | Required before any Family creation; currently hard-local. |
| `startFamilyDissolution` | Authenticated owner start, queues existing lifecycle | Required before any Family creation; currently hard-local through OwnerProLossStore. |
| `prepareFamilyDissolution`, `prepareFamilyShoppingPreservation`, `mergeFamilyShoppingPreservation`, `cleanFamilyShoppingSource`, `releaseDissolutionMembers`, `finalizeFamilyDissolution` | Authenticated legacy/internal-phase callables | Exported, but not needed for Flutter phase orchestration. Driver invokes stores directly. Exclude from an initial minimal client-facing deployment set unless separately justified; preserve guards, do not expose phase stepping as a production workaround. |
| `familyOwnerEntitlementChanged` | Retried Firestore write trigger on `users/{uid}/entitlementGrants/{grantId}` | Required for grant-change observation; currently no-op in production. |
| `familyOwnerProLossMaintenance` | Scheduled every minute, core identity, 540 seconds/maxInstances 1 | Required: owner scan and durable manual/Pro-loss dissolution intents; currently no-op in production. |
| `familyMemberDeletionMaintenance`, `familyOwnerDeletionMaintenance` | Scheduled every minute, core identity, 540 seconds/maxInstances 1 | Required handoff/recovery; currently no-op in production. |
| `ensurePrivateHousehold`, `ensureShoppingContext` | Authenticated routing/context callables | Required shared foundations, not Family-only; migration and old-client impact must be assessed. |
| `processShoppingMutation` | Retried Firestore create trigger on `users/{uid}/shoppingMutations/{mutationId}` | Required before S1C/client mutation admission. Not a passive read deployment. |
| `billingMaintenance` | Scheduled every five minutes, Play identity; dispatcher/maintenance | Shared dependency for CREATE/JOIN and shopping recovery plus existing billing/deletion. Must review shared changes, not replace with a fake Family-only worker. |
| `beginAccountDeletion`, `finalizeAccountDeletion` | Authenticated shared deletion callables; core/deletion identities | Required integration, actual Family admission is not production-enabled. |
| `authUserDeleted` | v1 Auth onDelete fallback, core identity, retries | Existing shared safety dependency; no real deletion E2E authorized. |
| `playRtdn` | Retried Pub/Sub on `kuktam-play-rtdn`, Play identity | Existing authoritative billing dependency, not automatically part of Family redeploy set. |
| `prepareProPurchase`, `verifyProPurchase`, `getEntitlementProof` | Existing billing/authenticated callables | Dependency context only; do not redeploy unrelated purchase endpoints just for Family. |

No separate exported historical-audit callable/trigger was found in index.ts. Historical audit is an internal owner-deletion stage, not a new client endpoint.

## 4. Runtime and adapter classification

**A — MUST REMAIN TEST-ONLY:** scripts/fixtures, local QA stdio bridge, synthetic worker dispatch/clock, simulated Auth deletion and demo reset endpoints. Never deploy these or use their execution as production runtime proof.

**B — PRODUCTION IMPLEMENTATION/POLICY REQUIRED:** local-only JOIN transfer, leave/remove, dissolution driver entry guards, Pro-loss trigger/sweep, member/owner deletion handoff and historical-audit continuation. Existing engines should be reused, not duplicated. Export declarations alone do not make them operational.

**C — ENABLE ONLY AFTER PROOF:** new-admission configuration, shopping mutation admission, actual deployed trigger/scheduler operation and appropriate IAM. Family ON is not a single existing universal flag.

**D — NOT NEEDED AS NEW INITIAL DEPLOYS:** internal dissolution phase callables, Hosting (reported live), unrelated purchase endpoints; existing billing dependencies still must be compatible.

`jobs/maintenance.ts` contains bounded nextAt scans of `familyOperations` (JOIN -> FamilyJoinStore, otherwise CREATE path) and `shoppingMutationWork`; `billingMaintenance` invokes the shared dispatcher. Dedicated owner maintenance drives dissolution via `familyProLoss` and `DissolutionLifecycleDriver`. Member/owner deletion sweeps use `familyMemberDeletions` / `familyOwnerDeletions`. Due work and operator outcomes require production proof, including classification of operation kinds, restart and retry behavior. A running Cloud Scheduler entry that returns immediately is not a healthy Family worker.

Pro-loss source is authoritative entitlement grants, aggregated server-side. Firestore grant writes wake `familyOwnerEntitlementChanged`; periodic owner scanning is also important for expiry without a new grant write. Both Family paths currently local-only. The client is not the enforcement mechanism.

**Actual Auth deletion adapter exists:** `FirebaseAdminAuthDeletionAdapter` in `adapters/firebase-auth.ts` calls Admin Auth deleteUser and classifies not-found/transient/permanent errors. `runtime/composition.ts` wires it into lazy production services. It is incorrect to report the Auth adapter itself as missing. What is blocked is production-enabled Family handoff/continuation before the private deletion engine. Validate later with injected simulated adapter in local tests; never production account deletion E2E.

## 5. Gates and fail-safe limits

| Exact gate | Owner / default | Rollout meaning |
|---|---|---|
| `familyRuntime/config.creationEnabled` | Server Firestore, requires literal true | New CREATE admission. Current-generation retry logic is separate. |
| `familyRuntime/config.inviteCreationEnabled` | Server Firestore, requires literal true | New invitation admission. |
| `familyRuntime/config.joinReservationEnabled` | Server Firestore, requires literal true | JOIN reservation admission, in addition to hard local guard. |
| `shoppingRuntime/config.enabled` | Server processor and client-request rules require true | Shared shopping admission; NOT a Family emergency switch. |
| `familyLifecycleEnabled()` and individual local checks | Code/environment, false in deployed runtime | Currently prevents production lifecycle; not an operator-managed switch. |

Missing/false config prevents the relevant new start; transport/config failures must not be treated as permission. Config fields require privileged writes and do not inherently require a deploy, but no approved production config-write tool/command or live values were established here. Do not invent a Firebase CLI document-write command.

There is no evidenced universal Family OFF/client-version/allowlisted-smoke gate. State/preview and some recovery calls are independent; settings contains a Family entry. Thus “Family inaccessible while OFF” cannot be promised as a blanket statement. Existing admission gates can block new starts, but an all-users gate ON is not a controlled test-account rollout mechanism.

Emergency intent: block NEW creation/invites/JOIN while keeping committed transfer, dissolution and deletion completion alive. Do not disable workers, shopping globally or billing to implement this. In particular JOIN reserve checks the gate before retry resolution; client recovery and committed continuation must be proven under admission OFF in the separate production-runtime work. This planning stop does not certify an exact safe kill-switch procedure.

## 6. Rules, historical data, indexes and old clients

Local `firestore.rules` is the only configured rules source. Exact live-versus-local delta is UNKNOWN without an authorized deployed-rules comparison; repository content does not prove what is deployed. Do not label every local clause “not deployed” merely from historical notes.

Affected local boundaries:

- `/users/{uid}` structural pointer create/update denied; coordinated deletion constraints.
- `/users/{uid}/shopping`: legacy create/update allowed only before migrated activeHouseholdId exists; older clients can still lose writes after migration even with Family OFF.
- `/users/{uid}/shoppingMutations/{mid}`: immutable, authenticated, epoch/payload/context-checked requests gated by shopping config.
- `/households/{hid}/shoppingItems/{itemId}`: S1C denies ALL direct client create/update/delete. Current-context reads only.
- Household/member structural writes denied; membership/current routing validated for shopping access.
- Family membership/invites/capacity/slots/operations/runtime server-only. Operation descendants denied. Pro-loss/deletion/audit maintenance paths fall through default deny unless explicitly covered.
- DISSOLVED audit remains backend history; current callable read uses current routing/membership and does not reactivate historical ownership.

**S1C: REQUIRES A COMPATIBLE SHOPPING CLIENT.** Admin SDK bypasses client rules, but older direct-writing clients do not. Shipping rules early can break those clients; reverting to permissive rules after Family data is active is not a safe rollback. Current public build behavior/adoption was not queried. Local `pubspec.yaml` is `1.0.0+1`; it is NOT proof of the first compatible Play build, a released minimum version or adoption. Require an identified Play artifact with mutation-based shopping, Family contracts, links and auth continuation, plus an approved old-client cutoff strategy before rules/migration/Family admission. No minimum version number can honestly be invented here.

No `firestore.indexes.json` was found and firebase.json has no indexes mapping. Live indexes are UNKNOWN. Examples needing explicit index planning include pending invites by household/status with expiresAt inequality, and historical traversal by owner/kind/document ID. Current worker due queries use one nextAt range/order; direct document reads and simple single-field queries do not themselves require a custom composite. Equality queries may use index merging; do not assert every chained where requires a composite. Exact complete index manifest/reconciliation remains unfinished because the production-runtime STOP condition was reached. Emulator PASS is not composite-index proof. No index deploy command is executable until a reviewed manifest and live inventory exist; avoid deleting unrelated indexes. Do not casually use a global index deployment as a substitute for reconciliation.

## 7. IAM, secrets and App Check

Source parameter names: `KUKTAM_CORE_RUNTIME_SERVICE_ACCOUNT`, `KUKTAM_PLAY_RUNTIME_SERVICE_ACCOUNT`, `KUKTAM_DELETION_RUNTIME_SERVICE_ACCOUNT`. Shared billing/deletion graph uses `KUKTAM_BINDING_KEYS`. Values/permissions are not inspected or reproduced. Core requires appropriate Firestore access and Auth user lookup for member identities; deletion identity needs actual Auth deletion permissions; shared Play maintenance needs its existing Play/billing dependencies as well as Firestore recovery access. Eventarc, scheduler invocation and deployed generation-specific IAM must be validated without broad grants. Firebase Auth is mandatory on user callables; invoker configuration is not a replacement for request.auth checks.

**App Check stays OFF throughout this rollout plan.** No enablement step. Future enforcement needs compatible client attestation and a separate finishing review; it is not a fix for missing Family runtime wiring.

## 8. Deployment stages — HOLD, not executable yet

| Stage | Required PASS before advancing | STOP / response |
|---|---|---|
| 0. Separate production-runtime implementation | Guards replaced by reviewed production policy; continuation, deletion handoff, admission-OFF recovery proven; no test adapter exposed | Current STOP point. No deployment. |
| 1. Final inventory and release preparation | Exact reviewed target set, existing deployment/rules/index inventory, compatible Play artifact/cutoff strategy, identity/IAM/secret readiness, all admission OFF | Unknown values or incompatible clients: hold. |
| 2. Backend foundations + continuation, separate GO | Workers and recovery are deployed/operational before any admission; partial deploy reconciled; auto-trigger side effects assessed | Functions are not all passive. Do not advance on partial failures. |
| 3. Reviewed indexes and rules, separate GO | Indexes ready; rules tests PASS; old-client strategy safe; compatible mutation processor live | Permission-denied spike: stop new admission, assess compatibility; never weaken structural boundaries blindly. |
| 4. OFF-state validation | Correct denials, healthy workers, approved version/context handling; no Family data mutation | No smoke until complete. |
| 5. Play-signed proof | Android 12+, correct Play-installed current build/certificate, automatic domain verified, link resolves correctly | Manual approval/explicit package launch is not automatic verification. |
| 6. Controlled smoke, separate GO | Authorized test accounts and genuinely bounded admission mechanism; no general population exposure | Existing global fields alone do not provide cohort isolation. Hold until strategy approved. |
| 7. General Family admission, separate GO | Smoke cleanup complete, no stuck work, monitoring healthy, all earlier gates PASS | Never auto-enable. |

Functions Admin writes do not require permissive client rules, so some server deployment can precede rules while new admission is OFF. This does not make deployment harmless: trigger/scheduler exports run automatically, shared maintenance processes existing work, and household initialization can migrate users independently of Family creation. Exact target ordering must be finalized after Stage 0 and old-client review, not assumed here.

### Exact command references — NOT approved deploy steps

All commands below use actual existing exports and explicit production project. They are a reference for the later completed runbook, not a claim that deploying this subset now is safe or sufficient. New production-runtime work may change the required set. No blanket functions/hosting deploy.

```powershell
# Read/state group, after all preconditions and a separate backend GO:
node .\functions\node_modules\firebase-tools\lib\bin\firebase.js deploy --only functions:getFamilyShareState,functions:previewFamilyInvite,functions:getFamilyJoinTransferState --project kuktam-67768

# Existing client mutation exports (currently BLOCKED by runtime restrictions):
node .\functions\node_modules\firebase-tools\lib\bin\firebase.js deploy --only functions:createFamilyShare,functions:createFamilyInvite,functions:revokeFamilyInvite,functions:acceptFamilyInvite,functions:prepareFamilyJoinTransfer,functions:confirmFamilyJoinDelete,functions:cancelFamilyJoin,functions:leaveFamilyShare,functions:removeFamilyMember,functions:startFamilyDissolution --project kuktam-67768

# Shared foundations and recovery; assess existing deployed versions first:
node .\functions\node_modules\firebase-tools\lib\bin\firebase.js deploy --only functions:ensurePrivateHousehold,functions:ensureShoppingContext,functions:processShoppingMutation,functions:billingMaintenance,functions:familyOwnerEntitlementChanged,functions:familyOwnerProLossMaintenance,functions:familyMemberDeletionMaintenance,functions:familyOwnerDeletionMaintenance,functions:beginAccountDeletion,functions:finalizeAccountDeletion,functions:authUserDeleted --project kuktam-67768

# Separate rules GO, ONLY after compatible-client and index gates:
node .\functions\node_modules\firebase-tools\lib\bin\firebase.js deploy --only firestore:rules --project kuktam-67768
```

No deploy command is provided for indexes without a configured/reconciled manifest. No Hosting deployment. No invented gate-write command. These reference groups are not a one-command rollout script and their listing order is not an execution order.

## 9. Later bounded validation and Play proof

After separately authorized runtime preparation: Functions build; focused production-policy/admission-OFF continuation tests with no production writes; existing 9B0 CREATE/JOIN generation regressions; representative JOIN, leave, dissolution and deletion handoff tests with simulated Auth; focused shopping/household rules suite for cutoff; manifest/config/export/index checks. Reuse 9A/9B evidence for unaffected cases. No full historical matrix by default.

Play checklist for later execution: Android 12+ device, Play-installed compatible app, package `com.bronxii.kuktam`, installed signing certificate equals verified Play SHA-256 ending `:E5:CD`. Reset/reverify only with device-verification authorization:

```powershell
adb shell pm set-app-links --package com.bronxii.kuktam 0 all
adb shell pm verify-app-links --re-verify com.bronxii.kuktam
adb shell pm get-app-links com.bronxii.kuktam
adb shell pm get-app-links --user cur com.bronxii.kuktam
```

Wait for verifier completion; require `kuktam-67768.web.app: verified`, not approved/user-selected. Open a nonsensitive structurally valid canonical test URL without forcing a package and verify resolution, then later the controlled real invite smoke. Do not add debug/upload fingerprints or mark synthetic token validity as proven. This check can follow passive deployment but is mandatory before any real Family smoke/admission ON under this plan.

## 10. Smoke, cleanup and rollback intent

Only after explicit authorization and a safe cohort strategy: controlled A already legitimately Pro, B normal user, both compatible clients with empty/minimal private lists. A creates Family and invite; B opens canonical link, previews and joins ADD; verify routing/member list and one harmless shopping item create/check/update visibility; B leaves; A dissolves; both read private state. Do not place the invite URL/token in logs or documentation. Remove the test item through normal UI if necessary. Historical audit remains; never manually delete lifecycle records.

Forbidden smoke: account deletion, induced Pro loss, worker crashes, corruption, stale injection, stress/races/large lists. No billing grant mutation just to create a smoke prerequisite.

Rollback categories:

- Before new data is used, code rollback may be possible only after compatibility review of shared billing/deletion changes.
- Once generated operations/data shapes are used, do not roll back to code that cannot interpret them.
- On callable 5xx, queue growth, stuck JOIN/dissolution or partial deploy: stop NEW admissions, preserve continuation workers, triage and forward-fix. Never reset committed phases or delete history.
- Rules failure: keep admission OFF. Permission-denied spike needs client/rules diagnosis; restoring unsafe direct writes is not an approved response.
- App Links failure: stop new invitation expansion and gate ON; existing members and lifecycle recovery must keep functioning.
- Family screen errors: prevent further expansion, retain authoritative recovery; do not disable the backend needed to complete existing operations.

Exact emergency command/permission/runbook requires Stage 0 completion. No evidence currently justifies a universal OFF toggle that safely accomplishes all these goals.

## 11. Observability and cost

Use existing Cloud Functions/Cloud Logging and scheduler/trigger health after authorized deployment: error rate/latency per callable, failed event deliveries, scheduler executions, nextAt backlog age/count, OPERATOR outcomes, JOIN/dissolution/deletion stuck phases, permission-denied and Firestore read/write trends. No raw tokens, invite URLs, credentials or shopping contents. Controlled audit access must be server-authorized.

Reuse 9B's bounded owner read shape (up to roughly 56 logical document reads at maximum healthy members/invite slots, excluding retries/billing details); do not treat it as a billable-price guarantee. Watch unexpected state-call frequency, repeated previews, retry storms and worker backlogs. Thresholds/baselines require rollout telemetry; no numbers invented or optimization implemented here.

## 12. Exact blocker classification and GO checklist

**Before backend deploy:** separately authorized production runtime/continuation and Family deletion handoff integration; reviewed safe admission/recovery separation; exact final exports and IAM/secret/deployed-version verification. Current code is not an operational production Family system merely because exports exist.

**Before rules deploy:** compatible shopping-client artifact and old-client cutoff strategy; actual deployed-rules comparison; complete index manifest and live reconciliation; required mutation worker active; targeted rules PASS. Repository alone cannot establish live rule/index state.

**Before production smoke:** all preceding prerequisites; Play-signed proof; explicitly controlled accounts and bounded admission strategy; separate smoke GO. No true cohort switch was evidenced.

**Before general Family ON:** successful bounded smoke/normal cleanup, healthy continuation/monitoring, compatible-client strategy, all prior blockers closed, separate activation GO. Browser fallback is reported LIVE PASS and is not carried forward as an open blocker here.

**Non-blocking follow-up:** aggregate cost/error monitoring and later App Check enforcement finishing work. App Check remains OFF during Family rollout.

- [ ] Production-runtime blockers resolved in a separate implementation checkpoint.
- [ ] Final exact deploy set and shared-function impact reviewed.
- [ ] Compatible Play artifact/minimum-client strategy proven (not inferred from `1.0.0+1`).
- [ ] Rules/index/deployed-config differences reconciled with authorized read-only evidence.
- [ ] Targeted build/regression/rules checks PASS after final preparation.
- [ ] Required IAM/identities/secrets and forward-only workers ready.
- [ ] New-admission OFF; recovery remains operational; emergency procedure proven.
- [ ] App Check OFF; no Hosting deploy required.
- [ ] Play-signed automatic App Links verification PASS.
- [ ] Controlled smoke and cleanup authorized and PASS.
- [ ] Separate backend, rules, runtime/config and Family ON approvals obtained at their stages.

## 13. Outcome and next action

**PLAN READY — IMPLEMENTATION BLOCKER FOUND.** The next step is NOT Stage 1 deployment. Request a separately scoped production-runtime readiness implementation for the existing local-only lifecycle paths, then finish this blocked runbook with the exact index/client/runtime evidence. Stop here as required by the planning brief.

Only this document was created. Source code changed NO; production data accessed NO; deploy NO; Family gate changed NO; App Check changed NO; commit/push NO.
