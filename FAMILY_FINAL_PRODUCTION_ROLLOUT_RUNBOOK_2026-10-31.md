# Kuktám Family Share • Final production rollout runbook • 2026-10-31

**READY FOR STAGED PRODUCTION ROLLOUT.** Phase 9E implemented and locally verified two-role smoke admission. Each stage still requires independent human GO.

## How to operate

Run future PowerShell commands from C:\Users\gabor\kuktam. Project kuktam-67768, default Firestore database in eur3, Functions in europe-west1, codebase monetization. No default project or .firebaserc. Record operator, time, artifact/config hashes, exact targets, previous/live revisions, results and separate GO in the change record. Stop after each stage until its exit evidence is signed. Never paste secrets, invite credentials, full invite URLs, shopping payloads or personal identifiers into logs or tickets.

**Physical order:** T0 → T2 index prerequisite → T1 backend → T2 transitional rules → T3 client → T4 closeout → T5 final rules → T6 smoke → T7 normal admission. The T2 index step is pulled forward because deploying a schedule or trigger starts it immediately, even with admission OFF. GO numbers identify distinct permissions. Obtain GO-2 for indexes before executing GO-1 backend commands. GO-2 does not authorize GO-3 rules. No backend command should depend on an index that is still building.

Evidence base: FAMILY_9C_PRODUCTION_RUNTIME_READINESS_CHECKPOINT_2026-10-30.md, FAMILY_9D_RULES_INDEX_CLIENT_COMPAT_CHECKPOINT_2026-10-31.md, FAMILY_9D1_SHOPPING_PROTOCOL_TRANSITION_CHECKPOINT_2026-10-31.md, FAMILY_BROWSER_INVITE_FALLBACK_CHECKPOINT_2026-10-30.md and FAMILY_8B_ANDROID_APP_LINKS_CHECKPOINT_2026-10-29.md. 9A and 9B0 passed, 9B delta conditional, 9C passed, 9D compatibility issue closed by 9D1. Rules evidence 91/91 final and 27/27 transitional. No fresh live inspection in this planning phase.

## T0 • Identify the starting point

Historical Alpha 1.0.1 (2), 100% within closed Alpha, is unsupported. Internal testing 1.0.9 (10) is the latest pre-Family household-direct reference. Local AAB correspondence is sufficient for planning, Play-side hash not established. A later signed Family-capable artifact/version is unassigned. Version 10 is not a Family minimum. Public DAL and browser fallback previously live PASS. Android automatic domain verification still deferred. App Check enforcement remains OFF through T7. No Family production data is expected; this runbook did not enumerate users or verify absence of data.

| Rule state | User legacy shopping | Direct household shopping | Mutation requests | Client routing | Window |
|---|---|---|---|---|---|
| A: live at 9D, ruleset 1c10f3f0-d2ea-4524-8c5f-b02e5d72f291 | Own create/update before pointer, own reads/deletes including remnants | Permitted to migrated, active account with membership | Denied | Restricted change to activeHouseholdId allowed | Existing fleet only, unsafe for Family |
| B: firestore.shopping-transition.rules | Own editable create/update and own delete only before pointer; own reads remain | Only current standalone private owner, complete migration, no Family binding, no epoch/expiry/revision fields; historical item envelope | Current context, gate and epoch required | Denied | Temporary mixed private fleet, Family admission OFF |
| C: firestore.rules | Same as B | All direct create/update/delete denied, including never-epoched homes | Same as B | Denied | Final S1C, required before smoke/admission |

T0 exit: re-read active rules release and index inventory, compare to checkpoint, record all three Family fields OFF/missing and smokeAdmissionEnabled OFF/missing, shared shopping runtime state, deployed functions/revisions, trigger/job health, authorized change windows and baseline metrics. Unexpected active Family state, config drift, existing mutation users, or unknown identity/permission → HOLD and reconcile. Never disable shared shopping to force this baseline. No rollout on the assumption that a missing release record means an endpoint is absent.

## GO-2 • T2 index prerequisite

Local firebase.json maps firestore.indexes.json. One collection-scope familyInvites composite: householdId ASC, status ASC, expiresAt ASC. 9D live inventory had zero custom indexes/field overrides. The 9C owner-deletion phase IN + document-ID scan needs no additional composite. Re-list now, including overrides; compare to manifest. Any remote-only entry, deletion/reset warning or database mismatch → stop and reconcile locally. No --force. No index removal on rollback.

