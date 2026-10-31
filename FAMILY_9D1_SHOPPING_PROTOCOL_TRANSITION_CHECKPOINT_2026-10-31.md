# Family 9D1 • Shopping protocol transition • 2026-10-31

**CONDITIONAL PASS — Play distribution evidence remains.** The compatibility bridge is implemented and tested locally. The Firebase default config still selects final S1C. No production action was performed. Do not approve rollout based solely on a local AAB.

## Artifact evidence

Local build/app/outputs/bundle/release/app-release.aab: manifest package com.bronxii.kuktam, versionName 1.0.9, versionCode 10. SHA-256 39a5993b245eb90d96c3652575ca37f704225ff8911ebc1c117ccb9e6acfe1e3. Its arm64 Dart binary contains ensurePrivateHousehold and shoppingItems, with no matching strings for ensureShoppingContext, shoppingMutations, previewFamilyInvite or startFamilyDissolution. Consistent with the household-direct generation. This does not identify the active downloadable Play artifact. No authenticated Play-track listing or signed release-to-source mapping was available. Production, open and closed track versions, percentages and rollout status are unknown. Operator must match active tracks/version codes to uploaded bundle provenance and check historical installations before selecting the transition. Do not use 10 as a minimum compatible build.

| Generation and source evidence | Read/write and routing | Family support |
|---|---|---|
| User legacy, c4225d2^ | Both on users/UID/shopping. Own list, no household provisioning. Repository awaits writes/batches. No guarantee every historical screen surfaces rejections. | none |
| Household direct, c4225d2 through parent of 8b6255c | ensurePrivateHousehold, active route, reads and writes households/HID/shoppingItems. Can migrate legacy data at usable auth startup. Batch create uses name, quantity, unit, isChecked, createdAt. Local-accept helper can complete on pending snapshot, with delayed onSyncFailure only while callback/session survives. | pre-Family |
| Mutation cutover 8b6255c; present 8C/9C source includes Family | Reads active household, submits immutable users/UID/shoppingMutations; context/epoch and expected revisions, processor and receipts. Recipe details/scaling and text import both enter addOrMergeItems, bulk or individual children. Dispatcher checks authoritative receipt on permission denial and handles context/authority failure. | mutation capability predates Family. Require tested full Family client for CREATE/JOIN UX |

Repository pubspec snapshots for these source boundaries give 1.0.0+1. Build flags can override them. Exact Play version/track for each remains unknown.

## Two distinct migration moments

Usable authenticated startup enters HouseholdGate, which resolves the household gateway. The cached gateway can reuse known routing; authoritative ensurePrivateHousehold provisions on the first unresolved account. HouseholdStore pages legacy source transactionally, checks target-ID collisions, copies and removes the same source IDs and sets activeHouseholdId on the first page. Version 1 means completion. Remaining source rows between pages are inputs, never an old-client fallback. A failed transaction commits neither copy nor removal, and retry selects remaining rows. No reverse migration.

Separately AuthGate starts productionShoppingCoordinator, which subscribes to auth, binds the household and obtains ensureShoppingContext on context refresh. With shoppingRuntime enabled the server initializes or renews shoppingEpoch and shoppingRevision on the household. The first such committed initialization permanently closes direct writes to that private household in the bridge. Expiry does not reopen them. Installation without an admitted/routed session alone does not migrate. Authenticated launch can cause both transitions without opening Shopping, requesting Family or making a first edit. No client migration timing change is needed under the tested account cutoff policy.

## Mixed installations using the bridge

| Current account | Old user-scoped install | Old household-direct install |
|---|---|---|
| No pointer | Own legacy reads/writes/deletes under existing lifecycle rules. | Its own first household ensure can initiate migration. |
| Migration started | Can read uncopied rows; all old-path changes including delete denied. After completion the old list is empty. | No direct writes during incomplete migration. |
| Standalone migrated private household, never issued epoch | Legacy path remains closed. | Current private owner may read and directly edit legacy-shaped items. No mutation is admitted until epoch exists. |
| First epoch issued, including after expiry or reinstall | Same closure. | May read current authorized shopping, all direct writes denied. Must use a compatible build to save. Offline submissions are checked against server state when replayed. |
| After Family JOIN | Legacy empty; cannot change either list. | Only current Family context can authorize canonical reads. Cached/hidden private-list reads are denied. Direct writes to either household and client pointer changes denied. |
| After leave/remove | No revival of the legacy route. | Server commitMemberExit switches routing and advances the private fallback epoch; current private reads work but direct writes remain closed. |

