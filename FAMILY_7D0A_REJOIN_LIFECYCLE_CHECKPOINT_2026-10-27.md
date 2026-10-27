# FAMILY 7D0A — REAL REJOIN LIFECYCLE

Date: 2026-10-27. Backend-only local checkpoint.
Result: **PASS — backend lifecycle**. 8/8 new rejoin tests and 150 distinct affected regression cases PASS after the focused corrections described below. Functions build PASS.

## Previous blocker and identity

`familyOperations/join_<sha256(uid)>` was both the current JOIN slot and its retained history. `FamilyJoinStore.reserve` treated a distinct invitation arriving after DONE as an in-progress conflict. Replacing/deleting that document would destroy history and could make old requests act on a newer membership.

The first JOIN retains the legacy UID-derived ID. Every later distinct invite uses `join_<sha256(JSON.stringify([uid, inviteId]))>`, where inviteId is the existing SHA-256 invitation identity, not the raw token. The operation schema remains 1/2; parsers accept the legacy or exact invite-bound identity. Old operation documents and their journals are not overwritten or deleted.

`users/{uid}.familyJoinBinding = {operationId, inviteId}` is server-owned current-generation metadata. It is written atomically with the reservation, invite claim, reverse membership index and capacity claim. Absence resolves to the legacy path, permitting existing historical/active accounts without migration. A present malformed, missing-operation or contradictory binding fails safely. The membership/index schema is unchanged; ACTIVE is still verified through the current reverse index, household membership, user routing and the referenced ACTIVE/DONE JOIN plus USED invitation.

Same invite retry uses the same operation. An ACTIVE/DONE retry is returned only while that generation is still current and ACTIVE. After membership ends the USED invite cannot reserve again. A new invite can start only after the previous operation is terminal, the reverse membership index is absent, its old household member record is absent, and existing standalone/account/owner/Family/invite/capacity/structural checks pass. An in-progress or OPERATOR generation cannot be displaced. A cancelled generation also retains its audit; the next invitation uses a new operation. Later C works by the same rule.

## Exit and stale requests

Self-leave and owner-remove resolve the server-owned current JOIN instead of the UID-only historical slot. The existing atomic exit primitive still performs membership/index removal, private routing, private epoch advancement and capacity handling. Request inviteId must match the current JOIN and its USED invitation. After B is current, A leave/remove returns STALE_MEMBERSHIP, including a previously successful A receipt when a later membership/reservation exists. Without a new membership, receipt retry remains idempotent DONE. Receipt identity remains invite-bound.

The existing member account-deletion admission now resolves this same generation and accepts its exact operation identity in intent validation; it continues using the existing exit/deletion engines. No deletion workflow was added.

## Shopping safety and unchanged transfer semantics

A shared shopping context carries household and epoch, not membership generation. Merely leaving and returning to the same Family would revive an unprocessed A-era command. At a later generation's atomic activation the existing `advanceShoppingEpoch` primitive rotates the Family context. This also invalidates other participants' pending old-context commands; fresh normal contexts work through the existing mechanism. It changes no item, quantity, revision or household sequence. DONE retries do not rotate again. First-generation activation retains its existing valid-epoch behavior.

ADD normalization/merge, DELETE source disposition, exact snapshot consent even for an empty DELETE list, source fencing, journals and COMMITTED_TRANSFER forward-only processing use the existing engine unchanged. Epoch rotation is at activation, after transfer/cleanup evidence validation. There is no new shopping mutation protocol or merge engine.

## Local proof

Real A → self-leave/remove → B → exit → C is executed through actual reservation, preparation, snapshot, transfer, cleanup and activation for both ADD and DELETE. A is never replaced by fabricated B membership data. The focused cases also cover legacy missing-pointer data and a later different Family, duplicate/competing B admission, stale A racing B, discarded acknowledgement/retry, restart after committed DELETE, empty-list mandatory consent, immutable A history, current B exits, capacity, stale accepted shopping command rejection, corrupt binding and surviving prior membership, and member-deletion admission resolving B.

