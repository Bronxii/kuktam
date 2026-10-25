# Family Phase 5C4B — Dissolution finalization

Date: 2026-10-25. Input: committed Phase 5C4A checkpoint. Routine Git baseline/status/log checks intentionally not run per task instructions.

## Atomic final boundary

Input NON_OWNER_RELEASE_COMPLETE / READY. Successful output DONE / DONE, lastOutcome dissolutionDone; updatedAt is the completion timestamp. A bounded finalization/state receipt retains identity, participant snapshot hash, exact owner/private household, final source/target epochs, timestamp, revoked invite IDs, aborted JOIN IDs and deterministic checksum.

The explicit local-only callable is finalizeFamilyDissolution({householdId}). Authenticated owner UID derives the dissolution operation; caller-selected UID/role/target routing is never accepted. Store rejects deployed runtime markers and any non-local/non-demo Firestore target. No runtime gate/deploy/automatic next phase.

One transaction validates the existing 5C4A participant-release proof (factored into a read-only reusable method), exact remaining owner topology and routing, source/target identities and fences, structural lock, terminal preservation/cleanup proofs, empty source, pending inventory and account structural validity. It does not revalidate Pro or original invite expiry as a cancellation condition.

All reads precede writes. It then:
1. Aborts each still-precommit reserved JOIN using the existing JOIN abort semantics. Reserved membership is removed, invite REVOKED with operationId null, operation ABORTED with lease/nextAt cleared and lastOutcome familyDissolved. If its private source was fenced before commitment, that owned fence is released with a fresh epoch. Snapshot/audit/items remain intact. Shared inventory writes are consolidated once in this final transaction.
2. Revokes remaining PENDING invites in bounded inventory; preserves USED/REVOKED historical records.
3. Reuses commitMemberExit for the owner under committed dissolution authority: removes Family member and reverse index, routes owner to exact private fallback, advances private epoch. Clears target operationId in the same commit.
4. Marks Family household DISSOLVED, clears source operationId, advances Family epoch. Shopping items are never written.
5. Clears invite slots, creates immutable finalization receipt, marks dissolution DONE/DONE.
6. Writes consistent empty schema-v2 capacity with structuralOperationId null as the last scheduled structural write. All writes become visible atomically; there is no earlier externally observable lock release.

There was no existing household terminal state writer/parser enum. DISSOLVED is the minimal terminal marker on the existing schema-v2 Family root; all normal consumers already require ACTIVE and valid membership. Household/audit identity is retained, not physically deleted.

## Invite and reservation completeness

The slot inventory is bounded to eight invites and capacity to seven pending JOINs. Finalization cross-checks all RESERVED invites and every unexpired PENDING invite through bounded queries; a usable/reserved invite missing from inventory, foreign ownership, inconsistent operation, missing claims or any committed JOIN contradiction is OPERATOR.

Older expired PENDING records can exist outside slots because existing invite creation prunes expired IDs without deleting history. They remain expired under the existing immutable seven-day expiry contract and additionally cannot target DISSOLVED Family. They need no unbounded scan or audit deletion. USED history stays unchanged. Every still-usable PENDING and every RESERVED invite is made REVOKED. No pending reservation can activate afterward.

The original member set remains snapshot-authoritative. Unexpected ACTIVE member/index causes OPERATOR, never silent deletion. Pending reservations are separately validated, never interpreted as participants. Normal pending invite/account/Pro lifecycle events cannot bypass the held structural lock.

## Retry, corruption and epochs

Owner private quantities and all pre-existing preserved items remain unchanged. Family source remains empty. Source/target epochs advance only in the final commit, invalidating stale contexts; owner routing and private writability change together. Family source becomes unfenced but remains unusable because DISSOLVED and membership absence independently deny normal routing.

Lost ACK and competing finalizers read the same terminal receipt. DONE reentry validates immutable operation/receipt identity and returns without reading or changing later private shopping/routing, epochs, invite/reservation history or capacity. Corrupt proof parks OPERATOR; there is no shopping compensation, reconstruction or partial finalize. Infrastructure/forced transaction failure rolls the entire attempted boundary back.

## Account deletion: intentionally guarded until Phase 6

Inspection found cleanupPrivateHousehold queries roots by ownerUid and explicitly refuses Family roots. Retaining a DISSOLVED Family audit root means merely removing owner membership would permit admission into a deletion job that cannot safely complete.

