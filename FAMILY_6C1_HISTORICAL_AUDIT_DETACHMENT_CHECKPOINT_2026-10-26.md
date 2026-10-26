# Family Phase 6C1 — historical DISSOLVED audit detachment

Date: 2026-10-26. Local/demo only. Acceptance: PASS - 39 PASS / 0 FAIL / 0 SKIP.

## Exact boundary

Input: `familyOwnerDeletions/{uid}.phase = WAITING_HISTORICAL_AUDIT`.

`WAITING_HISTORICAL_AUDIT -> DETACHING_HISTORICAL_AUDIT -> HISTORICAL_AUDIT_READY`

The account remains ACTIVE at the original account generation. No deletion job,
DELETING marker, private cleanup or Auth deletion is admitted by this phase.
HISTORICAL_AUDIT_READY means the historical ownership dependencies have been
removed, while an explicit separate handoff guard still prevents the deletion
engine from starting. Phase 6C2 is NOT STARTED.

## Inspected dependency graph and chosen model

Three separate existing paths interpreted household `ownerUid` as live ownership:

1. Family deletion admission in join-capacity.ts (historical DISSOLVED roots).
2. cleanupPrivateHousehold selects ownerUid roots and fails closed on a Family.
3. LifecycleStore.verifyDeletionContent counts any ownerUid household as content
   still needing cleanup.

Only weakening admission would therefore strand cleanup or risk deleting audit.
The solution separates the live reference on the historical root itself:

| Record / field | Meaning after detachment |
| --- | --- |
| households/{hid}.ownerUid | null; no live owner resource dependency |
| households/{hid}.auditOwnerUid | original immutable historical UID |
| households/{hid}.auditDetachmentPath | exact server receipt path |
| household kind/state/schemaVersion | family / DISSOLVED / 2, unchanged |
| household createdAt, shopping epoch, other evidence | unchanged |
| FAMILY_DISSOLUTION actorUid/ownerUid, snapshot, final receipt | immutable historical identifiers, unchanged |
| JOIN actorUid/ownerUid/inviteId and transfer evidence | historical identifiers, unchanged |
| MEMBER_LEAVE / OWNER_REMOVE_MEMBER actor/target identifiers | historical identifiers, unchanged |
| invite createdByUid/usedByUid | historical identity; status/expiry unchanged |
| capacity / invite slots | already empty and unlocked; unchanged |
| familyProLoss/{dissolutionId} | if present must be DONE or SUPERSEDED with matching terminal association; unchanged |
| owner deletion intent | original UID/account generation, plus 6C1 phase |

No active-household validator is relaxed to accept null ownerUid. DISSOLVED state,
absence of memberships, finalized invites and cleared capacity remain mandatory.
Normal shopping/membership routes still require active valid membership/root.
Terminal Phase 5 reentry validates its original receipt and remains compatible
with the detached historical root. No old audit hash is rewritten.

Existing billing binding tombstones remove live binding UID, but cannot be copied
verbatim here: Family operation identities and integrity hashes intentionally
bind historical UIDs. The new root fields are the minimal separation needed to
preserve those existing contracts without making the audit a live owned resource.

## Privacy and retained evidence

Retain only the existing historical UID and validation metadata: generation,
household/operation identities, timestamps, fingerprints and receipt links.
No email, display name, profile or entitlement content is copied into audit.
This is reference detachment, not a claim that existing historical identifiers or
shopping snapshot audit have been anonymized or erased. Existing audit retention
is preserved; no unrelated retention migration is introduced.

## Server-only admission and execution

HistoricalFamilyAuditStore is an explicit trusted local/backend primitive. It uses
the existing demo-project/local-emulator gate. It has no Auth API and no private
account-deletion engine dependency. There is no new client write path, callable,
UI or automatic 6C2 dispatch. Existing default-deny Firestore rules protect roots,
intents and receipts.

`step(uid)` resumes the 6B2 handoff. `admitHistorical({uid})` establishes the same
WAITING_HISTORICAL_AUDIT intent for an already-private historical owner, after
validating their private account and one actual terminal historical dependency.
It does not start deletion or admit active owners/members/committed JOIN actors.
A future 6C2 authenticated gateway can reuse this method and the SAME detachment
primitive; no second cleanup algorithm is needed. Recent-auth gateway integration
for that later workflow is not added in 6C1.

Each step reads the ACTIVE lifecycle marker, checks the original generation,
requires no deletion job/membership, exact private routing/ownership and no
in-progress actor/owner Family operation or live owned Family root.
Stale generation fails safely before detaching another root.

