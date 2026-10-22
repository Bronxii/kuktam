# S1D2A - Atomic ADD block executor

Date: 2026-10-22. Baseline: `261d5602d02bd091b9ac8c84dcfc89d47e8575ac`
(`test(shopping): establish S1D bulk cost baseline`). Initial worktree clean;
initial diff check clean. S1B remains accepted; S1C remains complete locally.
Only backend ADD-only BULK execution, focused tests/harness and documentation
changed. No client, SQLite, rules, Family lifecycle, gate or deploy changes.

## Algorithm and atomic boundary

`MAX_ADD_BLOCK_SIZE = 10`. `process(maxSteps)` still budgets CHILDREN, not blocks:
default 10, accepted range 1..20. The transaction reads the existing command,
validates its immutable hash/envelope and cursor/result length, then freshly runs
`shoppingAuthority` and epoch validation. Every SDK retry invokes these reads
again. No authorization/context cache escapes the transaction callback.

Only an entirely ADD-only BULK is optimized. Select the ordered payload suffix at
the durable cursor, bounded by 10, remaining worker budget and remaining children.
Standalone ADD and all mixed parents (including their ADDs) keep one-child
transactions; EDIT/DELETE/SET_CHECKED implementation is unchanged. No reordering,
child index reassignment, new mutation ID, protocol field or schema migration.

Read all normalized `(name, unit)` candidate queries before writes, `limit(3)`
unchanged. Repeated keys share their query within this attempt. Build a local
working map in payload order. A later ADD sees an earlier ADD's in-block quantity
and revision. A new destination is created once; subsequent children merge into
that same destination. Existing checked/created/custom values are preserved.
Incompatible dimensions remain separate. Multiple candidates retain the previous
FAILED_TERMINAL behavior, rather than choosing an arbitrary target.

Each successful child gets `max(current household sequence, target revision)+1`.
The working household sequence advances for every success, even repeated targets.
Each result retains its own itemId/revision/created flag. Only the first creation
has created=true. The final target document may legitimately have a later
revision than an earlier child receipt; dependent writes using that earlier
revision fail stale rather than rebase. No guessed revision or destructive
retargeting. Server requests have no unresolved-dependency representation: the
unchanged client intent queue materializes them from actual predecessor evidence.
The executor never pulls held client work into a block.

After planning, write each final target once, household sequence once, command
results/cursor/appliedCount/status once and work scheduling once, in the SAME
transaction. Per-child evidence is still the ordered results array in the parent
receipt; no evidence is removed. Payload retention/deletion, hash, terminal status
and receipt expiration remain unchanged. If a later child has an invalid quantity,
revision or ambiguous candidates, commit only the valid prefix and terminalize the
remaining children using the existing failure policy, atomically. Authorization
or epoch failure before planning applies no child in that block. Previously
committed blocks remain committed.

An aborted attempt commits nothing. A lost ACK after a committed block retains its
cursor/results; defer and subsequent recovery use the same command. Returning
PROCESSING means unresolved children remain; DONE/APPLIED/PARTIAL follows the
existing all-children-terminal criterion. Test interruption uses a new backend
worker, not Android/process-death claims.

## Size / operation bounds and legacy fallback

For a normal ten-distinct-key block, successful execution has:
- private: 1 command + 5 authority document gets + 10 candidate queries;
- family: 1 command + 7 authority document gets + 10 candidate queries;
- at most 10 final canonical writes + 1 household + 1 receipt + 1 work = 13 W;
- command admission adds one W outside processing, counted in cost tables.
Private RESERVED JOIN authority can add one familyOperations read (unchanged).
Epoch is checked on the already-read household; no extra epoch document read.

Maximum candidate result count is 30 (10 queries x limit 3); instrumented R upper
bound is 36 private / 38 family (37 private RESERVED), before retry amplification.
Ambiguous queries fail closed, so this upper read bound does not imply 30 writes.
Repeated keys reduce queries and final canonical writes, not child evidence.

Blocks accept only compact canonical targets: known six fields, bounded name
(1600 UTF-8 bytes), unit (64 bytes), ID (128 bytes), numeric quantity/revision,
boolean checked and Timestamp creation. A legacy/custom/oversized target reduces
that attempt to ONE child and retains the old single-item granularity. Queries
already prefetched are harmless extra reads; no cursor skip or unknown-field
rewrite occurs. A 300 KB custom legacy-field regression verifies preservation.
This conservative fallback is intentionally not a new legacy-data migration.

Compact new/updated canonical fields are small (roughly <3 KB/document including
path/field overhead); only quantity/revision are updated on existing targets.
The unchanged request cap is 256 KiB and result count cap is 200. Ten compact
canonical changes plus bounded receipt/work/sequence updates are far below the
10 MiB transaction request limit. Queries can return legacy data, but do not copy
it into write payloads. Unknown legacy document/index amplification is not
multiplied into ten-item commits. Firestore index-entry billing/serialized wire
bytes and latency are NOT measured by this meter. Future index configuration
changes still need normal size review; no claim of unlimited pathological data
or contention is made. SDK/server transaction limits remain enforced.
Reference: https://firebase.google.com/docs/firestore/manage-data/transactions
(transaction size includes modified documents/index entries).

