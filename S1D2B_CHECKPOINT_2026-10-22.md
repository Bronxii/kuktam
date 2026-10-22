# S1D2B - Full bulk cost validation and final S1D acceptance

Date: 2026-10-22. Baseline: `7719da0cdc78dfb565d509305fcdb624722df60a`
(`perf(shopping): batch ADD mutation processing`). Clean initial worktree and
initial diff-check. The default sandbox Git invocation incorrectly reported
not-a-worktree; the read-only check outside that sandbox confirmed the clean
actual C:/Users/gabor/kuktam checkout. No reset or unrelated work discarded.

S1D2B PASS. S1D COMPLETE / ACCEPTED locally. All four unchanged cost targets met.
No production/business implementation change was needed in S1D2B.

## Measurement method / scope

The S1D1 FirestoreMeter is unchanged. It delegates to the actual Admin SDK and
production ShoppingMutationStore/Maintenance implementations, counting only
explicit measurement scopes. R=documentGets+queryDocuments+emptyQueries; W counts
committed document writes, including ONE immutable command creation in primary
bulk tables. Fixture provisioning, initial context, assertion reads, teardown,
bootstrap and client/rules evaluation are excluded. Attempted writes, retries,
query returned documents and read categories remain separate. This is an
instrumented operation comparison, NOT Firebase billing/RPC/index-entry cost.

Historical S1D1_COST_BASELINE.json and S1D2A_COST_MEASUREMENT.json are unchanged.
New S1D2B_COST_MEASUREMENT.json embeds historical comparison rows, raw current
counts, retry/continuation records, acceptance targets/reduction arithmetic and
repeatability evidence. The measurement runner forces full mode, demo-kuktam-local
and loopback Firestore 127.0.0.1:8088, strips credential/target environment options,
and rejects target arguments. Each emulator run shuts down before the next starts.
The existing full emulator regression is separate, serial with measurement runs,
to avoid shared-fixture interference.

Architecture unchanged from S1D2A: max10 ordered ADD-only children per transaction,
fresh command/hash/auth/epoch on EVERY block and retry; final per-target write,
per-child durable result and revision; one household/receipt/work update per block.
Standalone and mixed operations retain the old path. Legacy/custom/oversized
canonical targets conservatively keep single-child granularity. No client/schema/
rules/gate change, whole-parent permission cache, polling or new listener.

## Distinct-product acceptance

| Context | Old R/W | Measured R/W | Target R/W | Blocks / attempts / retries | Result |
| --- | ---: | ---: | ---: | --- | --- |
| Private50 | 358/201 | 88/66 | <=88/66 | 5 / 9 / 0 | PASS |
| Private200 | 1438/801 | 358/261 | <=358/261 | 20 / 39 / 0 | PASS |
| Family50 | 458/201 | 98/66 | <=98/66 | 5 / 9 / 0 | PASS |
| Family200 | 1838/801 | 398/261 | <=398/261 | 20 / 39 / 0 | PASS |

Reduction, calculated as 100*(old-new)/old, rounded here to six decimals:
Private50 R75.418994% / W67.164179%; Private200 R75.104312% / W67.415730%;
Family50 R78.602620% / W67.164179%; Family200 R78.346028% / W67.415730%.
Artifact includes exact integer saved/baseline numerators/denominators as well as
computed percentages. Targets were NOT changed. Private/family1 and10 remain
7/5,16/14 and9/5,18/14 respectively.

Both complete measurement runs produced exactly identical 54 records, including
all categories, attempts, committed/attempted writes, progress and terminal state.
All four primary parents finished APPLIED, with 50/200 children and cursor50/200.

Every baseline measurement excludes retries (asserted zero). All children were
accepted as one parent, all results APPLIED, cursor equals child count, and parent
terminality follows every child. Distinct canonical rows and exact quantities are
checked, as are revision arrays 1..N and household sequence N. Family context gets
are asserted by the same meter; no cached authorization bypass is used.

## Operation decomposition

