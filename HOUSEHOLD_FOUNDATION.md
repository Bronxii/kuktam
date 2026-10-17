# Household foundation (local implementation)

No production rollout or migration has been performed.

## Schema and authority

- `users/{uid}.activeHouseholdId: string`: selected household, not ownership. Backend creates the root with merge, including when previously absent. Client may change ONLY this field, only after migration, only to a household containing their membership. No switching UI yet.
- `users/{uid}.shoppingMigrationVersion: 0 | 1`: server-owned migration barrier. 0 means pending, 1 means verified empty legacy source. It cannot be reset by a client. An ACTIVE client cannot delete a migrated user root to reopen legacy writes.
- `households/{id}.schemaVersion: 1`: household schema version.
- `households/{id}.ownerUid: string`: authoritative owner and deletion discovery key independent of the user root's existence.
- `households/{id}.createdAt: Timestamp`: creation audit time; not changed on replay.
- `households/{id}/members/{uid}.role: owner | member`: server-owned membership/role. Initial provisioning creates only the authenticated owner's member record. Client cannot create/update/delete memberships or households.
- `households/{id}/shoppingItems/{itemId}`: existing shopping payload (`name`, `quantity`, `unit`, `isChecked`, `createdAt`). Migration preserves ALL legacy fields and item IDs, not just this known subset. New client writes keep existing shopping semantics.
- `accountLifecycle/{uid}`: existing schema, initialized ACTIVE only if absent. Existing DELETING/DELETED markers are never reactivated.
- Recipes and billing/grants remain at existing private paths. No invite, household-name, platform or Play fields added.

Initial private ID = `private_` + SHA-256 of authenticated UID. This is a stable collision-resistant allocation key, NOT an authorization credential or anonymization promise. Concurrent startup transactions select the same document. Existing valid active households are reused. UID and household ID are never accepted in the callable request.

## Entry and migration

`ensurePrivateHousehold` is a GEN2 callable in europe-west1 under CORE. Empty `{}` request, Firebase Auth required, App Check enforcement false, no billing secret/Play dependency. Returns `{schemaVersion:1, ready:true, householdId}` or `{schemaVersion:1, ready:false}` for bounded continuation. Errors are sanitized.

AuthGate wraps the normal application in HouseholdGate for every verified authenticated session, including email/password and Google. Recipes are not prerequisites. The repository also resolves through the same gateway for every read/write, avoiding a global cached household shared across users. Gateway detects account switch (including A→B→A during a call), and the gate is keyed by authenticated UID. Failed provisioning offers retry and does not silently fall back to legacy writes. First provisioning/migration requires connectivity. Subsequent startup uses a UID-scoped, previously server-verified local context without waiting for a network response; see Offline startup below.

Each server transaction:
1. Reads the lifecycle, root, active household and membership; rejects invalid/deleting/deleted state.
2. Reads at most 50 legacy `users/{uid}/shopping` documents and all destination IDs before writes.
3. Creates missing lifecycle/private household/member/root metadata atomically.
4. Creates destination documents and deletes matching legacy documents in the SAME transaction. Collisions fail closed; no overwrite or source deletion.
5. Marks migration version 1 only after a transaction observes no remaining legacy items.

Up to 10 pages per callable, 20 invocations per gateway attempt. Very large lists can require the visible retry; completed pages remain durable. Transaction failures cannot leave an item deleted without its destination. The first-page approach avoids cursor skips. No migration query can select another UID. No external bulk migration command exists.

Legacy clients can read/delete their own legacy items; create/update is allowed only until their root has an activeHouseholdId. Household writes require membership, ACTIVE lifecycle and completed migration. Therefore old and new writers cannot diverge after migration starts. An old build used after migration will no longer be able to edit its legacy list: this is the accepted ONE-WAY migration policy. Migration starts only when the household-capable client invokes provisioning; old clients need not retain shopping write compatibility afterward. Do not roll rules back to reopen legacy writes after migration.

All normal shopping actions (manual CRUD, checks, text import, recipe and scaled-recipe transfer) share ShoppingRepository. No second Android-specific writer was found. Existing UI remains 'Bevásárlólista'.

## Deletion

LifecycleStore checks owned households on every nonterminal deletion step BEFORE user root cleanup and before DONE. It deletes a bounded shopping page; only once items are empty does it delete sole membership and household. Owner discovery does not depend on users/{uid} surviving client cleanup. Existing Auth, grant, ledger and recovery stages are unchanged. Content verification includes owned households. Emulator tests cover absent roots, client disappearance and external Auth deletion.

This release provisions ONLY private single-member homes. If an owned home has another member, cleanup fails closed and does not delete shared items or reach DONE. Before invite/join release, extend this isolated cleanup helper to enumerate every membership, remove a departing member, transfer ownership deterministically when required, and preserve nonempty shared homes. Also extend completion verification to non-owner memberships. This is REQUIRED before actual shared membership creation; it is not implemented here. Existing role/path contracts need no rewrite.

## Proposed rollout (NOT executed)

