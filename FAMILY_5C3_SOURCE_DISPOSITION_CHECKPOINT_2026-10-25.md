# Family Phase 5C3 — Family shopping source disposition

Requested checkpoint label: 2026-10-25. Local implementation/validation: 2026-10-24–25, crossing midnight in Europe/Budapest.
Baseline: `46b563277779b7e016dc1c91e4be040d5b0e8c1f`, committed 5C2B.
Initial worktree/status and diff check: clean.

## Scope and final boundary

Input: `PRESERVATION_MERGE_COMPLETE / READY`.
Successful output: `PRESERVATION_SOURCE_CLEANED / READY`, lastOutcome `preservationSourceCleaned`.
The operation is still forward-only and not DONE. Family remains ACTIVE, owner and members remain ACTIVE, every activeHouseholdId still points to Family. The Family source fence, owner-private target fence, both epochs and structuralOperationId remain unchanged. The owner-private merge result is read-only throughout 5C3.

The explicit callable is `cleanFamilyShoppingSource({householdId})`, using the existing authenticated selector adapter and deterministic owner/Family dissolution identity. It remains guarded to localhost Firestore emulator and project `demo-kuktam-local`, with deployed-runtime markers denied. No runtime gate was enabled, no timer/polling or automatic next-phase dispatch added. Each call performs one bounded transaction.

## Authoritative deletion proof

Only the immutable 5C2A `shoppingPreservation` entries choose deletion document references. A fresh query never supplies deletion IDs. Existing readPreservation/readPreservationPage, typed sourceFingerprint and the exported existing 5C2B merge progress/journal validators are reused, not forked.

Before any deletion, a bounded CHECK pass validates the entire committed snapshot and complete merge receipt hash chains. Each source entry is bound to operation, source/target fenced epochs, page/index, source document ID, updateTime/content fingerprint and stable transferId. Each corresponding merge receipt must be APPLIED with the expected target item, monotonic revision and target epoch. Target item identity/revision and target household sequence are checked without writing target data.

Every DELETE block freshly revalidates participant topology/version proof, source/target identity and fences, structural lock, completed merge root/progress and its page receipt evidence. It compares ALL current source documents in the block with committed updateTimes and full typed fingerprints before scheduling the first deletion. Explicit lastUpdateTime preconditions accompany transactional deletes. A mismatch in one item prevents deletion of the entire block.

There is no source reconstruction, snapshot regeneration, merge replay, quantity subtraction or automatic fence release.

## Stable cleanup identity and durable progress

`cleanupId = SHA256(JSON(["preservation-source-cleanup-v1", transferId]))`.
The transferId is the existing 5C2A preservation child identity, binding dissolution and exact snapshot routing. Reentry never generates replacement actions.

Progress: `familyOperations/{id}/preservationSourceCleanup/state`, schema version 1:
- CHECK / DELETE / VERIFY / COMPLETE stage;
- page index, completed count, last source ID;
- snapshot, merge-receipt and cleanup hash-chain cursors;
- expected final cleanup hash during verification.

Cleanup evidence: `preservationSourceCleanupJournal/{preservationPageId}`. Each page contains version, deterministic page identity/index, previous/current chain hashes and at most 10 terminal records: cleanupId, transferId, sourceId, DELETED. Snapshot and merge pages remain unchanged. Evidence links back to their exact source fingerprint/updateTime and completed target receipts.

One DELETE transaction atomically commits at most **10 source deletions + one cleanup page + progress**. Reads/validation precede every write. No private item or household root is modified. The durable structural lock is not a temporary worker lease; competing transactions serialize through operation/progress and the same source reads. A lost ACK cannot leave deletion without evidence or evidence without deletion.

## Missing, mismatched and extra items

- Pending source missing without its completed cleanup evidence: OPERATOR; no block deletion.
- Already-cleaned prefix with matching journal: resume from durable cursor; VERIFY accepts absence only with exact terminal evidence.
- Missing/corrupt cleanup journal, source change (including same content at a new updateTime), receipt/cursor/fence mismatch: OPERATOR.
- Recreated already-cleaned document: integrity failure; never delete it as fresh work.
- Extra source document: CHECK count detects pre-existing extras before any deletion; final empty-source query detects extras introduced later. The extra document is retained, never silently deleted.

Errors retain fences, memberships and structural ownership. Infrastructure failures roll the whole transaction back and remain retryable. Integrity failures park status OPERATOR with lastOutcome `preservationSourceIntegrity`; no rollback/compensation of earlier valid blocks.

