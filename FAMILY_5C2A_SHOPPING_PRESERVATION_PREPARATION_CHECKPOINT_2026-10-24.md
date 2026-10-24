# Family Phase 5C2A — Shopping preservation preparation

Date: 2026-10-24
Baseline: `6be302830f6ca469d3ec4a0b817c36114d0b30b6` (committed Phase 5C1).
Initial worktree clean; initial diff check clean. Local emulator only. No deploy, commit or push.

## Boundary and states

The existing deterministic `dissolve_<sha256(ownerUid, householdId)>` operation progresses:

`PREPARED / READY` → `SNAPSHOT_SHOPPING / READY` → `VERIFY_SHOPPING / READY` → `PRESERVATION_COMMITTED / READY`.

`PRESERVATION_COMMITTED` plus non-null `preservationCommittedAt` is the durable point of no return. It is not DONE and does not dissolve the Family. The existing participant array, participant count/hash, creation identity and structural lock remain unchanged. Root schema version 2 minimally extends the version-1 preparation document; it does not create a parallel operation.

This implementation only exposes an authenticated, local-emulator-guarded bounded continuation callable, `prepareFamilyShoppingPreservation({householdId})`. The authenticated owner and deterministic operation control all routing. Owner/target overrides are rejected. `nextAt` remains null: no polling, timer or automatic dispatch into 5C2B. One explicit call executes at most one transaction/page step. Existing production Family gates remain disabled.

## Atomic source and target fence

Every step reads and validates the exact participant proof, member/reverse-index update times, user routing, fallback identities/creation times, Family identity and v3 `familyJoinCapacity.structuralOperationId`. Before commitment it also validates participant lifecycle and absence of deletion jobs. No Pro entitlement check can undo a committed operation.

The first transaction uses existing `advanceShoppingEpoch` independently on the Family source and owner's private fallback, writes each household's `operationId` to the dissolution ID, and records both fence proofs on the operation atomically. Each proof contains household ID, operation ID, epoch and acquisition timestamp. The two epochs are distinct. Reentry never advances either epoch again. A forced abort writes neither fence nor operation progression.

The existing shopping authority checks already reject households with non-null `operationId`; no shopping business logic or Firestore-rule exception was added. Earlier committed shopping effects are included. Accepted but unapplied old Family commands reject, old private commands reject, and new normal source/target authority remains blocked. No command is retargeted. Epoch expiry does not release the operation fence.

No target item snapshot is necessary: its identity/creation time, fence owner, epoch and expiry metadata are bound and revalidated. Target item contents are untouched.

## Exact paged source proof

Pages live under `familyOperations/{id}/shoppingPreservation/{deterministicPageId}`. Each page contains at most 10 entries, deterministic document-ID order, version, operation ID, source/target epochs, page index, chain hash and an empty results array. There is no 200-item truncation and no unbounded root result array.

Each entry binds source document ID, updateTime, full typed Firestore `sourceFingerprint`, normalized ADD payload, normalized-payload hash and deterministic transfer child ID. The existing 4B1A `sourceFingerprint`/`digest` implementation is reused, including typed numeric/map canonicalization. The ADD payload is validated/normalized by the existing S1A `parseRequest` (including unit conversion). Payload map-key order does not change its hash or validity.

Page/child IDs bind dissolution ID, both fence epochs, page index and (for children) within-page index/source ID. The chain seed also binds participant hash, source/target identities and `S1D_APPLY_ADD_BLOCK_V1`. Thus restart preserves identities; relevant source content/version changes alter the proof.

Snapshot cursor `{pageIndex,count,hash,lastId}` is committed atomically with each immutable page. Exhaustion records `{version:1,count,pages,hash}` and begins a separate bounded verification pass. Verification rereads each frozen source page and checks ID, updateTime, typed fingerprint, normalized payload, child identity and chain. At final exhaustion it checks count/hash, absence of further source/page entries and exact page-collection count before committing. All structural/fence validations run inside every transaction and retry. The 201-item case uses 21 pages, including a final one-item page.

Pages are backend-owned immutable preparation evidence. 5C2B must validate each page/proof before its first transfer effect; it must not rebuild missing/corrupt evidence from live source. Committed reentry validates root/structure/fences and returns without rewriting pages, epochs or committedAt; it is not a new full snapshot audit.

## Failure, concurrency and external events

Transactions serialize concurrent workers through operation/cursor and household reads. There is no lease expiry that can release the durable structural lock. Interrupted snapshot/verification resumes from durable cursor and hash. Lost final acknowledgement returns the same committed state.

