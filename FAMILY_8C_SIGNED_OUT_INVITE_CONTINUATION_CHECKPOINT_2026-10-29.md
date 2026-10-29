# Family 8C — signed-out invitation continuation through authentication

Date: 2026-10-29. Final result: PASS. Implementation and targeted validation complete. Input: 8A PASS, 8B local PASS and Hosting association live PASS. Play-signed device domain verification remains deferred to final QA.

## Architecture

The existing FamilyLinkRouter now supports one optional PendingFamilyInviteStore, serialized asynchronous persistence and continuation resumption. FamilyLinkHost uses that store in production. The strict 8B URI parser and Android incoming URI adapter remain authoritative for URL syntax; credentials stay opaque. No second JOIN flow or authentication coordinator was added.

FamilyInviteAdmission is mounted **inside** the existing AuthGate usable-user branch, and in production inside HouseholdGate, itself below WalkthroughGate. Its post-frame admission signal enables routing only after the normal app is ready. The signal is revoked on disposal; the host also compares it with the current eligible authentication UID. Temporary registration/unverified sessions cannot admit Family routing. Existing navigation-change notifications resume only when no pushed route/dialog is active, so login dialogs finish normally. No polling or extra auth subscription was introduced.

Authenticated links after normal admission retain the 8B direct path with no pending-storage write. Links received before admission are stored, displayed as pending, and resumed once the normal gates and navigator allow. Invalid URLs never become pending and never call Family preview.

## Persistence and credential security

Uses already-installed flutter_secure_storage (no dependency changes), a separate Android Keystore-backed storage namespace `kuktam_family_invite`, key `pending_invite_v1`.

Only JSON `{ "version": 1, "token": "<exact opaque token>" }` is stored. No UID, URL, email, household, expiry, preview, members, shopping or JOIN operation data. Local validation checks format only; it does not confer invite validity or membership. The server remains authoritative for expiration, use, revocation and eligibility.

After write/delete, `kuktam/family_invite_durability` follows the existing encrypted-preference durability convention: background-thread commit waits for prior preference writes, scoped only to the three secure-storage namespace preference files. No auth or entitlement data is modified. Both Android backup formats exclude these namespace files from cloud backup and device transfer. Secrets are not logged or placed in route names. Read/write/delete errors produce generic Hungarian UI; no exception details or token are displayed.

After an acknowledged write, process recreation during login restores the one pending token. This is tested with coordinator recreation and the real auth-gate widget seam, not native process-kill E2E. Unreadable storage fails closed; malformed records are deleted rather than interpreted. Storage errors offer retry and explicit local discard.

## Auth paths and UX

Cold-start and warm signed-out links create the same single pending continuation. A visible banner says a Family invitation is waiting and will continue after login. `Meghívó elvetése` removes only local continuation, never consumes/revokes the backend invitation.

Email/password: normal verified usable session admits the continuation. Google: the same admitted session signal, no Google-specific Family logic. Registration: the current flow still sends verification email and signs out; pending survives until later verified login. Restored unverified sessions retain the existing forced-signout policy. No normal authentication/verification/household/walkthrough gate is bypassed.

Login failure, Google cancellation, verification failure or backing out of a login dialog retain pending. The persistent visible banner and discard action explain subsequent continuation; no hidden indefinite invitation. The user can dismiss it at any point before handoff. No client TTL was invented.

Duplicate token A is idempotent. A new explicit B replaces A before handoff; there is never an array/queue of invitations. Writes and deletes are serialized. Failed B replacement blocks automatic resume of old A and keeps B in volatile retry state; successful retry persists B. If the process dies during a failed/unacknowledged write, no durable-success guarantee is claimed.

## Ownership and clearing

At safe handoff the router requires usable current auth and a free root navigator, durably deletes pending storage, rechecks the same admitted session/navigation, then immediately opens existing FamilyScreen(initialInviteToken). If the gate changes during deletion it restores the pending token instead of navigating. Failed deletion blocks navigation. No UID is stored as invitation authority.

