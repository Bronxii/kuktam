# Family 9B — release readiness review — 2026-10-29

> Current status (2026-10-30): **CONDITIONAL PASS — EXTERNAL / ROLLOUT BLOCKERS REMAIN**. The post-9B0 delta at the end supersedes the original R1 OPEN / FAIL classification below. The original review is preserved as historical evidence.

## Scope and evidence
Read-only code review of current Family stores/handlers, Dart repository/screens, link router, secure pending storage, auth gate, Android adapter/backup policy, Hosting config and Firestore rules. Reuses 9A evidence (new repository/Auth/Firestore chain, 13 backend and 221 Flutter regressions). No full suite/build rerun. No production Firestore/config/account read or mutation. Only two expressly authorized public HTTPS GETs and adb device inventory. Live deployed Functions/rules/gate values have NOT been independently queried; local source and prior checkpoint are distinguished below.

## Security and authority
- CREATE: authenticated UID, active account, server Pro aggregation, private routing/owner records, no membership, runtime gate; transaction/lease/fence owns copying and activation.
- Invites: owner context is derived from authenticated UID; active Family, owner Pro, capacity and bounded pending slots. Token is 32 random bytes, canonical 43-character base64url. SHA-256 is the server lookup ID; raw token and URL are response-only. Seven-day expiry and existing single-use/revocation apply. No second credential.
- Preview/accept: possession is only a lookup capability, not membership authority. Server checks account, owner, Pro, routing, current membership, invite state, reservation/capacity and structural lock. DELETE consent binds exact source epoch/hash/count/version. Committed transfer is forward-only.
- Exit: immutable UID/invite pairing in Dart; server checks actor owner/member role, current JOIN generation, USED invite, routing and structural lock. Old completed exit replay remains historical and cannot modify a later membership.
- Dissolution: empty client request, authenticated current owner derived server-side. Existing preparation/driver/queue, no Flutter orchestration. Pro-loss comes from authoritative server grants; no member Pro privilege transfer or rollback UI.
- Deletion: member exit -> private deletion; owner dissolution -> verified historical audit detachment -> private deletion. Account generation and durable receipts checked; no production deletion performed.
- No direct structural Firestore access in lib/family. Client shopping migration/merge/delete/capacity updates absent. Local rules deny client structural writes and enforce current shopping context. No rules changed.
- No token/full-link logging or analytics calls found in reviewed Family paths. User intentionally sees/copies newly created credential; errors use typed Hungarian messages rather than exception text/internal IDs.

## Pending credential / auth / links
SecurePendingFamilyInviteStore uses existing flutter_secure_storage, namespace kuktam_family_invite, key pending_invite_v1, JSON exactly version + token. No UID, household, preview or operation stored. resetOnError=false; migrateWithBackup=false. Native flush commits the three dedicated preferences. backup_rules and both cloud-backup/device-transfer sections exclude all three namespace files. Handoff clears durable state first and rechecks admitted auth/navigation; failure remains safe. An abrupt death after clear but before route ownership can require reopening the link (at-most-once ownership tradeoff); it does not resurrect an old token.

Admission is inside existing usable-auth/email-verification/household gates. Google, email and registration converge on that gate. Failure preserves pending intent; explicit local cancel clears it without backend mutation. Latest distinct link replaces pending earlier link; duplicates are idempotent. After handoff, existing 7C owns retry/terminal error presentation; no persisted token repeatedly reopens invalid invites.

Strict parser requires exact HTTPS authority kuktam-67768.web.app, /family/invite, one canonical token query, no extras/fragment/userinfo/port/encoded aliases. Invalid links stop before backend. One active route and five-second same-user/token deduplication; another link cannot silently replace an active JOIN. No native intent data grants authority.

