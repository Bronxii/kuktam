# Family 4B1A - pre-commit JOIN foundation

Execution date: 2026-10-23 (filename retained as requested).
Baseline: `af7773a98a006fd2a42dd6e27af594b651428f08`, committed 4B0 contract.
Initial worktree clean. No reset/staging/commit/push, production access or deploy.

## Boundary and entry

Phase4A reserve/accept stays compatible and reaches READY_FOR_TRANSFER. The new
actor-authenticated `prepareFamilyJoinTransfer({operationId,inviteId})` explicitly
upgrades an eligible v1 operation to v2, fences the source, and leaves bounded
continuation to the existing leased Family maintenance path. The same preparation
request can be repeated without changing an existing generation. New preparation
requires the existing joinReservationEnabled gate; new API methods also enforce
the existing demo-project/loopback/no-deployed-runtime barrier. No gate is changed.
Continuation does not depend on an enabled admission gate or logged-in client.

ADD: READY_FOR_TRANSFER -> SNAPSHOT_SOURCE ->
SOURCE_FENCED_WAITING_CONFIRMATION -> COMMITTED_TRANSFER (no second consent).
DELETE follows the same preparation but waits for explicit confirmation, including
an empty list. No worker can fabricate the confirmation. The shared waiting phase
is a snapshot-ready checkpoint for ADD, not a second consent requirement.

COMMITTED_TRANSFER is the hard execution boundary. CLEAN_SOURCE,
TRANSFER_COMPLETE and ACTIVE/DONE have parser support for future compatibility;
this worker does not execute transfer, cleanup or activation. No JOIN shopping ADD
block runs; there is no private item deletion, family member creation, active pointer
switch, invite USED transition or automatic quantity compensation.

## Fence and snapshot

Source root operationId and advanceShoppingEpoch patch commit together with the
operation's sourceFence epoch/timestamp. The unchanged S1 authority guard rejects
old queued commands and new private write authority. Canonical writes committed
before fencing are included; local-only unsent work is not fabricated as canonical
data. Abort clears only the owned fence and rotates to a fresh epoch, never restores
the old one. Family root operationId stays null, preserving active members' writes.

Manifest pages contain at most 10 source references/fingerprints, ordered by source
document ID. Source remains intact. Journal path is the 4B0 SHA-256 of inviteId,
fence epoch and page number under familyOperations/{id}/transferJournal. Empty
results arrays are forward-compatible metadata, not executed-transfer receipts.
Cursor and each manifest page commit atomically. Final snapshot has exact count
and chain hash; lists larger than 200 are paged, not truncated. Tests include 201.

Fingerprint implementation uses the pinned Admin SDK's internal toDocumentProto
wire accessor to preserve Firestore integer/double distinctions that data() loses.
Canonical values are type-tagged and byte-length-prefixed: UTF-8 byte-sorted maps,
ordered arrays, integer decimal normalization, IEEE754 big-endian doubles (canonical
NaN, distinct negative zero), raw bytes, exact strings/reference paths, timestamp
seconds/nanos and two-double GeoPoints. Each document hash includes ID/updateTime.
Unknown wire types fail closed. SDK upgrades must retain/test this accessor; no
fallback to lossy JS serialization is allowed.

The chain seed binds operation, invitation incarnation, actor/source/destination,
mode and fenced epoch. Each entry extends it with the document hash and normalized
S1 ADD payload hash (null for DELETE). All ADD source items are codec-validated
before commit. Unsupported ADD payload aborts without deleting items. Reservation
sourceItemCount remains historical; the API's sourceItemCount is snapshot.count.
ADD preflight uses a synthetic validation-only parseRequest envelope; it never
submits/stores that envelope or treats its dummy ID as transfer identity. Future
execution must use the operation/invite/fence/page/child identity from 4B0.

## Consent, commit and cancellation

New lazy CORE APIs: prepareFamilyJoinTransfer, getFamilyJoinTransferState,
confirmFamilyJoinDelete and cancelFamilyJoin. Strict request fields; UID comes from
Auth. There is no client Firestore ownership of these documents and no UI change.

The state API returns the 4B0 challenge: exact operation/invite/source epoch/hash/
count, consentVersion=1, server-resolved target and original invite expiry. The
confirmation API compares against server-owned evidence; forged/stale identities,
UID, mode, count, hash, epoch and version are rejected. It validates current owned
source/reservation/invite/capacity, both lifecycles, absence of deletion jobs, owner
context/Pro and family capacity, then atomically sets committedAt/deleteConsent,
phase COMMITTED_TRANSFER and capacity.structuralOperationId. It invalidates prior
worker lease ownership in that same commit. Lost ACK reentry returns durable state.

Pre-commit decline/cancel/revoke, expiry and eligibility loss abort safely: release
owned source fence, reserved reverse index, capacity seat and invite inventory;
mark invite REVOKED and operation ABORTED. Existing v1 reserved JOIN revoke now
uses this safe abort instead of always returning IN_PROGRESS. The corresponding
Phase4A regression expectation is intentionally updated. Foreign claims are never
cleaned as if owned. ABORTED operation slots can be reused; journal namespace and
consent include invite/fence incarnation so old evidence cannot redirect new work.

