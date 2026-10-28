# FAMILY 7D0 — ACTIVE MEMBERSHIP BINDING READ CONTRACT

Checkpoint filename date: 2026-10-27. Implementation/validation completed: 2026-10-28 (Europe/Budapest).
Result: **PASS**. Input: supplied Phase 7D0A PASS checkpoint; no routine Git/baseline/log/commit checks.

## Authoritative current membership invariant

The server-owned `users/{uid}.familyJoinBinding = {operationId, inviteId}` points to the current JOIN generation. The user must currently route to the caller's ACTIVE Family; `familyMemberships/{uid}` must be ACTIVE/member in that same Family; the household member row must be a member. The referenced JOIN must be ACTIVE/DONE with the exact actor, Family, owner and private source identity. Its invitation must be USED by that actor, attached to that operation and Family/owner.

The read additionally requires the ACTIVE reverse-index document updateTime to equal the DONE JOIN document updateTime. Existing JOIN activation writes both atomically. This rejects a corrupted pointer back to a valid but historical A operation after B activated. It does not change JOIN or exit writes. Pre-7D0A users without the pointer use the existing `currentJoinId` legacy fallback, checked against the same live membership and atomic activation evidence. There is no search for an arbitrary historical operation and no guessed inviteId.

All checks occur in the existing read-only Firestore transaction. Malformed/missing/contradictory evidence produces FAMILY_UNAVAILABLE before Auth identity enrichment. Transport failures retain existing safe handling. The existing callable still authenticates the caller and accepts exactly `{}`: no caller-supplied household, UID, invite or history selection.

## Response and authorization

`getFamilyShareState({})` retains schemaVersion 1 and its existing display fields. An authorized member row gains `membershipInviteId`:

- Owner caller: every current non-owner row contains its exact membershipInviteId.
- Member caller: only their own row contains membershipInviteId. Other rows remain display-only.
- Owner row: field omitted; no fabricated owner self-exit binding.
- Private-only/historical-only state: no member rows or bindings.
- Removed/self-left members: absent from active rows.

The UID and inviteId belong to the same returned member object, scoped to the authenticated caller's Family. No raw invite token, historical-binding array or unrelated operation internals are exposed. USED membership invitations remain valid evidence even after their original invitation expiry; pending/revoked invitations cannot supply active membership evidence.

## Read cost

Flutter performs one getFamilyShareState callable per existing open/refresh operation. No polling, member call fan-out, Firestore client lookup, or new listeners.

After the existing bounded membership query (limit 9 to detect violation of the maximum 8), the server resolves K authorized non-owner bindings using four getAll batches:

1. K user roots.
2. K reverse membership indexes.
3. K exact current JOIN document paths.
4. K exact invitation document paths.

Owner K <= 7; normal member K = 1. Owner-only K = 0: no extra batches. The maximum-eight test verifies exactly [7,7,7,7] for these batches. There are no historical collection scans. Existing context validation is seven document requests; the valid member list is at most eight documents. Existing owner invite inventory costs one slot document plus up to eight invite documents. Thus a conservative valid-response bound is 52 document requests for an owner, 19 for a member, before any SDK caching/deduplication. These are request bounds, not a billing measurement. Existing Auth identity enrichment remains one bounded resolver call for at most eight identities.

## Flutter model and JOIN compatibility

`FamilyParticipant.membershipInviteId` is final internal metadata in the immutable participant object, next to UID and role. Parsing requires a 64-character lowercase hex binding for owner-visible non-owner rows and the current member's own row. Owner and unauthorized peer rows must omit it. Malformed/missing required metadata throws FamilyReadException(invalidState); server read errors retain the existing unavailable mapping. The field is never rendered or logged; display labels are unchanged.

CallableFamilyRepository.startJoin now retains the exact backend-issued operationId. It no longer derives or compares a UID-based JOIN hash. Only generic identifier sanity (nonempty string, bounded length, no slash/surrounding whitespace) is checked; there is no JOIN prefix/hash/generation pattern validation. Existing invitation-code hashing to inviteId is unchanged and is not operation-ID derivation.

Prepare/read/consent/cancel use the returned handle unchanged. Progress responses must still match that handle. Lost admission response continues to retry the same token/mode via existing 7C logic; the backend returns the same operation. No guessed operation ID is reconstructed. Tests accept legacy first-JOIN ID, actual later-generation ID and an opaque future identifier, for ADD and DELETE. Existing mandatory DELETE second confirmation and forward-only progress UX are unchanged.

## Real A/B/C and backward compatibility proof

The real rejoin tests execute A JOIN to DONE, self-leave or owner-remove, B JOIN to DONE and later C. Owner/member reads return B, then C. Reads after exit show private-only/no departed row. A's retained JOIN data/updateTime remain unchanged. A leave/remove still reject STALE_MEMBERSHIP; current B leave/remove succeed. A deliberately restored old pointer is rejected by read version validation. A legacy no-pointer user also reads correctly and can join a different Family.

No mutation implementation, shopping transfer, ADD/DELETE semantics, leave/remove engine or JOIN generation logic changed in 7D0.

## Validation

- Functions build: PASS.
- Backend: 24/24 targeted read and affected read-contract cases PASS; 5/5 real rejoin/stale A/current B/legacy regressions PASS. Total 29 distinct cases.
- Initial read fixture failures correctly exposed non-atomic synthetic ACTIVE index/JOIN creation. Fixtures now create those records in the same batch, matching existing activation. Only the affected read suite was repeated; the already-passing real JOIN suite was not repeated.
- Flutter: 107/107 Family tests PASS across family_binding_test, family_test, family_join_test, family_screen_test and family_mutation_test. Includes 17 new binding/opaque-ID cases and existing 7A/7B/7C regression, loading/retry, lost responses and DELETE confirmation.
- flutter analyze: PASS, no issues.
- Android debug build: NOT REQUIRED; production Flutter changes are confined to model/repository, no UI/platform/navigation runtime change.
- Local demo-kuktam-local Firestore emulator only. No production, deployment, full historical backend/Flutter suite, H2 or performance run.

## Files modified

- functions/src/households/family-invites.ts
- functions/test/family-invites.test.ts
- functions/test/family-rejoin.test.ts
- functions/scripts/emulator-tests.cjs
- lib/family/family_state.dart
- lib/family/callable_family_repository.dart
- test/family/family_test.dart
- test/family/family_binding_test.dart
- FAMILY_7D0_MEMBERSHIP_BINDING_READ_CONTRACT_CHECKPOINT_2026-10-27.md

## Exact handoff

7D0 PASS. 7C/7D0A are supplied input PASS gates; affected regressions above passed. 7D prerequisite is resolved, but 7D UI is NOT STARTED here. Future self-leave uses the current participant object's membershipInviteId; owner-remove uses the target participant object's UID and binding together, followed by existing authoritative refresh. Backend stale protection remains authoritative even if the screen's data becomes stale.

No leave/remove buttons, dialogs or Flutter mutation calls were added. Dissolution UI, 7E, App Links and additional lifecycle work were not started. Firestore rules unchanged. Production accessed NO. Deploy NO. Commit NO. Push NO. Blockers: NONE for 7D0. Next: separately resume Phase 7D.
