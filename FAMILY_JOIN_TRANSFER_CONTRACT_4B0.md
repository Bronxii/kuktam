# Family Phase 4B0 - JOIN transfer contract

Implementation staging note, 2026-10-23: 4B1A preserves the Phase4A accept/reserve
boundary and exposes explicit prepareFamilyJoinTransfer for the next bounded
preparation step. A later UI calls preparation after acceptance. This separates
the already-tested reservation API from the new pre-commit engine; it does not
add consent for ADD or permit transfer before commit. The API sequence in section4
describes the complete future flow, not an assertion that accept alone already
runs all preparation. See FAMILY_4B1A_CHECKPOINT_2026-10-22.md for implementation
and validation status; 4B0 itself remains a design-only historical checkpoint.

Date: 2026-10-22. Baseline: `13f1c898e24179764169413841ab179f422d6c83`.
Status: **PASS - design/contract only; no implementation or runtime proof**.
S1B remains accepted, S1C locally complete, S1D accepted. Production stays disabled.
This document is normative for the next 4B1 implementation. It supersedes only
the future JOIN handoff clauses of the older documents, not their historical results.

## 1. Existing contract and deliberate changes

Reviewed sources: FAMILY_JOIN_RESERVATION.md, FAMILY_CREATE_ENGINE.md,
FAMILY_INVITES_IDENTITY.md, SHOPPING_MUTATION_SAFETY.md, S1D2B checkpoint;
households/{family-join,family-create,family-invites,invite-contract,join-handler,
household-contract,household-store,operation-lease}.ts; shopping/mutation-store.ts;
billing/lifecycle-store.ts and the relevant existing Firestore rule boundaries.

The JOIN slot is `familyOperations/join_<sha256(authenticated UID)>`. It contains
actor/owner/invite/source/destination identity, immutable ADD or DELETE mode,
READY/ABORTED status, RESERVED/READY_FOR_TRANSFER phase, informational source count,
`deleteReconfirmationRequired`, and nextAt/leaseId/leaseUntil/lastOutcome timestamps.
The reverse index is RESERVED/member; the invite is RESERVED with usedAt/usedByUid
null; the capacity inventory retains the seat. No family member or pointer switch
exists. ABORTED slots can be reused for a different invite. Private IDs are derived
by the existing privateHouseholdId function, never provided by presentation code.

Explicit changes required by this contract, NOT existing capabilities:

- Reserved invite revoke must abort an owned **pre-commit** JOIN atomically.
  Current Phase 3 always returns IN_PROGRESS for RESERVED; that must change.
- Account deletion must check the committed transition guard **before** writing
  DELETING. Current beginDeletion can write DELETING first; cleanup's later
  fail-closed check alone is insufficient for mandatory forward completion.
- The S1D ADD algorithm can be reused, but ordinary shoppingAuthority cannot
  authorize the reserved invitee against the family. A server-only JOIN authority
  adapter is required. Do not impersonate the owner or weaken public authorization.
- Historical advice to fence both shopping lists is superseded for JOIN: fence
  the private source, serialize family structural changes separately, and permit
  existing family members' normal shopping transactions throughout transfer.

## 2. Decisions and state machine

No live family effect or private item deletion is allowed before commit.
After commit, **forward completion only**; no cancellation, inverse ADD, subtraction,
destination deletion, reopening the invite, or pre-transfer ABORT.

Use existing status conventions: READY, ABORTED; add JOIN support for the existing
CREATE vocabulary OPERATOR and DONE. Do not introduce a competing status machine.

| Phase | Status | Meaning / next normal phase |
|---|---|---|
| RESERVED | READY | Existing reservation; READY_FOR_TRANSFER |
| READY_FOR_TRANSFER | READY | Cancellable; acquire source fence -> SNAPSHOT_SOURCE |
| SNAPSHOT_SOURCE | READY | Cancellable, source frozen; bounded manifest construction |
| SOURCE_FENCED_WAITING_CONFIRMATION | READY | Complete manifest; DELETE needs explicit consent; ADD may proceed immediately |
| COMMITTED_TRANSFER | READY | Point of no return recorded; ADD executes manifest, DELETE executes no destination ADD |
| CLEAN_SOURCE | READY | All ADD results proven, or committed DELETE; bounded private item disposition |
| TRANSFER_COMPLETE | READY | Source empty, evidence complete; mandatory 4B2 handoff, no activation yet |
| ACTIVE | DONE | Future 4B2 atomic activation/finalization completed |