Let N=children, B=ceil(N/10), C=B-1 for default ten-child worker calls.
Private distinct R=N+6B+2C; family distinct R=N+8B+2C.
W=1+N+3B. Complexity O(N) document operations, lower constant than per-child auth.

Per block: one commandReceipt get, lifecycle, user, household, active membership,
reverse membership =6 gets private. Family adds private fallback household and
fallback membership =8. Epoch/owner/role are checked using already-read snapshots.
Private RESERVED JOIN can still require its extra operation check; it is not the
normal private fixture. Gate admission/ensure-context costs are separate, unchanged.

Per distinct normalized key: one transactional candidate query (limit3). Normal
new key gives one empty-query R; normal merge gives one returned-document R.
Same key within a block shares candidate lookup and working state. No separate
item-document get is hidden. Ambiguity still fails closed.

Per continuation: Maintenance queries due work (one returned document here), then
continueWork makes a read-only command receipt transaction, THEN the next block
reads its own command/auth/candidates. Added overhead =2 R, 0 W. Thus 50 children
have four continuations =8 R; 200 have nineteen =38 R, unchanged from S1D1.
Total transaction attempts include read-only cleanup checks: 9 for 50 (5 blocks
+4 checks), 39 for 200 (20+19), with zero retries in baseline measurements.

Writes: request1; distinct canonical N; household B; command receipt/cursor/results
B; work scheduling B. Child results remain an N-entry array, not removed evidence.
50: 1+50+5+5+5=66 W. 200: 1+200+20+20+20=261 W. Previously each child repeated
all three metadata writes (4N+1 total). Repeated targets further coalesce canonical
writes within a block, while retaining each child's target/revision/created proof.
Family/private delta =2 gets per block: +10 R at50, +40 R at200; same writes.

## Merge / partial / recovery evidence

| Fixture | Private R/W | Family R/W | Result |
| --- | ---: | ---: | --- |
| Original five-product merge50 | 63/41 | 73/41 | PASS |
| Semantic units merge50 (three keys) | 53/31 | 63/31 | PASS |
| Semantic units merge200 (three keys) | 218/121 | 258/121 | PASS |
| Semantic units25 (10/10/5) | 31/19 | 37/19 | PASS |
| Distinct25 (10/10/5) | 47/35 | not separately required | PASS |

Merge costs are lower because per-block candidate queries and canonical writes
are shared by repeated keys; child evidence remains per child.

Forced ten-child retry: R32, two transaction attempts/one retry, attempted
processing W26, committed processing W13. Including admission: attempted W27,
committed W14. Normal identical ten-child block R16/W14 including admission.
Lifecycle re-read twice; ten items quantity1, receipts/revisions1..10 exactly once.
The separate meter calibration also forces one retry; baseline rows have none.

Interruption: first30 children R48/W39 processing; resumed remaining20 R34/W26;
request adds1W. Final fifty-child effect exact, no child identity/revision change.
Terminal replay R1/W0. These are direct worker/continueWork measurements, with
scheduler-overhead differences explained below, not replacement acceptance totals.
Auth/epoch invalidation after30: terminalization R6/W2 (epoch), R6/W2 (missing family
member), R2/W2 (lifecycle). No later child applied. Lost ACK recovery and external
concurrent ADD PASS; no premature terminal parent, stuck parent, duplicate logical
effect or lost update in the tested paths.

Semantic fixture repeats a five-child pattern: Milk300ml, Milk2l, Milk500ml,
Milk1db, Flour2kg. Production normalization is used. Each block sees repeated milk,
and later blocks merge the same actual target. Three final rows: milk/ml, milk/db,
flour/g. At50: milk28000ml, milk10db, flour20000g. At200: milk112000ml,
milk40db, flour80000g. Result created flags/target identity are checked per child,
with exactly one creation per logical key, no receipt loss and revisions1..N.
The existing five-product 50-child merge characterization remains separately run.

The interruption case processes 30/50 children, constructs a fresh worker and uses
continueWork twice for the remaining20. Prefix receipts compare byte-for-value;
original ID/payload remain. This direct recovery measurement deliberately excludes
scheduler queries and is NOT substituted into the primary budget. Terminal replay
reads the existing receipt and writes nothing. S1D2A lost-ACK regression also runs
unchanged, proving committed work resumes rather than re-adds.

