## Phase 6B1 ACTIVE non-owner account deletion

See [FAMILY_6B1_MEMBER_ACCOUNT_DELETION_CHECKPOINT_2026-10-25.md](FAMILY_6B1_MEMBER_ACCOUNT_DELETION_CHECKPOINT_2026-10-25.md).
Local acceptance: 50 PASS / 0 FAIL / 0 SKIP (24 new + 26 affected regressions).
The existing recent-auth deletion entry admits a durable member-exit intent,
reuses Phase 5A/5B or dissolution evidence, then hands off to the original private
deletion engine. No DELETING/Auth action before proven Family exit.
New JOIN/CREATE is blocked during the handoff gap. Owner and historical-owner
protections remain for 6B2/6C; no production rollout or UI changes.

## Phase 6A owner Pro-loss lifecycle

See [FAMILY_6A_OWNER_PRO_LOSS_CHECKPOINT_2026-10-25.md](FAMILY_6A_OWNER_PRO_LOSS_CHECKPOINT_2026-10-25.md).
Local acceptance: 38 PASS / 0 FAIL / 0 SKIP (20 new lifecycle + 18 targeted regression).
Current authoritative grants admit one durable OWNER_PRO_LOSS intent and the
existing Phase 5 dissolution. Committed JOIN completes first; fresh topology is
then snapshotted. Stale events cannot initiate dissolution after Pro restoration.
The original local-only Family gate and all account-deletion guards remain.
6B/6C, production rollout and UI are not started by this milestone.

## Phase 5C4B owner release and dissolution finalization

See [FAMILY_5C4B_DISSOLUTION_FINALIZATION_CHECKPOINT_2026-10-25.md](FAMILY_5C4B_DISSOLUTION_FINALIZATION_CHECKPOINT_2026-10-25.md).
Local acceptance: 41 PASS / 0 FAIL / 0 SKIP; Phase 5C and Phase 5 COMPLETE locally.
Atomic finalization returns the owner to preserved private shopping, aborts pending
reservations, revokes usable invites and marks the Family DISSOLVED / operation DONE.
Fence epochs and structural-lock release commit together. Former-owner account
deletion remains admission-guarded pending Phase 6 historical Family-root policy.
Earlier checkpoint history below is unchanged.

## Phase 5C4A non-owner participant release

See [FAMILY_5C4A_NON_OWNER_RELEASE_CHECKPOINT_2026-10-25.md](FAMILY_5C4A_NON_OWNER_RELEASE_CHECKPOINT_2026-10-25.md).
The committed dissolution releases only immutable snapshotted non-owner members,
using the shared 5A/5B exit writes with atomic per-participant evidence.
Owner, both shopping fences and structural ownership remain held for 5C4B.
Earlier checkpoint history below is unchanged.

## Phase 5C3 Family source disposition

See [FAMILY_5C3_SOURCE_DISPOSITION_CHECKPOINT_2026-10-25.md](FAMILY_5C3_SOURCE_DISPOSITION_CHECKPOINT_2026-10-25.md).
The bounded local continuation deletes only exact, durably preserved Family
snapshot items, with atomic per-child cleanup evidence. SOURCE_CLEANED retains
both fences, memberships, routing and structural ownership. The owner-private
merge result stays unchanged. Participant release/final dissolution remain separate.
Earlier phase evidence below is unchanged.

## Phase 5C2B owner preservation merge (2026-10-24)

See [FAMILY_5C2B_OWNER_PRESERVATION_MERGE_CHECKPOINT_2026-10-24.md](FAMILY_5C2B_OWNER_PRESERVATION_MERGE_CHECKPOINT_2026-10-24.md).
The explicit local continuation reuses S1D ADD blocks and bounded durable child
receipts to preserve the committed Family snapshot in the owner's private fallback.
PRESERVATION_MERGE_COMPLETE retains source items, both fences, memberships,
routing and the structural lock. Source disposition and final dissolution remain
separate; earlier phase evidence below is unchanged.

