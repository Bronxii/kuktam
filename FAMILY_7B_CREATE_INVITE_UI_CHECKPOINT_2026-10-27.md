# FAMILY 7B — CREATE + OWNER INVITE UI

Date: 2026-10-27. Local implementation only. No deploy, production access, commit or push. Phase 7C not started.

## Existing contracts inspected

- `createFamilyShare({})` returns schemaVersion 1, deterministic create operationId and outcome. Server checks entitlement, lifecycle and private household validity. It copies/verifies the current private shopping into Family, activates Family routing and cleans the source. Flutter confirmation describes that product effect.
- A callable executes at most four engine steps. `jobs/maintenance.ts` already resumes due CREATE operations through existing maintenance. Flutter never loops mutation calls or pretends a partial outcome is DONE. It refreshes authoritative state once; an unfinished operation is shown safely with manual refresh. Normal runtime maintenance/configuration remains a rollout prerequisite, unchanged by 7B.
- `createFamilyInvite({})` needs NO email. It returns inviteId, a canonical 43-character bearer token and server expiresAt, NOT a URL and NOT an email-send result. `FAMILY_INVITES_IDENTITY.md` explicitly leaves future HTTPS URL selection to the client phase. This implementation displays a **meghívókód**, not an invented URL. Copy code is usable for sharing the credential; accepting it remains unimplemented in this app version and the UI says so.
- Separate invite requests intentionally mint separate tokens. A lost response cannot be recovered by repeating the call. No automatic mutation retry was added; ambiguous errors warn that another invitation may create another code. Existing bounded pending metadata remains visible on refresh; revocation is outside 7B.

## Flutter architecture and mutation flow

Existing FamilyRepository gains createFamily and createInvite. CallableFamilyRepository is still the only transport boundary, region europe-west1. Mutation timeout is 65 seconds against the existing 60-second endpoint. Empty payloads only. Strict response parsing, typed safe failures and auth-session/ABA fencing are repository responsibilities. There are no direct Firestore Family writes.

FamilyScreen retains its existing state flow. Only explicit taps mutate. The busy guard begins before creation confirmation, prevents double taps/refresh/back navigation during submission and resets on completion/failure/cancel. A session change clears credentials, identity and notices; late responses cannot reintroduce them.

Private-only plus existing ProScope.isPro displays “Család létrehozása”. Otherwise the existing ProfileProCard/Pro navigation appears with an ownership explanation. This is UX only; backend entitlement remains authoritative and is checked again at submission. Owner/member/in-progress screens have no create button. Members remain read-only. Full (8 participant) owners see a disabled invite action; backend remains authoritative for concurrent capacity and pending limits.

Create confirmation explains ownership and current list migration. Successful/accepted creation always performs one authoritative read; no owner/member state is fabricated from mutation data. Partial creation shows progress. Errors never display Firebase details.

Owner invite action requires no input form because the server requires no input. It shows the returned code and localized server expiration. Clipboard uses Flutter services, with a success/error message; no new plugin. Code exists only in transient screen memory and clipboard upon explicit copy: no storage, logging, analytics, restoration, email replication or URL parsing. Auth switch, refresh and navigation disposal discard screen credentials. Clipboard contents are intentionally user-owned after copying.

## Reads and pending metadata

- Open/manual refresh: one getFamilyShareState({}).
- Create: one createFamilyShare({}), then one state read.
- Invite: one createFamilyInvite({}), then one state read because the existing response includes the changed owner pending-invite inventory.
- Invite result retained even if that refresh fails, unless session invalidation occurred; a successful mutation is not repeated to obtain metadata.
- Pending/RESERVED metadata displayed read-only, bounded to 8, without exposing internal IDs. No token recovered from history.
- No polling, new Firestore listener, member fan-out, backend resume/repair or automatic retry.

## Error mapping

proRequired / OWNER_NOT_PRO → Pro explanation; alreadyFamily / ALREADY_MEMBER / ALREADY_IN_FAMILY → refresh membership; IN_PROGRESS / FAMILY_PREPARING / FAMILY_DISSOLVING → wait/refresh; lifecycle/private integrity conflicts → account unavailable; FAMILY_FULL → 8-person limit; PENDING_LIMIT → pending limit; NOT_OWNER → owner authorization; all unknown/transport/malformed outcomes → safe ambiguous-result message. No raw Firebase exception/token is rendered as an error.

## Validation

Final targeted suite: **64 PASS** = 28 Phase 7B + 27 Phase 7A + 9 directly affected Profile/navigation/Pro tests.

Command:
```
flutter test --no-pub test/family test/auth/auth_qa_test.dart test/auth/account_deletion_test.dart test/pro/pro_integration_test.dart test/export/export_test.dart test/sharing/recipe_file_receiver_test.dart --name '7A |7B |Settings|password eye|password validation|email change dialog|account A logout|password change preserves' --reporter expanded
```

Coverage: exact callable whitelist/empty payload, response validity, safe error mapping, no implicit retry, anonymous denial, auth ABA, pending inventory, Pro gating, confirmation/cancel, submission duplication, authoritative owner refresh, partial creation, no email form, invite result/copy, capacity/authorization/unknown failures, member/in-progress/full restrictions, late session response, small-screen layout. Existing 7A validates Profile navigation, roles, bounded members, loading/error/retry and historical-only state.

Development tests initially found one test-fixture cascade error and two test waits that tried to settle an intentional loading animation. Fixtures/waits were corrected; final full targeted run passed. No backend/emulator, shopping-scale, native H2 or production test was run.

Flutter analyze: **PASS**, no issues (5.4 seconds). Ten initial curly-brace style notices were fixed; the final 64-test run also passed after those fixes.
Android debug build: **PASS**, assembleDebug 49.5 seconds; build/app/outputs/flutter-apk/app-debug.apk. One executed final build. An earlier invocation never executed because automatic approval review hit a usage limit; after the user requested continuation the approved retry succeeded. Existing cloud_functions/firebase_app_check KGP future-compatibility warning is non-fatal; no dependency changes. APK not installed or launched.

## Exact boundary / remaining work

No create/invite backend business changes, rules changes or dependencies. No acceptance/JOIN/preview, token parsing from links, App Links, email sending, leave/remove/dissolution or invite revocation. 7C owns invite preview/JOIN + ADD/DELETE and second DELETE confirmation. HTTPS URL contract/link handling is not invented here; current backend exposes a shareable code only. No production rollout is authorized.

Files changed in 7B:
- lib/family/family_mutation.dart (new)
- lib/family/family_repository.dart
- lib/family/callable_family_repository.dart
- lib/family/family_state.dart
- lib/family/family_screen.dart
- test/family/family_mutation_test.dart (new)
- test/family/family_screen_test.dart (strict fake for added methods)
- FAMILY_7B_CREATE_INVITE_UI_CHECKPOINT_2026-10-27.md (new)


## Final gate

Phase 7B PASS. Phase 7C NOT STARTED. No blockers. Phase 4B/5/6 and 7A remain the supplied completed input checkpoints. Production Family rollout NO. Commit NO. Push NO. Deploy NO.

