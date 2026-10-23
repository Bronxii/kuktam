# Family 4B1B2 - source disposition

Date: 2026-10-23. Baseline: `cfc66b8bfe3680e545bac2ea583462a30b7933bd`.
Initial worktree clean, committed 4B1B1. No reset, production access, deployment,
gate changes, client/rules changes, staging, commit or push.

## Scope and invariant

Input READY / CLEAN_SOURCE already proves committed transfer/disposition results.
This phase deletes only the exact fenced manifest source items and reaches READY /
TRANSFER_COMPLETE. ADD and DELETE use the same source disposition primitive:
ADD has APPLIED family receipts; DELETE has NO_TRANSFER receipts and explicit
committed second consent. No family canonical mutation or ADD replay occurs here.

The private household, private owner membership, source operationId/epoch fence,
RESERVED reverse membership/invite, user pointers, capacity seat and structural
lock are retained. TRANSFER_COMPLETE remains non-writable to ordinary private
shopping commands. No activation, invite finalization or Phase5/6 action exists.

## Identity and bounded journal delta

The existing transferJournal page is reused; immutable entries/chainHash/results
are preserved byte-for-byte as Firestore data. No root result array is introduced.
At cleanup, one optional `cleanup` array is appended to the page, at most 10 items.
An absent field means no cleanup committed; a present array must cover the entire
page. Partial arrays are integrity errors because each page is one atomic unit.

Each result is:
`{childIndex, cleanupId, transferId, sourceId, dataHash, code:'DELETED', completedAt}`.
`cleanupId = sha256(JSON.stringify(['join-source-disposition-v1', transferId]))`.
The existing transferId binds operation/invitation/fence/page/child incarnation.
dataHash/sourceId bind the result to its original manifest entry, completedAt is
server time not before committedAt. No replacement cleanup identity is generated.

## Transaction and cursor

The existing leased JOIN dispatcher performs the same fresh committed authority,
source fence, structural lock, reservation/invite, lifecycle and deletion-job checks
before each cleanup transaction/retry. Temporary worker lease and durable structural
ownership remain separate.

Maximum deletion block: **10 documents**. For a nonempty page:

1. Validate original manifest and full successful transfer results via the existing
   4B1B1 page validator (now exported internally without a behavior change).
2. Validate the previous completed page's cleanup proof, ordering and source absence;
   validate the current hash-chain link, final digest when applicable and monotonic
   ADD result revisions across page boundaries. Reject skipped/unproven progress.
3. Read only current manifest source IDs; verify all updateTimes and full typed
   fingerprints before scheduling any deletion. Unexplained absence is OPERATOR.
4. Delete at most 10 exact documents using lastUpdateTime preconditions; append the
   cleanup results and advance cursor `{pageIndex:n+1, childOffset:0}` atomically.

Normal page write bound is 10 deletes + 1 journal update + 1 operation update.
Reads are bounded to current/previous pages and <=20 exact source documents plus
the existing authority checks. No whole-list transaction or destructive bulk clear.

A full recorded cleanup page with absent source documents can be safely reobserved
without writing new results or deleting again. A recreated document is OPERATOR,
never a replacement to delete. An incomplete/corrupt cleanup record is not proof.

After the last page deletion, the operation stays CLEAN_SOURCE until a separate
bounded transaction verifies the final committed page/digest and an empty source
query (`limit(1)`). It then atomically sets TRANSFER_COMPLETE and cursor=null.
This prevents read-after-write and speculative empty-list claims. An unrelated or
late document is retained and blocks completion with OPERATOR. Empty snapshots
check their seeded digest and actual source emptiness, then complete without fake
delete actions. Reentry at TRANSFER_COMPLETE never executes cleanup again.

## Recovery, failures and post-commit events

Deletion and evidence cannot commit separately. Pre-commit transaction failure
leaves both unchanged; lost acknowledgement sees the durable page/cursor. New
workers resume the existing identity. Competing workers conflict transactionally;
expired leases can be reclaimed but never release the structural lock.

Mismatched content/updateTime, unexplained missing items, malformed receipts,
invalid cleanup identity, recreated items or skipped cursor evidence park OPERATOR
with locks/source remainder retained. Valid earlier blocks stay committed; there
is no family compensation, rollback, activation or guessed cleanup of other IDs.