## Durable bounded progress

Progress: `familyOwnerDeletions/{uid}/historicalAudit/state`.

Fields: version=1, uid, accountGeneration, stage (SCAN/VERIFY/COMPLETE), count,
hash, current, verified, after, verifyHash. Current is bounded to one household:
householdId, original root updateTime, scan stage (INVITES/OPERATIONS/DETACH),
after-document cursor and accumulated auditHash.

Receipts: `familyOwnerDeletions/{uid}/historicalFamilies/{householdId}`.

Each receipt binds version, UID, accountGeneration, householdId, dissolution
operationId, householdCreatedAt, prior root updateTime, Phase 5 finalization hash,
paged audit fingerprint, detachedAt, previousHash and receipt hash.

Execution:

1. Initialize progress and DETACHING_HISTORICAL_AUDIT atomically.
2. Select one remaining ownerUid Family root in document-ID order. Verify full
   terminal eligibility; pin its exact updateTime.
3. Inspect historical invites and operations in pages of at most 10. Reuse existing
   strict invite/JOIN/CREATE/member-exit/dissolution parsers. Require terminal
   operation status and matching historical owner/Family identities. Expired
   PENDING invites may remain expired; RESERVED/usable PENDING cannot remain.
4. Revalidate terminal eligibility and the pinned root version. In ONE transaction
   write the unique receipt, clear live ownerUid, set auditOwnerUid/receipt path,
   and advance count/hash. No deleted-but-unrecorded or detached-but-unrecorded gap.
5. Repeat for every remaining ownerUid Family; there is no total historical-count
   truncation or unbounded root result array.
6. Verify receipts one per transaction in deterministic order, including their
   chain, generation, original Family incarnation, terminal receipt and detached
   root linkage. Verify count and primary 6B2/historical-admission dependency.
7. Freshly prove no live Family dependency remains, then atomically mark progress
   COMPLETE and intent HISTORICAL_AUDIT_READY.

The underlying audit history is terminal/server-owned; no client can mutate it
while inspected. The paged fingerprint is evidence of inspected history, not a
new mutable copy of those documents. Corrupt detected history stops processing;
no repair or historical record deletion is attempted.

## Terminal eligibility per Family

Every Family must have a parsed DONE/DONE dissolution and valid original
finalization receipt, matching historical owner and household creation time,
DISSOLVED source with released fence/terminal epoch, empty shopping source,
no member rows/reverse indexes, empty capacity and invite slots, no structural
lock, no RESERVED/usable PENDING invite, and no READY/OPERATOR Family operation.
The bounded participant-release receipt chain must also be complete. A present
Pro-loss intent must already be DONE (associated with this dissolution) or
SUPERSEDED (no admitted dissolution association). Both use the existing strict 6A
parser. PENDING/IN_PROGRESS/OPERATOR remains blocked; 6C1 does not finish that
lifecycle for it.

## Multiple historical Families

The current CREATE per-UID operation slot limits normal repeat creation, but this
is NOT a storage-wide invariant proving exactly one historical root forever.
Household IDs, historical imports/legacy state and the ownerUid index permit
multiple historical roots. All relevant live ownerUid Family roots are processed.
The local test creates two independently finalized Family audits using the real
Phase 5 engine, interrupts after the first detachment and resumes through both.
No first-match-only admission bypass is used.

## Deletion classification and the 6C2 barrier

`assertNoLiveFamilyDependency` is a read-only classifier. It blocks any membership,
Family routing, still-owned Family root (including undetached DISSOLVED), and
READY/OPERATOR actor/owner Family work. Pure terminal historical participant UIDs
in operations/invites are not blockers. Detached roots no longer match the live
ownerUid query, so the unchanged private cleanup/content-verification queries
will not select/delete them in a later authorized deletion.

`assertHistoricalAuditHandoffPending` is the separate mandatory phase barrier:
WAITING_HISTORICAL_AUDIT retains FAMILY_LIFECYCLE_NOT_READY; detaching, audit-ready,
or an attempted failed audit transition returns HISTORICAL_AUDIT_HANDOFF_REQUIRED.
The existing beginDeletion path calls this even for Auth-event fallback. Marker
advancement uses the same protected admission guard. A raw deletion call cannot
start merely because ownerUid references are now detached.

OwnerAccountDeletionStore recognizes the new phases as outside its 6B2 worker:
repeated user requests return historicalAuditPending/historicalAuditReady without
re-running dissolution or entering private deletion. No new Family CREATE/JOIN
can be admitted while the original owner deletion intent remains present.