Admission acknowledgement loss is modelled by discarding a committed response and retrying the same identity. The new B DELETE test injects a thrown acknowledgement after its commit transaction, then retries; existing regressions also inject lost acknowledgement at activation/exit. No real network or production Auth operation is used.

## Compatibility and exact next boundary

Historical pre-change JOIN documents coexist without migration. Used invitations remain USED; reservations are not recycled. One-Family, capacity eight, runtime gates, structural serialization, Pro ownership and account lifecycle protections remain authoritative.

The current Flutter 7C repository validates only the legacy UID-derived JOIN ID. It has not been changed in this backend-only phase. Before user-facing rejoin is enabled, a separately scoped Flutter contract update must accept the new server-returned generation safely. First JOIN retains its old ID. This checkpoint does not claim Flutter rejoin support.

7D0 read-contract work is NOT implemented or started. It should resolve current membership binding using this current-generation metadata, with exact current membership/operation/invite validation, never historical guesses. 7D UI remains blocked on that read contract. 7E is not started.

No Flutter changes, Firestore rules changes, production access, deploy, commit or push. Earlier Phase 4B/5/6 and 7A/7B/7C gates are supplied input guarantees, not a historical full regression claim.

## Files changed

- functions/src/households/family-join.ts
- functions/src/households/join-transfer.ts
- functions/src/households/member-leave.ts
- functions/src/households/member-account-deletion.ts
- functions/test/family-rejoin.test.ts
- functions/test/family-join.test.ts
- functions/test/family-join-foundation.test.ts
- functions/test/family-member-leave.test.ts
- functions/test/family-owner-remove.test.ts
- functions/scripts/emulator-tests.cjs
- FAMILY_7D0A_REJOIN_LIFECYCLE_CHECKPOINT_2026-10-27.md

## Final validation evidence

- `npm --prefix functions run build`: PASS. Later builds only recompiled corrected/strengthened tests; no subsequent backend implementation change.
- `node functions/scripts/emulator-tests.cjs --rejoin-regression`: first group 136 cases, 135 PASS, one historical test assumed deletion could begin while RESERVED. That expectation predated Phase 6; now it explicitly requires JOIN_COMMITTED_IN_PROGRESS with no deletion job/marker. Its focused recheck passed. The command's second group did not run after that failure.
- `node functions/scripts/emulator-tests.cjs --rejoin-boundary`: 32 selected cases, 31 PASS; includes the corrected admission test, all eight latest 7D0A tests (including injected B commit ACK loss and ACTIVE A rejecting B), plus the previously unrun 4B boundaries. A second historical lifecycle test assumed direct deletion admission despite the current Family guard. It now verifies the guard, then injects a trusted lifecycle marker in the emulator to test precommit abort safety.
- Only that last corrected lifecycle case was re-run using the same credential-isolated local runner, selected by `^precommit lifecycle `: 1/1 PASS. Temporary runner removed.
- Across the final versions: **158 distinct passing cases = 8 rejoin + 150 affected regressions**. No unresolved failure. Passing broad groups were not needlessly repeated. No historical full regression or transfer-scale matrix ran.
- Runtime: demo-kuktam-local Firestore emulator on loopback only. No Flutter tests, Android build, rule changes or production access.

## Final gates and handoff

7D0A: PASS. Self-leave and owner-remove A→B, same/different Family, B→C, current B exit, duplicate/concurrent B, lost ACK, stale A leave/remove and shopping rejection: PASS. A history preserved and A remains non-reusable. Capacity and first-JOIN compatibility remain intact.

7D0: prerequisite resolved; read-contract implementation NOT STARTED here.
7D: blocked until 7D0 PASS.
7E: NOT STARTED.
Commit: NO. Push: NO. Deploy: NO.

No backend blocker remains for this milestone. The separate Flutter generation-ID compatibility work and 7D0 authoritative binding read must precede user-facing rejoin/member management rollout. Do not start either automatically.
