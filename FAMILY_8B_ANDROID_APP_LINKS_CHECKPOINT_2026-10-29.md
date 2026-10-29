# Family 8B — Android App Links and authenticated invite routing

Date: 2026-10-29. Status: IMPLEMENTATION READY — AWAITING HOSTING DEPLOYMENT GO. Local implementation PASS. No deployment or live verification.

## Signing identity and correction

Package/applicationId/namespace: `com.bronxii.kuktam`, verified from android/app/build.gradle.kts.

Production Play App Signing certificate SHA-256:

`AF:21:94:5C:B6:95:4A:D8:F1:8A:00:D4:85:78:FF:B0:AD:60:58:77:A5:9E:3A:D0:96:6E:91:6D:23:A2:E5:CD`

Source: user-supplied Google Play Console screenshot, App signing → App signing key certificate → SHA-256 certificate fingerprint, and explicit user confirmation to use the image's complete `:CD` ending. Earlier text copies omitted the final byte. The actual stored value contains 32 colon-separated byte pairs / 64 hex characters. No byte was guessed. The earlier BLOCKED checkpoint is superseded by this implementation.

Local release configuration uses `kuktam-upload`; it was NOT substituted for the Play identity. No upload or debug fingerprint was added. A debug build verifies compilation but is not signed by the Play distribution key and therefore does not prove verified domain association.

## Android / Hosting contract

Exact canonical URI: `https://kuktam-67768.web.app/family/invite?token=<opaque-token>`.

MainActivity has one new `android:autoVerify="true"` VIEW / DEFAULT / BROWSABLE filter, HTTPS only, exact host and exact `android:path="/family/invite"`. It claims no other path, HTTP or custom scheme. Existing singleTask launch mode remains. `flutter_deeplinking_enabled=false` prevents Flutter's automatic route delivery competing with the dedicated adapter; existing recipe/text native adapters remain.

`hosting/.well-known/assetlinks.json` contains one Digital Asset Links relationship: `delegate_permission/common.handle_all_urls`, `android_app`, exact package, exactly the verified Play fingerprint above. No extra signing identities or personal data.

Existing Firebase Hosting site `kuktam-67768` and public `hosting` are retained. The old dotfile exclusion was narrowed so `.well-known/assetlinks.json` is included. The local Firebase CLI's actual listFiles implementation returns exactly `[".well-known/assetlinks.json"]`. JSON Content-Type header is configured. No `.firebaserc`, fallback page, website, redirect or iOS association was added. A landing page is not needed for Android association verification; app-unavailable/unverified browser navigation is not a completed web invitation experience.

## Adapter, parser and routing

No dependency added. Native MainActivity onCreate (cold start) and onNewIntent (warm app) consume the incoming VIEW data and place at most one <=256-character URI in volatile memory. MethodChannel `kuktam/family_links` exposes destructive `take` and `pending` notifications. It has no persistence, network or token logging. Activity replay is suppressed by consuming intent action/data and not replaying a restored launch intent. Queue overflow asks the user to reopen the link; no unbounded queue.

`AndroidFamilyLinks` drains initial/warm channel events serially. `familyInviteToken` is platform-independent Dart. It accepts only the exact HTTPS authority/path and one literal `token` query with the existing canonical unpadded base64url credential, including its canonical pad-bit constraint. Rejects wrong host/scheme/path, ports, userinfo, fragments, aliases, extra/duplicate/missing/empty query, percent-encoded aliases, whitespace and malformed URIs. It does not normalize, derive or reconstruct any credential/URL. All membership authorization remains server-side.

`FamilyLinkHost` is attached once to the app navigator with stable keys. Authenticated and email-verification-eligible sessions may route. `FamilyLinkRouter` permits one active navigation and deduplicates the latest UID/token for five seconds; no durable handled-token set. The same token may be deliberately reopened later. A second link while any pushed route/dialog is open is declined with an instruction to finish that flow and reopen the link. This conservative policy also protects manual JOIN, committed JOIN and unrelated destructive dialogs; no silent replacement or deferred execution.

