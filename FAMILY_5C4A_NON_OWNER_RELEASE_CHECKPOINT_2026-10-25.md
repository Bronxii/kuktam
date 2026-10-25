# Family Phase 5C4A — Non-owner participant release

Local implementation: 2026-10-25. Input: committed 5C3 checkpoint.
Routine Git baseline/status/log checks intentionally not run, per task policy.

## Boundary

Input `PRESERVATION_SOURCE_CLEANED / READY`; continuation `RELEASING_NON_OWNERS / READY`; successful output `NON_OWNER_RELEASE_COMPLETE / READY`.
Owner remains ACTIVE and routed to Family. Family household remains ACTIVE. The empty Family source and owner-private preservation target remain fenced with unchanged epochs. StructuralOperationId remains owned by dissolution. No invite/reservation finalization, shopping writes, owner release, Phase 6 or automatic 5C4B dispatch.

The explicit `releaseDissolutionMembers({householdId})` callable uses the existing authenticated selector adapter and server-derived dissolution identity. Its store is restricted to localhost Firestore emulator/project demo-kuktam-local and rejects deployed runtime markers. No production gates changed.

## Shared member-exit transition

5A/5B now call the extracted `commitMemberExit` write primitive. It performs exactly the existing membership/index deletion, user activeHouseholdId/private routing update and fresh private epoch write. Their admission checks and historical receipts remain unchanged.
5C4A invokes that same primitive only after validating the committed dissolution and exact immutable participant evidence. It does not borrow self-leave/owner-remove admission, which correctly rejects the dissolution's own structural lock. Each call releases at most one non-owner in one transaction; owner is excluded by the parsed immutable role/UID contract.

Active capacity is derived from `households/{family}/members` and ACTIVE reverse memberships. Removing both once releases one active slot; there is no independent decrement counter. The capacity document, pending reservation IDs and structural lock are not rewritten.

## Authoritative participants and progress

Only the immutable 5C1 participant array selects releases, in its deterministic ordering with owner filtered out. Bounded live membership queries validate exact remaining topology; they never discover additional release candidates.

Stable release ID: SHA256(JSON([dissolution-member-release-v1, operationId, participantSnapshotHash, participantUid])). Snapshot hash already binds membership/reverse updateTimes, fallback identity/creation time, role and original Family routing.

Progress lives in `familyOperations/{id}/participantRelease/state`: version 1, snapshotHash, cursor, receipt-chain hash.
Individual results live in `participantReleaseJournal/{releaseId}`: version, snapshotHash, releaseId, UID, source Family household, exact private fallback, resulting private epoch, completion timestamp, terminal PRIVATE result. Maximum seven member results; nothing unbounded is added to the operation root.

Each transaction reads and validates the complete bounded receipt prefix, owner, all unreleased participants, actual remaining topology, reserved JOIN authority, both fences, structural lock, source emptiness and terminal 5C2B/5C3 completion proofs. Pending membership updateTimes must still equal the immutable snapshot. Missing/wrong fallback, wrong routing/index/version, corrupted progress/results or locks parks OPERATOR without scheduling a participant exit.

The participant's two membership deletes, routing switch, new private epoch, durable result and cursor/root phase commit together. There is no temporary worker lease and no expiry takeover. Competing workers serialize on shared progress/topology reads. Abort rolls all writes back. Lost ACK reads the same committed result, without second epoch change or second capacity release.

## Completion and subsequent private lifecycle

Finalization freshly proves every non-owner has terminal evidence, no original Family membership remains for them, owner remains unchanged, Family source is empty and fences/structural lock remain valid. Owner-only input creates empty progress and directly completes without fake exits.
Completed reentry verifies durable progress and returns without writes.