ABORTED is terminal only with `committedAt == null`. OPERATOR preserves the phase,
commit marker and all owned locks; it is not a cancellable state. nextAt=null in
OPERATOR/ABORTED/DONE. READY retains a due time, including waiting-confirmation and
TRANSFER_COMPLETE, so existing maintenance can continue/check bounded work. A 4B1-
only deployment parks TRANSFER_COMPLETE safely; it must never activate implicitly.
Production enablement requires 4B2 and later lifecycle release gates separately.

## 3. Source fence and exact snapshot

In one transaction, validate the existing reservation, actor lifecycle/pointers,
private ownership, invite, target and eligibility; write source.operationId equal
to the JOIN slot, apply `advanceShoppingEpoch(now)`, save that new epoch and fence
time on the operation, and change phase to SNAPSHOT_SOURCE. No item changes occur.
The fence is owned by `(operationId, inviteId, sourceFence.epoch)`; an old worker
must also hold the current lease and match this incarnation on every transaction.

S1 writers read the source root transactionally. An old write committed before
the fence belongs to the snapshot; one racing after it retries and fails current
authority/epoch checks. An offline SQLite acceptance not yet applied is NOT a
canonical item: it is rejected under the old context, never silently retargeted.
This is the existing S1 stale-context policy, not a promise to transfer unsent work.
New private writes and ensure-context mutation authority fail closed while fenced.
Log out does not remove the fence. Direct client canonical writes stay denied.

Build a manifest in document-ID order, pages of at most 10, within leased
transactions which verify the source fence. Save document ID, updateTime and full
data fingerprint per entry, and for ADD the fingerprint of the exact normalized
semantic ADD payload. The source remains intact until all ADD effects finish.
Do not truncate the list at 200: 200 is a shopping command bound, not a household
list-size bound. Multiple bounded pages cover the finite fenced collection.
One invocation has a finite page budget; continuation resumes from durable cursor.

Fingerprint version 1 is SHA-256 over a domain-tagged, length-prefixed encoding:
maps sorted by UTF-8 key bytes, arrays ordered, Firestore types tagged distinctly;
timestamps use seconds/nanos, bytes raw bytes, references qualified resource paths,
GeoPoints their two doubles, integers/doubles distinct canonical numeric encodings
(negative zero and nonfinite values explicitly tagged), strings exact UTF-8,
booleans/null tagged. Include ID and updateTime. No JSON.stringify of arbitrary
Firestore values. Test encoding vectors; unknown types fail closed before commit.
The snapshot digest is an ordered hash chain over these entry fingerprints, seeded
with version, operationId, inviteId, actor/source/destination IDs, mode and fence
epoch. Count and the final chain digest are persisted after an empty final page.
Empty lists have count 0 and the seeded digest; no fake mutation is created.

ADD preflight validates EVERY source item using the accepted S1 semantic codec;
unsupported/ambiguous source representation aborts before commit without deletion.
Checked state follows existing ADD: existing target retains checked state; a new
target is unchecked. Unknown source fields are not silently treated as ADD fields.
The product action transfers shopping quantities, not arbitrary document metadata.
DELETE fingerprints all source documents without requiring ADD-normalizable data.

No ordinary privileged writer may bypass this fence. Source changes despite the
fence invalidate the manifest: before commit abort safely; after commit OPERATOR.
Do not silently refresh consent or substitute a new snapshot. Pre-commit abort
unlocks only the owned source and rotates its epoch again; never restore an old
epoch. Private items remain untouched. The private household itself is never deleted.

## 4. Consent and future API contract

**ADD: no second confirmation.** The explicit Phase4A ADD choice authorizes sharing
all canonical private shopping items present at the fence, not a frozen initial
count. This is an explicit product decision here. The initial choice must say that
the current list will be added to the named family, merged semantically, and removed
from the private fallback after success; recipes are never included. Source count
at reservation is informational. The user can cancel until the commit transaction.
No raw source payload is disclosed to family members before commit.

**DELETE: a second affirmative confirmation is mandatory, including count zero.**
Keep deleteReconfirmationRequired=true as the mode requirement, not completion.
Record a separate `deleteConsent={version:1, snapshotHash, confirmedAt}` only after
an authenticated actor explicitly confirms the current complete fenced manifest.
The digest binds operation, invitation incarnation, UID, source, target, mode,
fence epoch, every source item and count. A matching old count is insufficient.

