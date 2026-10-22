# S1D1 - Bulk cost baseline, hotspot audit and S1D2 design

Date: 2026-10-22. Baseline: `6891ceabeef90d8dd4efc34bcbcb5b18d9bbfa8d`
(`security(shopping): harden canonical write rules`). Starting status and diff-check
clean. S1B accepted; S1C complete LOCALLY. This milestone measures/designs only.
No production business source, Dart, rules, schema, runtime gate or deployment
configuration changes. No S1D2 implementation or Family Phase 4B work.

## Measurement method and limitations

`functions/test/firestore-meter.ts` wraps the actual Admin Firestore instance and
transaction callbacks using local proxies, delegates to the real SDK, and counts
only inside an explicit `measure` scope. No fake executor, prototype patch, SDK
replacement or production hook. `ShoppingMutationStore.process`, `continueWork`
and `Maintenance.run({only:['shopping']})` are production implementations.

Local runner: `npm run build`, then `node scripts/shopping-cost.cjs` in functions.
It rejects arguments/target overrides, strips credential environment variables,
requires demo-kuktam-local, starts Firestore on 127.0.0.1:8088 using the existing
firebase.emulators.json/root firestore.rules, and runs cost + contract tests.
The test guard rejects every non-demo/non-loopback target before creating Admin.
No monetary pricing or web research is used.

MEASURED fields in `S1D1_COST_BASELINE.json`:
- `documentGets`: explicit document snapshot requests, INCLUDING missing docs;
  `missingDocuments` separately records absence (private reverse-index absence).
- `queryCalls`, `queryDocuments`, `emptyQueries`, `maxQueryDocuments`: actual SDK
  query invocations/results; query result docs are NOT counted again as doc gets.
- `readCategories`: commandReceipt, lifecycle, user, household, membership,
  reverseMembership, fallbackHousehold/fallbackMembership and item.
- `queryCategories`: itemCandidates and dueWork. Query collection metadata is
  read from the pinned SDK; tests assert these categories so SDK drift fails.
- `attemptedWrites` versus `committedWrites`: SDK document write operations.
  Transaction writes count as committed only after successful runTransaction;
  discarded attempts never inflate committed writes. Categories separate item,
  household sequence, commandReceipt and work.
- transaction calls, callback attempts, retries and committed read-only checks.

DERIVED comparison unit R (`readEquivalent`) = documentGets + queryDocuments +
emptyQueries. It applies a one-read floor for each empty query. This is NOT a
Firebase billing measurement. SDK calls are not a count of RPCs; getAll can serve
multiple documents in one call, retries/internal RPCs/index scans and repeated
reads of the same document may have billing behavior this meter does not observe.
Missing-doc requests, query floors and duplicate snapshot retrievals are explicit,
not hidden. No index-entry, network-byte, pricing or billed-unit claim is made.

Primary tables report server processing R, including required due-work recovery,
and W including the ONE immutable command creation. Creation is measured
separately through Admin create of the same stored envelope, representing one
document write; this is not a claim to measure client rules evaluation. Fixture
setup, provisioning, initial context issuance, clock setup, assertion reads,
teardown, emulator bootstrap, client canonical/receipt listeners and rule-dependent
reads are excluded. Context issuance and authenticated server submit helper are
separately measured and must NOT be added when not actually invoked.

Each scenario uses a reset demo database and fixed injected clock; contexts are
preinitialized before resetting counters. All baselines require zero transaction
retries; unexpected retries fail the test instead of silently inflating baseline.
A calibration deliberately raises one ABORTED result after staging a write: real
SDK retries once, 2 document reads/2 attempted writes/1 committed write, final value
correct. getAll, missing-doc, populated/empty query and counter reset also verified.
Repeated whole-run measurements are compared by scenario, excluding no counters.

## Measured single-operation baseline

DG = document gets, Q = query calls, QD = query documents, EQ = empty queries.
W includes request creation; processor alone is W-1. EDIT here renames to an absent
logical identity. CHECK is explicit SET_CHECKED (same path for false/true).

