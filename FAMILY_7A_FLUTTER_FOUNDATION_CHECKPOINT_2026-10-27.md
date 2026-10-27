# Family Phase 7A - Flutter foundation and read-only screen

Date: 2026-10-27. Local validation only. Acceptance: PASS (36 tests, analyze and Android debug build).

## Architecture

The existing SettingsScreen is the app's Profile/settings route. An authenticated
user gets a Családi megosztás ListTile beneath the existing Pro card. It opens
FamilyScreen with the existing Navigator/MaterialPageRoute convention. A navigation
guard prevents duplicate route pushes. Constructor injection supports tests without
Firebase initialization; normal composition creates the callable repository lazily
when the Family route opens. Profile itself performs no Family read.

lib/family/family_state.dart contains platform-independent immutable domain objects:
FamilyStatus (privateOnly, activeOwner, activeMember, inProgress), FamilyRole,
FamilyParticipant and typed FamilyFailure/FamilyReadException. The repository
interface is pure Dart. Firebase SDK details stay in CallableFamilyRepository;
StatefulWidget/request generation handling follows existing app conventions. No new
state-management dependency or Android-specific code was introduced.

Parsing validates schemaVersion 1, membership response, current UID/role agreement,
exactly one owner, unique UIDs, and 1..8 participants. Lists are immutable and sorted
owner first, then by UID. Widgets receive no raw Firestore maps or SDK errors.
Owner identity is the unique owner row, not inferred from an activeHouseholdId.
The existing response intentionally omits householdId: 7A needs no household routing,
so the client neither invents nor obtains one through a second read.

## Authoritative source and exact read shape

The ONLY callable invoked is getFamilyShareState with an empty request, in the
existing europe-west1 region, with a 20-second request timeout. Backend source was
inspected: FamilyInviteStore.state uses a read-only transaction, authoritative
familyMemberships, household/member validation and a bounded member query. Email
identity comes from its existing Admin Auth resolver, not client profile copying.
No backend or Firestore rule changes were needed.

- One callable per route opening or explicit refresh/retry.
- Zero Firestore listeners, per-member listeners, direct Firestore reads or polling.
- Zero Family reads during Profile/widget rebuilds.
- One route-level auth invalidation subscription; while a request is pending, one
  temporary auth subscription also fences switch-away/switch-back responses.
  Both are local Auth state subscriptions, not Firestore/billed member listeners.
- Existing server shape: private-only = 3 document reads (account, user, membership).
  Active = 7 context documents + up to 8 member documents; owner additionally reads
  the invite slot document and at most 8 slot-referenced invite documents. The
  defensive member query limit is 9, with >8 rejected. One Auth batch resolves up
  to 8 member identities. Owner invite data is ignored by the 7A client.

There is no new offline cache. A failed network read shows an error; retry clears
previous state while loading. A displayed snapshot remains the last server read
until explicit refresh; this is not a realtime topology monitor. No mutation can
be enabled from that snapshot because 7A has no mutation controls or repository API.

## UI states and identity

- Loading: dedicated progress indicator, never an early no-Family flash.
- Private-only: explanatory empty state about shared shopping and the private list.
- Owner/member: active summary, own role, total participant count, bounded list,
  owner label and Te marker for the authenticated participant.
- Identity: returned email only; missing email displays Ismeretlen tag. No raw UID
  is used as a display name, no Family name feature or replicated profile storage.
- IN_PROGRESS / FAMILY_PREPARING / FAMILY_DISSOLVING backend errors map to a safe
  progress message, with manual refresh only and no operation resume/repair.
- Network, malformed/inconsistent response and other failures show friendly errors
  and retry. Raw Firebase messages/details never appear in widgets.
- Account changes clear identities and invalidate pending responses; dispose removes
  the route subscription and request-generation checks ignore late completions.
- DISSOLVED history is never queried/rendered: authoritative familyActive:false is
  privateOnly even if historical audit records remain on the backend.

Current contract limitation: getFamilyShareState does not expose every structural
lock or lifecycle intent. A PREPARED dissolution may still be a valid ACTIVE Family;
7A does not claim it is structurally idle. Fence-related ACCOUNT_NOT_READY or
FAMILY_UNAVAILABLE becomes safe unavailable UI. Only explicitly exposed transitions
are labelled in-progress. Later mutation phases must freshly validate server-side;
this display model is not admission authority. No backend redesign was attempted.

## Scope boundary

No create/invite/accept/join/leave/remove/dissolution/lifecycle callable, shopping
mutation, App Link, Android Intent adapter, backend operation resume or repair.
The only active controls on the Family route are back, refresh and retry.
Material 3 cards, ListTiles, typography, app bar and existing theme are reused.

## Validation

- Initial focused Family run: 27 PASS.
- First combined validation found 6 brace-style lints in new files and two old
  Profile tests assuming fixed viewport visibility. Added braces and explicit
  scrollUntilVisible calls in those tests, retaining their original assertions.
- Final code: 36 PASS / 0 FAIL (27 Family + 9 directly affected Profile/navigation).
- Final flutter analyze --no-pub: PASS, No issues found (5.4 seconds).
- Android debug build: PASS, exit 0, assembleDebug 47.9 seconds. Exactly one build.
  Artifact: C:/Users/gabor/kuktam/build/app/outputs/flutter-apk/app-debug.apk.
  No device install or app launch occurred. The build reported a non-fatal future
  KGP compatibility warning for cloud_functions/firebase_app_check; dependencies
  were not changed in this phase. There are no open 7A validation blockers.

New coverage includes private/historical-only, owner/member, identity/fallback,
malformed schema/role/duplicates/missing current user/>8, bounded member UI, loading,
error/retry, explicit transition codes, anonymous refusal, account switch/ABA,
Profile navigation/back/disposal, and only the empty read-only callable being sent.
Regressions cover Profile password/email controls, account switch/logout, deletion
navigation, Pro-scoped deletion confirmation, export and recipe picker navigation.

Logs: C:/Users/gabor/AppData/Local/Temp/family-7a-focused.log,
family-7a-final-tests.log (initial findings), family-7a-final-validated.log,
family-7a-analyze.log, family-7a-analyze-final.log, family-7a-android-debug.log.

No backend/emulator regression, H2/native matrix or performance suite was run.
No production service was contacted. Tests use SDK doubles and injected repositories.
No deploy, commit, push, rules change or backend business-code change.

## Files

- lib/family/family_state.dart (new)
- lib/family/family_repository.dart (new)
- lib/family/callable_family_repository.dart (new)
- lib/family/family_screen.dart (new)
- lib/settings/settings_screen.dart
- test/family/fakes.dart (new)
- test/family/family_test.dart (new)
- test/family/family_screen_test.dart (new)
- test/auth/auth_qa_test.dart
- this checkpoint

## Next boundary

7B creation/owner-invite UI is NOT STARTED. Production rollout is not enabled or
validated by this local task. Later integration may need a separate explicit read
contract extension for richer structural status; 7A uses only existing safe reads.