Future backend surface (names are new contract proposals, not implemented exports):

1. Existing acceptFamilyInvite({token,mode}) reserves and starts bounded preparation.
2. `getFamilyJoinTransferState({operationId,inviteId})`: actor-only, authoritative
   phase/progress; wrong UID or incarnation rejected. While preparing, no challenge.
3. Once complete, return schemaVersion=1, phase, operationId, inviteId, sourceHouseholdId,
   sourceEpoch, sourceItemCount (fenced count), snapshotHash, consentVersion=1,
   and confirmationDeadline equal to the existing invite.expiresAt. Return server-
   resolved target identity so UI identifies the family; no client routing override.
   An optional paginated actor-only snapshot display can read the manifest/source;
   current canonical rules may deny normal reads while fenced. Do not change rules.
4. UI explains irreversible private-list discard, exact fenced count and target;
   only an explicit second action calls
   `confirmFamilyJoinDelete({operationId,inviteId,sourceEpoch,snapshotHash,
   sourceItemCount,consentVersion:1})`. UID derives exclusively from Auth. Reject
   unknown fields, stale version/hash/epoch/count/incarnation, wrong mode or phase.
5. Confirmation validation and point-of-no-return commit occur in the SAME
   transaction. Write confirmedAt from server time. There is no accepted-consent
   window in which the source can be replaced. On lock contention return retryable
   IN_PROGRESS; do not store consent or silently commit later without this request.
6. `cancelFamilyJoin({operationId,inviteId})` declines/cancels pre-commit by the
   atomic abort below. After commit return IN_PROGRESS/non-cancellable. No mode
   switch in place; a fresh invite/reservation is required after abort.

Lost confirmation ACK: repeating the same authenticated, exact challenge returns
the stored committed state, without effects. A mismatched challenge always fails.
Get state after restart provides the same challenge while valid. Closing the app,
sign-out or never confirming causes no deletion. At invite expiry, maintenance or
the next request aborts; expiry is checked by server time even if maintenance is
late. There is no sliding consent deadline. This uses bounded existing maintenance,
not client polling. No UI or callable is implemented by 4B0.

## 5. Point of no return: atomic commit

Predecessor: SOURCE_FENCED_WAITING_CONFIRMATION with complete manifest. Final
transaction reads and validates:

- Strict operation identity/incarnation/phase, current lease for worker ADD commit;
  DELETE authenticated consent commit instead invalidates any existing worker
  lease atomically (workers must reread phase/lease before every write).
- Both account lifecycle documents ACTIVE; no deletion job/admission in progress;
  joiner standalone pointers/migration/private ownership, matching owned fence.
- Family ACTIVE/unlocked, exact owner, owner ACTIVE index/member/pointers/private
  fallback; current effective Pro via canonical full grant aggregation.
- Invite RESERVED for this operation, exact owner/household, unexpired, present in
  invite inventory; actor RESERVED/member index and capacity entry intact; no active
  destination member for actor; member count plus all seats <=8.
- Source epoch/count/manifest digest complete and immutable, mode unchanged,
  required DELETE challenge exact; target structural guard free.

Atomic writes: set `committedAt=serverNow`, phase COMMITTED_TRANSFER, cursor=null,
updatedAt/nextAt; persist deleteConsent for DELETE; clear old lease when the
confirmation endpoint commits; set capacity.structuralOperationId=operationId.
No canonical item write is needed in the commit transaction. All other claims
remain RESERVED. A crash immediately after this transaction is still committed,
even if zero items have been transferred. No later code may infer cancellation
eligibility from cursor==0. OPERATOR repair cannot clear committedAt.

Before commit, cancel/revoke/expiry/eligibility loss transactionally verifies
ownership, marks ABORTED, clears leases/due time, deletes only its reserved reverse
index, removes only its capacity/invite inventory entries, revokes its RESERVED
invite with operationId=null, and releases/rotates only its source fence. No source
item or family item is deleted. No missing user/root is recreated. Foreign or
corrupt ownership is OPERATOR rather than guessed cleanup. Bounded manifest GC may
follow abort; incarnation namespaces prevent it touching replacement work.

## 6. Structural serialization, not shopping exclusion