| Context / operation | DG | Q | QD | EQ | R | W |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Private ADD new | 6 | 1 | 0 | 1 | 7 | 5 |
| Private ADD merge | 6 | 1 | 1 | 0 | 7 | 5 |
| Private EDIT | 7 | 1 | 0 | 1 | 8 | 5 |
| Private CHECK | 7 | 0 | 0 | 0 | 7 | 5 |
| Private DELETE | 7 | 0 | 0 | 0 | 7 | 5 |
| Family ADD new | 8 | 1 | 0 | 1 | 9 | 5 |
| Family ADD merge | 8 | 1 | 1 | 0 | 9 | 5 |
| Family EDIT | 9 | 1 | 0 | 1 | 10 | 5 |
| Family CHECK | 9 | 0 | 0 | 0 | 9 | 5 |
| Family DELETE | 9 | 0 | 0 | 0 | 9 | 5 |

EDIT keeping its logical identity still queries and returns the source after its
explicit target get: R remains 8/10, W 5. EDIT merging into a DIFFERENT item adds
one source deletion: R 8/10, W 6. No revision read is proposed for removal.
ADD merge fixture verifies trim/lowercase and kg->g: 1000g + 2kg = 3000g.
The same production contract converts l->ml and keeps db/incompatible units apart.

## Measured bulk / operational import examples

All-distinct ADDs, one parent, default process bound 10; actual maintenance resumes
remaining children. C = number of continuation rounds. No duplicate trigger,
contention retry or eventual retention cleanup in these primary totals.

| Context / children | DG | candidate Q | due Q/QD | empty candidate Q | C | R | W |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Private 1 | 6 | 1 | 0 | 1 | 0 | 7 | 5 |
| Private 10 | 60 | 10 | 0 | 10 | 0 | 70 | 41 |
| Private 50 | 304 | 50 | 4 | 50 | 4 | 358 | 201 |
| Private 200 | 1219 | 200 | 19 | 200 | 19 | 1438 | 801 |
| Family 1 | 8 | 1 | 0 | 1 | 0 | 9 | 5 |
| Family 10 | 80 | 10 | 0 | 10 | 0 | 90 | 41 |
| Family 50 | 404 | 50 | 4 | 50 | 4 | 458 | 201 |
| Family 200 | 1619 | 200 | 19 | 200 | 19 | 1838 | 801 |

These are also the 10/50/200-item import operation examples, not prices.
Child core alone at 200 is 1400/1800 R +800 W; one command creation adds 1 W,
and 19 maintenance continuations add 38 R. Earlier estimates omitted recovery.

50-child merge-heavy fixture uses five products repeated ten times: 5 empty
candidate queries, 45 returned candidates, 4 due-work results, final five rows
quantity 10 each. R/W equal distinct 50: 358/201 private, 458/201 family.
The metric hides the new-versus-merge difference; raw QD/EQ fields preserve it.

Mixed parent: ADD new, ADD merge, EDIT rename, CHECK, DELETE on distinct seeded
targets. Private: DG33/Q3/QD1/EQ2 -> R36/W21; family: DG43/Q3/QD1/EQ2 -> R46/W21.
Successful siblings/receipt verified. Context cost is still paid five times.

ADD duplicate candidates: query is EXACT normalized name + normalized unit,
`limit(3)`; 2, 3 and 4 existing equivalent documents return 2, 3 and 3 respectively.
All fail closed without canonical writes. Private R8/9/9, W3 (one request plus
receipt/work); no hidden unbounded candidate scan. Four docs are deliberately
seeded only to prove the query bound, never treated as valid canonical state.

Separate measured overheads:
- Warm ensureContext: private 7 DG / family 9 DG, 0 W. User root is requested
  twice (initial pointer discovery and authority helper); gate read once.
- Cold ensureContext: private R8 / family R10, 1 household write, including the
  bounded maximum-revision query. Not a per-child processing expense.
- Authenticated submit helper: private 7 DG / family 9 DG, 1 request write.
  Flutter uses rules-mediated creation instead, so do NOT add this helper cost.
- Terminal duplicate process delivery: 1 command get, 0 W; not reapplication.
- Eventual expiry cleanup through maintenance: R2/W2 (due work + receipt read,
  delete receipt/work). An idle due query returns 0 docs but has derived R1.
  Scheduler cadence/other jobs/duplicate deliveries are outside primary totals.