~~~powershell
node .\functions\node_modules\firebase-tools\lib\bin\firebase.js firestore:indexes --project kuktam-67768 --json
node .\functions\node_modules\firebase-tools\lib\bin\firebase.js deploy --only firestore:indexes --non-interactive --project kuktam-67768
~~~

In Firestore Console → kuktam-67768 → (default) → Indexes, record exact fields/scope and enabled/READY state, or use authenticated Firestore Admin indexes.list metadata. A successful CLI submission or listed manifest is insufficient. Poll status; BUILDING/CREATING → wait, ERROR/NEEDS_REPAIR or absent → HOLD. Unused READY index may stay.

## GO-1 • T1 backend

**Identity checklist: all NEED OPERATOR VERIFICATION; any unmet row blocks GO-1.** No IAM mutations are authorized here.
* KUKTAM_CORE_RUNTIME_SERVICE_ACCOUNT: verify actual principal, Admin Firestore operations, required Auth lookup, event delivery and first-gen Auth fallback compatibility.
* KUKTAM_PLAY_RUNTIME_SERVICE_ACCOUNT: verify existing Play billing/voided feed access, Firestore dispatcher access, recovery permissions including Auth deletion if that existing shared execution path reaches the final deletion boundary. Confirm approved privilege separation.
* KUKTAM_DELETION_RUNTIME_SERVICE_ACCOUNT: verify finalizer Firestore and Firebase Admin Auth deletion permission, correct principal/least privilege. Do not exercise real deletion for a rollout test.
* KUKTAM_BINDING_KEYS: verify expected secret version/access by the existing consumers and valid rotation configuration without reading its value into the runbook. Verify deploy identity can act as each configured principal, Scheduler invocation/Eventarc delivery and region quotas. App Check stays false.

Diff deployed revision/source and shared dependencies against the reviewed artifact. Below are exact target groups when all listed targets need installation/update. Omit individually proven byte-equivalent/current endpoints from an operator-reviewed group. Do not redeploy unrelated purchase verification, entitlement proof, RTDN or purchase preparation. Internal dissolution phase adapters are excluded. The installed CLI resolves unqualified function selectors against a different/default codebase; use the explicit monetization prefix. The local predeploy build must succeed. Stop on any unexpected target or deletion prompt.

**Shopping foundation**
~~~powershell
node .\functions\node_modules\firebase-tools\lib\bin\firebase.js deploy --only "functions:monetization:processShoppingMutation,functions:monetization:ensurePrivateHousehold,functions:monetization:ensureShoppingContext" --non-interactive --project kuktam-67768
~~~

**Required lifecycle workers**
~~~powershell
node .\functions\node_modules\firebase-tools\lib\bin\firebase.js deploy --only "functions:monetization:familyOwnerDeletionMaintenance,functions:monetization:familyMemberDeletionMaintenance,functions:monetization:familyOwnerProLossMaintenance,functions:monetization:familyOwnerEntitlementChanged" --non-interactive --project kuktam-67768
~~~

**Shared recovery and deletion**
~~~powershell
node .\functions\node_modules\firebase-tools\lib\bin\firebase.js deploy --only "functions:monetization:billingMaintenance,functions:monetization:beginAccountDeletion,functions:monetization:finalizeAccountDeletion,functions:monetization:authUserDeleted" --non-interactive --project kuktam-67768
~~~

**Family reads**
~~~powershell
node .\functions\node_modules\firebase-tools\lib\bin\firebase.js deploy --only "functions:monetization:getFamilyShareState,functions:monetization:previewFamilyInvite,functions:monetization:getFamilyJoinTransferState" --non-interactive --project kuktam-67768
~~~

**Creation, invites and JOIN**
~~~powershell
node .\functions\node_modules\firebase-tools\lib\bin\firebase.js deploy --only "functions:monetization:createFamilyShare,functions:monetization:createFamilyInvite,functions:monetization:revokeFamilyInvite,functions:monetization:acceptFamilyInvite,functions:monetization:prepareFamilyJoinTransfer,functions:monetization:confirmFamilyJoinDelete,functions:monetization:cancelFamilyJoin" --non-interactive --project kuktam-67768
~~~