1. Review local diff and test evidence. ONE-WAY migration is accepted; old-client shopping writes need not work after migration. Verify the offline startup behavior below in the controlled Internal smoke.
2. Roll out household-aware deletion workers before provisioning: finalizeAccountDeletion, billingMaintenance, authUserDeleted. Use scoped project-local CLI targets; authUserDeleted requires --force for its existing intentional failure policy. Check revisions, identities, trigger, Scheduler and empty/unexpected deletion work read-only.
3. Deploy reviewed Firestore rules only. Existing non-migrated users retain legacy compatibility. Verify member/non-member and migration barrier behavior in a controlled test plan.
4. Deploy ONLY ensurePrivateHousehold. No client call/migration until the controlled new build is intentionally opened. Check CORE identity and no secret attachment.
5. Build/release an Internal client (separate authorization), using one disposable account with seeded legacy shopping, then verify zero/one/multi-item migration, restart, imports, session switch, private deletion. Do not reuse production deletion accounts without explicit permission.
6. Broader release only after client-update compatibility plan and regressions. Rollback after migration must retain household-aware rules and cleanup workers; an old-only client is not a safe rollback.

Possible scoped commands, for later review only, from repository root:

```powershell
node .\functions\node_modules\firebase-tools\lib\bin\firebase.js deploy --only "functions:monetization:finalizeAccountDeletion,functions:monetization:billingMaintenance,functions:monetization:authUserDeleted" --project kuktam-67768 --force
node .\functions\node_modules\firebase-tools\lib\bin\firebase.js deploy --only firestore:rules --project kuktam-67768
node .\functions\node_modules\firebase-tools\lib\bin\firebase.js deploy --only "functions:monetization:ensurePrivateHousehold" --project kuktam-67768
```

## Next Family Share phase

Neutral HTTPS invite link with high-entropy opaque token; store only token hash plus household/expiry/use constraints. Authenticated server-side accept transaction validates invite, ACTIVE lifecycle and member limit, creates member role, and changes activeHouseholdId atomically. Finish the joining user's private migration first; do not silently merge two household shopping lists. Recipes remain private. No recipe existence check. Authorize invite/member management by server-owned role. Define leave/owner-transfer/deletion policy before enabling joins. Listeners must rebind when activeHouseholdId changes; no switch UI is shipped in this foundation.

Android App Links and later iOS Universal Links deliver the same neutral token to the Dart gateway. Neither domain schema nor backend assumes Android. Invitation UI, token issuer/consumer, member management and live shared cleanup remain next-phase work.

## Validation

Completed local validation:
- Full Flutter suite after offline hardening: 1373 PASS, 0 FAIL, 1 intentional SKIP (17 tests added by the hardening).
- Targeted household/shopping/auth hardening run: 213 PASS; this overlaps the full suite.
- Backend unit foundation baseline: 209 PASS, 0 FAIL; not rerun for this client-only hardening.
- Full backend/Firestore emulator suite rerun after hardening: 409 PASS, 0 FAIL, including 28 household/rules tests and all existing deletion/billing suites.
- Flutter analyzer: no issues.
- TypeScript build: PASS.
- git diff --check: PASS.

Tests use demo-kuktam-local emulator and SDK doubles only. No production migration or purchase/deletion operation is executed. Existing Image Import changes were not edited.

## Offline startup hardening

The existing flutter_secure_storage dependency stores one versioned JSON record per Firebase UID, using `household_v1_<base64url(uid)>` keys. Fields: `version:1`, exact `uid`, `householdId`. Only a successful authoritative `ensurePrivateHousehold` completion writes the record. Invalid shape/version/UID/path, missing storage, or cleared state requires network provisioning. There is no client-side household/member creation and no legacy path fallback. No token or personal profile is stored in this context.

`CachedHouseholdGateway` is platform-neutral Dart with injected persistence, session, authoritative gateway and server-change streams. The production adapter supplies Firebase Auth, secure storage and server-only Firestore root metadata. Both HouseholdGate and ShoppingRepository resolve through the same per-Auth context. A cached ready result opens the app without waiting for the background callable, even when that call hangs. A transient unavailable/deadline/network error retains the record. An authoritative non-transient rejection clears and blocks it, notifies observers, and cancels old shopping delivery. The cache is only a routing hint: rules remain the authority for every online or queued write. It never reactivates a deleted lifecycle.

Session listeners fence in-flight A→B and A→B→A responses. Sign-out closes the old observable session; another UID cannot read its context. Verified records may remain encrypted per UID so returning to A can use only A's record. No global unscoped household ID is used. Persistence failure permits the successful online result but does not promise offline readiness on the next startup.

Every server-confirmed root snapshot (including reconnect with the same ID) requests authoritative revalidation. Cached and locally pending snapshots are not confirmations. A hinted new activeHouseholdId is never accepted directly: the callable verifies it before replacing persistence and emitting it. Shopping listeners cancel old delivery and fence late events before rebinding. The repository uses normal Firestore cache reads and write queues on that resolved path; it does not add a second local shopping database.

First-use offline UI explicitly requests connectivity and offers retry. No sleep, periodic retry loop, connectivity plugin or release debug bypass was added. Full shared invite/member management remains next phase.

Controlled rollout smoke must cover: online first provisioning; force-close and airplane-mode restart; cached list read and a queued edit; reconnect and rule-authorized sync; A/sign-out/B/A isolation; known backend-denied lifecycle invalidation. The local SDK-double test verifies offline routing/commit submission, not physical radio-off behavior or native Firestore queue durability. No production migration was run by these tests.