An accepted link opens existing `FamilyScreen(initialInviteToken: ...)`, reads authoritative Family state, and only privateOnly opens the EXISTING `FamilyJoinScreen(initialToken: ...)`. That screen invokes its same `_validate` / repository.previewInvite path exactly once. ADD/DELETE, mandatory second DELETE confirmation, recovery, forward-only commit and completion are unchanged. Initial read failure allows normal read retry without silently losing the link. Active owner/member and inProgress are rendered from authoritative state, with no new JOIN preview/mutation. A backend race after this read is still handled by existing preview/JOIN errors.

Signed-out or email-verification-required sessions receive “Jelentkezz be, majd nyisd meg újra a meghívólinket.” The event is discarded, no token is persisted or replayed after login. Login screens are unchanged. SIGNED-OUT CONTINUATION: NOT IMPLEMENTED. No promise of process-death recovery before preview; 8C owns continuation. Normal manual code entry remains available.

## Local verification

Final targeted Flutter suite: 139/139 PASS = 30 new 8B cases + 109 affected regressions. Files:
- test/family/family_app_links_test.dart
- test/family/family_join_test.dart
- test/family/family_invite_link_test.dart
- test/family/family_screen_test.dart
- test/auth/auth_qa_test.dart
- test/auth/email_verification_test.dart
- test/walkthrough/walkthrough_test.dart

Coverage includes strict parser and zero preview for invalid input; initial/warm native channel seam through real host/navigation to existing 7C screen; duplicate/different link while flow open; signed-out notice/no continuation; authoritative owner/member/progress conflicts; ADD completion and committed second-link suppression; empty-list DELETE second consent; failed-read retry. Existing 7C manual code, ADD/DELETE and recovery regressions pass.

Two development widget tests initially timed out because pumpAndSettle waited for the intentionally busy confirmation dialog. Their bounded frame waits were corrected; both then passed, followed by the final complete targeted run. No JOIN semantics were changed for tests.

Flutter analyze: PASS, no issues (61.6 seconds). One final Android debug build: PASS (36.3 seconds), APK not installed/launched. Source, merged debug and packaged debug manifests: PASS using the same local validator. Existing nonfatal Kotlin/plugin future-compatibility warnings remain; no dependency upgrade was introduced. `python tool/validate_family_app_links.py`: PASS for source manifest, exact package/certificate, JSON and Hosting configuration. No device installation, public domain check or production Family action executed.

## Deployment gate and later verification

DO NOT DEPLOY without separate explicit GO. From C:/Users/gabor/kuktam, after rechecking the sole Hosting site binding and upload file list:

    node .\functions\node_modules\firebase-tools\lib\bin\firebase.js deploy --only hosting --project kuktam-67768

Current firebase.json explicitly binds the sole Hosting site to `kuktam-67768`; no Functions/rules deployment is selected. This command has NOT run.

After an explicit deployment GO: verify HTTPS `/.well-known/assetlinks.json` returns 200/application-json with no redirects and the expected certificate; use a Play-signed installed build whose certificate matches; run `adb shell pm verify-app-links --re-verify com.bronxii.kuktam`, then `adb shell pm get-app-links com.bronxii.kuktam`. Use an unforced HTTPS VIEW/BROWSABLE intent to test real resolver behavior. A package-forced intent only tests local routing, not domain verification. Cold/warm preview/JOIN E2E requires separately authorized test accounts/environment; Hosting GO alone does not enable production Family gates or authorize production data mutation.

Platform references: https://developer.android.com/training/app-links/configure-assetlinks and https://developer.android.com/training/app-links/add-applinks .

## Files authored/modified

- android/app/src/main/AndroidManifest.xml
- android/app/src/main/kotlin/com/bronxii/kuktam/MainActivity.kt
- firebase.json
- hosting/.well-known/assetlinks.json (new)
- lib/app/app.dart
- lib/family/android_family_links.dart (new)
- lib/family/family_invite_link.dart (new)
- lib/family/family_link_host.dart (new)
- lib/family/family_screen.dart
- lib/family/family_join_screen.dart
- test/family/family_app_links_test.dart (new)
- tool/validate_family_app_links.py (new)
- FAMILY_8B_ANDROID_APP_LINKS_CHECKPOINT_2026-10-29.md