A released member is private-only immediately. Normal private shopping may refresh its context or mutate its own list, so receipt epoch is historical transition evidence rather than a permanent restriction on future epoch changes. Existing account-deletion admission becomes available simply because membership is absent. An admitted private deletion (deletion document plus non-ACTIVE lifecycle marker) is permitted to continue while the remaining dissolution participants are processed; it must not stall owner forward completion. Owner deletion remains JOIN_COMMITTED_IN_PROGRESS. No account-deletion implementation changes are required.

Earlier shopping preparation recognizes later release phases without trying to restore ACTIVE membership topology. Earlier merge/cleanup execution rejects an out-of-phase invocation without replaying effects.

## Validation

Final acceptance: PASS. Final code targeted regression completed once: 53 PASS / 0 FAIL / 0 SKIP, exit 0, duration 362756 ms. Breakdown: 23 new 5C4A tests, 11 relevant 5A tests, 14 relevant 5B tests, 3 selected 5C3 boundary/guard tests, 2 callable/runtime tests. Earlier development-only focused run: 22 PASS. Full Functions build/typecheck after final backend change: PASS. Emulator shutdown completed. No routine Git/baseline/status/log/diff checks were run, as requested.
Required fixtures: owner only, owner + 1, owner + 3, maximum owner + 7 (8 total). Every member fallback contains an existing item; real 5C1/5C2A/5C2B/5C3 fixture execution establishes preserved owner shopping and empty/fenced Family source.
The final selection includes new 5C4A, shared 5A/5B exit regression, selected 5C3 boundary/guards and callable/runtime checks. Shopping routing and deletion admission are exercised by the same targeted suites. No historical scale/performance/Flutter/native/full backend matrix.

## Remaining work

5C4B NOT STARTED: owner release, pending invite/reservation finalization, safe fence and structural-lock release, dissolution DONE. No part of that later finalization is performed here.
Production access/deploy/commit/push: NO. Flutter/rules: unchanged.

## Files changed in 5C4A

- functions/src/households/dissolution-member-release.ts (new)
- functions/src/households/member-leave.ts (shared write primitive extraction)
- functions/src/households/dissolution-preservation.ts (later phases and receipt-authorized remaining topology validation)
- functions/src/households/dissolution-source-disposition.ts (export existing cleanup progress parser, no cleanup behavior change)
- functions/src/index.ts (explicit local continuation callable)
- functions/test/dissolution-member-release.test.ts (new)
- functions/test/runtime.test.ts (callable contract coverage)
- functions/scripts/emulator-tests.cjs (targeted selectors)
- FAMILY_JOIN_RESERVATION.md (additive progress entry)
- FAMILY_5C4A_NON_OWNER_RELEASE_CHECKPOINT_2026-10-25.md (new)

Reproduction: `npm --prefix functions run build`, then `node functions/scripts/emulator-tests.cjs --participant-release-regression` from the repository root.
Final log: `C:/Users/gabor/AppData/Local/Temp/family-5c4a-final.log`.

## Final gates

5C4A: PASS. Required implementation or validation deferred: NONE. Blockers: NONE.
All required 1/2/4/8-participant fixtures completed; respectively 0/1/3/7 non-owners released. Family active count ends at owner only; unrelated RESERVED capacity entries remain intact.
Old Family commands rejected with REJECTED_CONTEXT_CHANGED; fresh released-member commands applied to their private fallback, including while later participants were still being processed. Existing private items and preserved owner shopping remained unchanged by release.
Forced failure rolled back the entire participant transition. Reentry, competing workers, interruption and lost acknowledgement passed. Corrupt evidence parks OPERATOR without partial exit or compensation.
Source/target fences and structural lock retained. Owner remains ACTIVE/routed to Family. Family source remains empty. Account deletion admission restored for released private member; owner remains JOIN_COMMITTED_IN_PROGRESS guarded.
Prior 4B/5A/5B/5C1/5C2A/5C2B/5C3 acceptance is retained. 5C4B and Phase 6: NOT STARTED. No Flutter/rules changes, production access, deploy, commit or push.