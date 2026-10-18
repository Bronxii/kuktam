# Family Share Phase 3 — invite backend and current email identity

Local implementation on committed Phase 2 `d809614`. No JOIN, invite delivery,
Flutter UI, deep links, polling, deployment or production configuration change.

## Callables and authority

All four exports use CORE, GEN2, europe-west1, 60s, maxInstances=5,
enforceAppCheck=false and no secret binding. Admin initialization is lazy.

| Callable | Request | Response / authority |
|---|---|---|
| createFamilyInvite | `{}` | Authenticated ACTIVE owner, effective Pro, consistent ACTIVE family, available caps and server gate; returns token once, inviteId, expiresAt (epoch ms) |
| revokeFamilyInvite | `{inviteId}` | Current ACTIVE owner of that invite's family only; REVOKED / USED / IN_PROGRESS result |
| previewFamilyInvite | `{token}` | Authenticated ACTIVE invitee; read-only eligibility, owner email and private item count on VALID |
| getFamilyShareState | `{}` | Caller-derived verified family only; bounded member identities and owner-only pending invite metadata |

Every response includes schemaVersion=1. Client UID, family ID, role, expiry and
Pro fields are rejected. No arbitrary email/UID lookup exists. The same complete
`hasPro` → `parseGrant` → `aggregateGrants` authority used by CREATE is reused;
multiple valid grants and expiry matter, while cached effective Pro does not.

## Schema and token handling

`familyInvites/{sha256(rawToken)}` has exactly:

- schemaVersion=1;
- householdId and createdByUid: server-resolved family/owner;
- createdAt and expiresAt: backend clock, exactly 604800 seconds apart;
- status: PENDING / RESERVED / USED / REVOKED;
- operationId: null for PENDING/REVOKED, required for RESERVED/USED;
- usedAt and usedByUid: null until USED; both required for USED.

Token generation uses Node crypto.randomBytes(32): 256 random bits encoded as
43-character unpadded base64url. Hashing is SHA-256 over the UTF-8 encoded token
string. Noncanonical input is rejected. The raw token exists only in the create
response and transient preview input; it is never stored, logged, placed in
errors, returned by state or reconstructed. A collision fails closed before any
write. Separate successful calls intentionally create separate links. A lost
response/link cannot be retrieved: revoke its listed identifier and create anew.

No complete URL is generated; the later client phase will choose the HTTPS link.
Email is not stored in any member, index or invite document.

## Bounded pending inventory and concurrency

`familyInviteSlots/{householdId}` contains exactly
`{schemaVersion:1, inviteIds:[hash IDs]}` (unique, at most 8).

This small server-only inventory is both the bounded management read set and the
common transaction write guard for concurrent creates/revokes. Creating a link
atomically creates the invite and updates this inventory. Every slot target must
exist, validate and belong to the family; corruption fails closed. There is no
unbounded historical-invite scan, denormalized email or permanent member-slot
reservation. Physical old invite documents remain available for future bounded
retention cleanup; they cannot be used after expiry.

Create prunes expired PENDING and terminal references from the inventory (not
their documents). RESERVED references continue to consume inventory capacity,
even when expired: only the future durable JOIN may settle/release them. Pending
and reserved links together never exceed 8. Current member count must be <8 to
create an invite; members are read with limit=9 and invalid overflow fails closed.
The owner counts toward the 8-person total. Invitations do not reserve seats.

## Gates, expiry and outcome codes

`familyRuntime/config.inviteCreationEnabled === true` is required for new invites.
Missing field/document is OFF, independent of Phase 2 creationEnabled. No config
document is created by this code. Revoke, state and safe preview do not require
invite creation to remain enabled. Future accept needs a separate default-off
gate; no accept endpoint is implemented here.

Expiry does not depend on maintenance: at expiresAt, preview returns EXPIRED.
USED/REVOKED/RESERVED are not reusable. Revoke can also invalidate an expired
PENDING link; it never extends expiry. USED returns USED, RESERVED returns
IN_PROGRESS, and neither is modified. Repeated REVOKED is stable. Revocation does
not require current Pro, but does require consistent current ownership/lifecycle.

Preview failures are `{schemaVersion:1, code, eligible:false}` without owner email,
member list or shopping contents. VALID adds eligible=true, inviteState=PENDING,
expiresAt, privateShoppingItemCount and owner `{email,displayIdentity}`.

Codes: VALID, EXPIRED, REVOKED, USED, IN_PROGRESS, SELF_INVITE, ALREADY_MEMBER,
ALREADY_IN_FAMILY, FAMILY_FULL, FAMILY_UNAVAILABLE, FAMILY_PREPARING,
FAMILY_DISSOLVING, OWNER_UNAVAILABLE, OWNER_NOT_PRO, ACCOUNT_UNAVAILABLE,
ACCOUNT_NOT_READY, NOT_OWNER, NOT_FOUND, INVALID_ARGUMENT, FEATURE_DISABLED,
PENDING_LIMIT, INVITE_STATE_UNAVAILABLE, RETRYABLE_UNAVAILABLE.

