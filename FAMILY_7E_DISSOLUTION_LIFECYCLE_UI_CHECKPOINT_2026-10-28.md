# Family 7E — dissolution and lifecycle UI

2026-10-28. Input: committed 7E0 contract, 7A–7D PASS. Flutter only; no backend or rules changes, production access, deployment, commit or push.

## UX and server contract

Only authoritative activeOwner shows the restrained destructive outlined “Család megszüntetése” action, including owner-only and eight-participant Family. First tap opens a scrollable Material confirmation; no mutation occurs. Hungarian copy explains that all members return to private lists, shared contents are preserved into the owner's private list with possible compatible-item merging, pending invites cease to work, and the action cannot be undone. “Mégse” cancels before submission. Only “Család végleges megszüntetése” confirms the second destructive step.

FamilyRepository.startDissolution() calls exactly startFamilyDissolution({}) through the existing CallableFamilyRepository mutation helper. No householdId, participant identity, phase or other arguments. Acceptance validates schemaVersion 1, nonempty opaque operationId and outcome IN_PROGRESS; it does not imply terminal completion. No identifier is displayed or derived. Existing session validation and timeout conventions are reused.

FamilyDissolutionException provides safe Hungarian messages for NOT_OWNER, IN_PROGRESS, ACCOUNT_UNAVAILABLE, FEATURE_DISABLED and generic/unknown failures. No raw Firebase detail is displayed. Existing create/invite/JOIN/leave/remove mappings remain unchanged.

## Submission and recovery

The screen's existing busy flag covers confirmation, submission and authoritative refresh. Conflicting invite/remove operations and repeat dissolution are disabled. Existing navigation protection applies. Session changes invalidate the captured request. There is no optimistic removal, participant-list reconstruction or locally fabricated privateOnly result.

After success OR uncertain/error response, the screen performs getFamilyShareState({}) before any retry. IN_PROGRESS maps through the existing repository to non-actionable progress. privateOnly renders the normal no-Family UI and removes old participant rows. activeOwner permits another explicit action plus confirmation and displays safe feedback; there is no automatic destructive retry. Failed read hides stale controls and uses the existing read retry UI. Read completion/session checks prevent late results changing a newer session.

Manual refresh/reopening uses the same authoritative read. Manual dissolution, Pro loss and owner account deletion all use the existing generic “Folyamatban lévő családi művelet” presentation; internal phase names are hidden. No create/join/invite/leave/remove/dissolve control appears during progress. There is no client cancellation, rollback, polling or phase advancement. Server-side maintenance remains responsible for forward completion through Phase 5.

## Shopping and scope

Existing production household context listens to server-confirmed users snapshots (excluding cache/pending writes) and follows activeHouseholdId. No additional shopping invalidation, new listeners, transfers, merging, deletes, capacity changes or list selector were needed. No Firestore access was added to Family UI. Account-deletion UX, Pro-loss actions, App Links and login continuation remain unchanged/out of scope.

## Validation

- New 7E tests: 30/30 PASS. Exact empty callable, typed safe errors, malformed acceptance, role visibility, owner-only/8-participant cases, explicit confirmation/cancel, in-flight duplication/conflicting-action guards, no optimistic completion, success/lost-response outcomes, deliberate retry, failed refresh, reopen/lifecycle source progress, session changes and small screen.
- Final targeted Flutter run: 184/184 PASS: 30 new 7E + 154 affected Family regressions (7A/7B/7C/7D, binding and 7E0 progress parsing). No backend emulator/historical suite was run.
- flutter analyze: PASS, no issues (5.4 seconds).
- One final Android debug build: PASS (assembleDebug 32.9 seconds). APK: build/app/outputs/flutter-apk/app-debug.apk. Not installed or launched. Nonfatal existing Kotlin/plugin future-compatibility warnings; no dependency changes.
- Logs: C:/Users/gabor/AppData/Local/Temp/family7e-final.log, family7e-analyze.log, family7e-android.log.

## Authored files

- lib/family/family_repository.dart
- lib/family/callable_family_repository.dart
- lib/family/family_mutation.dart
- lib/family/family_screen.dart
- test/family/family_dissolution_test.dart (new)
- FAMILY_7E_DISSOLUTION_LIFECYCLE_UI_CHECKPOINT_2026-10-28.md (new)

## Boundary

Final 7E gate: PASS. Core Family Flutter UI is complete locally. Blockers: NONE. App Links/invite links and signed-out/login continuation are a separate future milestone, followed by dedicated integration QA. Neither that milestone nor final Family QA/production rollout is started. No commit or push.