## Recovery and integrity

- Unique per-household receipt and atomic root/progress transaction: duplicate,
  lost ACK and competing workers have one effect and stable historical identity.
- Retry after detachment: remaining-owner query excludes completed root; durable
  receipt verification recognizes it without another version update.
- Interruption between historical Families: continue using bounded progress.
- Failure before commit: root owner and progress remain unchanged.
- Missing/corrupt terminal proof, active membership/work, owner mismatch, held lock,
  usable invitation/reservation, or inconsistent receipt chain: OPERATOR.
- Already-detached records are not rolled back if a later record is corrupt.
  The handoff barrier remains; no partial audit result can admit private deletion.
- Reentry after readiness checks account generation/private safety/progress and
  live dependency absence, returns existing readiness, and writes nothing.

## Exact 6C2 handoff

6C2 must revalidate the intent generation, COMPLETE receipt evidence and absence
of live Family dependencies, then explicitly implement its authorized handoff
past the separate barrier into the existing private deletion engine. It must
recognize an already-admitted job after lost ACK and retain the audit receipts.
It must not remove the barrier globally or restore ownerUid. Local simulated Auth
completion and final private data cleanup remain 6C2 work. No 6C2 code is present.

## Validation

Final Functions build/typecheck: PASS (exit 0). Runner syntax check: PASS.

After the final backend change, the selected suite ran once:
`node scripts/emulator-tests.cjs --historical-audit-regression`

- 24 new 6C1 cases: PASS.
- 5 relevant 6B2 historical-handoff cases: PASS.
- 3 relevant 6B1 guards/former-owner references: PASS.
- 3 Phase 5 DISSOLVED/terminal-audit cases: PASS.
- 3 private deletion admission/generation cases: PASS.
- 1 root export/discovery check: PASS.
- Total: 39 PASS / 0 FAIL / 0 SKIP, exit 0, 377679.1918 ms.
- Final log: C:/Users/gabor/AppData/Local/Temp/family-6c1-final-validated.log.
- Demo Firestore emulator shut down normally; no test process remains running.

Earlier development runs: 21/21 focused PASS (253194.3429 ms), then 38/38
selected PASS (362219.2155 ms). Code review identified one additional valid
terminal Pro-loss state (SUPERSEDED); the existing strict parser was reused,
that case was added, and the final 39-test run above validates the final code.
The earlier logs are family-6c1-focused.log and family-6c1-final.log in the same
temporary directory. No failing test was skipped or weakened.

The new audit tests keep the owner account ACTIVE, assert absence of the owner
deletion job, and assert FakeAuthDeletionApi.calls=0 throughout. Direct normal
admission, Auth-event fallback and marker advancement remain blocked at the
6C1 boundary. Existing private-account admission regression fixtures intentionally
exercise their pre-existing barriers/jobs separately; no 6C1 owner is handed to
that engine and no Auth deletion occurs in the selected tests.

Former non-owner historical references are additionally proved harmless by both
read-only Family dependency/admission guards after real JOIN + leave/remove.
Their old operations/invites and the member's private data remain intact.

No mandatory 6C1 test remains unexecuted. No unresolved 6C1 blocker remains.
Phase 6C2 is NOT STARTED: authorized private-engine handoff and simulated terminal
Auth completion are intentionally future work.

No routine git checks, historical full regression,
transfer/performance matrices, Flutter/native/Android tests, production access,
production deletion E2E, deploy, commit or push.

## Files modified in 6C1

- functions/src/households/historical-family-audit.ts (new server-only primitive)
- functions/src/households/owner-account-deletion.ts (shared intent parser and
  audit phases; owner deletion entry remains stopped at the handoff)
- functions/src/households/owner-pro-loss.ts (exports the unchanged strict intent
  parser; no Pro-loss transition behavior changed)
- functions/src/households/join-capacity.ts (live dependency classification and
  explicit 6C1/6C2 admission barrier)
- functions/src/billing/lifecycle-store.ts (applies that barrier before any
  deletion-job/marker write, including Auth-event fallback)
- functions/test/historical-family-audit.test.ts (new targeted suite)
- functions/scripts/emulator-tests.cjs (targeted suite selections)
- FAMILY_6C1_HISTORICAL_AUDIT_DETACHMENT_CHECKPOINT_2026-10-26.md (new)
- FAMILY_JOIN_RESERVATION.md (additive progress note)

The historical root's receipt pointer must remain resolvable after later account
cleanup. 6C2 must preserve the referenced receipt/progress audit metadata; those
server-side records are not disposable user profile content.