Revoke/cancel remain IN_PROGRESS; expiry/Pro loss/admission flags cannot abort a
committed JOIN. Existing actor/owner deletion admission guard remains active in
CLEAN_SOURCE and TRANSFER_COMPLETE. Old source commands remain rejected; new source
authority remains denied. Source epoch is not restored, renewed or released here.

## Validation

Final validation PASS on the final production source, 2026-10-23:

| Suite | PASS | FAIL | SKIP |
|---|---:|---:|---:|
| New 4B1B2 source disposition | 27 | 0 | 0 |
| 4B1A emulator | 36 | 0 | 0 |
| 4B1A pure contract | 3 | 0 | 0 |
| 4B1B1 transfer | 28 | 0 | 0 |
| Phase4A JOIN | 51 | 0 | 0 |
| Invite/revoke | 67 | 0 | 0 |
| Shopping executor | 45 | 0 | 0 |
| S1C shopping protocol/rules | 26 | 0 | 0 |
| Household rules | 33 | 0 | 0 |
| Total | 316 | 0 | 0 |

Final harness exit 0; duration 755099.0813 ms. Functions build PASS. Final diff-check
PASS, with new files separately checked for trailing whitespace/conflict markers.
No unexplained intermittent failures. The final selection ran once after the last
production source change; no production fix was needed during regression.
Emulators shut down cleanly. All tests used demo-kuktam-local and loopback only.
Final log: `C:/Users/gabor/AppData/Local/Temp/family-4b1b2-final.log`.
Commands in functions/: `npm run build`,
`node scripts/emulator-tests.cjs --disposition` for development and
`node scripts/emulator-tests.cjs --disposition-regression` for final acceptance.

Development run: 25 PASS / 1 FAIL (26 tests). The updateTime-only corruption fixture initially performed an identical set, which the emulator treated as a no-op. It now performs a real change and restores the original payload, explicitly asserting the new updateTime before exercising cleanup. Production logic was not weakened or changed for this fixture correction. The final suite also includes an old accepted private-command regression through cleanup/completion.

No full backend/emulator run is needed: shared lifecycle/lease/shopping business
algorithms are unchanged. Changes are an internal cleanup adapter, committed JOIN
dispatch and exporting the existing page validator; affected paths are covered by
the selected regression. No Flutter, native H2 or Android build runs.

## Exact 4B2 prerequisites / remaining work

4B2 must validate the same committed incarnation, full family transfer receipts,
cleanup evidence, empty fenced source, retained reservation/invite/capacity lock,
consistent lifecycle and authoritative target. It must complete forward rather
than re-admit on Pro/expiry or cancel. Its future atomic activation owns member and
reverse-index activation, user family/active pointer switch, invite consumption,
inventory/seat removal, structural lock release and source fence release with a
fresh epoch. None of these changes is implemented by 4B1B2. There must be no writable
private interval before the pointer/membership activation boundary.

## Files

- functions/src/households/join-source-disposition.ts (new bounded cleanup adapter)
- functions/src/households/join-transfer.ts (CLEAN_SOURCE dispatch)
- functions/src/households/join-transfer-execution.ts (export existing page validator)
- functions/test/family-source-disposition.test.ts (new focused tests)
- functions/scripts/emulator-tests.cjs (local targeted/final selections)
- FAMILY_4B1B2_CHECKPOINT_2026-10-23.md
- FAMILY_JOIN_RESERVATION.md (current progress; prior history retained)

4B2 NOT STARTED. Family Phase4B is not complete. Production rollout remains NO.

## Final gates

4B0 PASS; 4B1A PASS; 4B1B1 PASS; 4B1B2 PASS. 4B1 COMPLETE: YES.
Ready for 4B2 implementation: YES, as a separate task. No activation performed.
Successful ADD 0/1/11/25/201 and DELETE 0/1/25 cases end with 0 source items;
private household/fence, RESERVED membership/invite and structural lock retained.
Account-deletion admission remains ACTIVE (blocking) through TRANSFER_COMPLETE.
Corrupt/mismatched/unexplained-missing cases park OPERATOR with no guessed cleanup.
Client code/rules unchanged. Production accessed NO; production changes NONE;
deploy NO; commit NO; push NO. Blockers: NONE for this phase.
