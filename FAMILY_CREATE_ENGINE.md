# Family Share Phase 2 — CREATE only

Local implementation on Phase 1 checkpoint `13c236b`. No UI, invites, JOIN,
DISSOLVE, automatic Pro-loss handling or family-aware account deletion is enabled.

## Authority and rollout gate

`createFamilyShare` is an authenticated GEN2 callable in `europe-west1`, using
CORE, 60s timeout, maxInstances 5, no secrets, and `enforceAppCheck:false`.
Only `{}` is accepted. UID comes exclusively from Firebase Auth. Household IDs
and all structural state are resolved by the server.

Creation requires `familyRuntime/config.creationEnabled == true`. An absent
document/field is OFF. Rules deny client access to this configuration. No
configuration document is created by this implementation. Existing accepted
operations can resume when the gate is OFF; disabling creation cannot strand
cleanup. Keep this gate OFF until family deletion/lifecycle integration and
the later rollout gates are complete. Client UI visibility is not authorization.

Effective Pro is calculated using the existing `aggregateGrants` and `parseGrant`
over the complete trusted `users/{uid}/entitlementGrants` collection (same 500
grant safety ceiling as billing). It does not trust cached effective documents,
device proof, historical purchases or a single grant. Eligibility is rechecked
before activation, including grant expiry and concurrent account deletion.
No Play API, acknowledgement, consume or billing mutation is performed.

## Durable schema

`familyOperations/create_<sha256(uid)>` is the single per-UID CREATE slot:

| Field | Purpose |
|---|---|
| schemaVersion=1, kind=CREATE | Strict operation contract |
| actorUid | Authenticated actor and durable continuation identity |
| sourceHouseholdId | Verified private fallback P |
| householdId | Allocated-once family destination F |
| phase | COPY / VERIFY / ACTIVATE / CLEAN_SOURCE / FINALIZE / ABORT |
| status | READY / DONE / ABORTED / OPERATOR |
| cursor | Last atomically committed source document ID for copy/verification |
| createdAt, updatedAt | Server-clock audit times |
| leaseId, leaseUntil | Persisted exclusive worker lease (120s by default) |
| nextAt | Due time; null for terminal/operator records |
| lastOutcome | Sanitized result/retry reason, never item contents |

An aborted slot may be reused after fresh authorization. DONE returns stable
success and never allocates another household. No per-item payload journal is
needed or retained: the source itself remains intact and fenced until activation.
Terminal records contain no shopping payload. Their later account-deletion/
retention treatment belongs to the explicitly deferred family lifecycle phase.

Household/user/member schemas remain Phase 1 contracts. Reservation writes:

- family root: schemaVersion=2, kind=family, ownerUid, createdAt,
  state=PREPARING, operationId;
- reverse index: householdId=F, role=owner, state=RESERVED, operationId;
- private source: operationId fence; user pointers still point to P.

Activation atomically makes family root ACTIVE/operationId=null, creates the
owner membership, makes reverse index ACTIVE/operationId=null, and writes
familyHouseholdId=F and activeHouseholdId=F while retaining privateHouseholdId=P.
The private operation lock is cleared in this same transaction because Phase 1
family access requires a valid unlocked private fallback. The ACTIVE reverse
index and family pointers replace the temporary fence: private shopping remains
hidden and unwritable. No stable partially activated pointer state is exposed.

## Bounded transfer and failure behavior

VALIDATE + RESERVE are one transaction. Source ownership, migration=1,
standalone pointers, lifecycle ACTIVE, Pro, membership absence and gate are
checked before any reservation. Transaction conflicts prevent duplicate CREATE.

COPY uses document-ID pages (25 by default, capped at 50), copying full Firestore
document data without shopping merge/parsing. IDs, timestamps, numeric values,
unknown nested fields, bytes, references and GeoPoints survive. Page writes and
cursor advancement commit together. An unexpected target ahead of the cursor
fails closed. VERIFY independently rereads every source/destination pair before
ACTIVATE. Only backend workers can write PREPARING data; clients cannot mutate
the source while reserved. This relies on server/rules authority, not protection
against arbitrary concurrent privileged Admin writes.

After activation, CLEAN_SOURCE deletes bounded pages from private shopping;
FINALIZE clears the lease and marks DONE. Family edits after activation are never
recopied or overwritten. The private root/owner membership remain as fallback.

Loss of eligibility before activation enters durable ABORT. It deletes only the
operation-owned, unexposed PREPARING destination and its reserved index, releases
the source fence, and preserves source shopping. Missing/deleting user roots are
not resurrected. Structural corruption that makes ownership unsafe reaches
OPERATOR with locks retained instead of deleting uncertain data. After activation,
Pro/lifecycle changes never roll the list back: cleanup resumes toward DONE.

Every mutation transaction verifies lease ownership and expiry. A crashed worker
can be replaced after expiry. Transient errors release the lease and schedule
retry after 30s. Callable execution awaits at most four steps; it never starts
unawaited background work. A timeout leaves persisted state for continuation.

`billingMaintenance` adds a final `family` category. A single-field nextAt due
query returns at most five operations, with one bounded step per operation per
run under the existing overall budget. Terminal records have nextAt=null and
are excluded. Individual errors are isolated. There is no user scan, bulk
migration or new Scheduler. The existing billing/deletion categories are unchanged.

## Rules and deletion boundary

Operations, any nested journals and runtime gate configuration are backend-only.
Existing Phase 1 rules enforce source fencing, PREPARING exclusion, owner access
after activation, hidden private fallback and recipe privacy. No client can
change membership, structural pointers, root state or locks.

Deletion begun before activation invalidates CREATE and permits safe abort.
Deletion after activation continues to fail closed at the existing family
relationship safety check; it must not claim deletion DONE. Phase 2 deliberately
does not solve shared-account deletion. Therefore production creation must remain
disabled even if the callable/maintenance code is deployed in a later rollout.

## Tests and future rollout notes

Local tests cover validation, aggregate Pro, 0/1/multiple/67-item lists, lossless
data, phase interruptions, expired and competing leases, concurrent callable/
maintenance work, transient retry, abort/retry, activation-boundary Pro loss,
post-activation edits, deletion fail-closed behavior and client rules.

No rollout is performed in Phase 2. Future order: retain gate OFF; deploy/test
updated continuation worker and rules; deploy the gated callable; complete family
deletion/lifecycle integration before enabling creation for any real user.
Rolling the maintenance dispatcher back to pre-Phase-2 code needs care: its stored
nextCategory may now be `family`, which old code does not recognize. Do not roll
back readers blindly or abandon in-progress operations.

Next implementation scope: Invite backend + member email identity only. No
ownership transfer, selector, recipe sharing or final product decision changes.