**Exits and dissolution**
~~~powershell
node .\functions\node_modules\firebase-tools\lib\bin\firebase.js deploy --only "functions:monetization:leaveFamilyShare,functions:monetization:removeFamilyMember,functions:monetization:startFamilyDissolution" --non-interactive --project kuktam-67768
~~~

Keep growth OFF. Do not issue first epochs to public accounts while A still permits direct writes: establish shared shopping gate is not serving mutation clients, hold new client distribution, and arrange separately approved shoppingRuntime/config.enabled activation only under B. If existing usage prevents this, stop. ensurePrivateHousehold can migrate an account at usable auth startup independently of Family; deployment of a callable by itself is not a client release.

| Export/worker | Trigger, role and operational evidence |
|---|---|
| processShoppingMutation | Retried document-create users/{uid}/shoppingMutations/{mutationId}; validate trigger registration, identity, delivery and errors. Missing worker leaves receipts pending. End-to-end production proof waits for separately authorized private test under B. |
| billingMaintenance | Existing firebase-schedule-billingMaintenance-europe-west1 every 5 minutes. Shared billing, deletion, Family CREATE/JOIN and shopping recovery. Deploy current shared composition if older. It can process existing unrelated billing/deletion work immediately. Verify schedule, successful invocation, dispatcher lease/cursor movement and unchanged billing outcomes. |
| familyOwnerEntitlementChanged | Retried document write users/{uid}/entitlementGrants/{grantId}. Processes authoritative entitlement changes. Verify event trigger/identity; missing trigger delays loss detection. |
| familyOwnerProLossMaintenance | Scheduled every minute; entitlement expiry scan and existing dissolution progression, including manual start. Outage can strand dissolution. |
| familyMemberDeletionMaintenance | Scheduled every minute; member exit before private deletion. Outage delays handoff. |
| familyOwnerDeletionMaintenance | Scheduled every minute; owner dissolution, audit detachment and private deletion handoff. Outage delays handoff. |
| beginAccountDeletion / finalizeAccountDeletion / authUserDeleted | Existing shared deletion entry and finalizer, plus first-gen Auth onDelete fallback. Require Family-aware deployed composition/cleanup. Compare revisions before redeploy, check existing private deletion health and fallback binding. Never delete an account as validation. |

Verify all expected exports and revisions (future read-only command below), runtime principals, region, callable authentication posture, trigger subscriptions, scheduler targets and successful invocations across at least one scheduled interval per worker. Distinguish idle successful scans from immediate no-op/error using reviewed 9C artifact and worker/checkpoint telemetry where available. Check absence of new successful admission/Family writes via available audit/metrics, all three growth fields and smokeAdmissionEnabled still OFF and no unexpected shared shopping activity. Record evidence gaps, do not infer real processing from HTTP deployment success. Missing worker, retry storm, elevated errors, unexplained mutation or lack of observability → STOP before rules. Continuation workers must stay available.

~~~powershell
node .\functions\node_modules\firebase-tools\lib\bin\firebase.js functions:list --project kuktam-67768 --json
~~~

## GO-3 • T2 transitional rules only

Prerequisites: GO-2 READY, GO-1 healthy, A still matches baseline, admission OFF. Review the SHA-256 of B and C and the B/C diff against 9D1. Use a separate root-level CLI config; never switch the checked-in default config. The following is a future operator block; run only after GO-3.
~~~powershell
$ErrorActionPreference = 'Stop'
$cfg = Join-Path (Get-Location) 'firebase.family-transition.deploy-only.json'
if (Test-Path -LiteralPath $cfg) { throw 'Temporary config already exists' }
try {
  [IO.File]::WriteAllText($cfg, '{"firestore":{"rules":"firestore.shopping-transition.rules"}}')
  if ((Get-Content -LiteralPath $cfg -Raw | ConvertFrom-Json).firestore.rules -cne 'firestore.shopping-transition.rules') { throw 'Wrong rules source' }
  Get-FileHash firestore.shopping-transition.rules,firestore.rules
  node .\functions\node_modules\firebase-tools\lib\bin\firebase.js deploy --only firestore:rules --config firebase.family-transition.deploy-only.json --non-interactive --project kuktam-67768
  if ($LASTEXITCODE -ne 0) { throw 'Rules deployment failed' }
} finally { if (Test-Path -LiteralPath $cfg) { Remove-Item -LiteralPath $cfg } }
~~~
Read back default Firestore release/source via Rules API and compare deployed content to B (normalize line endings only). Use separately authorized existing private test identities/data: old internal build writes/edits a disposable row on an unmarked private home before any epoch issuance. Then exercise current command client with shared shopping gate enabled under approved config procedure, verify receipt/one canonical change and rejection of a queued direct edit after epoch issuance. Validate wrong-home/direct unsafe access denied using approved negative probe or existing emulator evidence plus exact live rules comparison; do not fabricate a Family to test this. Explicitly label emulator-only negatives. Test authorization is separate from permission to deploy rules. Delete disposable shopping rows via normal app operations. Failure, unexpected public access or divergent data → HOLD T3.

