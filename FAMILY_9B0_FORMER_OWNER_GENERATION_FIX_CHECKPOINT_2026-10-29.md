# Family 9B0 — former-owner lifecycle generations

Implementation and local validation: 2026-10-30. Requested checkpoint filename retained.

## Original defect

CREATE always used `create_<sha256(uid)>`. Reservation returned an existing non-ABORTED operation, including historical DONE after its household had dissolved. Consequently a new create command returned historical success without activating a Family. JOIN checked that same UID slot and rejected any non-ABORTED CREATE as IN_PROGRESS, even when its complete lifecycle was historical.

## Authoritative generation model

- First CREATE keeps `create_<sha256(uid)>` for compatibility.
- New CREATE records use schemaVersion 2 and store `accountGeneration` from the ACTIVE account lifecycle marker.
- After a terminal prior generation, a new server-generated household ID is allocated. Its CREATE identity is `create_<sha256(JSON.stringify([uid, accountGeneration, householdId]))>`.
- `users/{uid}.familyCreateBinding = {operationId, accountGeneration}` is written atomically with the new operation, owner reservation and private source fence. This bounded pointer serializes simultaneous requests; it is not client-controlled (existing rules deny user-root create/update).
- Missing pointer falls back to the legacy UID slot. Legacy schemaVersion 1 is retained and conservatively belongs to account generation 1. No migration or history deletion is required.
- ABORTED operations are also retained; a later eligible explicit request allocates a distinct operation instead of overwriting them.

The current pointer is an owner-CREATE pointer, not a membership binding. After a former owner joins elsewhere, `familyJoinBinding` and the existing current membership invite binding remain authoritative for leave/remove.

## Retry and terminal proof

Retries while the same valid CREATE is reserved/active return its current ID. Concurrent reservations conflict on the same user/membership documents and converge on one generation. Existing structural locks, dissolution operations, Pro-loss intents and deletion handoffs block admission where applicable.

Rollover of a DONE CREATE requires its FINALIZE state, a matching DISSOLVED household with no operation fence, matching deterministic dissolution DONE operation, valid finalization receipt, empty capacity reservations/structural lock and invite slots, and no household/reverse memberships. The proof uses five document reads and two limit(1) membership queries, not a historical operation scan. New admission also checks a bounded live-owned-household query, normal private routing/fences, ACTIVE account generation, deletion records, server gate and current authoritative Pro grants.

JOIN uses the same current CREATE pointer and terminal proof to distinguish history from genuinely running ownership. It then follows the unchanged normal JOIN admission/transfer path. Former members do not need Pro; owner CREATE still does.

## Stale requests and account safety

`createFamilyShare({})` has no client request ID. It is a current-state command: after B is reserved/active, a delayed empty call returns B, never historical A. An empty call after A is fully terminal cannot be distinguished from a genuinely new user command; it may initiate the next generation under all normal guards. No stronger request-ID guarantee is claimed.

Explicit old operation IDs are rejected by the unchanged empty-request callable contract. Internal resume of DONE A returns historical DONE without changing routing or B. Old dissolution retries remain bound to A. New READY workers validate their identity, current pointer and account generation before progressing. An operation from an earlier ACTIVE account generation cannot activate for a recreated generation. Existing DELETING post-activation forward-cleanup behavior remains intact.

Historical audit validation recognizes both legacy and generated CREATE identities. This is a compatibility update to audit parsing, not a change to account deletion sequencing. CREATE A, dissolution A and household A remain immutable during subsequent lifecycle generations; audit detachment still follows the existing Phase 6 contract.

## Targeted proof

New `former-owner-generation.test.ts` exercises real Firestore-emulator stores and the existing lifecycle drivers:

1. Legacy A → dissolution → concurrent/lost-ACK B → stale A retries → Pro-loss dissolution B → Pro restored → C; preserved history and existing audit traversal of all three generations.
2. A → dissolution → preview VALID → JOIN ADD without member Pro → current invite binding → leave → CREATE C.
3. Same cross-path with JOIN DELETE and the existing explicit consent contract.
4. Running dissolution, missing terminal receipt, nonterminal household, structural lock, mismatched account generation, broken current pointer and deletion barriers reject CREATE/JOIN.
5. Stale READY CREATE cannot activate against a newer ACTIVE account generation.

These are local engine/transaction tests; they are not production or Flutter end-to-end tests. Private account deletion test fixtures include its atomically associated DELETING account marker, matching existing admission behavior.

Validation: PASS — 5/5 new tests plus 20/20 affected existing regressions; Functions TypeScript build PASS.

Commands from `functions/`:

```text
npm run build
node scripts/emulator-tests.cjs --former-owner
npm run build
node scripts/emulator-tests.cjs --former-owner-dev
```

The bounded final package ran 25 cases: all 20 existing regressions passed and 4 new cases passed; one new deletion-guard test used an impossible private-deletion fixture (job present but account still ACTIVE). Existing admission writes that job and DELETING marker atomically. Only the fixture was corrected. The five new tests were then rerun: 5 PASS, 0 FAIL. No backend source changes followed the bounded package; unaffected existing regressions were not rerun. These results are combined coverage, not a claim of one all-green 25-case run.

Existing selected regressions cover default-off/create admission (free, expired, revoked, DELETING, DELETED, malformed lifecycle, migration/private/member state), canonical entitlement aggregation, competing CREATE requests/workers, aborted CREATE recovery, worker failure, deletion after activation, one-participant dissolution finalization, real rejoin A→B→C, Pro-loss lifecycle and full local owner-deletion handoff. Real ADD and DELETE former-owner eligibility and account-generation mismatch are covered in the new file. No real Auth deletion was performed.

Logs: `C:/Users/gabor/AppData/Local/Temp/family9b0-final.log` (bounded package) and `C:/Users/gabor/AppData/Local/Temp/family9b0-confirm.log` (corrected five-case proof). Development runs also exposed and fixed the CREATE retry path returning a current owner operation while dissolution was PREPARED; reservation now checks the current structural/dissolution/intent evidence before returning an active retry.

## Files changed in 9B0

- `functions/src/households/family-create.ts`
- `functions/src/households/family-join.ts`
- `functions/src/households/historical-family-audit.ts`
- `functions/test/former-owner-generation.test.ts`
- `functions/test/family-create.test.ts`
- `functions/scripts/emulator-tests.cjs`
- This checkpoint.

## Boundaries and handoff

No Flutter/native changes, rules changes, shopping/ADD/DELETE/preservation changes, production access, deployment, commit or push. Existing first-generation IDs and client response shape remain compatible. No Flutter suite or Android build is required or run.

9B0: PASS. No unresolved blocker remains within this fix. 9A remains PASS. 9B review remains FAIL at its prior checkpoint until a separately requested small delta review considers this fix and the final release blocker list. 9B0 does not authorize production rollout or automatically start that review. Play-signed device verification and browser fallback remain outside this fix.