## Phase 5C2A shopping preservation preparation (2026-10-24)

See [FAMILY_5C2A_SHOPPING_PRESERVATION_PREPARATION_CHECKPOINT_2026-10-24.md](FAMILY_5C2A_SHOPPING_PRESERVATION_PREPARATION_CHECKPOINT_2026-10-24.md).
The dissolution continuation atomically fences Family source and owner-private target,
creates/verifies bounded exact source pages, then durably commits preservation.
Normal shopping is intentionally blocked from fence acquisition onward. No merge,
cleanup, member exit or routing change occurs; the structural lock stays held.
5C2B execution and Phase 6 remain separate. Earlier evidence below is unchanged.

## Phase 5C1 dissolution preparation follow-up (2026-10-24)

See [FAMILY_5C1_DISSOLUTION_PREPARATION_CHECKPOINT_2026-10-24.md](FAMILY_5C1_DISSOLUTION_PREPARATION_CHECKPOINT_2026-10-24.md).
Owner preparation atomically stores a bounded participant snapshot and the v3
structural guard. No shopping transfer, member exit or household dissolution.
Normal Family shopping stays available; Phase 5C2 and Phase 6 are separate.

## Phase 5B owner-remove follow-up (2026-10-24)

See [FAMILY_5B_OWNER_REMOVE_CHECKPOINT_2026-10-24.md](FAMILY_5B_OWNER_REMOVE_CHECKPOINT_2026-10-24.md)
for owner-authorized atomic member removal using the shared Phase 5A exit primitive.
Family shopping and historical JOIN evidence are preserved. Phase 5C/6, re-JOIN
admission, UI and production rollout remain separate. Earlier results below are
unchanged historical evidence.

## Phase 5A member self-leave follow-up (2026-10-24)

See [FAMILY_5A_MEMBER_LEAVE_CHECKPOINT_2026-10-24.md](FAMILY_5A_MEMBER_LEAVE_CHECKPOINT_2026-10-24.md)
for atomic non-owner self-leave, own private routing, immutable completion evidence
and unchanged family shopping data. It does not implement owner removal/dissolution,
Family-aware deletion, re-JOIN admission or UI. Production remains OFF. Earlier
phase results below remain historical evidence.

## 4B2 activation follow-up (2026-10-23)

See [FAMILY_4B2_CHECKPOINT_2026-10-23.md](FAMILY_4B2_CHECKPOINT_2026-10-23.md)
for the atomic TRANSFER_COMPLETE → ACTIVE/DONE implementation and validation.
It finalizes membership, routing, invite/capacity and source/structural locks without
shopping item mutations. ACTIVE Family deletion remains admission-blocked pending
its separate lifecycle milestone. Production remains OFF. Earlier phase boundaries
below are preserved as historical evidence.

## 4B1B2 source disposition follow-up (2026-10-23)

See [FAMILY_4B1B2_CHECKPOINT_2026-10-23.md](FAMILY_4B1B2_CHECKPOINT_2026-10-23.md)
for bounded exact-manifest source cleanup through TRANSFER_COMPLETE. The private
fallback and source fence remain, membership stays RESERVED and activation is not
implemented. Earlier phase boundaries below remain historical evidence.

## 4B1B1 committed execution follow-up (2026-10-23)

See [FAMILY_4B1B1_CHECKPOINT_2026-10-23.md](FAMILY_4B1B1_CHECKPOINT_2026-10-23.md)
for committed snapshot execution through CLEAN_SOURCE. Source items/fence and
reservation/structural lock remain intact; no cleanup or activation is implemented.
The earlier 4B1A and Phase4A boundaries below are historical checkpoints.

## 4B1A implementation follow-up (2026-10-23)

The original Phase4A history below is preserved. See
[FAMILY_4B1A_CHECKPOINT_2026-10-22.md](FAMILY_4B1A_CHECKPOINT_2026-10-22.md)
for the new explicit preparation API, v2 source fence/snapshot/consent/commit
boundary, pre-commit revoke semantics and deletion admission guards.
No JOIN transfer or activation is implemented by 4B1A. Production remains OFF.

