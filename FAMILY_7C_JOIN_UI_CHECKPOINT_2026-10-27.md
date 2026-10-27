# FAMILY 7C — INVITE PREVIEW + JOIN UI

Date: 2026-10-27. Local Flutter implementation from the supplied Phase 7B checkpoint. No deploy, production access, git baseline/status/log checks, commit or push. Next phase not started.

## Exact existing backend mapping

| Purpose | Callable and exact request |
|---|---|
| Preview | previewFamilyInvite({token}) |
| Reserve selected intent | acceptFamilyInvite({token, mode: ADD or DELETE}) |
| Upgrade/prepare the same operation | prepareFamilyJoinTransfer({operationId, inviteId}) |
| Authoritative operation read | getFamilyJoinTransferState({operationId, inviteId}) |
| DELETE second consent | confirmFamilyJoinDelete({operationId, inviteId, sourceEpoch, snapshotHash, sourceItemCount, consentVersion: 1}) |
| Pre-commit cancellation | cancelFamilyJoin({operationId, inviteId}) |
| Membership/success | getFamilyShareState({}) |

No endpoint names or business operations were invented. Existing region europe-west1 and session-fenced callable transport are reused. Request mutation timeout remains 65 seconds. No direct Firestore reads/writes were added.

acceptFamilyInvite returns the existing deterministic `join_ + SHA256(UTF8(uid))` operation identity. The repository verifies it, and derives inviteId using the existing backend SHA256(UTF8(canonical token)) identity contract. Existing crypto dependency is reused, no dependency added. Neither identity is shown in UI. These identities locate the existing operation; the server remains the authorization authority.

IMPORTANT runtime boundary: backend reserve/prepare/state/confirm/cancel retain their existing demo-project + loopback Firestore + no K_SERVICE/FUNCTION_NAME local-runtime barrier and joinReservationEnabled gate. 7C does NOT remove or bypass these gates or enable production JOIN. FEATURE_DISABLED is shown safely. Flutter validation below uses local SDK/repository doubles, not a production or Functions-emulator JOIN E2E. Runtime rollout/transport enablement remains separate work.

## Entry and preview

Only the authoritative privateOnly Family state offers “Meghívókód megadása”. It is outside Pro gating. Active owner/member and inProgress have no entry. The existing FamilyScreen pushes FamilyJoinScreen with the same repository; this is a route-local StatefulWidget flow, not a new state framework.

Input trims surrounding whitespace, preserves case, accepts paste, disables correction/suggestions and validates canonical 43-character base64url shape for UX. Backend is authoritative. No URL parsing, token persistence, logging, signed-out continuation or platform link adapter.

Preview must be schemaVersion 1, VALID / eligible true / PENDING and structurally valid. It displays backend owner email (or “Ismeretlen tag”) and expiry. No family name or participant count is fabricated. Private shopping count is parsed but is NEVER used to skip consent; second consent uses the later fenced snapshot evidence, not preview count. Raw code field is cleared after preview and the credential remains transient until the operation ends/route disposes/session changes.

Expected preview/application codes are mapped to Hungarian messages: invalid/not found, expired, used/revoked, full, already member/other family, self-invite, structural progress, account unavailable, owner/family unavailable and feature disabled. Unknown or transport errors show an uncertain-result message, not backend details.

## ADD and DELETE contract

Exactly two mutually exclusive ChoiceChips, initially neither selected:
- Saját listám hozzáadása: existing private items are semantically merged into Family, then source contents cleaned by backend.
- Saját listám eldobása: existing contents are not transferred and are removed by backend. No fallback household deletion is implied; no list selector is exposed.

ADD requires a separate confirmation dialog before reservation/preparation. The user explicitly authorizes the existing ADD workflow; the server commits automatically once its snapshot is ready.

DELETE first selects the destructive handling and starts preparation. Once the server reports SOURCE_FENCED_WAITING_CONFIRMATION, a distinct “Eldobás megerősítése” action opens a SECOND scrollable destructive dialog. Its explicit CTA is “Csatlakozás és saját lista eldobása”. Cancelling this dialog sends NO consent. Confirming passes the exact sourceEpoch, snapshotHash, sourceItemCount and consentVersion 1 returned by the backend. This sequence is identical when sourceItemCount == 0. No defaults, remembered or automatic consent.

Both explanations describe content removal; there is no client shopping merge, normalization, copying, deletion, compensation or optimistic activation.

## Progress, cancellation and recovery

Before submission the user may leave without server work. During requests controls/back are disabled. After a known cancellable pre-commit operation exists, an explicit “Csatlakozás megszakítása” invokes the existing cancellation endpoint; ordinary back navigation cannot silently strand that known operation. Backend cancellation revokes/releases according to its existing contract; this UI does not restore the invite.