## Live public checks (one GET per URL, redirects disabled)
- https://kuktam-67768.web.app/.well-known/assetlinks.json: HTTP 200, application/json, no redirect, JSON exactly equals local file.
- Relation delegate_permission/common.handle_all_urls; namespace android_app; package com.bronxii.kuktam.
- Sole certificate AF:21:94:5C:B6:95:4A:D8:F1:8A:00:D4:85:78:FF:B0:AD:60:58:77:A5:9E:3A:D0:96:6E:91:6D:23:A2:E5:CD. No debug/upload identity.
- https://kuktam-67768.web.app/family/invite?token=test: HTTP 404, no redirect. No Family backend call.
- adb devices -l: no devices. Automatic Play-signed domain verification is DEFERRED — RELEASE BLOCKER, not an implementation failure.
- Hosting source contains only assetlinks.json and ignored .gitkeep; explicit site kuktam-67768/public hosting; no .firebaserc. No unexpected secret-bearing content found.

## Read/write shape (not a billing benchmark)
Family open or explicit refresh: one getFamilyShareState; build does not call it. Auth changes invalidate the session instead of rereading in a loop. Return from JOIN and completed/uncertain mutations trigger bounded refreshes. No polling, per-member client calls or Family document listeners.

Normal state logical Firestore read requests, excluding retries/billing minimums/caching: private user ~3; active context ~11 + member query M (max8, limit9 fails closed). Owner adds slot document + up to8 pending invitation documents and four direct document reads for each of at most7 non-owner bindings (user/index/current JOIN/invite). Thus owner approximately 12+M+4N+I, up to56 logical document reads for healthy max-size/max-slots state; two-person/no-pending ~18. Normal member resolves only own binding: ~15+M, up to23. One Admin Auth getUsers batch of up to8 follows; it is not a Firestore fan-out. No historical JOIN collection scan. In-progress usually exits earlier.

Invite creation: one callable then one Family refresh. Transaction reads gate/context/Pro grants/member list/bounded slots and collision target; creates invite and writes slot inventory. Pro aggregation has limit501/fails above500. No history scan or URL record. Lost invite creation response is NOT automatically retried; a deliberate new create may create a new credential (existing documented semantics).

JOIN: preview once per explicit attempt (plus count aggregation over private shopping and owner lookup); explicit mode/consent; _advance reads Family then starts/reuses same token operation only if needed, then prepare/status, and a final Family read on DONE. Refresh is user-driven, no timer. Backend item/page/journal work scales with shopping contents; bounded pages do not imply constant total cost. No client per-item writes. Preview count aggregation also scales with indexed item count.

Leave/remove: one mutation + one authoritative refresh after success or error. Dissolution: one start + one refresh; later manual/reopen reads only. Server maintenance is bounded/paged and scheduled; client never iterates members or calls internal phases. No automatic destructive retry loop found. STALE triggers refresh; JOIN lost-ACK recovery retains same token/mode; dissolution uncertainty reads before deliberate retry.

## UI / errors / historical boundary
DELETE second consent, explicit leave/remove confirmation and dissolve entry + final destructive CTA are present. Busy guards prevent duplicate submits. Owner cannot self-remove; member cannot dissolve; inProgress hides structural actions. Errors map to safe messages; internal source/hash/epoch/operation values are only domain metadata. Historical DISSOLVED records are not rendered as active and private routing is restored. Subsequent former-owner reuse is a confirmed failure (R1 below).

## Rollout state
familyOptions enforceAppCheck=false in source. App Check enforcement remains release finishing work; no change made. creationEnabled/inviteCreationEnabled/joinReservationEnabled are backend config gates. In addition, JOIN transfer, leave/remove, dissolution and Family deletion/lifecycle workers contain hard local-demo guards (K_SERVICE/FUNCTION_NAME reject; demo project + emulator required). Therefore production activation requires explicit, separately reviewed runtime/worker integration and deployment planning, not merely setting config booleans. This is an intentional rollout boundary, not permission to weaken guards in this phase. Live gate/rules values were not queried; production rollout remains NO under current checkpoint.