## Fixed/per-child costs and transaction map

One child = one runTransaction callback with ALL reads before writes:
1. Command get; terminal short-circuit, parse/hash/cursor validation.
2. shoppingAuthority reads lifecycle, user, household, member, reverse index.
3. Family additionally reads private fallback household and fallback member.
4. Epoch/expiry is checked from the ALREADY READ household, no extra get.
5. Non-ADD source item get/revision check; ADD/EDIT bounded candidate query.
6. Canonical effect + household sequence + receipt cursor/results + work written
   atomically. Every successful child has 4 writes (EDIT merge has 5).

A parent is NOT one transaction. process default 10 (explicit max 20) loops child
transactions. continueWork first makes a separate read-only receipt transaction,
then process. Maintenance first queries up to five due work rows. A single-parent
baseline thus has C=ceil(N/10)-1 extra queries + C receipt checks, and N+C
transactions. Context is never prefetched outside child transactions today.

Fixed per parent: one command creation; optional context/admission costs above.
Per authorization: 5 private or 7 family document requests PER child. UID itself
is local input/validation, not another Firestore read. Private also reads the
usually absent reverse index; family does NOT add a second reverse-index read.
Family +2 is precisely fallbackHousehold + fallbackMembership. Owner identity,
role, state and epoch use already-read documents. RESERVED private JOIN adds its
operation-document check; it is not the normal private baseline.

Per ADD candidate: one query, 0/1 valid returned row, max3 on corrupt ambiguity.
Per target: source get for EDIT/CHECK/DELETE; EDIT has an additional query.
Per retry: repeated callback reads/queries and staged writes; only winning writes
commit. Calibration separates this; production contention rate was NOT estimated.
All measured document-operation growth is O(N), not O(N squared). CPU/network
payload work can be O(N squared): parseRequest validates all N children per child,
and growing results/payload are repeatedly read/written. This is source-derived,
NOT a measured CPU or byte benchmark. N is capped at 200.

## Freshness and unsafe caching decisions

| Value | Fresh in committing child transaction today? | Safe for whole-parent cache? | Why / permitted sharing |
| --- | --- | --- | --- |
| Immutable actor/household/epoch value/payload | Identity checked each attempt | Identity only, not permission | Keep exact hash/UID/path, never rebind; command cursor/results remain transactional |
| Lifecycle state/generation | YES | NO | DELETING must conflict with pending mutation |
| User active household/migration/family pointers | YES | NO | Routing can switch mid-parent |
| Household state/owner/epoch/expiry/sequence | YES | NO | Fence/dissolve/activation and concurrent list writers |
| Active membership role/existence | YES | NO | Removal/role change must revoke authority |
| Reverse membership | YES | NO | ACTIVE/RESERVED/operation/household changes |
| Family private fallback/member | YES | NO | Current eligibility includes both records |
| RESERVED JOIN operation | YES where applicable | NO | Operation state/actor/source must still match |
| Runtime gate | NO during accepted processing | Existing admission policy only | Read during ensure/submit/rules; accepted work intentionally finishes after gate OFF |
| Item revision/current quantity | YES | NO | Concurrent EDIT/DELETE/CHECK and semantic ADD |
| Candidate query result/absence | YES | NO | Another client may create/merge/rename same product |

All mutable authority can be shared ONLY by children in the SAME atomic transaction
and recomputed on EVERY retry. A household epoch is NOT a universal authorization
version: current lifecycle/user/member/index writers do not all atomically advance
it. Prefetch-once-per-parent plus epoch-only recheck is therefore REJECTED.
A new universal auth guard would require auditing/changing all invalidators; that
is a broad redesign and is NOT the recommended S1D2 path.

## Recommended S1D2 design (NOT implemented)

Optimize only bounded all-ADD chunks, at most min(10, caller maxSteps, remaining
contiguous ADD children). Keep mixed/revision operations on the current executor
initially. This avoids needing a general EDIT/DELETE virtual-query engine.