Extend existing `familyJoinCapacity/{hid}` to schemaVersion 2 with nullable
`structuralOperationId`. This is a durable ownership token, NOT an expiring lease.
JOIN commit acquires it; only the owning 4B2 activation transaction releases it.
OPERATOR retains it. Existing schema v1 means no committed holder and is upgraded
transactionally by a new writer; malformed records never mean an empty lock.

Do NOT set the live family root.operationId: current shoppingAuthority/rules require
that field null for active-family shopping. Normal member ADD/EDIT/DELETE/CHECK
continues with fresh ordinary S1 authority and revisions. Transfer uses the same
sequence allocator and transactional candidate discovery, so concurrent ADD is safe.

All structural writers must read this guard in the transaction authorizing their
change, not as a preliminary advisory read. Future owner end-family, dissolution,
membership removal, owner deletion and household deletion defer/reject temporarily
with IN_PROGRESS while owned. Their admission writes the same guard, so it conflicts
with JOIN commit. No ownership transfer is added. Second JOIN for the same UID is
already excluded by the reverse index; different invitees may reserve seats, but
only one committed JOIN per household proceeds. Others wait cancellably and must
pass fresh eligibility checks when the guard becomes free. No expired-worker lock
stealing: only worker lease can be replaced, never structural ownership by timeout.

Per-block authority is freshly read on EVERY transaction/retry: committed operation,
incarnation/lease, structural guard, source fence, reservation/invite bindings,
actor/owner lifecycle, user pointers, family owner/state/member evidence, current
shopping epoch/revision. Owner Pro and invite expiry are admission conditions, not
post-commit revocation conditions. This is a server-owned committed JOIN capability,
not cached ordinary user authorization. Public shopping commands keep their existing
fresh authorization checks and never gain this capability from a payload flag.

Structural epoch changes must respect the guard. Ordinary expiry-driven family
shopping epoch renewal may continue through the existing transactional mechanism;
each transfer block reads/validates the current epoch, including any safe renewal.
Transfer identity is the operation/fence/manifest identity, not a replayed public
client command with a replaced epoch. No old client request is ever rebound.
An unsolicited structural epoch/state/ownership mutation violating the guard is
OPERATOR, not permission to retarget. Source epoch remains the frozen identity;
its normal expiry does not cancel a committed server operation or refresh consent.

## 7. Lifecycle ordering and post-commit failure

Before commit, owner/joiner deletion wins by transaction conflict on lifecycle:
JOIN aborts safely and releases source/reservation; deletion cleanup may proceed
only afterward. Existing cleanup's family guard remains fail-closed until release.

After commit, and equally after TRANSFER_COMPLETE but before activation, ordinary
joiner/owner deletion admission returns retryable IN_PROGRESS **without** setting
DELETING, deleting Auth, private data, operation/journal, membership or roots. It
does not falsely claim the deletion was scheduled. Caller must retry after the
transition; future lifecycle jobs may persist their own deferred request, but 4B1
does not introduce a Phase5 deletion queue. This ordering applies to every exposed
marker transition, beginDeletion and Auth-delete path, not only UI actions.
For joiner resolve reserved index -> operation -> guard; for owner resolve active
family index -> capacity guard. Read these alongside lifecycle in one transaction.

Unexpected external Auth removal, an already-DELETING marker despite committed
ownership, missing roots or corrupted bindings is an internal invariant failure:
OPERATOR, with source/journal/locks retained, no activation, no fake account
resurrection. This is not automatic recovery of arbitrary privileged admin damage.
Repair requires an audited administrator to restore/prove structural consistency
and resume the SAME committed operation; it cannot subtract live quantities,
clear commit, or release the guard while unresolved. Production remains gated
until operator monitoring/repair and final family deletion are available.

Owner Pro loss after commit updates billing truth normally; do not fake Pro or
block entitlement reconciliation. It cannot abort this JOIN. A future Pro-loss
dissolution request must defer through activation. Subsequent JOIN admissions
still require Pro. Expiry/revoke/cancel return IN_PROGRESS or existing terminal
result after commit and do not modify claims. Continuation is independent of
admission feature gates and a currently logged-in app session.