A confirmed committedAt/committed phase latches the workflow forward-only: no mode switches, consent, cancel or new JOIN. UI shows “Csatlakozás folyamatban…” without raw phases/IDs. A cancellation race that returns IN_PROGRESS is resolved by an authoritative read and becomes forward-only if committed. Impossible regression from an observed committed state to pre-commit is treated as unavailable, not permission to cancel.

Every explicit progress refresh first reads current Family membership:
- ACTIVE member: clear transient code/preview/choice and return; parent performs its authoritative refresh to render owner/member list and Te marker.
- Still private or in progress: use the same operation handle; read progress.
- Lost initial accept response: retry only the SAME token/mode after the membership read; deterministic server reservation reuses the same operation. No fresh choice/token is accepted.
- Lost prepare response: repeat preparation of the same handle; existing v2 preparation is idempotent.
- Lost DELETE confirmation/cancel response: mark uncertain, hide consent/cancel and require an authoritative state read. No automatic destructive retry.
- Known definitive reservation rejection before any returned handle restores the pre-submit UI; ambiguous failures retain the frozen intent.

No polling or automatic mutation retry. Existing backend maintenance owns bounded continuation. Manual “Állapot frissítése” reads state; it does not implement a worker. A route/app reopened without transient credentials relies on getFamilyShareState inProgress, not a new JOIN entry. The current read API does not expose recovery handles for that route; no local persistent-token/reconstruction architecture was invented. Abandoned pre-commit work remains governed by existing backend expiry/abort; committed work progresses server-side.

Session changes clear UI identity/code and invalidate late responses (including A→B→A). Pro is not consulted for JOIN admission. The server checks owner entitlement.

## Shopping integration and cost

Existing productionHouseholdContext already observes server-confirmed users.activeHouseholdId, and the shopping coordinator switches household/context streams. No shopping or household code was changed. No new per-member listener, Family Firestore listener or polling.

Preview = one callable. Start = one membership read, one accept, one prepare. Refresh = one membership read plus status (or same-handle recovery preparation when needed). A DONE status is verified with membership before success. Parent refresh renders authoritative activeMember; no local membership fabrication.

## Validation

Final command: `flutter test --no-pub test/family --reporter expanded`

**90 PASS**: 35 new 7C tests + 27 7A + 28 7B regressions, including Profile → Family navigation. No shopping code was touched, so no unrelated shopping suites were run.

7C covers exact callable/payload whitelist, hash-bound identity, DELETE snapshot consent with zero items, invalid preview codes, safe raw-error handling, malformed progress, Free entry, owner/member/progress exclusion, trim/empty input, preview/submission double-tap safety, ADD confirmation/cancel, DELETE second dialog/cancel/confirm, backend cancellation, forward-only progress, authoritative activeMember, lost accept/preparation/consent responses, already-active recovery, commit/cancel race, auth ABA/session invalidation, small screen and navigation back to authoritative inProgress. No test invokes production.

One development assertion expected the hidden parent route's loading indicator to be visible; it was corrected to assert the current route's non-loading state. Final tests pass.

Flutter analyze: **PASS**, no issues (6.8 seconds).
Android debug build: **PASS**, assembleDebug 11.1 seconds. One final build executed; build/app/outputs/flutter-apk/app-debug.apk. APK not installed/launched. Existing cloud_functions/firebase_app_check future KGP compatibility warning is non-fatal; dependencies unchanged.

## Exact phase boundary

No backend business code, Firestore rules, dependency, Android/native or shopping changes. No invite link handling, signed-out continuation, leave/remove/dissolution UI, rollout or deploy. Future exit/lifecycle UI and dedicated App Links/login continuation remain separate tasks. Production JOIN enabling requires a separately authorized runtime rollout; this task leaves all existing safety gates intact.

Files changed:
- lib/family/family_join.dart (new)
- lib/family/family_join_screen.dart (new)
- lib/family/family_repository.dart
- lib/family/callable_family_repository.dart
- lib/family/family_screen.dart
- test/family/family_join_test.dart (new)
- FAMILY_7C_JOIN_UI_CHECKPOINT_2026-10-27.md (new)

## Final gates

Phase 7C: PASS for local Flutter implementation and focused validation. No implementation blockers. Phase 4B/5/6 COMPLETE and 7A/7B PASS are the supplied input checkpoints, not revalidated historical matrices. Next phase NOT STARTED. Production Family rollout NO. Deploy NO. Commit NO. Push NO.