## Structural and lifecycle guards

Capacity schema v2 adds structuralOperationId; legacy v1 remains readable. All
existing capacity writes preserve the field. The lock is not an expiring lease;
another operation cannot steal it. Post-commit cancel/revoke return IN_PROGRESS,
and maintenance ignores expiry/Pro loss as abort triggers. Structural or lifecycle
inconsistency observed by a committed worker parks OPERATOR with locks retained.

beginDeletion and advanceAccountMarker's non-ACTIVE transitions read the Family
guard inside their transaction before marker writes. Committed invitee and owner
deletion admission refuse with JOIN_COMMITTED_IN_PROGRESS (existing public runtime
sanitizes this to retryableUnavailable). No DELETING marker or deletion job is
created by that refused request. Before commit the existing lifecycle invalidation
can win; JOIN then aborts and existing fail-closed cleanup can retry after release.

Trusted unexpected Auth deletion marks the blocking JOIN OPERATOR with
externalAuthDeletion and retains source/evidence/locks. Because Auth is already
gone, this trusted path also preserves the existing DELETING access barrier and
deletion job; shared cleanup still fails closed on the retained reservation. It
does not resurrect Auth, activate membership or delete shared data. This is a
repair case, not ordinary user deletion admission. Full Family-aware deletion and repair tooling remain
later release gates, not implemented here.

## Validation

Final validation on the final production source, 2026-10-23:

- Functions build/typecheck: PASS.
- Full backend unit suite: 240 PASS / 0 FAIL / 0 SKIP (includes 3 new contract tests and 15 S1A contract tests).
- Full local Firebase emulator regression: 698 PASS / 0 FAIL / 0 SKIP; exit 0; duration 783609.0705 ms.
- New 4B1A emulator cases: 36 PASS, included in the 698 total. Together with the 3 pure unit cases: 39 new tests PASS.
- Existing Phase 4A, invite/revoke, account deletion, household/family, shopping executor and S1C protocol/rules regression: PASS within the final suites.
- git diff --check: PASS; new files separately checked for whitespace/conflict markers.
- Emulator process shut down cleanly after the successful run. Local demo-kuktam-local only.

Final commands: Functions build, the repository full backend unit command, and `node scripts/emulator-tests.cjs`. Evidence logs:
`C:/Users/gabor/AppData/Local/Temp/family-4b1a-unit.log` and
`C:/Users/gabor/AppData/Local/Temp/family-4b1a-acceptance-emulator.log`.

Earlier focused (24) and full (694) passes were intermediate evidence only. An additional full run was intentionally stopped to correct the external-Auth-deletion access barrier; it is not counted as final acceptance. The new API export inventory expectation was updated during development. No tests were excluded, and no unexplained intermittent failures remain. All final results above follow the last production source change.

4B1A: PASS. Ready for 4B1B implementation: YES; 4B1B and 4B2 NOT STARTED.
Family Phase 4B is NOT complete. No live destination transfer, private source cleanup,
membership activation, activeHouseholdId switch, production access, deploy, commit or push.
The user requested closure after this final test; no further test round or phase was started.
No Flutter/native H2 matrix is required or run: production Dart is unchanged.
Firestore rules and shopping executor code remain unchanged.

## Remaining 4B1B / 4B2

4B1B must reuse the accepted max10 S1D ADD primitive with server JOIN authority,
record actual child results atomically with canonical effects, then perform fenced
source cleanup and reach TRANSFER_COMPLETE. This task implements none of those
effects. 4B2 separately owns mandatory activation/finalization and lock release.
Production Family gates must remain disabled through these and later lifecycle
rollout prerequisites. S1B/S1C/S1D acceptance history is not rewritten.

## Exact file inventory

Backend implementation:

- functions/src/households/join-capacity.ts (versioned guard and deletion admission)
- functions/src/households/join-snapshot.ts (typed canonical fingerprint)
- functions/src/households/join-transfer-contract.ts (strict v2 operation parser)
- functions/src/households/join-transfer.ts (bounded pre-commit state machine)
- functions/src/households/join-transfer-handler.ts (strict authenticated APIs)
- functions/src/households/family-join.ts (v2 dispatch and capacity compatibility)
- functions/src/households/family-invites.ts (state-aware reserved revoke)
- functions/src/billing/lifecycle-store.ts (normal deletion guard / external Auth barrier)
- functions/src/index.ts (lazy local-only API exports)

Tests/harness:

- functions/test/family-join-foundation.test.ts
- functions/test/join-foundation-contract.test.ts
- functions/test/family-join.test.ts (intentional pre-commit revoke expectation)
- functions/test/runtime.test.ts (new exported API inventory)
- functions/package.json (new unit suite included)
- functions/scripts/emulator-tests.cjs (new emulator suite included; focused selector)

Documentation:

- FAMILY_4B1A_CHECKPOINT_2026-10-22.md
- FAMILY_JOIN_TRANSFER_CONTRACT_4B0.md (explicit staged prepare API clarification)
- FAMILY_JOIN_RESERVATION.md (current progress link; original history retained)

Unchanged: production Flutter, Firestore rules, Firebase configuration, shopping
executor and S1D cost artifacts. No 4B1B transfer/cleanup or 4B2 activation code.