Transient network/Firestore failure: retry same state via existing bounded work
and leases; retry backoff does not prove success or trigger abort. No terminal
retry-count cutoff may discard committed transfer evidence. Structural/semantic
permanent failure (including ambiguous destination duplicates/overflow) enters
existing OPERATOR vocabulary, nextAt=null, sanitized lastOutcome, locks retained.
The family may contain a visible transferred prefix; never compensate that prefix.
The operation requires explicit repair and forward resumption, not silent expiry.

## 8. Transfer, journal and activation boundary

Identity: `(operationId, inviteId, sourceFence.epoch, manifestPageIndex, childIndex)`.
InviteId is essential: the per-UID JOIN slot can be reused after ABORTED. Persist
server-only manifests/results under
`familyOperations/{id}/transferJournal/{sha256(inviteId + ':' + fenceEpoch + ':' + pageIndex)}`.
No client may submit these IDs as a privileged transfer request.

ADD executes <=10 manifest children in original source-ID order using the accepted
S1D transaction-local overlay, normalization, <=3 candidates and conservative
legacy fallback. Factor/reuse that primitive with the explicit JOIN authority and
journal adapter; do not call submit as the owner or implement a second merge loop.
Each successful child gets real target ID, created flag and monotonic revision;
one final household sequence write per block. Journal results, canonical writes,
operation cursor and continuation time commit atomically. Repeated worker/ACK loss
reads the durable result prefix, checks payload hashes and resumes, never re-adds.
Partial primitive fallback advances only the committed child prefix.

Keep frozen source items until every ADD child has APPLIED evidence. Only then
enter CLEAN_SOURCE. DELETE enters CLEAN_SOURCE directly after committed consent;
it produces disposition receipts, never fake ADD results. Delete exact manifest
source IDs in bounded transactions, checking fingerprints and owned fence, and
commit cleanup cursor/results atomically. Source changes/missing unexplained items
are OPERATOR. An empty final source query plus full manifest/result coverage proves
TRANSFER_COMPLETE. Source root/private owner membership remain; source is empty
and fenced. ADD and DELETE both disposition the old private list, never retain a
second usable list. Unknown metadata is not copied into semantic ADD output.

Progress is one phase-specific cursor `{pageIndex, childOffset}`; phase change resets
cursor atomically. Manifest pages store bounded entry fingerprints plus append-only
results/disposition evidence. No giant operation document or permanent raw-payload
snapshot. Retain manifest/journal until operation DONE and a separately safe
retention decision; generic shopping receipt TTL must not purge JOIN recovery data.
Completed or OPERATOR operation slots are not reusable. ABORTED-generation GC must
match invite/fence identity; it cannot delete a new generation's journal.

4B1 stops at TRANSFER_COMPLETE, committedAt non-null, status READY. Reverse index
and invite remain RESERVED, capacity seat AND structural lock retained, no member
document created, user pointers unchanged. Reserved users gain no family read access.
The source may be unavailable through ordinary canonical rules while fenced; future
UI uses actor-only operation state, not a second active shopping list.

4B2 must finish, not re-admit. It validates structural identity, all durable results,
empty fenced source, valid owned reservation/guard and consistent lifecycle; invariant
failure -> OPERATOR. It MUST NOT abort for elapsed invite expiry, Pro loss, logout,
disabled admission gates or user change of mind. Its single activation transaction
creates member, changes reverse index ACTIVE/operationId=null, changes family and
active pointers, retains private pointer/root, releases source fence with a fresh
epoch, consumes invite as USED with actor/server usedAt, removes its capacity and
invite inventory entries, releases structural guard, sets phase ACTIVE/status DONE.
Current family epoch must remain valid; activation-related structural epoch change
uses the existing helper if required by the activation contract, never restores an
old epoch. This is an obligation/specification only, not 4B2 implementation.

## 9. Minimal schema delta (backend-owned only; not implemented)

