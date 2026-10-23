# Family 4B1B1 - committed JOIN transfer execution

Date: 2026-10-23. Baseline: `7bbf91046d09b9f447f68f72302d07d7fecfde74`.
Initial worktree clean; committed 4B1A. No reset, staging, commit, push, production
access, deployment, runtime-gate enablement or client/rules change.

## Exact boundary

Input: READY / COMMITTED_TRANSFER, committedAt and exact manifest present, source
fenced, membership/invite RESERVED, structuralOperationId owned.
Output: READY / CLEAN_SOURCE. All required destination effects/disposition results
are durable. Source items and updateTimes remain unchanged, source fence and
structural lock remain owned. No cleanup, invite finalization, member creation,
pointer switch or activation runs. CLEAN_SOURCE and later phases are parked.
4B1B2 and 4B2 are not implemented.

The existing leased FamilyJoinStore dispatch calls the new internal execution
adapter. No new callable/API/export is introduced. Public shopping commands keep
their existing authorization. The reserved invitee is never impersonated as an
active member or as the owner.

## Authority and transaction algorithm

Every block/retry reads the committed operation and worker lease, owned structural
lock, source fence, reservation, invite/inventory, actor/owner lifecycle and user
pointers, owner membership/fallback and destination root. Deletion jobs are also
checked. Pro/expiry/admission flags are not post-commit abort conditions. Invalid
owned structure enters OPERATOR without compensation or releasing locks.

Each worker step performs at most one bounded page/prefix of 10 children:

1. Validate current journal page and previous completed page (if any), result
   prefix, exact manifest cardinality, ID ordering and hash chain. Final page must
   match the committed snapshot digest. Cursor must match durable result length.
2. Read only manifest-named frozen source documents. Verify exact updateTime and
   full typed fingerprint, then recover the same normalized S1 ADD payload and
   compare its hash. Live source data is NOT a new transfer snapshot or routing
   authority. Missing/changed evidence is OPERATOR; nothing is silently refreshed.
3. ADD calls the unchanged S1D applyAddBlock algorithm in this same transaction:
   <=10 children, <=3 normalized candidates, transaction-local overlay, per-child
   monotonic revision, one final root sequence write, conservative single-child
   legacy-target fallback. Only server visibility and an explicit 1..10 argument
   bound were added to this existing primitive; no second merge engine exists.
4. Append per-child journal results and advance the cursor atomically with the
   canonical effects. On a complete last page, reset cursor=null and enter
   CLEAN_SOURCE. A final aggregate source count verifies manifest cardinality;
   source item mutations are never performed.

Destination epoch/revision bootstrap or natural expiry renewal uses the existing
advanceShoppingEpoch contract in a separate bounded step before ADD effects. An
initialized valid destination needs no extra bootstrap step. Each result records
the actual destination epoch. Replacement of a still-live previously used epoch
parks OPERATOR; natural expiry permits transactional renewal. The source epoch
is never renewed/rebound during transfer, even after its normal expiry deadline.

## Identity, journal, exact-once

Journal path is unchanged:
`familyOperations/{operationId}/transferJournal/{sha256(inviteId + ':' + sourceEpoch + ':' + pageIndex)}`.
Page schema remains version/identity/entries/chainHash/results, entries/results <=10.
No growing result array is added to the operation root.

Child transferId is SHA-256 of JSON encoding
`[operationId, inviteId, sourceFence.epoch, pageIndex, childIndex]`.
It is a server journal identity, not a newly submitted public shopping command.
ADD result: `{childIndex,transferId,code:'APPLIED',itemId,revision,created,epoch}`.
These are actual committed target/revision/creation outcomes from S1D, not predicted
values. Retry/ACK loss reuses the durable result prefix and identity. All reads run
again on a transaction retry; no source/authority/destination working set survives it.

The S1D primitive's valid-prefix semantic-failure behavior is retained. Applied
prefix evidence and a FAILED_TERMINAL child outcome commit atomically, JOIN parks
OPERATOR, and no CLEAN_SOURCE transition or inverse quantity operation occurs.
Manual repair must prove consistency and continue the same operation; this phase
does not implement repair tooling or silently drop failed children.

DELETE writes `{childIndex,transferId,code:'NO_TRANSFER'}` per snapshot entry. No
family shopping write or fake APPLIED receipt occurs. The final page reaches
CLEAN_SOURCE with source data intact. Empty ADD/DELETE verifies the seeded empty
manifest and empty source, then changes phase without manufacturing child work.

## Recovery and guards

Worker lease expiry replaces only execution ownership; it never releases the
structural lock. Concurrent workers conflict on the operation/journal/root and
read the committed prefix on retry. Interruptions resume from cursor/results.
Lost acknowledgement after commit cannot re-add the completed prefix.

