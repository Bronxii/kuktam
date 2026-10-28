# FAMILY 7D — MEMBER LEAVE + OWNER REMOVE UI

Date: 2026-10-28 (Europe/Budapest).
Result: **PASS**.
Input: supplied Phase 7D0 PASS checkpoint; earlier 7C/7D0A gates unchanged. No routine Git/baseline/status/log/commit checks.

## Implemented UI

ACTIVE non-owner members see `Kilépés a családból`. One explicit, scrollable Hungarian confirmation explains return to their own private shopping list and that the Family list/other participants remain. Cancel sends no mutation. Owner, privateOnly and inProgress views have no self-leave action.

ACTIVE owners see a restrained `Tag kezelése` overflow menu on each non-owner row, containing `Tag eltávolítása`. The owner row has no menu. Confirmation uses the existing email/unknown-member label and explains private-list return, preserved shared shopping, and that the member's account/private data are not deleted. No UID, invitation binding, epoch or operation ID is shown.

The existing screen busy state covers confirmation, request and authoritative refresh. Conflicting create/invite/JOIN/exit controls and refresh/navigation are disabled while busy. There is no optimistic membership/list update. Session changes invalidate an open confirmation or delayed result.

## Callable contract and immutable binding

FamilyRepository gains `leaveFamily(FamilyParticipant member)` and `removeMember(FamilyParticipant target)`; CallableFamilyRepository implements them using the existing authenticated mutation transport:

- leaveFamilyShare: `{inviteId: member.membershipInviteId}`.
- removeFamilyMember: `{inviteId: target.membershipInviteId, targetUid: target.uid}`.

The UID and invitation binding are taken together from the same immutable participant object. No separately editable UID/binding pair, history lookup or ID derivation is introduced. The screen verifies the selected object belongs to its current authoritative state and has the appropriate member role. Repository validation rejects missing/malformed binding, owner role, self-remove, or a self-leave target other than the authenticated user before any callable. The backend remains the authorization authority.

Successful replies must be schemaVersion 1 / outcome DONE with a nonempty backend operation ID. Malformed/unknown responses are treated as uncertainty, not fabricated completion. Leave/remove backend semantics, JOIN behavior and Firestore rules are unchanged.

## Refresh, stale generations and lost responses

After either successful response or failure/uncertainty, the screen makes an authoritative Family read. It never automatically repeats the captured destructive request.

- Leave + fresh privateOnly: complete, including when the original response was lost or owner-remove won the race.
- Remove + fresh activeOwner without the target UID: complete, including when self-leave won or the reply was lost.
- STALE_MEMBERSHIP / NOT_ACTIVE_MEMBER: refresh immediately and render the server state.
- A screen holding A while B has become current: A is sent once and rejected; the refresh replaces the state with B. Only a new explicit action and confirmation may submit B.
- Same current binding still active after uncertain response: safe message and explicit retry remain available, using the refreshed object and existing backend idempotency.
- Unexpected new state/inProgress: render that authoritative state; no compensation or repair.
- Failed refresh: old state is cleared, read error/retry is shown, and no exit controls remain available until a successful read.

A DONE reply alone never produces a local privateOnly state or removes a list row. Removing the final non-owner leaves the owner-only activeOwner view and its normal invite action.

## Error mapping

FamilyExitException provides safe Hungarian text for STALE_MEMBERSHIP, NOT_ACTIVE_MEMBER, OWNER_CANNOT_LEAVE, OWNER_CANNOT_REMOVE_SELF, NOT_OWNER, WRONG_FAMILY, IN_PROGRESS, ACCOUNT_UNAVAILABLE, FEATURE_DISABLED and INTEGRITY_REQUIRES_OPERATOR. Network/unknown errors use a safe uncertain-result message. Raw Firebase messages are not displayed.

## Shopping and read shape

No client shopping transfer, copying, deletion, household-pointer update or capacity update. Existing `productionHouseholdContext.watch()` observes only server-confirmed user routing snapshots; ProductionShoppingCoordinator already uses that stream. No new shopping invalidation or listener is necessary, and shopping code is untouched.

One explicit confirmed action makes one exit callable and one getFamilyShareState refresh. Cancel makes no mutation. There is no polling, cross-device push feature, background removal listener or hidden list selector. A removed member's later open/refresh uses the same authoritative privateOnly read.

## Validation

Final Flutter suite: **147/147 PASS**, comprising **40 new 7D cases** and **107 affected 7A/7B/7C/7D0 cases**:

- family_exit_test.dart
- family_test.dart
- family_screen_test.dart
- family_mutation_test.dart
- family_join_test.dart
- family_binding_test.dart

Coverage includes exact callable payloads, missing binding, owner/self guards, both confirmations/cancel, duplicate/conflicting controls, awaited authoritative refresh, owner-only state, selected target identity and retained other member, both exit race outcomes, lost reply, same-binding explicit retry, A→B refresh without automatic retry, failed read recovery, session invalidation, small-screen dialog and safe error mapping. Existing JOIN ADD/DELETE consent/progress/recovery and binding parsing regressions pass.

Development test waits were adjusted for the intentionally animated busy indicator. Final analysis initially found only style notices in the new test file; those were fixed without production behavior changes.

Flutter analyze: **PASS**, no issues (5.3 seconds).
Android debug build: **PASS**, one final `flutter build apk --debug`, assembleDebug 32.2 seconds. Output: `build/app/outputs/flutter-apk/app-debug.apk`. APK not installed or launched. Existing plugin KGP future-compatibility notices were non-fatal; no dependency changes were made.

No backend emulator suite, historical Phase 4–6 matrix, H2, performance suite or production E2E ran. No backend business source, rules, account-deletion UI, Pro-loss UI or shopping code changed.

## Files modified

- lib/family/family_repository.dart
- lib/family/callable_family_repository.dart
- lib/family/family_mutation.dart
- lib/family/family_screen.dart
- test/family/family_exit_test.dart
- FAMILY_7D_EXIT_MEMBER_MANAGEMENT_CHECKPOINT_2026-10-28.md

## Boundary

No Family dissolution UI, owner exit, App Links/deep links, Pro-loss controls or account-deletion UI changes. Phase 7E is NOT STARTED. Production Family rollout NO. Production accessed NO. Deploy NO. Commit NO. Push NO.

Next only after 7D PASS: a separate Phase 7E owner Family dissolution and lifecycle/progress UI milestone. Do not start automatically.


Final gates: 7C PASS, 7D0A PASS and 7D0 PASS supplied as input; relevant Flutter regressions passed. **7D PASS. 7E NOT STARTED.** No unresolved blockers within this milestone. No production access, deployment, commit or push.