| Location / field | Type; set / cleared | Why existing data is insufficient |
|---|---|---|
| JOIN schemaVersion | 2; lazy transactional upgrade of eligible v1 pre-commit record | Strict v1 parser rejects additional phases/fields; never reinterpret old record as committed |
| phase/status | Values in section 2; preserve OPERATOR phase | Distinguish cancellable preparation, irreversible work, cleanup and activation handoff |
| committedAt | Timestamp/null; set once at commit, never cleared | Cursor zero, lease and READY alone do not prove cancellability |
| sourceFence | null or `{epoch:string, at:Timestamp}`; set at fence, retained as audit evidence | Root operationId alone is reused and lacks exact incarnation |
| snapshot | null or `{version:1,count:integer,hash:string}`; finalized once before challenge | Reservation count cannot detect replacement/edit |
| cursor | null or `{pageIndex:integer,childOffset:integer}`; per-phase monotonic, reset at phase transition | Durable bounded manifest/transfer/cleanup progress |
| deleteConsent | null or `{version:1,snapshotHash:string,confirmedAt:Timestamp}`; server writes with commit, never edits | Boolean requirement is not consent; actor and full context derive from immutable op/digest |
| transferJournal page | `{version:1,inviteId,fenceEpoch,pageIndex,entries,chainHash,results}`; entries<=10 immutable, results append-only | Bounded content fingerprint and per-child exact-once evidence; source remains payload store until cleanup |
| capacity schemaVersion / structuralOperationId | 2 / string or null; commit acquires, activation releases, OPERATOR retains | Seat list is not exclusive lifecycle ownership; root lock would disable member shopping |

Each entry is `{sourceId,updateTime,dataHash,addPayloadHash}` (last field null for
DELETE); results carry child offset, APPLIED target/revision/created for ADD and
disposition completion for cleanup. Snapshot construction resumes chainHash from
last committed page; no digest in memory is authoritative. Existing actor/owner/
source/target/invite/mode fields are immutable; existing sourceItemCount remains
historical reservation metadata. No membership/invite schema change, new household
state, parallel operation collection, expiring structural lock or duplicated UID
in consent. All new writes belong to authenticated server handlers/trusted workers;
client Firestore access remains denied. No schema is physically changed in 4B0.

## 10. Complete recovery matrix

Cells describe the JOIN response. A = ABORT with section5 cleanup; R = RETRY same
identity/progress; D/F = external action DEFER, JOIN CONTINUE FORWARD; F = CONTINUE
FORWARD ignoring admission-only condition; I = INVALID as a JOIN action (no writes;
future lifecycle API is separate); O = OPERATOR with locks and evidence retained.
An event concurrent with commit is resolved by transaction serialization: commit
wins -> post-commit column; cancel/invalidation wins -> pre-commit column.

| Event | READY_FOR_TRANSFER | SNAPSHOT_SOURCE | SOURCE_FENCED_WAITING_CONFIRMATION | COMMITTED_TRANSFER / CLEAN_SOURCE | TRANSFER_COMPLETE | ACTIVE/DONE |
|---|---|---|---|---|---|---|
| Owner revoke | A | A | A | D/F: IN_PROGRESS | D/F: IN_PROGRESS | I: USED |
| Invite expiry | A | A | A | F | F | I: no effect |
| Joiner cancel / decline | A | A | A | D/F: IN_PROGRESS | D/F: IN_PROGRESS | I: no JOIN undo |
| Joiner deletion request | A then deletion may retry | A then retry | A then retry | D/F before DELETING | D/F before DELETING | I: separate lifecycle; current family cleanup fail-closed |
| Owner deletion/end-family request | A before structural change | A before change | A before change | D/F | D/F | I: separate lifecycle |
| Owner Pro loss | A | A | A | F; dissolution deferred | F; dissolution deferred | I: separate lifecycle |
| Worker crash / lost ACK | R | R | R: same challenge | R: same result prefix | R: handoff | I: return existing DONE |
| Valid authorization/household change request | A before change | A before change | A before change | D/F | D/F | I: separate lifecycle |
| Unexpected actual structural/auth corruption | O | O | O | O | O | I: flag integrity issue; never undo JOIN |
| Snapshot content changes despite fence | I: not fenced yet | A if owned cleanup safe, else O | A if owned cleanup safe, else O | O | O | I: source is fallback |
| App close / logout | R by maintenance | R by maintenance | R: wait until confirmation or expiry | F by maintenance | F to 4B2 | I: no effect |
| Destination semantic conflict/overflow | I: no transfer | I: no transfer | I: no transfer | O; retain committed prefix | I: no transfer remaining | I: no JOIN replay |
| Second worker / expired lease | R after exclusive claim | R after claim | R; cannot fabricate consent | R after claim | R after claim | I: stable DONE |

In OPERATOR, all mutating user cancellation/lifecycle requests defer; admin repair
alone resumes the preserved phase after proving invariants. Pre-commit OPERATOR may
be repaired into safe ABORT; post-commit OPERATOR may only resume forward. Explicit
corruption is not a transient error retried forever without operator visibility.