## GO-4 • T3 client publication

Release a later com.bronxii.kuktam build to **internal testing first**, using Play App Signing and tested epoch/household routing, immutable mutations and receipts, Family UI/callables, former-owner generation-compatible no-stale-identity create/join, strict App Links and signed-out continuation. Record actual versionName/code, signed artifact provenance and release availability. From Play-installed build on an approved private account verify add, edit, check, uncheck, delete and text import or recipe-to-shopping, authoritative list across restart and successful receipts. No Family start. Verify normal auth and no repeated submissions. Before broader release require internal checks, healthy worker/denial metrics and explicit publication decision. Old second devices can show rejected, empty or stale UI after migration; communicate the upgrade requirement.

**Play-signed device verification** (prefer T3, mandatory before ON). Android 12+, confirm API level, version, Play installer and installed app-signing certificate matches public DAL (AF:21:94:5C:B6:95:4A:D8:F1:8A:00:D4:85:78:FF:B0:AD:60:58:77:A5:9E:3A:D0:96:6E:91:6D:23:A2:E5:CD). Reconfirm HTTPS DAL 200 without redirect. Use a dedicated test device:
~~~text
adb shell getprop ro.build.version.sdk
adb shell pm list packages -i com.bronxii.kuktam
adb shell dumpsys package com.bronxii.kuktam
adb shell pm set-app-links --package com.bronxii.kuktam 0 all
adb shell pm verify-app-links --re-verify com.bronxii.kuktam
adb shell pm get-app-links com.bronxii.kuktam
adb shell pm get-app-links --user cur com.bronxii.kuktam
adb shell am start -W -a android.intent.action.VIEW -c android.intent.category.BROWSABLE -d "https://kuktam-67768.web.app/family/invite?token=routing-test"
~~~
Wait for verifier, reread. Require **kuktam-67768.web.app: verified** plus unforced implicit VIEW opening Kuktám and existing invite handling. User-selected/approved, explicit package launch or a debug signature is insufficient. Synthetic token only for diagnostic commands; actual T6 invite opened normally. No debug fingerprint addition.

## T4 • Close support window
Record successful T2/T3 results, usable Play update for intended population, healthy private shopping, acceptable rejection/support trend, upgrade communication and explicit operator acceptance that all remaining direct writers, including never-epoched private homes, can lose write capability. No arbitrary adoption threshold. Stay at B if these criteria fail.

## GO-5 • T5 final S1C

Confirm T4 sign-off, runtime healthy, READY index, default firebase.json points to firestore.rules and correct hash, then:
~~~powershell
node .\functions\node_modules\firebase-tools\lib\bin\firebase.js deploy --only firestore:rules --config firebase.json --non-interactive --project kuktam-67768
~~~
Read back C. With separately authorized private test data verify current household read and command receipt succeed; direct household write even before epoch, migrated legacy write/delete, queued stale direct write and wrong-household access are denied. Verify structural stores deny raw client access (use safe reads and local denial tests plus exact deployed source for unsafe negative write probes). Distinguish expected permission-denied from broken current clients. Do not start smoke on an unexplained failure.

## GO-6 • T6 controlled smoke — bounded by authenticated UID

Verify deployed 9E revisions of createFamilyShare, createFamilyInvite and acceptFamilyInvite. Under GO-6 only, apply the exact atomic familyRuntime/config update in FAMILY_9E_BOUNDED_SMOKE_ADMISSION_CHECKPOINT_2026-10-31.md: three global fields explicitly false, smokeAdmissionEnabled true, smokeAllowedUids a two-key map with owner=A and member=B (actual verified UIDs). Read back privately with an approved writer. Global true overrides smoke for that operation: stop immediately on any global true. Preview remains separate. No client payload grants smoke status.