Auth/epoch tests revoke family membership, invalidate lifecycle or advance epoch
after30/50 committed children. Previously committed prefix survives; next block
terminalizes the remaining20 with current rejection semantics. No canonical
mutation after revocation. External concurrent ADD starts through an SDK callback
barrier alongside the next block of a 50-child parent; both use real transactions.
Final17000ml, one row, all51 successful revisions exactly once. No timing sleeps.

## Regression and safety

- Full backend unit: 237 PASS / 0 FAIL / 0 SKIP; includes 15 S1A contract tests.
- Full Firebase emulator: 662 PASS / 0 FAIL / 0 SKIP, exit0, 667677.5849ms.
  Includes 45 shopping executor and 59 shopping/household rules tests (26+33),
  account deletion, billing, household/family CREATE/invite/Phase4A and runtime.
- Acceptance round1: 75 PASS / 0 FAIL / 0 SKIP (27 complete S1D2A tests +48
  measurement/scale tests). Round2: same48 measurement/scale tests PASS again.
  Final harness exit0; 54/54 measurement records identical.
- Functions build/typecheck PASS. Final git diff --check PASS, including separate
  whitespace inspection of new files. No production fix or flaky test exclusion.

Commands (functions): npm run test:unit; node scripts/emulator-tests.cjs;
npm run build; node scripts/shopping-cost-acceptance.cjs.
Logs: C:/Users/gabor/AppData/Local/Temp/s1d2b-unit.log,
s1d2b-full-emulator.log, s1d2b-cost.log. All emulators stopped cleanly.
No test failure was ignored or excluded. The new scale cases supplement existing
S1D2A tests; its matrix was not redesigned.

Full backend unit and full emulator suites run once against unchanged final
business code. New measurement/scenario tests and complete S1D2A suite run via the
acceptance runner, then measurement repeats independently. No full Flutter,
Android/native H2 or process-death matrices: client business code did not change.
Quick source recheck: only two production shoppingItems references, both read-only
(get/server absence helper and canonical snapshots). Direct canonical writes0.
Firestore rules and their hardened S1C boundary unchanged; real server protocol
and denial tests are included in full emulator regression. No production project,
data, credentials, deploy, App Check, Play or Family runtime gate changes.

## Limitations / next gate

These are zero-contention baseline budgets, not production billing guarantees.
Retry cases repeat a whole block's attempted reads/writes; only committed writes
have logical effect. Extra scheduler jobs, duplicate deliveries, future index
configuration and large/custom legacy targets can have higher counts. Conservative
legacy fallback remains intentional. Mixed parents and standalone CRUD were not
optimized; their measured old costs remain green. No safety invariant was relaxed
or target moved to obtain a passing result.

S1B COMPLETE / ACCEPTED. S1C COMPLETE LOCALLY. S1D1 PASS. S1D2A PASS.
S1D2B PASS. S1D COMPLETE / ACCEPTED. Blockers: NONE.
Family Phase4B READY FOR DEVELOPMENT: YES; NOT STARTED by this task.
Production Family rollout: NO. Production access/changes/deploy: NONE.
Commit/push: NO. Next separate phase: Family Phase4B JOIN transfer / activation.

## Exact changed files

- functions/test/shopping-cost.test.ts (measurement/scale assertions only)
- functions/scripts/shopping-cost.cjs (force full measurement mode)
- functions/scripts/shopping-cost-acceptance.cjs (two local runs and comparison)
- S1D2B_COST_MEASUREMENT.json (54 records, repeated-run proof, historical comparisons)
- S1D2B_CHECKPOINT_2026-10-22.md
- SHOPPING_MUTATION_SAFETY.md
- S1B_PROGRESS_REPORT.md

Unchanged: functions/src, lib, firestore.rules, Firebase configuration, meter
implementation and both historical S1D1/S1D2A JSON/checkpoint artifacts. STOP.