For each chunk, inside ONE transaction:
1. Read command/cursor/hash; validate full immutable payload and terminal state.
2. Read the FULL existing authority set once, check epoch/expiry. Never import
   permission from an earlier transaction or parent-level cached context.
3. Read normalized candidate queries for all chunk keys BEFORE any write.
   Retain the limit3 ambiguity rule and current household sequence contention.
4. Simulate ADDs in array order using transaction-local destinations/quantities;
   repeated keys use the earlier simulated result, not a second new row. Preserve
   checked/createdAt/unknown fields, unit rules, arithmetic limits and created flag.
   Assign the same monotonically increasing revision for every successful child.
5. Commit final canonical state, final household sequence, EVERY child result in
   order, cursor/appliedCount/status and one durable work entry atomically.
   No external side effect or UI acknowledgement inside the retrying callback.
6. Next chunk re-reads ALL authority. Explicit maxSteps=1/3 still limits work;
   interruption is safe at chunk boundaries. No need to transact all 200 children.

Membership removal, owner invalidation, DELETING, epoch/family state changes and
concurrent item edits conflict with the read set: the whole attempt retries or
rejects before effects. Every committed child in the chunk shares one atomic
serialization point; revocation cannot interleave inside that commit. Previously
committed chunks remain durable. A retry must not duplicate contributions or IDs.
Terminal per-child failure still preserves the valid preceding prefix, marks the
same remaining children rejected as current policy, and writes the receipt and
only those valid effects together. No phantom APPLIED result from failed attempt.

Mixed EDIT/DELETE/CHECK stay unchanged because prefetched limit3 queries can become
incomplete after virtual deletes/renames expose a fourth candidate. Do not solve
that by weakening ambiguity checks. ADD-only simulation does not remove candidates.
This is a bounded internal transaction change, not a client/schema/rules redesign.

| Candidate | Current cost | Expected saving | Risk / complexity / required recheck |
| --- | --- | --- | --- |
| ADD chunk context sharing | (6/8 command+authority reads)*N | (6/8)*(N-ceil(N/10)) R | Medium/high implementation; full authority fresh each chunk/attempt, atomic receipts and sequential semantics |
| Coalesce sequence/receipt/work writes within chunk | 3N metadata writes | 3*(N-ceil(N/10)) W | Medium; retain every child result/revision/hash and durable continuation |
| Cache immutable parse within invocation | N payload parses | CPU only, no promised R/W saving | Low/medium; exact payload/hash and UID binding, invalidate on mismatch; optional later |
| Deduplicate warm ensure user get | 2 user SDK requests/context issuance | At most 1 SDK read/context, not per child | Low, but no meaningful bulk saving; defer |
| Cache auth for parent / epoch-only guard | 5/7 reads per child | Would appear large | UNSAFE with existing invalidators; rejected |
| Prefetch targets outside transaction | 1+ per child | Apparent savings | UNSAFE stale revision/absent-target race; rejected |
| Drop receipt/work evidence or skip revisions | 2+ writes per child | Apparent savings | UNSAFE replay/recovery; rejected |
| Runtime gate per-child removal | 0 reads today | 0 | Not a hotspot; do not alter gate policy |

## Derived S1D2 acceptance budgets

These are DESIGN targets, not measured optimized results. For distinct, valid
ADD-only parents without retries, chunk K=10, B=ceil(N/10), C=B-1:
R target private=N+6B+2C; family=N+8B+2C.
W target <=1+N+3B (request included). Repeated keys may use fewer reads/writes;
never rely on that to pass the distinct-product budget.

| Context | Measured current R/W | Target upper bound R/W |
| --- | ---: | ---: |
| Private 50 | 358 / 201 | 88 / 66 |
| Private 200 | 1438 / 801 | 358 / 261 |
| Family 50 | 458 / 201 | 98 / 66 |
| Family 200 | 1838 / 801 | 398 / 261 |

Approximately 75-79% reduction in R and 67% in W follows from actual repeated
context/metadata counts, not an arbitrary percentage target. At 10: private
70/41 -> <=16/14; family90/41 -> <=18/14. Singles and mixed revision paths must
not regress. Retention cleanup remains separate R2/W2. Higher contention can
retry a larger chunk, so report retry attempts/read amplification separately;
no absolute production billing/savings guarantee is made. Chunk planning must
also respect SDK transaction size/duration limits and large legacy item fields;
reduce to a smaller chunk or the existing one-child path under bounded size
constraints, never skip guards or invent a replacement mutation ID. Budgets above
apply to the specified representative small-item, no-contention fixtures.