## Checks performed
Existing tool/validate_family_app_links.py: PASS (manifest, exact path/host/package, DAL, certificate, Hosting). Backup XML/storage/source inspection. Two public GETs; adb inventory. One focused local lifecycle hypothesis reproduction only; no 9A/full historical suite, Flutter regressions, analyze or Android rebuild.

## Confirmed findings
### R1 — OPEN functional release blocker: historical CREATE permanently occupies owner lifecycle
Reproduction uses actual create callable handler, server worker, owner dissolution and read, followed by another create; then a second local owner creates a distinct valid invite for the former owner.
- After complete dissolution, getFamilyShareState is privateOnly.
- createFamilyShare reuses the original create_<sha256(uid)> and returns DONE; no new active Family exists.
- Another owner's invite preview returns VALID, but acceptFamilyInvite returns IN_PROGRESS.
- Root cause: family-create.ts reserve returns any non-ABORTED historical operation (including DONE); resume returns DONE. family-join.ts rejects any non-ABORTED CREATE record, without distinguishing historical dissolved ownership.
- This is a functionality/history-liveness failure, not a demonstrated cross-user access bypass. Old-member A->B rejoin safety remains intact, but former-owner reuse is broken.
- NOT FIXED in 9B: safe new CREATE identity/current-generation/history compatibility must be designed and tested together. Deleting audit history or weakening replay/structural checks is not an acceptable quick fix. Dedicated lifecycle correction is required before production. 9A's bounded cases remain valid but did not cover subsequent former-owner reuse; they do not establish full release readiness.

### R2 — FIXED locally: fresh owner-only Family with no invitation cannot finish dissolution
The initial targeted test exposed NON_OWNER_RELEASE_COMPLETE -> OPERATOR/dissolutionFinalizationIntegrity. A newly created Family has no familyInviteSlots document until an invitation is created; finalization called strict readInviteSlots(undefined). Existing fixture owner-only tests had precreated empty indexes, hiding this case.
- Minimal production edit in dissolution-finalization.ts: an absent slots document is interpreted as empty, matching FamilyInviteStore.slots. Existing malformed documents still use strict validation.
- Existing queries for actual pending/reserved invites remain mandatory; an unindexed actual invite still prevents finalization. No shopping, release, authorization or generation semantics changed.
- New real create -> no-invite -> owner-only dissolution chain now completes and creates the empty terminal slots index; owner becomes privateOnly.
- Seeded shopping revision was normalized during test development; the same failure remained until the actual missing-index fix. It was not a shopping-data repair.

## Exact blocker classification
### BLOCKER BEFORE FAMILY PRODUCTION ROLLOUT
1. R1: fix historical CREATE/new-owner-generation reuse and later JOIN eligibility with history/idempotency/one-Family safety intact; targeted lifecycle proof required.
2. Play-signed installed Android 12+ build verification: automatic domain state verified and canonical link -> existing flow. No device available; no debug certificate workaround.
3. Separately reviewed production activation plan and explicit GO: current local-only runtime guards cover JOIN, leave/remove, dissolution and deletion continuation; production workers, gates, IAM/App Check policy and matching client/server/rules versions must be prepared and validated together. Do not simply turn on create/invite booleans while required exit/deletion paths remain disabled. No live deployed configuration assertion is made here.

### BLOCKER BEFORE 1.0 PUBLIC RELEASE
4. Browser invite fallback 404: minimal safe static Hosting page, no rendered/logged token, no web auth/JOIN/backend call. Classified non-blocking only for a restricted installed-app Family rollout after blockers 1–3; mandatory before public 1.0/invite-link distribution to recipients without the app. Not implemented/deployed here.

### NON-BLOCKING FOLLOW-UP
Post-rollout aggregate monitoring of callable/worker failures and read volume; no token/URL diagnostics. No speculative schema/read optimization required by this review. Device/process handoff behavior can be observed during release validation; existing at-most-once ownership contract remains explicit.