# Family Share Phase 4A: JOIN reservation only

Baseline: `337282e` (Phase 3), following `d809614` CREATE and `13c236b` state foundation.

**PHASE 4A MUST NOT BE ENABLED IN PRODUCTION WITHOUT PHASE 4B.**

## Callable and rollout barrier

`acceptFamilyInvite({token, mode: 'ADD' | 'DELETE'})` derives UID exclusively
from Firebase Auth. No household/owner/role/count identifiers are accepted.
The existing 32-byte URL-safe token is validated and hashed with SHA-256 before
lookup. Only its hash is persisted. Errors contain stable sanitized reason codes.
CORE, europe-west1, GEN2, 60 seconds, maxInstances 5, App Check enforcement false,
no billing secrets and no email/Auth-admin lookup.

Reservation requires ALL of:

- `familyRuntime/config.joinReservationEnabled === true` (missing defaults OFF).
- `GCLOUD_PROJECT` starts with `demo-` and Firestore emulator host is loopback.
- No Cloud Run `K_SERVICE` or deployed-function `FUNCTION_NAME` environment.

Production config alone cannot enable this incomplete operation. Phase 4B must
explicitly replace this hard incomplete-engine barrier only when transfer,
activation, cleanup, consent and broader rollout prerequisites are implemented.
Existing CREATE/invite gates are unchanged. Continuation/abort does not depend
on the reservation gate, so disabling new work never strands existing claims.

## Authoritative transaction

Validation reuses Phase 3 lifecycle, family owner/context, private-household and
member validators, and Phase 2 `hasPro`: canonical `parseGrant` +
`aggregateGrants`, not the effective cache or historical purchase alone.
Invitees may be Free. Owner must remain effectively Pro, including multi-grant
semantics. The caller must have a fully migrated standalone private household.
An existing CREATE operation other than ABORTED also blocks reservation.

One transaction writes all four claims or none:

1. `familyInvites/{tokenHash}`: PENDING -> RESERVED, `operationId` set.
2. `familyOperations/join_{sha256(uid)}`: durable JOIN operation.
3. `familyMemberships/{uid}`: RESERVED/member, destination household and operation.
4. `familyJoinCapacity/{familyId}`: bounded reservation inventory.

Invite `usedByUid` and `usedAt` remain null; reservation identity is the linked
operation's `actorUid`. No USED transition exists in this phase.

The deterministic per-UID operation slot plus reverse-index transaction prevents
two invitations/families being claimed by one UID. Matching token/UID/mode retries
reuse the operation; changing mode or token while READY returns IN_PROGRESS.
An ABORTED slot may be reused by a new eligible invitation. Every mutation is
lease-checked, preventing a previous worker from modifying the replacement.

## Capacity invariant

`familyJoinCapacity/{familyId}` contains exactly:

| Field | Purpose |
|---|---|
| schemaVersion: 1 | Strict structural contract |
| operationIds: string[] | At most seven unique JOIN reservation IDs |

Each reservation transaction reads the existing family member query (limit 9)
and this common guard document. The owner counts as an active member. It rejects
when `active members + reserved operation IDs >= 8`, then writes the same guard.
Concurrent final-slot requests conflict/retry on this shared document. Pending
invites consume no seats. Retrying the same JOIN consumes no extra seat.

Phase 4B MUST update this same guard in its activation transaction: create the
active membership and remove its reserved operation ID atomically. All future
membership/capacity writers must preserve this protocol; preview counts do not
authorize admission. A malformed capacity document fails closed, not as empty.

## JOIN operation schema

`familyOperations/{operationId}` has only:

