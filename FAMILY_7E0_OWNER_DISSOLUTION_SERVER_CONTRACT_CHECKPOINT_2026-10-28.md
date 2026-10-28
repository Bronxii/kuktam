# Family 7E0 — owner dissolution server contract

Date: 2026-10-28. Scope: local backend integration and read contract only. Final result: PASS. No deployment, production access, rules changes, Flutter mutation/UI changes, commit or push.

## Previous gap and existing execution path

`prepareFamilyDissolution({householdId})` calls `DissolutionPreparationStore.prepare` and creates the deterministic `dissolve_<hash(ownerUid, householdId)>` operation at PREPARED/READY. It does not run the remaining phases. `DissolutionLifecycleDriver.step` selects exactly one existing Phase 5 engine step, including preservation, merge, source disposition, participant release and finalization. The existing `familyOwnerProLossMaintenance` scheduler calls `OwnerProLossStore.sweep` every minute; the bounded scan can adopt existing dissolution operations and the due-intent loop runs the shared driver. Account deletion independently uses the same driver. These paths retain the existing local-only `demo-kuktam-local` + loopback-emulator gate, which rejects deployed Functions environments.

## New owner entry

`startFamilyDissolution({})`: authenticated callable, empty object only. Client householdId, operationId and phase parameters are rejected before store access. Family context is derived from the caller's current `familyMemberships/{uid}` ACTIVE owner entry and verified against household owner, owner member record, current user routing, migration and private fallback. Private users, normal members and historical owners without ACTIVE membership cannot start.

The operation uses the unchanged deterministic dissolution identity. `OwnerProLossStore.startOwner` durably admits/reuses an intent in the existing `familyProLoss/{dissolutionId}` maintenance queue, then invokes one bounded existing `step`. No second scheduler or dissolution engine was introduced. Response is `{schemaVersion:1, operationId, outcome:"IN_PROGRESS"}`; operationId is internal opaque evidence, not client phase control. Completion is established by authoritative read, not the start response.

A new manual intent uses reason `OWNER_REQUEST`. Existing Pro-loss intent provenance is retained. If a manual request adopts a still-pending Pro-loss intent before a dissolution exists, optional server timestamp `ownerRequestedAt` records the new manual authorization without overwriting OWNER_PRO_LOSS. Restored Pro does not cancel an explicit manual request. Existing operation and account-deletion admission evidence are not rewritten. Existing schema/version and queue paths remain compatible; no migration.

## Continuation, conflicts and recovery

Acceptance and `nextAt` are committed before execution. A crash/lost ACK at that boundary leaves durable work for the existing sweep. Each sweep handles at most 20 owner observations and 20 due intents; failures are deferred using the existing retry path. The same preparation and driver are used for manual starts. Same-operation retries do not redo admission or allocate a new operation. Already-fenced operations bypass fresh-private-home admission checks and are validated by the existing driver.

`beforeAdmission` retains existing serialization. A committed JOIN forward-completes first; dissolution snapshots the resulting ACTIVE participant set. Precommit reservations are finalized by Phase 5. Leave/remove winning before snapshot is reflected; an existing dissolution lock wins later attempts. No lock stealing or expiry was added.

PREPARED is a durably accepted request. PRESERVATION_COMMITTED remains the existing preservation point of no return. The manual contract exposes no cancellation or rollback and automatically continues all accepted work using the existing semantics. OPERATOR remains safe/non-actionable; no repair is attempted. Reentry after final owner release is rejected as NOT_OWNER (historical/private caller); the read response is privateOnly and no new operation is created.

## Authoritative read

`getFamilyShareState({})` retains its one-call contract and existing typed `failed-precondition / IN_PROGRESS` convention. No new Dart parser or response envelope is required. While a caller is still an ACTIVE participant, a bounded four-document batch reads:

- deterministic current dissolution operation;
- Family capacity/structural lock;
- existing maintenance intent keyed by dissolutionId;
- owner account-deletion intent keyed by owner UID.

It checks operation identity/owner/household/lock consistency. Pending, running or operator lifecycle intents, a current dissolution operation, or a structural JOIN lock prevent normal actionable Family state. Inconsistent/missing dissolution lock evidence fails closed as FAMILY_UNAVAILABLE. This read-only check is specific to `state`; mutation admission, JOIN and leave/remove semantics are unchanged.

