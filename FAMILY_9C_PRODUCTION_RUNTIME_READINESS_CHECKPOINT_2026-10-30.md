# Family 9C — production runtime readiness

Status: PASS. Final Functions build passed. Final bounded emulator run passed 28/28 with zero failures, skips or cancellations. No deployment or production access authorized/performed.

## Original guard map — completed before code changes

All source environment checks were inventoried with a search across `functions/src`.

| File | Original guard / blocked path | Classification |
|---|---|---|
| households/family-join.ts | K_SERVICE/FUNCTION_NAME or not demo + loopback emulator; reserve rejects | New JOIN admission AND same-op retry |
| households/join-transfer.ts | private local(), same demo predicate; state/prepare/confirm/cancel | Admitted operation consent, recovery and continuation |
| households/member-leave.ts | deployed vars or not exact demo-kuktam-local + emulator | Current membership leave/remove and idempotent replay |
| households/dissolution-preparation.ts | deployed vars or not exact demo + emulator | Owner/Pro-loss/deletion dissolution preparation |
| households/dissolution-preservation.ts | same exact demo guard | Existing dissolution continuation |
| households/dissolution-merge.ts | same exact demo guard | Existing dissolution continuation |
| households/dissolution-source-disposition.ts | same exact demo guard | Existing dissolution continuation |
| households/dissolution-member-release.ts | same exact demo guard | Existing dissolution continuation |
| households/dissolution-finalization.ts | same exact demo guard | Existing dissolution continuation |
| households/owner-pro-loss.ts | familyLifecycleEnabled() + private local(); startOwner/observe/step/sweep | Owner exit, mandatory entitlement enforcement and continuation |
| households/member-account-deletion.ts | private local() delegates familyLifecycleEnabled | Family exit admission, step and sweep |
| households/owner-account-deletion.ts | private local() delegates familyLifecycleEnabled | Dissolution/deletion handoff, step and sweep |
| households/historical-family-audit.ts | private local(uid) checks predicate + UID | Historical audit admission/continuation |
| accounts/account-deletion.ts | false predicate immediately chooses private beginDeletion | Family-aware orchestration bypassed in deployed runtime |
| index.ts | four handlers return if !familyLifecycleEnabled | Entitlement write trigger and owner Pro-loss/member deletion/owner deletion schedules |

CREATE/invite already use server config; no Cloud Functions denial. Shared billing maintenance already dispatches bounded CREATE/JOIN and shopping recovery. Runtime composition already injects real Admin Firestore/Auth deletion; test adapters live in test/scripts. No additional Family environment denial was found elsewhere in functions/src.

## Intended policy

Environment selects infrastructure, not business authority. CREATE, invite creation and NEW JOIN require literal-true existing server admission fields read transactionally. Same logical admitted JOIN retries resolve before checking NEW JOIN admission. Authoritative reads, consent/recovery for admitted JOIN, membership exits, owner dissolution, server Pro-loss, account-deletion handoff and historical cleanup keep their existing actor/state/fence/generation proofs and do not depend on new-growth gates. No global lifecycle OFF field is added.

Legacy internal dissolution phase callable adapters remain test-only; production uses startFamilyDissolution plus the existing server driver. Their test-only transport restriction is separate from the production-capable stores.

## Implemented policy and wiring

`households/runtime-policy.ts` centralizes literal-true checks for creationEnabled, inviteCreationEnabled and joinReservationEnabled. Undefined/null/malformed/false config denies NEW growth; failed reads propagate. JOIN resolves a proven same-token/current-binding operation before reading NEW admission config. Existing CREATE retry already resolves its current generation before NEW admission. No config document or live gate was changed.

Removed environment authorization from domain stores, historical audit and account deletion orchestration. Auth, role, capacity, account generation, current membership bindings, consent, transaction locks, receipts and forward-only semantics remain in the existing engines. No new lifecycle state machine, new public endpoint or broad runtime switch.

Membership exits and owner dissolution are allowed under existing authorization even with growth OFF. Server Pro-loss and deletion handoff are required enforcement/cleanup, not new Family growth. Do not disable their workers or the shared shopping gate as an emergency shutdown. Emergency policy: deny NEW creation/invites/JOIN through the three existing fields while preserving reads, admitted-operation recovery, explicit DELETE consent, exits and lifecycle completion.

The four existing Family exports no longer return solely because Cloud Functions variables exist. Shared billing Maintenance still handles CREATE/JOIN and shopping work; the same injected maintenance engine is exercised by the new production-simulation tests. Unrelated billing behavior was not changed.