New install/reinstall resolves current server context; local cache or a restored old client confers no write authority. Old software can show cached data or an optimistic change which later rolls back, particularly after process restart. No claim that every old install shows an upgrade prompt. This is a usability cost for the affected device, including non-Family private users. The policy here accepts the requested data-integrity priority; communicate the update requirement before client cutover. No adoption percentage proves all secondary devices upgraded.

## Rules and ownership

Fixed legacy DELETE in both sources. Once a user's root contains activeHouseholdId, no client may delete even an uncopied legacy row. Pre-migration deletes retain original owner permissions. Server migration and deletion cleanup use Admin.

**Transition only:** firestore.shopping-transition.rules. Diff from the final rules is confined to the household shoppingItems direct-write clause. Direct write requires current validated standalone private owner/context, ACTIVE account, complete migration, no reverse Family membership, and absence of all three protocol fields shoppingEpoch, shoppingEpochExpiresAt and shoppingRevision. Create/update accept only the five historical field names and check the basic item types. Neither client can set or remove the household protocol marker. Canonical commands require current unexpired epoch. No pointer switch, Family direct write, or overlapping direct/command write window is authorized. The host's existing server epoch transaction supplies the boundary; a pending old write reaching the server after cutoff is rejected. Separate pre- and post-cutover rules tests model this server replay, not a physical offline-device E2E.

**Final:** firestore.rules. All direct household C/U/D denied, including on unmarked homes. No version gate, new backend adapter, Flutter change, dual write, or forced-update platform. A writable private-only bridge without an epoch check would still bypass revision/consent fences. A percentage rollout or hiding the Family menu cannot make that safe.

## Local validation and release gates

Local Firestore emulator demo-kuktam-local. Final shopping, household (including DISSOLVED) and general rules suites: 91/91. Transition shopping suite: 27/27. Tests include authenticated legacy source writes, forced two-page migration and denied delete of the uncopied second row, repeat ensure, intact source-to-target rows, old private CRUD before epoch, stale update/delete/replace after issuance/expiry, actual mutation with receipt, ADD/EDIT/check/uncheck/DELETE and bulk, Family direct-write attack cases. Both rule sources were loaded separately. No Functions or Flutter build required. Index manifest unchanged.

1. Identify the current downloadable artifacts, track/status and protocol. Confirm the five-field legacy write envelope against any additionally identified released binary. If a different writer exists, hold here. Provide clear upgrade guidance for affected old devices.
2. With Family admission OFF, separately authorize prerequisites: required indexes READY, compatible household/mutation processor and recovery deployed and operational. Do not expose a mutation client to the existing command-denying live rules. Prevent early context issuance to public clients until the bridge is available.
3. Separately deploy the reviewed TRANSITION source using an explicit stage-specific rules mapping, verifying the exact source diff and resulting ruleset. The default firebase.json still points at S1C and must not be used for this transitional stage. Verify untouched unmarked private clients, migration barrier, new command processing and stale-write denial in an authorized smoke. Set shared shopping runtime ready before releasing the mutation client. Keep Family growth OFF.
4. Release verified compatible shopping/Family build. At authenticated launch a migrating account may render older software read-only/empty as documented. No client writes in both protocols. Monitor denied-write/support and mutation receipt outcomes. No server-trusted app-version signal exists; epoch/context and final rules supply security. Operational minimum = signed tested artifact with routing, mutation/epoch, current Family contracts and recovery. Numeric version requires Play evidence.
5. After support for remaining never-upgraded direct writers is explicitly retired (or proven no longer needed), separately deploy final S1C. Verify final denial even for an unmarked private home. This global cutoff can interrupt still-unmigrated household-direct installations, independently of Family; it requires a deliberate release decision. Do not restore permissive rules after Family activity.
6. Before Family smoke require final rules, READY indexes, functioning processor/lifecycle maintenance, compatible signed client, limited smoke plan and separate authorization. Before Family ON also close Play-signed link verification, smoke results, monitoring and separate activation GO.

Known 9D billingMaintenance read-cost investigation stays separate. No production data access/mutation, rules/index/Functions/Hosting deployment, Play rollout, gate change, commit or push.