## Final emptiness and reentry

After DELETE, a separate bounded VERIFY pass rechecks all snapshot/merge/cleanup pages and confirms each committed source ID is absent with its valid terminal cleanup proof. Finalization checks exact snapshot/merge/cleanup page counts, full count and chain hashes, fresh authority/fences, and a transactional `shoppingItems.limit(1)` empty result. That query is only an emptiness test, never deletion authority. The final progress COMPLETE and root PRESERVATION_SOURCE_CLEANED writes are atomic.

For zero source items, the first transaction verifies empty snapshot/journal/source, valid merge completion and correct seeds, then directly commits COMPLETE/PRESERVATION_SOURCE_CLEANED. No fake delete and no item write.

Completed reentry validates root/progress/fences/merge completion and empty source, returning without writes or epoch changes. It is not a new full historical journal audit. Earlier 5C2A/5C2B entry points recognize the later state and return it without rebuilding snapshots or replaying merge effects.

## Structural/lifecycle boundary

The existing structural guard continues blocking self-leave, owner removal, JOIN commit and another dissolution. Account deletion remains `JOIN_COMMITTED_IN_PROGRESS` under the existing admission guard, during cleanup and after source-cleaned completion. Pro loss cannot cancel forward completion. Normal Family and owner-private shopping remain blocked; stale private requests reject. No Phase 6 lifecycle consequence is implemented.

## Validation

Final acceptance: PASS. Final code validation: 44 PASS / 0 FAIL / 0 SKIP, exit 0 (340830 ms). Breakdown: 25 new 5C3 cases, 5 affected 5C2B cases, 8 affected 5C2A cases, 4 structural 5C1 cases, 2 callable/runtime cases. Functions build/typecheck: PASS. Git diff check: PASS. Emulator shut down successfully. The earlier focused run passed 25/25; an intervening final-regression attempt was interrupted before its summary and is not counted as a completed run. The same final selector was restarted without code changes and completed successfully. Build/typecheck uses the full Functions build. All Firestore setup/execution is local emulator only. The 201-item case builds real committed 5C2A and 5C2B input as its fixture; no unrelated historical transfer-scale or performance suite is run.

Tests cover 0/1/11/25/201, exact preserved-source deletion, immutable owner-private result and evidence, interruption, lost ACK, competing workers, forced atomic transaction failure, missing source, changed content/updateTime, corrupt preservation/cleanup/cursor/fence evidence, extra source before and after partial deletion, recreated source, retained guards, wrong actor/state and no-op reentry.

Full historical backend regression, Flutter, native H2, Android and shopping performance suites are intentionally not run: no shared shopping algorithm, rules or client code changed. Preservation/merge parser extensions and validator exports receive directly affected regression coverage.

## Next separate milestone

Participant release / final dissolution is NOT STARTED. Its prerequisites are source-cleaned root, COMPLETE cleanup proof, empty Family source, valid completed preservation evidence, intact owner-private result, immutable participants and both fences/structural lock still held. It must define and implement atomic membership/routing transitions and safe fence/lock release separately. 5C3 does not perform any of those transitions.

Production access/change: NONE. Deploy: NO. Commit: NO. Push: NO. Phase 6: NOT STARTED.

## Acceptance and handoff

5C3: PASS, locally complete. Required 5C3 implementation/tests deferred: NONE.
No unresolved blocker. Prior accepted Phase 4B / 5A / 5B / 5C1 / 5C2A / 5C2B checkpoints remain unchanged.
The next participant-exit/final-dissolution milestone and Phase 6 are NOT STARTED.
Membership/routing changes, invite/reservation finalization and safe fence/structural-lock release remain future scope, not incomplete 5C3 work.

Files changed:
- functions/src/households/dissolution-source-disposition.ts (new)
- functions/src/households/dissolution-preservation.ts
- functions/src/households/dissolution-merge.ts
- functions/src/index.ts
- functions/test/dissolution-source-disposition.test.ts (new)
- functions/test/runtime.test.ts
- functions/scripts/emulator-tests.cjs
- FAMILY_JOIN_RESERVATION.md
- FAMILY_5C3_SOURCE_DISPOSITION_CHECKPOINT_2026-10-25.md (new)

Reproduction after compilation: `node functions/scripts/emulator-tests.cjs --source-cleanup-regression`.
Final local log: `C:/Users/gabor/AppData/Local/Temp/family-5c3-final-complete.log`.