## 11. Exact next 4B1 implementation and test plan

1. Add versioned strict JOIN/capacity/journal codecs and v1 compatibility; all
   readers/writers of capacity preserve the new lock. Old workers must not process
   v2 records; no deployment/rollback can silently downgrade a committed operation.
2. Add guarded backend preparation, actor-only state/DELETE-confirm/cancel contracts
   and pre-commit reserved-invite revoke; reuse lease/maintenance and existing
   authoritative validators. No Flutter UI and no rules exception.
3. Add the minimal deletion-admission/marker/cleanup serialization checks described
   above for actor and owner. This is required 4B1 safety integration, not Phase5
   deletion implementation. Test existing paths; do not claim the current code
   already defers DELETING. Do not permit a new committed path without these guards.
4. Fence source and build deterministic bounded manifest; validate all ADD data;
   expose DELETE challenge. Implement atomic final validation/commit and durable lock.
5. Reuse S1D block primitive with server JOIN capability and journal adapter;
   fresh structural authority each retry, <=10, conservative fallback, no public
   mutation privilege escalation. Implement source cleanup and TRANSFER_COMPLETE.
6. Preserve reservation/invite/pointers and park handoff. Do not implement activation.
   Ensure pre-commit abort dispatch is impossible once committedAt is non-null.

Required deterministic local tests (new tests are NOT created/run in this phase):

- Pre-commit revoke, expiry, cancel and eligibility loss in all three preparation
  phases; commit-vs-revoke/delete races in both serialization orders; zero item loss.
- DELETE fence and exact challenge; valid confirmation+commit; decline; wrong UID,
  source/target routing, version/hash/count/epoch/invite; same-count replacement;
  reused per-UID slot stale challenge/worker; restart/log-out waiting confirmation;
  confirmation ACK loss; no automatic consent, including empty lists.
- Post-commit revoke/cancel/expiry/Pro loss cannot abort; actor AND owner deletion
  defer before lifecycle marker/Auth/root changes; malformed/unexpected lifecycle
  -> OPERATOR, no source cleanup/activation/resurrection; retained repair evidence.
- 0/1/11/25 and representative >200 source items; 10/10/5 blocks; exact manifest
  coverage; unsupported ADD data pre-commit failure; source cleanup only after full
  ADD evidence; empty private fallback and unchanged pointers at final handoff.
- Same-product create/merge within/across blocks, existing Milk1000+300+2000=3300ml,
  incompatible db/ml separate; concurrent external family ADD; target duplicate or
  overflow -> OPERATOR without undo; source late old-epoch writes blocked even
  after abort/unlock; ordinary family members remain able to mutate during transfer.
- Forced transaction retry, competing workers, interruption and lost ACK after
  manifest/commit/each transfer/cleanup block; identical IDs/hashes, no duplicate
  effect, correct child targets/revisions/sequence/cursor; terminal reentry no-op.
- Guard prevents second committed JOIN/lifecycle operation; seats stay <=8;
  unrelated pending reservations may expire/abort independently; lease expiry never
  releases structural guard; feature gates OFF cannot strand committed work.
- Explicit natural epoch expiry/renewal versus forbidden structural epoch change;
  source freeze outlives epoch deadline without authorizing stale client writes.
- 25-item meter confirms accepted max10 block shape (no new cost target).
- Existing Phase4A, S1A contracts, complete S1D block suite, S1C shopping/household
  rules/protocol, Functions build, diff-check; broader backend/emulator regression
  is required for the shared lifecycle admission changes. No Flutter/native H2 run
  unless client code unexpectedly becomes necessary, in which case stop.

## 12. Acceptance and limits

4B0 resolves both product gaps: final commit removes ordinary compensation/abort
after visible effects; DELETE has exact fenced second consent. 4B1 is implementable
under this contract without further product choice. Runtime correctness is NOT
proven until 4B1 tests pass. Permanent invariant failures intentionally require
operator repair; there is no claim that arbitrary data corruption auto-recovers.

No production source, tests, rules, gates or configuration changed. No emulator,
build, Flutter/native or production test run for this documentation-only task.
No deploy, production access, commit or push. 4B1/4B2 and Phase5/6 NOT implemented.
Next separate task: 4B1 transfer engine plus its explicitly required serialization
guards and backend consent contract. Production Family rollout remains NO.