## Exact S1D2 validation and integration boundary

1. Re-run this meter on original and optimized executor; distinct/merge 1/10/50/200
   private/family, singles/mixed, raw DG/Q/QD/EQ/W categories, zero-retry budgets.
2. S1A shopping-contract unit suite; Functions build and diff-check.
3. S1A shopping-mutation emulator suite including concurrent same-key ADD, both
   processing orders, incompatible units, duplicate delivery/hash conflicts.
4. Stale EDIT/DELETE/CHECK, ABA delete/recreate and legacy revision normalization.
5. Boundaries: maxSteps1/3/10/20; ADD chunks near 200; mixed fallback; repeated keys;
   valid prefix followed by overflow/duplicate ambiguity; full result/cursor parity;
   large-item size-bound fallback to smaller chunks without losing accepted work.
6. Fail before commit, after commit before ACK, partial parent/new worker resume;
   same IDs, exact quantities, each child revision/created flag, no orphan work.
7. Deterministic conflict barriers: membership/index/fallback/owner change,
   lifecycle DELETING, user household switch, epoch advance, DISSOLVING; ensure
   whole attempt retries/rejects and earlier committed chunks remain unchanged.
8. Concurrent other-client ADD/EDIT/DELETE to candidates while chunk reads/commits;
   measure retries separately and verify no lost contribution or duplicate row.
9. S1C shopping-rules/household-rules integration: commands work, canonical writes
   denied; actual Admin ADD/merge/CRUD/clear remain valid. Rules are not relaxed.
10. Retention/replay and due-work bounds, scheduler isolation, receipt expiry;
    existing family/private/RESERVED-authority and CREATE epoch fence regressions.

No default full Flutter, Android build or historical native H2 rerun is needed
for a backend-only S1D2. If client contract/Dart behavior changes, stop and review
scope rather than silently expanding. Family Phase4B later must retain its epoch
fence and transactional authority/sequence writes. No caching across JOIN transfer,
activation or household switch; no new Family lifecycle implementation here.
S1C remains hard-deny canonical client writes, and the client remains immutable
command -> trusted backend -> canonical state. No polling or observer changes.

## Validation / final result

S1D1 PASS. Final run: 50 PASS, 0 FAIL, 0 SKIP, exit 0 (105515ms):
35 measurement/calibration tests +15 existing shopping-contract unit tests.
40 measurement records retained in S1D1_COST_BASELINE.json. All 34 records shared
with the first run are identical, including category counts, attempts, writes and
read equivalents. First run: 44 PASS (29 measurement +15 contract); final run
adds cold context and same-identity/merge EDIT coverage, not a production change.
Business baseline retries: 0; deliberate calibration retry: exactly 1.
Functions build PASS. Diff-check PASS; new-file whitespace checked too.

Commands: `npm run build`; `node scripts/shopping-cost.cjs` from functions.
Logs: C:/Users/gabor/AppData/Local/Temp/s1d1-build.log, s1d1-cost.log,
s1d1-cost-final.log; first-run JSON comparison snapshot s1d1-first-baseline.json.
No full Flutter/native/Android/unrelated backend suite run. Emulators shut down.
No production source/rules/config difference from baseline. No blockers.

Files: functions/test/firestore-meter.ts; functions/test/shopping-cost.test.ts;
functions/scripts/shopping-cost.cjs; S1D1_COST_BASELINE.json;
S1D1_CHECKPOINT_2026-10-22.md; SHOPPING_MUTATION_SAFETY.md; S1B_PROGRESS_REPORT.md.

S1B COMPLETE / ACCEPTED. S1C COMPLETE LOCALLY. S1D1 PASS.
S1D COMPLETE: NO. Family Phase4B READY: NO.
Production changes/deploy/commit/push: NONE. Next separate S1D2 implementation
and measured validation. S1D2 has NOT started. STOP.