The established Family screen owns the token after handoff. It reads authoritative Family state, opens existing FamilyJoinScreen for privateOnly, and renders existing owner/member/inProgress restrictions otherwise. It does not force a second Family. Existing previewInvite, ADD/DELETE consent, JOIN recovery and forward-only behavior are unchanged.

Persistent pending is cleared at route ownership, not because login opened or preview returned a network error. A transient preview failure retains the code in existing 7C route-local input and supports its existing retry. Terminal invalid/expired/used/revoked errors use existing safe 7C copy and cannot retrigger on later launches because persistent ownership was already relinquished. Closing the established flow is a deliberate abandonment of its route-local credential; it is not requeued. Later logout/account switch cannot resurrect persistent pending after handoff. A crash after handoff follows existing 7C/server recovery; 8C does not persist a second JOIN recovery state machine.

Different links while a pushed Family/JOIN/destructive flow is active do not replace it. Existing 8B finish-and-reopen behavior remains. No token is bound client-side to a login account; the eventual authenticated account is validated by existing server contracts.

## Validation

Development: 21 initial 8C tests PASS; 30 directly affected 8B tests PASS. Final targeted run: 135/135 PASS = 23 new 8C + 112 affected regressions:

- test/family/family_continuation_test.dart
- test/family/family_app_links_test.dart
- test/family/family_join_test.dart
- test/auth/auth_qa_test.dart
- test/auth/email_verification_test.dart
- test/walkthrough/walkthrough_test.dart

New coverage: minimal encrypted-store payload and flush, corrupt payload handling, duplicate/replacement, process recreation, login failure/cancel, no pre-auth preview, no authenticated storage write, durable-delete failure, dialog navigation wait, failed replacement retry, email/Google/registration admission through actual AuthGate for cold/warm events, unverified rejection, explicit local cancel, terminal invalid/expired/used/revoked errors, transient preview retry and restored-pending widget resume. Auth provider credentials are simulated; existing auth repository/UI regressions validate their normal behavior. No production sign-in/E2E performed.

Backup exclusion XML validation PASS for legacy backup, cloud backup and device transfer. New continuation source contains no logging/analytics calls. Final flutter analyze PASS, no issues (5.4 seconds). One style-only missing-braces notice was corrected and only analysis was repeated; behavior and passed tests were unchanged. One final Android debug build PASS (35.3 seconds); APK not installed/launched. Existing nonfatal Kotlin/plugin future-compatibility warning remains, with no dependency changes.

## Files authored/modified

- lib/family/pending_family_invite.dart (new)
- lib/family/family_invite_link.dart
- lib/family/family_link_host.dart
- lib/features/auth/presentation/widgets/auth_gate.dart
- android/app/src/main/kotlin/com/bronxii/kuktam/MainActivity.kt
- android/app/src/main/res/xml/backup_rules.xml
- android/app/src/main/res/xml/data_extraction_rules.xml
- test/family/pending_invite_fake.dart (new)
- test/family/family_continuation_test.dart (new)
- test/family/family_app_links_test.dart
- FAMILY_8C_SIGNED_OUT_INVITE_CONTINUATION_CHECKPOINT_2026-10-29.md (new)

## Boundaries and remaining QA

No backend, Firestore rules, Hosting, assetlinks/signing, manifest intent-filter, dependency or JOIN business semantic changes. No production data access or deployment. iOS Universal Links remain unimplemented. The known browser fallback HTTP 404 is separate and unchanged.

Final Family integration QA is NOT STARTED. Remaining QA includes matching Play-signed 8B-capable Android build automatic domain verification and unforced link routing, real-device auth/process recreation, and separately authorized full Family integration scenarios. No Play rollout, Hosting/Functions/rules deploy, commit or push. STOP before final QA.

Final gates: 8A PASS; 8B LOCAL PASS; 8B HOSTING PASS; PLAY-SIGNED DEVICE VERIFICATION DEFERRED TO FINAL QA; 8C PASS. Blockers NONE. FINAL FAMILY QA NOT STARTED. PRODUCTION FAMILY ROLLOUT NO. COMMIT NO. PUSH NO. STOP.