Revoke/cancel returns IN_PROGRESS after commit. Invite expiry, Pro loss and disabled
new-JOIN admission do not abort forward execution. Normal actor/owner account
deletion remains rejected by the existing 4B1A admission guard during transfer and
at CLEAN_SOURCE. Source normal mutation authority stays denied. Unexpected lifecycle
or integrity invalidation parks OPERATOR; there is no subtraction/rollback.

## Cost characterization

25 distinct ADD items, initialized destination, execution transactions only:
118 R / 34 W; 3 transaction calls/attempts, 0 retries; 93 document gets, 25 empty candidate queries and 1 separately reported aggregate RPC. The development and final runs produced identical records.
Fixture, snapshot preparation, lease claim/release, assertions and teardown are
excluded. The S1D R metric remains document gets + returned query documents + empty
query minimums; it is NOT Firebase billing. Aggregate RPCs are now counted separately
in test instrumentation and are not disguised as one document read or added to R.

Measured document reads: 25 frozen source documents; 5 journal page reads; 63 operation/authority/context reads (21 per block, including the existing outer/inner operation read and owner-validation/destination root read). There is no per-child authorization cache or new cost target.

The measured write shape is 25 canonical writes + 3 sequence writes + 3 journal
updates + 3 operation/cursor updates = 34. Three transactions revalidate authority;
authorization is not repeated separately for all 25 children. Legacy targets may
retain conservative single-child granularity. There is no new optimization target.

## Validation

Final acceptance on the final source: PASS, 2026-10-23.

| Suite | Pass | Fail | Skip |
|---|---:|---:|---:|
| New 4B1B1 emulator | 28 | 0 | 0 |
| 4B1A emulator | 36 | 0 | 0 |
| 4B1A pure contract (separate command) | 3 | 0 | 0 |
| S1D ADD block | 27 | 0 | 0 |
| S1A contract | 15 | 0 | 0 |
| S1A shopping executor | 45 | 0 | 0 |
| S1C shopping rules/protocol | 26 | 0 | 0 |
| Household rules | 33 | 0 | 0 |
| Family Phase4A JOIN | 51 | 0 | 0 |
| Family invite/revoke | 67 | 0 | 0 |
| Total | 331 | 0 | 0 |

Final emulator selection: 328 PASS, exit 0, duration 571576.7723 ms. All emulators
shut down. Separate pure-contract command: 3 PASS, exit 0. Functions build PASS;
final git diff --check PASS, including separate whitespace/conflict checks on new
files. No unexplained intermittent failure remains. All final tests follow the last
production source change.

Commands: `npm run build`, `node scripts/emulator-tests.cjs --transfer-regression`,
and `node --test lib/test/join-foundation-contract.test.js` in functions/.
Final emulator log: `C:/Users/gabor/AppData/Local/Temp/family-4b1b1-final.log`.
The selected final run includes complete 4B1A, new 4B1B1, complete S1D ADD block,
S1A contract/executor, S1C shopping/household rules, Phase4A and invite tests.

Full backend/emulator regression is not required for this narrow change: no shared
lifecycle/lease/authorization algorithm was changed; the existing S1D algorithm was
made callable internally with an explicit bound. Its complete correctness suite
and affected production executor/rules paths are included. No Flutter/native H2 or
Android build runs; production Dart remains unchanged.

Initial focused development run: 25 PASS / 1 FAIL. The failure was a malformed test
fixture that rewrote invite.expiresAt inconsistently with the fixed seven-day invite
contract. Corrected to advance the test clock; no production expiry rule was weakened.
The final run also includes null-result corruption and natural epoch-renewal tests.

## Files

- functions/src/households/join-transfer-execution.ts (new internal adapter)
- functions/src/households/join-transfer.ts (committed dispatch/authority)
- functions/src/shopping/mutation-store.ts (reuse existing max10 primitive)
- functions/test/family-join-transfer.test.ts (new focused tests)
- functions/test/firestore-meter.ts (separate aggregate call accounting)
- functions/scripts/emulator-tests.cjs (focused/final selection and full-suite inclusion)
- FAMILY_4B1B1_CHECKPOINT_2026-10-23.md
- FAMILY_JOIN_RESERVATION.md (current progress link; historical text preserved)

## Remaining work

4B1B2 must implement bounded exact-manifest source disposition and prove
TRANSFER_COMPLETE. It must not infer that CLEAN_SOURCE means source data is already
deleted. 4B2 separately owns membership/pointer activation and invite finalization.
Neither later phase, production enablement nor deployment is part of this change.
S1B/S1C/S1D and 4B0/4B1A accepted history is retained.

## Final gates

4B0 PASS; 4B1A PASS; 4B1B1 PASS. Ready for 4B1B2: YES for a separate task.
4B1B2 NOT STARTED; 4B2 NOT STARTED; Family Phase4B NOT complete.
Source cleanup NO; source fence/structural lock retained YES; membership ACTIVE NO;
activeHouseholdId switched NO; invite finalized NO. No production access or changes,
no production rollout, no deploy, no commit, no push. Blockers: NONE for this phase.
Production Flutter and Firestore rules unchanged; direct canonical client writes 0.