A narrow admission-only guard therefore preserves FAMILY_LIFECYCLE_NOT_READY when the account owns a DISSOLVED Family root. Before finalization existing JOIN_COMMITTED_IN_PROGRESS remains. No deletion job is started after DONE for that former owner. Released non-owner private deletion remains available. This is the explicitly allowed safe guard, not Phase 6 lifecycle implementation.

Phase 6 must define deletion/retention of historical Family-owned roots before relaxing this guard. Pro loss after commitment does not block finalization; broader Pro-loss lifecycle remains unimplemented.

## Validation

Final acceptance: PASS. Final backend build/typecheck: PASS. Final selected regression ran once after the last backend change: 41 PASS / 0 FAIL / 0 SKIP, exit 0, 322224 ms. Breakdown: 25 new 5C4B, 5 relevant 5C4A, 7 JOIN invite/reservation/fence/structural cases, 2 private deletion-admission cases (5A/5B), 2 callable/runtime checks. Emulator shutdown completed. Required new cases include original participant counts 1/2/4/8, pending unfenced/fenced JOIN abort, historical/expired invite preservation, stale Family/private rejection and fresh private ADD, lost ACK, competing workers, rollback, integrity and safe deletion guard.
Final regression selection includes directly affected 5C4A, JOIN precommit cancellation/revoke/expiry and postcommit guards, 5A/5B private deletion admission, and callable/runtime tests. No transfer-scale/performance/Flutter/native/full historical regression.

## Remaining boundary

No Phase 6 or UI implementation. Phase 6 lifecycle integration and eventual UI/client rollout are separate tasks; production remains untouched. No commit/push/deploy.

## Files changed

- functions/src/households/dissolution-finalization.ts (new)
- functions/src/households/dissolution-member-release.ts (reuse existing read-only completion validation)
- functions/src/households/dissolution-preservation.ts (terminal operation phase/status parsing)
- functions/src/households/join-transfer.ts (dissolution-owned precommit abort preparation; existing abort write semantics reused)
- functions/src/households/join-capacity.ts (safe former-owner deletion admission guard)
- functions/src/index.ts (local-only explicit callable)
- functions/test/dissolution-finalization.test.ts (new)
- functions/test/runtime.test.ts (callable metadata/authority coverage)
- functions/scripts/emulator-tests.cjs (targeted selectors)
- FAMILY_JOIN_RESERVATION.md (additive progress entry)
- FAMILY_5C4B_DISSOLUTION_FINALIZATION_CHECKPOINT_2026-10-25.md (new)

Reproduce after `npm --prefix functions run build`: `node functions/scripts/emulator-tests.cjs --dissolution-finalization-regression`.
Final local log: `C:/Users/gabor/AppData/Local/Temp/family-5c4b-final.log`.
Development-run note: five assertions originally expected the existing aborted JOIN worker resume return to be ABORTED. Its established response is notDueOrBusy when no lease is claimable; the durable operation remains ABORTED. Tests were corrected to assert both established response and unchanged durable ABORTED state; no worker response contract was changed.

## Final gates and handoff

5C4B PASS. Phase 5C COMPLETE locally. Phase 5 COMPLETE locally. Required 5C4B implementation/tests deferred: NONE. Blockers: NONE.
Owner-only, 2-, 4- and maximum 8-original-participant cases pass. Pending unfenced/fenced and multiple reservations abort safely. Final active Family membership count is zero, source item count zero, preserved owner shopping unchanged.
Both operationId fences are cleared with fresh epochs. Family remains as DISSOLVED audit root. Capacity is schemaVersion 2 / operationIds [] / structuralOperationId null. Operation is DONE/DONE with durable terminal receipt. Used history remains unchanged; usable pending invites are REVOKED and reserved JOINs ABORTED. Historical already-expired PENDING outside inventory remains expired/unusable without mass audit mutation.
Lost ACK, competing workers, forced transaction rollback, reentry and all integrity cases pass. No partial finalization. Normal owner shopping targets private; old Family/private commands reject.
Known deliberate Phase 6 restriction: former-owner account deletion remains FAMILY_LIFECYCLE_NOT_READY until historical DISSOLVED Family-root retention/cleanup policy is implemented. This is the task-authorized safe admission alternative, not an unfinished 5C4B acceptance test. Released non-owner private deletion remains available.
Phase 6 and UI work NOT STARTED. No client/rules changes, production access, deploy, commit or push. Routine Git/baseline/status/log checks were not run per request.