After scoped GO-6 and T5 proofs, use two designated existing accounts, A eligible Pro owner, B private non-Pro member. Record starting private state and safe minimal lists. A creates Family and invite; B taps canonical link on Play-signed device, previews and explicitly chooses ADD. Verify B active member and one shared route; add one harmless shopping item, verify visibility and check/edit across devices. Remove test item normally if appropriate. B leaves, verify private list and A still owner. A dissolves, refresh authoritative progress until completion, verify both private and no stuck jobs. Close smoke scope atomically: keep all three globals false, set smokeAdmissionEnabled=false, remove smokeAllowedUids and verify readback. Retain historical audit; no manual Firestore deletes, real deletion, Pro-loss or stress tests. Any failure → close new scoped growth, preserve workers, investigate using redacted evidence.

## GO-7 • T7 normal admission and emergency procedure

Requires T1–T6 evidence, healthy monitoring, Play-signed verification PASS, smoke completed/cleaned, no stuck continuation and a separate signed public scope decision. Operator must establish audited server config write procedure and authorized principal before changing familyRuntime/config. Apply creationEnabled=true, inviteCreationEnabled=true, joinReservationEnabled=true as one reviewed update keeping smokeAdmissionEnabled=false, removing smokeAllowedUids and preserving unrelated fields. Verify readback and effective cohort/general policy. No approved live config writer is established here; no invented CLI write. Leave App Check OFF.

Emergency: record incident/time, use approved writer to set all three NEW admission fields and smokeAdmissionEnabled false together; remove smokeAllowedUids, verify effective OFF for general AND scoped admission, stop widening client release, check no new reservations. Leave shoppingRuntime and workers operational. Track admitted JOINs, exits, dissolution, mandatory Pro-loss, deletion handoff and historical cleanup to terminal or operator state. Preserve receipts and history. Record recovery owner and require fresh GO to reopen.

## Rollback and monitoring

| Stage | Safe response |
|---|---|
| T0 | Hold baseline. |
| T1 | Hold admission; code rollback only to an explicitly compatible revision preserving all admitted work. Otherwise forward-fix. Keep shared billing/deletion active. |
| T2 index | READY index can remain unused. |
| T2 rules | Before any cutover, previous rules only after proving no epoch/mutation users or pending commands. After any cutover never reopen broad direct writes; forward-fix. |
| T3 | Halt further publication. Existing installs cannot be recalled; preserve mutation backend/receipts. |
| T4 | Defer support closeout and keep B. |
| T5 | Keep growth OFF and forward-fix C. No reversion to permissive direct writes. |
| T6 | Close smoke growth; finish accepted operations, cleanup through product lifecycle. |
| T7 | Execute emergency OFF, then forward-fix with continuation intact. |

Baseline before GO-1; compare at each gate and during the agreed observation window. Track callable 4xx by expected denial vs unexpected, 5xx/retries, Firestore permission-denied and read/write volume, command receipt delay, scheduler delivery/failures and lease recovery, oldest due work/backlog by JOIN/dissolution/deletion stage and operator-required states. Redact identifiers; monitor aggregates, revisions and timestamps. Stop expansion on stuck leases/work beyond expected retry/lease deadlines, missing workers, unsafe grants, repeated failed commands or material unexplained divergence from baseline. Assign on-call and operator before every GO.

Billing cost follow-up is non-blocking on current evidence. Four inbox scans can each return 50 documents per five-minute invocation, up to 57,600 returned docs/day before other work. Comparable to observed 40k–70k daily reads; production attribution unproven. Correlate dispatch metrics with volume later and preserve all recovery paths. Escalate only if measured cost threatens operations.

## Operator sign-off

- [ ] T0 baseline, drift and identities verified; smoke blocker closed/reviewed.
- [ ] GO-2 index separately recorded, READY evidence attached.
- [ ] GO-1 exact backend groups approved, revisions and healthy triggers/jobs recorded.
- [ ] GO-3 B deployed and read back, controlled private old/new behavior verified.
- [ ] GO-4 signed internal client published, private CRUD/import verified, device proof recorded or tracked.
- [ ] T4 support closeout signed; GO-5 C deployed/read back and negative checks passed.
- [ ] GO-6 bounded accounts and outsider denial proven, smoke passed, normal cleanup complete.
- [ ] GO-7 separate general-admission authorization, config procedure/readback and incident owner recorded.

Stop. No deployment, config change, production access, commit or push in this planning phase.