Backend business semantics, Firestore rules, invite tokens, manual JOIN semantics, dependencies, login UX and Family production gates unchanged. No production data access. No deploy, commit or push. 8A PASS (input); 8C NOT STARTED; final Family QA NOT STARTED. STOP before Hosting deployment.

Final gates: 8B LOCAL IMPLEMENTATION PASS. 8B LIVE VERIFICATION BLOCKED UNTIL EXPLICIT HOSTING DEPLOYMENT GO and a matching Play-signed installed build. HOSTING DEPLOYED NO. APP LINKS LIVE VERIFIED NO. No local implementation blockers remain.


## LIVE VERIFICATION — 2026-10-29

Current status: HOSTING LIVE — PLAY-SIGNED DEVICE VERIFICATION DEFERRED.
This section supersedes the earlier awaiting-deployment status. The user reports manually executing `node .\functions\node_modules\firebase-tools\lib\bin\firebase.js deploy --only hosting --project kuktam-67768` successfully, publishing exactly one file. The assistant did NOT deploy again.

Public ordinary HTTPS GET from the development machine, with redirect handling explicitly disabled:
- URL: https://kuktam-67768.web.app/.well-known/assetlinks.json
- HTTP 200; Content-Type application/json; exact URL retained, no redirect.
- JSON parses successfully and is structurally identical to intended local assetlinks.json.
- Exactly one relation: delegate_permission/common.handle_all_urls.
- Namespace android_app; package com.bronxii.kuktam.
- Exactly one fingerprint: AF:21:94:5C:B6:95:4A:D8:F1:8A:00:D4:85:78:FF:B0:AD:60:58:77:A5:9E:3A:D0:96:6E:91:6D:23:A2:E5:CD.
- No unexpected, debug or upload fingerprint. PUBLIC DAL ASSOCIATION PASS.

Device inspection used C:/Users/gabor/AppData/Local/Android/sdk/platform-tools/adb.exe devices -l. Result: `List of devices attached` with zero device entries. No connected device/emulator was available. Installed app/version/signing cannot be inspected; this does NOT establish that no app exists on the user's disconnected phone. Android version/API: not testable. Domain verification state: not testable. No pm state reset, re-verification or link launch was attempted without a device. No emulator was started or APK installed.

Therefore automatic `verified` domain state and live canonical-link routing remain DEFERRED, not an implementation failure. This is the no-device case (D), not a diagnosed debug/upload signing mismatch. The existing 139/139 local tests, analyze, build and merged-manifest PASS remain the evidence for local implementation; none were rerun.

Optional browser fallback observation: GET https://kuktam-67768.web.app/family/invite?token=test returned HTTP 404, Content-Type text/html; charset=utf-8. No Family backend was invoked and no real invite was used. Missing browser fallback content does not invalidate the separate published DAL association. No fallback implementation was added.

Remaining proof: connect an Android 12+ device with a Play-signed Kuktam build containing the 8B intent filter/adapter, verify the installed certificate and version, then perform the already documented automatic re-verification and unforced canonical-link routing check. A previously published Play build without the new manifest is insufficient. No Play upload/rollout was initiated. No further Hosting deployment is required by the observed public association result.

HOSTING DEPLOY PASS (manual user action). 8A PASS; 8B LOCAL IMPLEMENTATION PASS; 8B HOSTING ASSOCIATION PASS; 8B PLAY-SIGNED DEVICE VERIFICATION DEFERRED (no connected device). AUTO VERIFIED NOT TESTABLE. CANONICAL LINK ANDROID ROUTING DEFERRED. FLUTTER ROUTING existing local PASS, live deferred. 8C and final Family QA NOT STARTED. Production Family rollout NO.

This verification pass changed only this checkpoint document. No application/source, rules, signing, Hosting content or Family gate changes; no production Family data access; public Hosting GET only. No second deploy, Functions/rules deploy, commit or push. STOP.