## Measured costs (not Firebase billing counters)

Same S1D1 `FirestoreMeter`, actual production executor and actual Admin SDK against
Firestore emulator. R = document gets + query returned documents + empty-query
floor. Fixture setup, assertions, context issuance, bootstrap and client/rules
reads excluded. W includes one separately measured immutable command creation.
No alternate executor. Baseline zero-retry costs are separated from deliberate
retry tests. Raw current measurements: `S1D2A_COST_MEASUREMENT.json`; historical
`S1D1_COST_BASELINE.json` unchanged.

| Case | S1D1 R/W | S1D2A measured R/W |
| --- | ---: | ---: |
| Private BULK 1 | 7 / 5 | 7 / 5 |
| Private BULK 10 distinct | 70 / 41 | 16 / 14 |
| Family BULK 1 | 9 / 5 | 9 / 5 |
| Family BULK 10 distinct | 90 / 41 | 18 / 14 |

Ten-child R saving: private 54 (77.14%), family 72 (80%). W saving 27 (65.85%).
Fixed per block: 6/8 document gets (command included), 3 metadata writes.
Remaining per distinct key: one bounded candidate query and one canonical write.
Per child: result and sequence progression, no separate authorization re-read.
Retries repeat the entire block read phase; attempted and committed writes differ
under deliberate abort and are reported separately. No cached permission shortcut.
Standalone/mixed costs retain S1D1 values; their small measurement regressions run.

## Targeted evidence

S1D2A PASS. Final source run: 175 PASS / 0 FAIL / 0 SKIP, exit 0,
160973ms: 27 new block tests, 29 small cost/calibration tests, 15 S1A contract,
45 existing S1A executor and 59 household/shopping rules tests (33 + 26).
34 measurement records retained. The four representative 1/10 bulk measurements
all had zero retries; two block tests deliberately cause one SDK retry each,
including lifecycle invalidation before retry. Separate meter calibration causes
one deliberate retry. No unexplained failing/intermittent test.

Commands from functions: `npm run build`; `node scripts/shopping-add-block.cjs`.
Functions build PASS; final diff-check PASS. Final log:
C:/Users/gabor/AppData/Local/Temp/s1d2a-final.log. Initial run before legacy-size
fallback additions: 143/143 PASS, s1d2a-tests.log. Acceptance uses the final run.
Emulator exited cleanly and stopped. Project demo-kuktam-local, Firestore
127.0.0.1:8088 only; credentials stripped and local-target guard enforced.
Protected-file diff verifies lib/, firestore.rules and S1D1_COST_BASELINE.json
unchanged. No production access. No blocker.

The new tests cover ten unique ADDs, create/merge and existing repeated merges,
incompatible units, duplicate normalized candidates (2/3/4, query limit3), valid
prefix overflow, 25-child 10/10/5 recovery, 20-child worker budget as two blocks,
epoch/lifecycle/member/active-household invalidation between blocks, actual SDK
forced retry (atomic absence before retry, fresh lifecycle read, invalidation on
retry), deterministic two-command concurrent ADD, mixed fallback, actual receipt
revision dependency EDIT/CHECK/DELETE, stale earlier-receipt destructive intent,
large legacy fallback and lost commit ACK recovery. Concurrent transactions start
through a shared test barrier before execution, never correctness sleeps.

Existing S1A executor regression includes 10/50/200 correctness/replay fixtures;
these are NOT S1D2B cost benchmarks. S1D2A meter runner explicitly sets
S1D_COST_SMALL_ONLY=1, registering only 1/10 ADD bulk measurements, not 50/200 or
50 merge-heavy cost cases. The generic cost suite's expected formulas now reflect
the current executor, but its full 50/200 cost acceptance run is deferred to S1D2B.
Historical S1D1 JSON is never overwritten by the current meter runner.

No full Flutter, Android/native H2, unrelated backend regression or S1D2B run.
S1C tests use the unchanged root firestore.rules and actual server protocol.
No rule or client escape hatch. No added listener, polling or frontend work.

## Remaining gate / scope

S1D2B must run the full private/family distinct and merge-heavy 50/200 measured
acceptance, verify the S1D1 targets against actual counts and close S1D. This phase
does not claim those measurements or S1D acceptance. H1/H2/S1B history preserved.
S1B COMPLETE / ACCEPTED; S1C COMPLETE LOCALLY; S1D1 PASS.
S1D COMPLETE: NO. Family Phase4B READY: NO.
Production data/config/deploy: NONE. Commit/push: NO. Stop after S1D2A.

## Exact changed-file inventory

- Production backend: functions/src/shopping/mutation-store.ts
- New focused test: functions/test/shopping-add-block.test.ts
- Updated measurement assertions/output isolation: functions/test/shopping-cost.test.ts
- New local-only runner: functions/scripts/shopping-add-block.cjs
- Current-meter runner comment: functions/scripts/shopping-cost.cjs
- Raw measurement: S1D2A_COST_MEASUREMENT.json
- Documentation: S1D2A_CHECKPOINT_2026-10-22.md, SHOPPING_MUTATION_SAFETY.md,
  S1B_PROGRESS_REPORT.md

S1D2A PASS. Next separate S1D2B only; not started. No automatic commit/push.