## Final status and changed files
9B: FAIL because R1 remains reproducible. Security/authorization and read/retry review found no additional defect within reviewed scope; historical active rendering is safe, subsequent former-owner reuse is not. R2 is fixed locally only and must be included in any later reviewed deployment.
Changed: functions/src/households/dissolution-finalization.ts; functions/scripts/family-9b-review.cjs (new guarded test-only reproduction); this checkpoint. Flutter/native/rules/Hosting source unchanged. No production data mutation, production Family E2E, deployment, gate change, debug fingerprint, commit or push.

Validation: local App Links configuration validator PASS; two public GETs as above; no connected devices; focused emulator reproduction confirms R1a/R1b and passes corrected R2; three existing finalization regressions PASS. Functions build PASS after the production edit. No Flutter production edit, so no Flutter suite/analyze/Android rebuild. Final negative integrity test results recorded below.

Next: dedicated R1 lifecycle correction and targeted verification; then close Play device verification and browser fallback in their authorized phases, prepare production activation plan and obtain separate GO. STOP — no rollout started.

Final negative checks: 2/2 PASS — corrupted invite and unindexed actual invite both prevent partial finalization. Total existing affected backend regression: 5/5 PASS. The new focused script reports corrected no-invite dissolution PASS and deliberately reproduces the two remaining R1 failures; its successful exit is diagnostic completion, NOT product readiness PASS. Logs: C:/Users/gabor/AppData/Local/Temp/family9b-review.log, family9b-integrity.log, family9b-build.log.

FINAL GATES: Family core implemented; 8A PASS; 8B LOCAL + HOSTING PASS, Play device deferred; 8C PASS; 9A prior bounded PASS; 9B FAIL (R1); production Family rollout NO; commit NO; push NO. No security or cost guarantees beyond the reviewed code and specified evidence are implied.

## Post-9B0 delta review — 2026-10-30

**CONDITIONAL PASS — EXTERNAL / ROLLOUT BLOCKERS REMAIN. R1 CLOSED.** No actual Family functional/security blocker remains identified within the original review plus this bounded delta. This is not a new full security audit or production approval.

### Exact reproductions rerun

Used the existing `family-qa-bridge.cjs` with real local Auth sign-in/token verification, callable handler factories, Firestore transactions and existing worker/lifecycle engines. Project `demo-kuktam-local`, Auth `127.0.0.1:9098`, Firestore `127.0.0.1:8088`. Scheduler dispatch is the existing test substitution; this is not a deployed Functions HTTP or native Flutter E2E claim.

- **R1A PASS:** CREATE A → owner-only dissolution → authoritative non-active/private state → new CREATE B → `familyActive: true`, role owner. B operation and household differ from A; the current CREATE binding points to B.
- **R1B PASS:** fresh CREATE A → dissolution → private state → another owner's Family B/invite → preview VALID → accept ADD and existing transfer preparation/worker completion → `familyActive: true`, role member in B. Recipient Pro was removed before preview/JOIN. Current JOIN operation and membership invite binding belong to the new invitation.
- **Historical isolation PASS:** after each path, CREATE A remains DONE, dissolution A remains DONE and household A remains DISSOLVED. Their complete data and update timestamps remain unchanged. The authoritative read is private after dissolution and reflects only the new owner/member state afterward.
- **R2 owner-only dissolution PASS:** the real create path initially has no invite-slot document. Dissolution completes, owner reads private and finalization leaves an empty slot index. No invite is invented or required.
- **R2 negative integrity PASS, 2/2:** `5C4B integrity invite cannot partially finalize` and `5C4B integrity unindexedInvite cannot partially finalize`. Corrupt invite ownership and an actual unindexed invite still prevent finalization; protected state is unchanged and no finalization receipt is written.