The lifecycle check occurs before fenced private-home/current-member enrichment. Thus PREPARED, preservation, partial member release and owner-last progress cannot be mistaken for actionable activeOwner/activeMember. Already-released members read privateOnly. At DONE, owner reverse membership and active Family routing are gone, so the normal existing privateOnly read applies. Historical DISSOLVED records are not queried as active Family.

Normal active reads add exactly four bounded document reads in one batch. Existing owner binding batches remain bounded to seven invited members. A max-size normal owner read has batch sizes `[4,7,7,7,7]`; progress does not invoke member email enrichment. No history scan, polling, per-member client calls or new listeners.

## Flutter compatibility and 7E boundary

Existing `CallableFamilyRepository.load` already converts IN_PROGRESS to `FamilyState.inProgress`. The existing screen shows generic progress and hides create/join/invite/leave/remove controls. Internal phases, household IDs and operation metadata are not displayed. Tests connect actual callable parsing to the existing screen with SDK fakes, including privateOnly completion. No production Dart changes, start repository method, dissolve button or dialog were added.

7E may implement an explicit owner confirmation followed by one `startFamilyDissolution({})` request and authoritative `getFamilyShareState({})` refresh. On uncertain response it must read, not execute phase callables. Manual refresh/reopen can observe inProgress until privateOnly. No Phase 5 orchestration, cancellation after commitment, shopping manipulation, App Links or login continuation belongs in this handoff.

## Validation

Development: 19 new backend tests passed, including 1/3/8 participants, auth and exact empty payload, duplicate/concurrent starts, PREPARED and fenced retries, lost ACK at durable intent and preparation commit, pre-admission rollback, Pro-loss/restoration and deletion reuse, precommit/committed JOIN ordering, leave/remove races, normal and historical reads, corrupt lock. Existing server sweep alone completes the 1/3/8 participant cases with preserved shopping and private routing.

Seven focused Flutter tests passed in development: lifecycle-origin/reopen progress display, no normal actions/internal phase text, one read callable, completion to privateOnly and unchanged normal roles.

Final validation: PASS.

- Functions TypeScript build: PASS.
- New 7E0 backend tests: 19/19 PASS.
- Regression: 80 invite/read, 20 Phase 6A Pro-loss, 30 Phase 6B2 owner-deletion, four Phase 5 finalization cases: 134 distinct cases PASS. Total distinct backend coverage: 153 passing cases.
- Initial final backend run: 149 executed, 147 passed, two legacy expectations failed. The rejected-member invite test incorrectly expected zero invites despite its historical USED-invite fixture; it now verifies the whole collection is unchanged. The Phase 2 deletion test expected the pre-6B2 exception; it now verifies familyDissolutionPending / DISSOLUTION_IN_PROGRESS with no deletion job or DELETING marker. No business behavior changed for these corrections. Only these two corrected tests and four previously unexecuted Phase 5 cases were rerun: 6/6 PASS.
- Final Flutter tests: 51/51 PASS (seven new progress cases plus 44 existing repository/model/binding/screen cases).
- Production Dart unchanged; Flutter analyze and Android debug build NOT REQUIRED under this phase policy.
- Logs: C:/Users/gabor/AppData/Local/Temp/family7e0-final.log, family7e0-recheck.log, family7e0-flutter-final.log.
- No full historical suites, native H2, performance suites, production E2E or routine git checks.

Final gates: 7D PASS (input); 7E0 PASS; 7E prerequisite satisfied but UI NOT STARTED. App Links and final Family QA NOT STARTED. Production rollout/deploy/commit/push: NO. Blockers: NONE.

## Authored files

- functions/src/index.ts
- functions/src/households/owner-dissolution-handler.ts (new)
- functions/src/households/owner-pro-loss.ts
- functions/src/households/family-invites.ts
- functions/test/owner-dissolution.test.ts (new)
- functions/test/family-invites.test.ts
- functions/scripts/emulator-tests.cjs
- test/family/family_dissolution_progress_test.dart (new)
- FAMILY_7E0_OWNER_DISSOLUTION_SERVER_CONTRACT_CHECKPOINT_2026-10-28.md (new)

7E UI, App Links, final QA and rollout have not been started.