Invalid token shape is an invalid-argument callable error. Create/revoke/state
domain failures use sanitized machine codes in failed-precondition errors.
Unexpected infrastructure/Auth failures become unavailable/RETRYABLE_UNAVAILABLE,
not fabricated missing-member results. Backend error messages contain no final
Hungarian UX copy. The explicit product fallback label below is display data.

## Email identity and privacy

For an ACTIVE family, getFamilyShareState verifies caller lifecycle, reverse
index, user pointers, family root, caller member record and private fallback.
It reads at most 9 member records to detect overflow, verifies roles and exactly
the root owner's owner role, and resolves at most 8 member UIDs via one Admin Auth
getUsers batch. Owner and members can view this same verified member list.

Member response: `{memberId,role,email,displayIdentity}`. memberId is a machine UID
for later actions, NEVER a normal UI label. displayIdentity is current Auth email
or `Ismeretlen tag`; missing Auth users/no email both have email=null. Only these
fields are projected; phone/provider/profile/metadata/password data is discarded.
An email change appears on the next explicit request without a sync worker.

Only owners receive invites: `{inviteId,createdAt,expiresAt,status}` for currently
live PENDING and RESERVED inventory entries. No raw link/token is returned.
Standalone state is only `{schemaVersion:1,familyActive:false}` and no Auth lookup.
Preview resolves just the owner identity; it never returns other member emails.

Direct client Firestore access to familyInvites and familyInviteSlots is denied.
Reverse index, structural membership/pointers and root state remain backend-only.
Existing shopping, recipe privacy and CREATE fences remain unchanged.

## Read budget (one transaction attempt, before retries)

Let G be trusted owner grants (maximum 500, a 501st detects overflow), M family
members (maximum 8, a 9th detects overflow), K inventory references (maximum 8).

| Operation | Firestore reads | Auth |
|---|---|---|
| Create | 10 point reads + K invite reads + grant query G + member query M | none |
| Revoke PENDING | 9 point reads + K invite reads; terminal outcomes stop after 8 | none |
| VALID preview | 13 point reads + grant query G + member query M + one count aggregation | one owner lookup batch |
| State owner | 8 point reads + K invite reads + member query M | one batch of M UIDs |
| State member | 7 point reads + member query M | one batch of M UIDs |
| State standalone | 3 point reads | none |

Empty queries can have minimum billing charges; transaction retries may repeat
reads. Count aggregation uses only `households/{caller's verified private ID}/shoppingItems`;
it returns a count, not item bodies. Index work/cost scales with that private
list's size. Count is informational and JOIN must revalidate actual contents.

There is no realtime identity/invite listener, polling, app-start call, or new
shopping-screen read. Future management calls state on open/explicit refresh;
preview calls once on explicit preview flow. No Dart contract changed in Phase 3.

## IAM preflight — NOT applied

Expected runtime: kuktam-core-runtime@kuktam-67768.iam.gserviceaccount.com.
Existing Firestore access must remain sufficient for the transactions above.
Additional Auth-read permission is exactly `firebaseauth.users.get`, required by
[projects.accounts.lookup](https://docs.cloud.google.com/identity-platform/docs/reference/rest/v1/projects.accounts/lookup).
Admin [getUsers](https://firebase.google.com/docs/auth/admin/manage-users#bulk_retrieve_user_data)
uses batched user identifiers. This phase bounds the SDK's larger batch capability
to 8 verified members (or one owner).

Current production permission was NOT inspected and must not be assumed. Before
deployment, read-only verify CORE's effective project IAM. If missing, recommend
a project custom role `kuktamFamilyAuthReader` containing ONLY
`firebaseauth.users.get`, bound to CORE at project kuktam-67768. Do not grant
Firebase Admin/Auth Admin or add delete permission. The existing custom
firebaseauth.users.delete role is unrelated and does not substitute for reads.
No role, binding, API, credentials or production configuration is changed here.

## Phase 4 contract and later lifecycle integration

No JOIN writes exist here. Future JOIN must transactionally validate authenticated
actor, separate gate, expiry, PENDING status, owner Pro/lifecycle, caller's one-family
invariant and capacity; then reserve this invite with its persisted operationId.
Only that operation may advance RESERVED to USED with usedByUid/usedAt, or safely
release its reservation. Preview never reserves or consumes the invite.

JOIN must use a shared family membership/capacity serialization guard and enforce
<=8 again at activation. Counting only pending invites is NOT a capacity check.
The eight links allowed here must not allow eight accepts to overfill a family
already containing an owner. JOIN must update/release this invite inventory in
its terminal transaction; a reserved invite cannot be owner-revoked out from
under the durable operation. This document specifies that future requirement;
Phase 3 does not claim to implement accepts or their capacity engine.

Later owner deletion/dissolution must invalidate pending invites and settle
RESERVED operations before cleanup. Member deletion must not invalidate unrelated
pending invites. Current family deletion safety stops are unchanged and covered
by regression tests; invite existence is never accepted as cleanup completion.

Keep creationEnabled and inviteCreationEnabled OFF until the full lifecycle stack
and production preflight are ready. Later controlled rollout must retain these
gates while rules, callables, IAM reads and lifecycle integration are verified.
No production rollout, user purchase, migration, invitation or E2E is performed.