Owner deletion previously stopped scheduling at WAITING_HISTORICAL_AUDIT; tests manually advanced audit. Existing owner deletion sweep now additionally processes a bounded, rotating 20-document phase query for WAITING_HISTORICAL_AUDIT / DETACHING_HISTORICAL_AUDIT / HISTORICAL_AUDIT_READY. Cursor: `familyLifecycleMaintenance/ownerDeletionAuditScan`. It calls the existing HistoricalFamilyAuditStore and, only after READY, the existing LifecycleStore.beginDeletion(uid,false,true), which revalidates admission. It does not call Auth. Pre-9C waiting records are covered without migration. The private deletion worker retains cleanup/Auth responsibility. Production index reconciliation must include this phase/document-ID query; no index was created here.

Legacy internal phase callable handlers use `internalFamilyPhaseCallsAllowed`: exact demo/loopback environment, no Cloud Functions runtime. Stores themselves are production-capable. These six transport exports are not a production orchestration workaround. QA bridges, reset helpers, synthetic clocks and fake Auth remain in scripts/test; real FirebaseAdminAuthDeletionAdapter and runtime/composition.ts are unchanged.

## Validation and scope

Development run: **9/9 new tests PASS** in family-runtime-policy.test.ts. They simulate K_SERVICE and FUNCTION_NAME, non-demo environment project identity and absent FIRESTORE_EMULATOR_HOST. Before changing environment, the injected Firestore client is initialized and pinned to 127.0.0.1:8088 with explicit demo-kuktam-local project; no real production connection or Auth adapter is used. Test environment is restored after each case.

Coverage: fail-closed growth; CREATE retry OFF; ADD/DELETE committed JOIN through shared Maintenance OFF; current binding leave/remove OFF; owner and Pro-loss dissolution sweep OFF; member deletion and owner dissolution/audit/private-deletion handoff OFF with fake Auth; four actual export handlers invoke injected store methods in deployed-like environment; internal phase callables remain denied. Final package also strengthens DELETE testing with admission disabled before prepare/consent and reruns bounded former-owner, stale generation, deletion, legacy-transport and shared runtime regressions.

Commands: `npm run build`, `node scripts/emulator-tests.cjs --runtime-9c-dev`, final `npm run build` then `node scripts/emulator-tests.cjs --runtime-9c`. The strengthened DELETE test exposed a second reservation gate in JoinTransferStore.prepare. Removed that duplicate check after durable reservation and READY proof. Explicit consent and structural checks remain in force. Final evidence: C:/Users/gabor/AppData/Local/Temp/family9c-final2.log (exit 0). Earlier logs: `C:/Users/gabor/AppData/Local/Temp/family9c-dev.log`, `family9c-final.log`. The first final-run attempt was not executed because approval review hit a usage limit; user requested continuation and the subsequent authorized attempt started normally.

No Flutter/native/Hosting/rules/index/App Check changes, no production reads/writes, no deploy, no commit/push. New production data may NOT be enabled merely because 9C passes.

## Runtime identity assumptions / remaining rollout work

No IAM values assumed or changed. Core identity requires existing Admin Firestore access and Auth lookup. Existing Play identity runs billingMaintenance, including injected deletion recovery, so its effective Auth-deletion capability/approved execution separation must be checked along with the deletion identity before deployment. The existing FirebaseAdminAuthDeletionAdapter is not replaced. No real account-deletion E2E permitted. App Check declarations remain false.

Before backend deploy: review exact exports, service identities/IAM/secrets, runtime scheduling, deployed-version differences and production index availability; complete the gated rollout runbook. Before rules deploy: reconcile local/live rules and indexes, S1C-compatible client/minimum version and old-client strategy. Before Family ON: all previous prerequisites, Play-signed device App Links proof, controlled smoke/admission strategy and separate explicit GO. Browser fallback/DAL remain previously reported live PASS; no Hosting work here.

## Files changed

Production: `functions/src/households/runtime-policy.ts` (new); `family-create.ts`, `family-invites.ts`, `family-join.ts`, `join-transfer.ts`, `member-leave.ts`, `dissolution-preparation.ts`, `dissolution-preservation.ts`, `dissolution-merge.ts`, `dissolution-source-disposition.ts`, `dissolution-member-release.ts`, `dissolution-finalization.ts`, `dissolution-preparation-handler.ts`, `dissolution-preservation-handler.ts`, `owner-pro-loss.ts`, `owner-account-deletion.ts`, `member-account-deletion.ts`, `historical-family-audit.ts` (all under functions/src/households); `functions/src/accounts/account-deletion.ts`; `functions/src/index.ts`.

Tests: `functions/test/family-runtime-policy.test.ts` (new), `family-join.test.ts`, `family-join-foundation.test.ts` (obsolete import only), `family-member-leave.test.ts`, `family-owner-remove.test.ts`, `family-dissolution-preparation.test.ts`; `functions/scripts/emulator-tests.cjs`; this checkpoint.
