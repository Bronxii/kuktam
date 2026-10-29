# Family 8A — canonical HTTPS invite-link contract

Date: 2026-10-28. Input: verified 8A0 Hosting origin and locally complete Family core. Final result: PASS.

## Canonical contract

Origin: `https://kuktam-67768.web.app`, accepted from 8A0 authenticated Firebase Hosting LIST/GET metadata for `projects/kuktam-67768/sites/kuktam-67768`, DEFAULT_SITE. This phase did not rediscover the host, contact production, change Hosting configuration or deploy content.

Exact sole emitted format:

`https://kuktam-67768.web.app/family/invite?token=<existing-opaque-token>`

No trailing path slash, aliases, alternate query names, fragments, userinfo or ports. The only credential is the existing 32-random-byte canonical unpadded base64url token (43 characters). `functions/src/households/invite-url.ts` centralizes the backend origin and construction. `familyInviteUrl` validates through existing `hashInviteToken`, constructs `new URL('/family/invite', FAMILY_INVITE_ORIGIN)` and sets one URLSearchParams `token` value. URL construction occurs before the invitation transaction, so an invalid credential cannot cause a created invite with a fake URL.

All currently valid token characters are URI-unreserved; the builder preserves case and exact bytes without trimming or double encoding. Standard URL parsing/searchParams.get('token') returns the exact original token. Tests cover zero, low, mixed-case, hyphen and underscore producing byte patterns. No UID, household, email, operation ID, participant count or lifecycle metadata occurs in the URL. Possession grants only the existing invite-code capability.

## Server response and persistence

`createFamilyInvite({})` preserves schemaVersion, inviteId, token and expiresAt, adding only `inviteUrl`. Old clients may ignore the extra field. No second credential/document/state machine/TTL was added. PENDING/RESERVED/USED/REVOKED and expiry checks are unchanged; previewFamilyInvite({token}), JOIN ADD/DELETE, consent, rejoin generations, cancellation and recovery are unchanged.

Pending/read-only invite rows remain unchanged: the server stores only the hash inviteId, not raw token, so it cannot reproduce the credential from the pending list. URL/token are returned only in the newly created result, are not logged by new code and are not stored in Firestore or application persistence. Copying/displaying the result causes no invite mutation.

## Flutter

`FamilyInviteResult` gains immutable inviteUrl. Existing callable parsing requires HTTPS, exact `kuktam-67768.web.app` authority, `/family/invite`, one exact token query matching the returned code, no fragment and canonical textual representation. Missing/malformed/non-HTTPS/wrong-host/port/userinfo/path/duplicate/extra/token-mismatch/encoded-alias values fail with existing safe FamilyMutationException. The received string is retained unchanged; no URL is reconstructed or used as a fallback. New client deployment therefore requires the backend response addition first; missing URLs intentionally fail closed per the task contract.

The existing owner invite result presents the link first, then manual code and the existing expiry. “Link másolása” and “Kód másolása” use the existing Clipboard API. Copying adds no reads or mutations. Existing pending-list refresh after creation remains unchanged. Hungarian copy explicitly says link opening does not yet start in-app joining and manual code entry is supported. No sharing dependency, automatic navigation or tappable-link routing was added.

URI validation here applies only to trusted callable-response parsing; it is not an incoming-link handler. Manual 7C code input/preview/ADD/DELETE/second consent and recovery were not edited.

## 8B handoff and hosting limits

8B must accept this exact canonical HTTPS origin/path, extract the single token without changing its case/content, then use the existing server-authoritative preview/JOIN contracts. Tokens remain opaque; URL validity never replaces invite authorization, expiry or single-use checks. Incoming-link acceptance/routing and malformed-input policy must be implemented separately.

No Hosting page/redirect or deploy was necessary to validate the representation. The /family/invite path is a contract, not a claim of deployed landing content or functioning App Links. No Android intent filter/autoVerify/assetlinks, Apple association, incoming route, signed-out persistence, login continuation or auth change was made. 8B and 8C remain separate; no final Family QA or production rollout was started.

## Validation

Development backend: 11 new URL/create-response cases PASS. Final backend validation: PASS. 91 URL/invite tests passed. Five real rejoin cases initially failed only because their old fixture's empty Auth resolver reported the owner unavailable when the new preview assertions ran. The test-only resolver now represents the existing fixture users (no email data); production behavior was not changed. Only these five failed cases were repeated, all PASS. Distinct final backend coverage: 96 cases = 12 new 8A cases + 84 affected regressions (80 invite/read and four existing real rejoin ADD/DELETE/self-leave/owner-remove A-to-B-to-C cases). The new real rejoin test creates B after A leaves, verifies URL A is USED/non-reusable, previews and activates B, and preserves A's historical JOIN evidence. Functions build: PASS.

Final Flutter targeted run: 80/80 PASS (17 new 8A + 63 existing 7B/7C cases). A test-only missing-braces style notice was corrected without behavior change. Final flutter analyze: PASS, no issues (5.6 seconds). One Android debug build: PASS, assembleDebug 11.2 seconds; APK not installed or launched. Existing nonfatal Kotlin/plugin future-compatibility warnings did not require dependency changes.

Logs: C:/Users/gabor/AppData/Local/Temp/family8a-final-backend.log, family8a-final-flutter.log, family8a-analyze.log, family8a-android.log.

## Authored files

- functions/src/households/invite-url.ts (new)
- functions/src/households/family-invites.ts
- functions/test/invite-url.test.ts (new)
- functions/test/family-invites.test.ts
- functions/test/family-rejoin.test.ts
- functions/scripts/emulator-tests.cjs
- lib/family/family_mutation.dart
- lib/family/family_screen.dart
- test/family/family_invite_link_test.dart (new)
- test/family/family_mutation_test.dart
- FAMILY_8A_INVITE_LINK_CONTRACT_CHECKPOINT_2026-10-28.md (new)

No Firestore rules, Hosting files, Flutter JOIN implementation, backend JOIN/exit/dissolution engines or production gates changed. No production access, deployment, commit or push. Final gates: Family core backend/UI COMPLETE (input), 8A0 PASS, 8A PASS. Blockers: NONE. 8B and 8C NOT STARTED, final Family QA NOT STARTED, production Family rollout NO. STOP before 8B.