| Field | Purpose |
|---|---|
| schemaVersion: 1, kind: JOIN | Strict parser and maintenance dispatch |
| actorUid, ownerUid | Auth-derived invitee and validated inviter |
| inviteId | Token hash; never raw token |
| householdId | Authoritative destination family ID |
| sourceHouseholdId | Authoritative private source ID |
| mode: ADD / DELETE | Original explicit choice, immutable during operation |
| phase: RESERVED / READY_FOR_TRANSFER | Phase 4A boundary |
| status: READY / ABORTED | Durable pending or terminal state |
| sourceItemCount | Informational aggregate count at reservation |
| deleteReconfirmationRequired | True for DELETE; mandatory Phase 4B consent barrier |
| createdAt, updatedAt | Server-side operational timestamps |
| nextAt | Due continuation time; null when terminal |
| leaseId, leaseUntil | Persisted worker exclusion/recovery |
| lastOutcome | Sanitized progress/abort/retry category |

There are no copied item payloads, item snapshots or journals.

## Lease and continuation

CREATE and JOIN share `claimFamilyLease`, the same persisted READY/nextAt/
leaseId/leaseUntil protocol. Default lease is 120 seconds. Every JOIN step checks
lease ownership and expiry within its transaction. A stale lease can be reclaimed;
a live lease blocks another worker. Exceptions do not launch background work.

Existing `billingMaintenance` family category dispatches CREATE or JOIN from the
due `familyOperations` query, at most five jobs per run and one bounded step per
job. JOIN revalidates claims/eligibility, then stops at READY_FOR_TRANSFER. It
rechecks at most once per five minutes; transient failures retry after 30 seconds
at the next normal worker opportunity. Malformed jobs are isolated from others.
There is no user scan, scheduler, shopping mutation, transfer fence or activation.

## Abort and deletion

Before transfer, loss of owner Pro, invalid lifecycle, unavailable/dissolving
family, expired invite or invalid owned reservation causes terminal ABORTED.
The transaction removes this operation's RESERVED reverse index, releases its
capacity entry, removes its pending-invite inventory entry and revokes its owned
RESERVED invite (`operationId = null`). It NEVER returns a claimed invite to
PENDING; a new invitation is required after eligibility failure.

Transient failures/crashes are retries, not aborts. Foreign/ACTIVE membership
ownership is never deleted or downgraded; unexpected structural ownership fails
closed. No account/root/pointer is recreated. Private items are untouched.
Existing account deletion continues to fail closed while the reservation exists;
maintenance abort releases it when the invitee enters deletion. Final family-aware
deletion remains a later phase. Owner revoke of RESERVED remains IN_PROGRESS.

## Private list and Phase 4B consent

The user keeps `activeHouseholdId = privateHouseholdId`, `familyHouseholdId = null`.
No family member document is created. Rules allow private CRUD only for a matching
backend-owned READY JOIN reservation, actor, source, destination and safe phase.
Private root must still be ACTIVE/unlocked. RESERVED never grants family shopping
access. Household ensure returns this existing private context without mutation.

There is currently no reliable per-list revision covering all shopping writers.
An item count cannot detect same-count edits/replacements. Consequently **every
DELETE operation requires renewed consent in Phase 4B before destructive work**,
even if its count is unchanged. The count is informational, never a deletion
authorization. Phase 4B must define a bounded, authoritative fence + confirmation
protocol so writes after the confirmed snapshot cannot introduce unseen deletions.
This phase adds no reconfirmation UI and never executes DELETE.

Phase 4B handoff must implement ADD/DELETE, consent/source fencing, durable
idempotent transfer/merge, active membership + pointers + capacity conversion,
invite USED and cleanup. No phase may switch pointers before preservation is safe.

## Privacy, reads and tests

All operation, capacity, reverse-index and invite documents remain backend-only.
No polling/member listener/client code added. Reservation uses bounded structural
reads, at most nine family members, canonical grants (existing 501 safety limit)
and one private-list count aggregation. No shopping payloads or emails are read.

Tests cover validation, Free/Pro invitees, all four reservation writes rolling back
on injected interruption, token/UID races, final-slot races, leases/crash recovery,
maintenance collision, gate-off continuation, safe abort, deletion fail-closed,
private rules and no family authorization. CREATE/invite/billing/deletion suites
remain part of full emulator regression. No production test is authorized here.
