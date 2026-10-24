# Family Phase 5C2B — Owner shopping preservation merge

Date: 2026-10-24
Baseline: `40ee9b6fb37b9eafef137d30a5a16b7ae42caff9` (committed 5C2A).
Initial worktree/status and diff check: clean. Local demo emulator only.

## Exact boundary

Input: `FAMILY_DISSOLUTION / PRESERVATION_COMMITTED / READY`.
Output: `PRESERVATION_MERGE_COMPLETE / READY`, `lastOutcome=preservationMergeComplete`.
This is not DONE: Family remains ACTIVE, source items remain present, all members remain ACTIVE and their activeHouseholdIds remain Family. Both shopping fences and `familyJoinCapacity.structuralOperationId` remain owned by this dissolution. No source cleanup, fallback release, membership exit or dissolution finalization is performed.

`mergeFamilyShoppingPreservation({householdId})` is an explicit authenticated local-only continuation. The authenticated owner determines the existing dissolution ID. Caller-supplied owner/target/operation overrides are rejected. The same handler validation/sanitization and CORE lazy export conventions are reused. Production guards remain closed; there is no worker timer, polling or automatic next-phase dispatch.

## Reuse and authority

No shopping merge algorithm was introduced or changed. Each effect block calls the existing `ShoppingMutationStore.applyAddBlock`, maximum 10 children. Its semantic normalization/compatible-unit contract, same-block overlay, incompatible-unit separation, per-child revision/created evidence, valid-prefix failure behavior and conservative legacy single-child fallback remain intact.

The 5C2A validator is reused inside every transaction and every retry: immutable participant identity/version proof, Family identity, owner fallback, source/target fence and bound epochs, structural ownership, pending invite/reservation consistency. Post-commit Pro/expiry concerns cannot invoke pre-commit cancellation. Account-deletion admission remains guarded. Self-leave/owner-remove/JOIN/another dissolution fail closed under existing guards. No Phase 6 consequences were added.

A first bounded initialization records target sequence baseline as max(household sequence, highest existing item revision). A nonempty transfer may initialize that metadata once; it never rotates either epoch. Thereafter every transaction requires exact equality between the target household sequence and the durable merge sequence. Each successful child advances it once. Unexpected sequence/fence/receipt evidence parks OPERATOR rather than overwriting or compensating. Ordinary target writes remain impossible through the existing fenced shopping authority. This is not a new full target-content snapshot or a defense against arbitrary privileged administrators rewriting all proofs consistently.

## Authoritative snapshot and identity

The 5C2A `shoppingPreservation` pages remain immutable, including their empty preparation results arrays. Their stored normalized ADD payloads are the only merge deltas. Live source documents are read only to validate ID/updateTime/typed content fingerprint, never to reconstruct or replace the payload.

The existing `preservationChildId` is reused unchanged: dissolution identity + both fenced epochs + snapshot page/index + source document ID. Each receipt refers to that child, whose immutable snapshot entry also binds source updateTime/content/payload hashes. Restarts and transaction retries do not manufacture a new logical ADD identity. Random candidate canonical IDs generated inside an aborted S1D attempt are not committed; the winning canonical ID is durably recorded with its receipt.

## Journal, cursor and atomicity

Progress lives at `familyOperations/{id}/preservationMerge/state`, version 1:
- stage APPLY / VERIFY / COMPLETE;
- pageIndex, child offset, count, last source ID and snapshot chain hash;
- receipt-chain hash/final expected hash;
- base/current target sequence and committed block count.

Receipts live in bounded `preservationMergeJournal/{preservationPageId}` documents. Each page stores version, page identity/index, previous and resulting receipt-chain hashes, and at most 10 results. A result contains childIndex, transferId, APPLIED, canonical itemId, revision, created, target epoch. Hashing uses explicit ordered values; map serialization order does not change identity.

One effect transaction reads fresh authority/proofs, invokes S1D, then commits target canonical writes, household sequence, journal prefix and cursor together. All reads precede S1D's writes. The source and preparation pages are never written. Large/custom legacy targets retain S1D single-child granularity, with durable within-page offsets; no forced unsafe batching.

Before another page applies, the previous receipt prefix is revalidated and tied to cursor/snapshot evidence. After all effects, a bounded VERIFY pass rechecks every page/result/chain, target receipt identity and revision, and unchanged source proof. Final completion requires full count/hash, exact snapshot/journal page counts, source item count, expected target sequence and valid fences/structural proof. It atomically marks progress COMPLETE and operation PRESERVATION_MERGE_COMPLETE. Each successful child has a distinct monotonically increasing revision starting above all existing target revisions.

Completed reentry validates root/structural/fence/progress/sequence evidence and returns without ADD, new epoch or any write. It is not a repeated full-page corruption audit. Later source disposition must validate all relevant immutable snapshot and terminal journal evidence before deleting any source document.

## Recovery and integrity