No broad lifecycle permutations were rerun. Temporary test harnesses `C:/Users/gabor/AppData/Local/Temp/family9b-delta.cjs` and `family9b-delta-runner.cjs` adapt the original local reproduction to assert corrected outcomes, with a separate reset between A and B scenarios. They emit no credentials or invite URLs. The old `functions/scripts/family-9b-review.cjs` remains a historical defect-reproduction script; its old failure expectations must not be interpreted as current acceptance tests.

Executed `node C:/Users/gabor/AppData/Local/Temp/family9b-delta-runner.cjs`. It invokes the project-local Firebase CLI with `emulators:exec --only firestore,auth --project demo-kuktam-local --config C:/Users/gabor/kuktam/firebase.family-qa.emulators.json`, then the two exact journeys and the two selected integrity tests. Exit 0. Log: `C:/Users/gabor/AppData/Local/Temp/family9b-delta.log`.

### Security delta and reused evidence

Read inspection of current CREATE/JOIN admission confirms ACTIVE account generation, deletion barriers, current membership/owned-family exclusion, private routing/fences, current Pro grants for new owner CREATE, capacity and structural locks remain authoritative. JOIN admits a former owner only after the bounded terminal dissolution proof; it does not require member Pro. No new historical scan or client authority was introduced.

Reuse the 9B0 checkpoint and its 5/5 new + 20/20 affected regression evidence for concurrent/lost-ACK CREATE, stale CREATE/dissolution isolation, running dissolution rejection, malformed terminal evidence, newer account generation and deletion admission. No additional broad regression or Functions build was run: backend source is unchanged by this review and the 9B0 build evidence is sufficient. Flutter tests, Android build, full 9A/9B, H2 and performance tests were not run.

The empty `createFamilyShare({})` remains a current-state command, not a request-ID-bearing replay protocol. After B exists it resolves B; a delayed empty request after terminal A is indistinguishable from a new create intent and must pass normal admission. Old identified internal operations cannot mutate B. This explicitly documented 9B0 contract remains unchanged.

### Final blocker list (supersedes original list)

**Before Family production rollout:**

1. Play-signed Android device App Links verification — **DEFERRED / ROLLOUT BLOCKER**. Reuse existing local implementation, public DAL and Hosting PASS evidence; no new suitable-device evidence is available in this delta. Require automatic `verified` domain state and canonical link routing on a suitable Play-signed build. No debug fingerprint added and no live verification claimed.
2. Explicit production activation/deployment/runtime plan and separate GO — **OPEN / ROLLOUT BLOCKER**. Current local-only runtime/worker guards require coordinated review of production continuation, gates, IAM/App Check and matching client/server/rules versions. A config toggle alone is not the rollout plan. No plan implementation or activation is authorized by this review.

**Before 1.0 public release:**

3. Browser Family invite fallback — **OPEN RELEASE TODO / REQUIRED BEFORE 1.0**. The last authorized HTTP observation was 404; it was not fetched or fixed again here. A safe minimal fallback is required before public/no-app invite distribution: no token rendering/logging, web JOIN/login or Family backend calls. It remains non-blocking only for a restricted installed-app Family rollout after the two rollout blockers close.

**Non-blocking follow-up:** the original aggregate monitoring/read-volume follow-up remains; no new code blocker or speculative optimization is added.

### Final gates and changes

- Former-owner CREATE/JOIN, historical CREATE/dissolution isolation, owner-only dissolution: PASS.
- One-Family invariant, Pro CREATE rule, member JOIN without Pro, account-generation and deletion safety: PASS within inspected delta and reused targeted evidence.
- 9A PASS; 9B0 PASS; **9B delta CONDITIONAL PASS**.
- Actual identified Family code blockers: **none remaining**.
- Only repository change: this checkpoint document. Backend/Flutter/native/rules/Hosting source unchanged.
- No production data access, deployment, production rollout, commit or push.
- Next, under separate authorization: prepare the production rollout plan and close Play-signed device verification plus browser fallback release work. STOP; no next-phase implementation started.