Transient infrastructure failure leaves state for retry. Impossible participant/fence/snapshot/reservation evidence parks the operation with `status=OPERATOR`, `lastOutcome=preservationIntegrity`, no nextAt/lease, retaining existing fences/structural lock. It never silently reconstructs data or compensates quantities. Automatic abort/unfencing is intentionally absent: no data has moved before commitment, but manual repair must resolve the evidence before any later controlled release. Old epochs must never be restored.

Post-commit Pro loss does not roll back the point of no return. Participant account-deletion admission remains blocked by the existing structural guard. Self-leave is IN_PROGRESS; owner removal fails closed (IN_PROGRESS or existing fenced-owner integrity refusal). Pending JOIN continuation is IN_PROGRESS. No lifecycle/dissolution consequences are implemented.

Pending invite/reservation documents are read freshly, validated as pre-commit reservations, and left unchanged. Cancellation may safely remove a pre-commit reservation through existing logic; immutable participant membership does not change. A contradictory committed JOIN is OPERATOR. No reserved JOIN can activate through the held structural lock. Later dissolution finalization must close/revoke remaining invites and reservations; this phase performs no broad cleanup.

## Required 5C2B execution contract — not implemented

Only the committed snapshot's normalized ADD deltas may feed the accepted `ShoppingMutationStore.applyAddBlock` semantics, maximum 10 children. Preserve each deterministic child identity and durable result/target/revision/created evidence; validate dissolution authority and both fences in each execution transaction. Existing owner-private contents are merged into, never replaced. Compatible units use accepted conversions; incompatible units remain separate. Example: existing Milk 1000 ml plus snapshot 300 ml + 2 l later yields 3300 ml. No such merge runs in 5C2A.

After preservation starts, recovery is forward-only; no automatic subtraction from Family/owner quantities. Source cleanup, participant exit, active-household switches, fence/structural-lock release and dissolution finalization belong to later phases. No writable gap is introduced here.

## Validation

Final acceptance: **PASS**. Final Functions build/typecheck: PASS.
Final command: `node functions/scripts/emulator-tests.cjs --preservation-regression`.
**41 PASS / 0 FAIL / 0 SKIP**, harness exit 0; emulator shut down normally.

| Group | Passed |
| --- | ---: |
| New 5C2A suite (including 0/1/11/25/201, recovery, integrity and guards) | 26 |
| Existing 5C1 structural lock/JOIN races/cancellation | 6 |
| Existing 4B1A bounded snapshot/fence/fingerprint | 4 |
| Existing fingerprint encoding contract | 1 |
| Runtime export/discovery isolation | 2 |
| Existing shopping stale-context/operationId barrier | 2 |
| Total | 41 |

Final log: `C:/Users/gabor/AppData/Local/Temp/family-5c2a-final.log`.
Final diff check: PASS. No remaining required 5C2A targeted test is deferred.
The final regression was run once after the last production code change.

The initial focused run had 25 PASS / 1 FAIL: its membership-version corruption fixture wrote the same value, which the emulator treated as a no-op. The fixture now changes/restores the role to create a real new document version while retaining the same final content. No unexplained flaky failure was accepted. Payload-map order independence was also made explicit and covered before the final run.

No Flutter/native/Android/performance/transfer-execution scale or full historical backend suite is needed: shared shopping/fencing/fingerprint/structural primitives were reused without modification. All actual Firestore activity is guarded localhost with project `demo-kuktam-local`.

## Safety

No shopping-item writes/deletes/merge, membership writes, activeHouseholdId changes, private fallback deletion or structural lock release are performed by this phase. Only household fence metadata, dissolution root and bounded proof pages are written. Production data/access/deploy: none. Flutter and firestore.rules: unchanged. Phase 6 and 5C2B: not started.

## Final gates and files

Phase 4B COMPLETE; 5A PASS; 5B PASS; 5C1 PASS (committed baseline evidence).
5C2A PASS; 5C2B NOT STARTED; Phase 6 NOT STARTED. No blockers.
The next separate milestone is exact-once Family snapshot → owner-private semantic ADD execution, with concurrency/retry/journal validation. Later cleanup, member exits and final dissolution are not implemented here.

Changed files:
- `functions/src/households/dissolution-preservation.ts` (new bounded store/parser)
- `functions/src/households/dissolution-preservation-handler.ts` (new local guarded callable adapter)
- `functions/src/index.ts` (lazy export)
- `functions/test/dissolution-preservation.test.ts` (26 focused emulator cases)
- `functions/test/runtime.test.ts` (export isolation expectations)
- `functions/scripts/emulator-tests.cjs` (focused/final local selections)
- `FAMILY_JOIN_RESERVATION.md` (additive progress entry)
- this checkpoint.