No temporary lease is needed for one bounded atomic continuation: transaction conflicts on shared progress/household reads serialize competing calls. A worker cannot expire or steal structural ownership. Lost ACK and interruption resume from committed journal/cursor, not in-memory decisions. Forced ABORTED retry reruns fresh transactional validation; accepted quantities and receipts commit once.

Malformed committed snapshot, journal/receipt identity/hash, cursor, source/target fence or target sequence parks `status=OPERATOR`, with no automatic compensation or release. An S1D semantic failure preserves its valid committed prefix and failure receipt atomically, then parks OPERATOR. Already committed quantities are never subtracted. Infrastructure exceptions remain retryable; premature/wrong-owner calls do not mutate a valid preparation.

## Semantic examples and scale

- Existing Milk 1000 ml + snapshot 300 ml + 2 l = 3300 ml.
- Existing Milk 1000 ml + snapshot 300 ml + 2 l + 500 ml = 3800 ml.
- No existing Milk + those three deltas = one Milk 2800 ml row; created flags true/false/false.
- Repeated products across page boundaries accumulate exactly once.
- Same product db versus ml remains separate; unrelated private items/custom fields are preserved.
- Source sizes 0/1/11/25/201 use 0/1/2/3/21 effect blocks for compact targets. Zero executes no fake item mutation.

The source/target duplication is intentional temporary preservation evidence while both lists are fenced. Later disposition must remove only the exact proven Family source; this phase must not do so.

## Validation

The final targeted regression is `node functions/scripts/emulator-tests.cjs --preservation-merge-regression`; **72 PASS / 0 FAIL / 0 SKIP**, harness exit 0. Functions build/typecheck: PASS after the final production code change. The final regression ran once after that change. Emulator shut down normally. Diff check: PASS.

| Final selected coverage | PASS |
| --- | ---: |
| New 5C2B suite | 26 |
| Relevant 5C2A fence/integrity/forward-only tests | 13 |
| Relevant 5C1 structural lock/JOIN races | 4 |
| Complete S1D ADD block suite | 27 |
| Runtime export/discovery isolation | 2 |
| Total | 72 |

Final log: `C:/Users/gabor/AppData/Local/Temp/family-5c2b-final.log`.
No required targeted 5C2B validation is deferred. No unexplained flaky failures.

25 distinct-item measurement (existing S1D test-only meter, fixture/preparation excluded): **257 R / 42 committed writes**, **9 transaction attempts / 0 retries**, **3 S1D effect blocks (10/10/5)**. R is the existing instrumented comparison metric, not Firebase billing ground truth: 194 document gets + 37 returned query documents + 26 empty-query equivalents; 5 aggregate calls are separate. The 9 transactions are one initialization, three effects, one verification transition, three proof-page checks and one completion. Writes: 25 canonical items, 4 target sequence writes (initialization + three blocks), 13 journal/progress/operation writes. Source proof and receipt verification overhead is included. No new cost target or optimization was introduced.
Initial implementation-only run: 23 PASS / 0 FAIL / 0 SKIP, local emulator exit 0. Before the final run, receipt-prefix validation was strengthened and tests added for exact 3300/2800 ml examples and conservative legacy fallback.

No full historical backend, Flutter, Android/native H2, transfer history scale or unrelated performance suites were run. Shared shopping business logic, rules and Flutter remained unchanged; only the preservation parser/validator visibility was extended to reuse its authority boundary and recognize the new final phase.

## Next separate milestone

Source disposition / dissolution continuation is NOT STARTED. Preconditions: merge-complete root and COMPLETE progress agree; all source snapshot children have valid terminal merge proof; original source and both fences/epochs/structural lock remain intact. Future work must define and implement atomic cleanup evidence, resumable source disposition, participant fallback transitions and final dissolution boundaries separately. No Phase 6 lifecycle work is included here.

Production accessed: NO. Deploy: NO. Commit: NO. Push: NO.

## Final acceptance and changed files

5C2B: **PASS**. No blockers. Phase 4B COMPLETE; 5A/5B/5C1/5C2A PASS from committed baseline. Next dissolution phase and Phase 6 NOT STARTED. No commit/push/deploy.

Changed files:
- `functions/src/households/dissolution-merge.ts` — new bounded execution/journal verification, existing S1D primitive only.
- `functions/src/households/dissolution-preservation.ts` — shared authority validator and recognition/idempotent return of merge-complete phase.
- `functions/src/households/dissolution-preservation-handler.ts` — structural step interface reused, validation behavior unchanged.
- `functions/src/index.ts` — lazy local-guarded merge callable export.
- `functions/test/dissolution-merge.test.ts` — 26 focused cases and operation meter sanity.
- `functions/test/runtime.test.ts` — expected export and selector isolation.
- `functions/scripts/emulator-tests.cjs` — focused/final merge selections; new suite also registered for future full regression.
- `FAMILY_JOIN_RESERVATION.md` — additive progress entry.
- this checkpoint.
