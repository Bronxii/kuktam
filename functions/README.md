# N2: local entitlement contracts and Firestore rules

Current closure contract: [N4B.8 audit](N4B-CLOSURE.md). Earlier phase sections
are historical; the closure document supersedes their intermediate limitations.

Status: LOCAL ONLY. No deployed functions, Play integration, billing product,
IAM changes, application integration or production retention job.

## Run

From `functions/` with Node 24 and Java 21 available:

```
npm ci
npm run test:unit
npm run test:rules
```

The locked dependencies include the Firebase CLI; no global install/login is
needed. First emulator startup may download the Firestore emulator binary.
`test:rules` exclusively starts Firestore on 127.0.0.1:8088, using the explicit
project `demo-kuktam-local` and `../firebase.emulators.json`. UI is disabled.
No `.firebaserc` default or functions deploy configuration is supplied. The
existing production app `firebase.json` remains unchanged. There is no deploy
script, exported callable handler, Functions SDK or service account credential.

The runner strips credential/config environment overrides, disables Compute
metadata credential probing and sets both project variables. The tests refuse
to construct either SDK unless host/project variables match the local demo target
and metadata probing is disabled. Running the
compiled rules test directly without those variables must fail before any I/O.
Emulator startup failure aborts the run, never falls back to a cloud database.

## Document contracts

All time fields are Firestore `Timestamp`, not strings, local dates or client
timestamps. All parsers reject unknown fields and return immutable results.
Future server writers must supply server-authoritative times. There is no
client-facing persistence adapter in N2.

| Path | Contract | Client access |
| --- | --- | --- |
| users/{uid}/entitlements/pro | EffectiveEntitlement | Own read only |
| users/{uid}/entitlementGrants/{grantId} | Grant | None |
| billingPurchases/{tokenHash} | BillingPurchase | None |

Effective entitlement: schemaVersion=1, active, nullable validUntil, unique
sources, positive revision, verifiedAt, updatedAt. Inactive has no sources or
expiry. Permanent Pro has null expiry. No token or binding is app-readable.

Grant: source PLAY_PURCHASE/PROMO/ADMIN/TEST; status ACTIVE/INACTIVE/REVOKED;
startsAt, nullable expiresAt, createdAt, nullable revokedAt; optional sourceRef,
actorRef, reasonCode. Coupon codes/redemption are outside N2. A promo can be
permanent or time-limited. No source has priority over another.

Aggregation matches N1: complete known grant set, explicit time; inclusive start,
exclusive expiry; any recorded revocation disqualifies; OR of eligible grants.
Empty/inactive yields Free, not unknown. Latest active expiry is used unless an
active permanent grant exists. Sources are deduplicated in stable enum order.
Revision allocation/concurrency and purchase verification are future backend
responsibilities. `verifiedAt` here describes trusted grant evaluation, NOT an
independent Google Play purchase verification. The helper must not be used to
renew offline proof from stale purchase data. No offline grace/cache is issued.

Ledger: schemaVersion, packageName, productId, bindingState, purchaseState,
acknowledgementState, verifiedAt, updatedAt, nullable revokedAt/revokeReason,
testPurchase. BOUND additionally requires raw purchaseToken, boundUid and
accountBinding. Product/package allowlisting and cryptographic token/account
verification belong to N3, not schema validation. Document ID is a stable token
hash (synthetic IDs/tokens only in tests); uniqueness enforcement is not yet built.

## Retention contract (no arbitrary retention duration)

* BOUND active lifetime: keep the token and binding needed for verification,
  reconciliation and replay prevention while entitlement exists.
* ACCOUNT_DELETED or REVOKED: remove boundUid/accountBinding; retain token-hash
  document identity, product/package, terminal binding and minimal lifecycle state.
* A retired record may retain raw purchaseToken only with
  reconciliationRequired=true; once false, the schema rejects the raw token.
* No email, name, content, device fingerprint, card data or full Play response.
* Retired binding is non-transferable. Schema parsing alone is not authorization:
  N3 must prevent overwriting a terminal record with a new BOUND record and handle
  late purchases not yet in the ledger. Separate deletion/binding coordination
  will be required then. N2 does not alter the current client deletion flow.
* Post-delete/revoke retention lasts only while actual replay prevention, Play
  lifecycle or documented legal/operational necessity requires it. Exact cleanup
  criteria and legal retention remain a compliance decision, not a timer here.

## Local rules and current app compatibility

Recipes and shopping retain own-user document CRUD/list access without Pro,
count, field or slot restrictions. Their unknown nested collections are denied.
Ingredients retain authenticated reads and no client writes.

User root supports own get/delete ONLY, preserving AccountDeletionRepository's
read/delete behavior. No normal app root create/update was found, so those and
root listing are denied. Root deletion does NOT recursively remove entitlement
or grant documents; future backend account cleanup remains necessary.

No recursive owner allow remains. Explicit backend-only denies plus default deny
prevent grants, ledger, arbitrary user subcollections and nested paths from being
opened by the old broad wildcard. Admin SDK bypass is proven separately with
real emulator writes and readback, not only with rules-disabled test seeding.

## Scope and future release gate

This file set must not be deployed during N2. Before any later deployment, review
the supplied production rules against the then-current deployed version, test
legacy client paths and complete account deletion/lifecycle protection. N3 needs
approved verification/account-binding contracts; real API/IAM/Play setup requires
separate explicit authorization. No recipe/shopping monetization backend exists.

## N3: local purchase verification (implemented)

`src/billing/` contains an injectable PlayPurchaseApi, strict minimal response
validation, AccountBinding and PurchaseVerifier. No real Play adapter, HTTP
endpoint, callable export, acknowledgement processor or deployment was added.
`test/fake-play-api.ts` supports values, errors and deferred/concurrent responses.

The only request field is purchaseToken. AuthContext is a trusted service input:
any future transport MUST construct it from verified Firebase Auth, never request
fields. Backend constants fix com.bronxii.kuktam / kuktam_pro_lifetime. The future
real adapter must obtain state/binding from authenticated Play API responses; it
must not wrap client purchase assertions as trusted responses.

Binding uses versioned HMAC-SHA256 over a domain-separated UID, with an injected
server-only key of at least 32 bytes. It exposes no raw UID/email to Play. There
is no fallback or embedded production secret. Provisioning, secure storage and
key-rotation compatibility need explicit later authorization; do not rotate the
key without supporting identifiers attached to existing purchases. The identifier
is opaque and not a client authorization credential: verification always compares
it with the authenticated UID's server-generated value.

Processing has two stages: read the existing ledger version, then validate the
external lookup outside a transaction; finally re-read ownership/version and
atomically write ledger + deterministic play_<tokenHash> grant + effective
entitlement. Token hash is SHA256(package + NUL + token). No unverified request
reserves ownership. Pending purchases may bind a verified token but grant nothing.
Canceled/missing/invalid/conflicting responses grant nothing and do not revoke
existing entitlements. Revocation is N4.

N3 transition vocabulary maps to the minimal N2 schema as follows:

* processing / verified: invocation stages, no persistent job or lease;
* pending purchase: BOUND ledger with PENDING purchaseState, no grant;
* granted: BOUND/PURCHASED ledger and ACTIVE permanent PLAY_PURCHASE grant;
* invalid/rejected/binding conflict: structured failure, no new ledger write;
* terminal ACCOUNT_DELETED/REVOKED records: never rebound or resurrected.

No extra verification status field is needed for this atomic synchronous operation.
Acknowledgement state only records the Play response; the service never acknowledges
or consumes a purchase. Missing grant and stale effective entitlement are repaired
transactionally. Identical replays leave timestamps/revision unchanged. Revision
increments only for changed effective active/expiry/source values, not request count.
No offline proof or grace renewal is issued by this service.

Concurrent identical verification is safe. Different owners cannot claim a token.
Intervening non-identical ledger transitions reject a stale response and require a
new explicit verification attempt. Future grant/lifecycle writers must follow the
same entitlement transaction contract. Existing tombstones win over late responses;
unknown tokens during account deletion still require N4 account-level coordination.
An external API response cannot itself be atomic with Firestore: future RTDN and
reconciliation remain necessary to observe later Play changes.

Errors expose stable codes only. SDK exception messages, raw purchase tokens and
full Play responses are never logged or returned by this service. Transient Play
failure does not downgrade Pro. Pending never grants or acknowledges. Independent
PROMO/ADMIN/TEST grants retain N1/N2 OR semantics.

### N3 verification and next boundary

`test:unit` runs N2 schema/aggregation and N3 binding tests. `test:rules` runs the
N2 rules/Admin and N3 transaction suites sequentially in the guarded demo emulator.
No production credentials or live Play calls are required.

N4 prerequisites: authenticated endpoint design, real Play adapter contract,
server secret provisioning/rotation, acknowledgement retry/idempotency strategy,
RTDN ordering and reconciliation, account deletion coordination and lifecycle
retention decisions. None of those integrations is implemented in N3. This local
service must not be released for real purchases before acknowledgement and purchase
lifecycle handling exist.

## N4A: acknowledgment delivery (local implementation)

`PurchaseAcknowledger.run(tokenHash)` is a trusted backend operation, not a callable
client endpoint. It uses `PlayAcknowledgmentApi`; only a fake exists. N3 verification
and this operation remain separately invocable so a committed grant can be recovered
without repeating the purchase UI. No scheduler or automatic retry loop is installed.

Delivery state is stored at:
`billingPurchases/{tokenHash}/acknowledgment/state`.
The existing default-deny rules protect this backend-only subdocument (emulator
read/write/query tests included). Ledger purchase truth stays in the N2 schema;
N3 therefore cannot accidentally replace acknowledgement delivery metadata.

State schema: schemaVersion=1, status, attemptCount, lastAttemptAt, nullable leaseId,
leaseUntil, nextRetryAt and failure. It contains no raw token or UID. State is parsed
strictly; unknown fields and impossible combinations fail closed. Parent ledger
retention/cleanup must eventually include this subdocument; deleting a Firestore
parent alone does not delete it. No retention job is implemented here.

### Explicit lifecycle transitions

| State | Allowed next action |
| --- | --- |
| verificationInProgress / verified | N3 invocation stages; no ack yet |
| pending purchase | No grant, no ack; N3 may later verify PURCHASED |
| terminalInvalid / accountBindingConflict | N3 structured rejection; no ack/job |
| granted, no delivery state | Validate ledger + permanent grant + effective Pro, claim ack |
| acknowledgmentPending, lease live | busy; no second external action |
| acknowledgmentPending, lease expired | new lease/attempt if budget permits |
| acknowledgmentRetry, before nextRetryAt | deferred; no external action |
| acknowledgmentRetry, retry due | new lease/attempt if budget permits |
| pending + success/alreadyAcknowledged | atomic ledger ACKNOWLEDGED + delivery acknowledged |
| pending + temporary/unknown reply | acknowledgmentRetry, or acknowledgmentFailed at budget |
| pending + permanent failure | acknowledgmentFailed; no automatic retry |
| acknowledged | no-op; no new API action |
| corrupt/impossible state | internalConflict; do not overwrite |

An already-ACKNOWLEDGED verified ledger can complete an interrupted delivery record
without another API action. A delivery record saying acknowledged while the ledger
still says PENDING is inconsistent and rejected. Terminal failure has no automatic
reset operation in N4A. Future operational recovery must recheck Play before allowing
an explicit new delivery budget; a fresh verifier does not silently reset it.

### Transaction and retry contract

1. Transaction reads and validates the bound PURCHASED ledger, deterministic active
   PLAY_PURCHASE grant and effective lifetime Pro. It commits a random lease ID,
   timestamp and incremented attempt counter before external I/O.
2. One external acknowledge call, outside Firestore transactions.
3. Transaction compares lease ID and the parent ledger's observed updateTime.
   Only its current claim can commit the result. Success updates ledger+delivery
   atomically; failures update delivery only, never grants/effective revision.

Local defaults: 120-second lease, 60-second minimum retry delay, maximum 8 external
attempts per delivery record. These are bounded operational retry settings, not an
entitlement expiry or offline-grace policy. A future real adapter must enforce a
network deadline shorter than the lease. No background worker, sleep/retry loop or
production timing guarantee exists in N4A. After budget exhaustion, explicit later
operational recovery is required; this must not be silently ignored before release.

A crashed process consumes its claimed attempt. Restart can recover after lease
expiry. A remote success with lost local commit is recovered using an idempotent
acknowledge/alreadyAcknowledged response (or later authoritative verification).
External exactly-once delivery cannot be guaranteed across crashes/lease expiry;
the guarantee is one live claim, idempotent remote semantics, and one durable local
outcome. Late workers cannot replace a newer lease/outcome. Changed ledger versions
return stale; the current worker/reverification must settle that state.

Temporary failure, permanent failure, malformed reply and adapter exception never
revoke Pro. Structured failure values contain no SDK/raw response or purchase token.
`alreadyAcknowledged` is success, not an error. Invalid transitions are rejected
before external I/O. All reads and writes use the injected Firestore instance; test
startup remains restricted to demo-kuktam-local.

### N4A boundary / N4B prerequisites

No RTDN, refund/revoke, voided-purchase API, scheduled reconciliation, account deletion
coordination, real Play adapter, Flutter Billing or UI was added. N4B must coordinate
all lifecycle writers with ledger versions, decide operational handling for exhausted
ack jobs, integrate authoritative Play lifecycle changes and test out-of-order events.
Real deployment additionally requires separately authorized credentials/API/IAM and
actual Play integration tests. Local fakes prove state handling, not real Play delivery.

## N4B.1 / N4B.2: v2 foundation, not yet a production integration

Status: LOCAL / EMULATOR ONLY. No RTDN, revoke processor, scheduler, deletion
cleanup/Auth trigger, live Play adapter, Functions transport, Flutter gate or deploy.

### Contracts and compatibility

`schema-v2.ts` is the new explicit read boundary. It reads strict v1/v2 purchase
and effective entitlement documents. Unknown versions/fields are rejected without
writes; a future version needs a reviewed reader update. Reading a v1 ledger only
normalizes it in memory. It defaults lifecycleRevision to 1 and new operational /
account-reference fields to null: no account generation or freshness proof is
invented. New ledgers start at revision 1; expected revision 0 means absent.

Ledger v2 retains all v1 fields and adds lifecycleRevision, lastCheckedAt,
nextCheckAt, operationalError, accountGeneration and bindingKeyVersion. Effective
v2 retains the existing fields and meaning, including semantic revision. Grant
schema remains unchanged; there is no reason to add fields to each grant here.
Existing effective v1 is read safely and only rewritten if effective facts change.

There is no migration job. The new writer explicitly upgrades a ledger on a
successful requested operation, after account and binding validation. Existing
fields are read/validated and updated; ack delivery subdocuments are untouched.
Unknown persisted fields fail closed rather than being dropped. N3/N4A legacy
readers intentionally remain v1-only: they reject a v2 record instead of erasing
its new fields. Do NOT mix the old and new writers on live data. Their integration
is N4B.3; all previous emulator regression tests still run on independent fixtures.

### Lifecycle decisions and revisions

`purchase-lifecycle.ts` is a pure decision function: current purchase, trusted
observation, account state, expected lifecycle revision and expected generation.
It returns apply/noop, stale/recheck or rejected. Pending grants nothing; a verified
purchased observation requires an atomic grant/effective commit. Acknowledged is
monotonic. Ack pending/retry are operational delivery transitions and do not change
purchase truth. Invalid observations grant nothing. Existing revoked/deleted/canceled
terminal records cannot be reactivated; no revoke processing is implemented.

Content changes (pending->purchased, purchased->acknowledged) increment the purchase
lifecycle revision. Replay, freshness, nextCheckAt and retry data do not. Registry
adoption during validated v1 normalization is metadata, not a new purchase event.
Effective revision increments only for changed active/expiry/source facts. Missing
grant/stale effective repair is supported without a false revision increment.

`LifecycleStore.commit` accepts a TRUSTED Play adapter observation and a trusted
AuthContext, not client purchase assertions. Future transport must authenticate
Firebase UID and future verifier must perform the authoritative Play lookup first.
No external API call is made by the writer. It checks account marker, opaque binding
registry owner/key version, ledger identity and expected revision within one
transaction, then writes ledger + grant + effective atomically. Missing markers
are rejected. Concurrent identical expected revisions yield one commit and stale
responses for the others; a retry must re-read/recheck rather than force an update.

`recordCheck` changes only operational metadata with account/revision fencing;
it does not renew effective verifiedAt, grant offline proof, or increment lifecycle
revision. It is an internal primitive, not a scheduler or API endpoint.

### Accounts and binding

`accountLifecycle/{uid}`: schemaVersion 1, state ACTIVE/DELETING/DELETED,
generation, updatedAt, nullable deletionStartedAt/deletedAt. Initialization is a
separate trusted operation, never an implicit side effect of purchase verification.
ACTIVE->DELETING->DELETED is monotonic. Same-state requests with the current
generation are idempotent; stale generations or reactivation are rejected.

`billingAccountBindings/{opaqueBinding}`: schemaVersion 1, state, keyVersion,
createdAt, updatedAt; uid exists only for ACTIVE. TOMBSTONED omits UID. Registration
requires an ACTIVE account and correct generation, uses server-generated HMAC, and
cannot replace a different UID or a tombstone. Lookup is backend-only. The single
binding tombstone primitive requires a non-active matching account; it is not a
bulk account deletion flow. Both new collections are explicitly denied to clients
in LOCAL rules, including query/nested-path tests.

The existing AccountBinding v1 algorithm/output is unchanged; keyVersion is exposed
as v1. Schemas permit future version labels but there is no new key, rotation,
Secret Manager integration or automatic binding transfer. N4B.3 must preserve
verification support for existing key versions before any future rotation.

Deletion races are serialized by reading the same account marker transactionally.
If deletion commits first, no grant can commit; if grant commits first, advancing
the marker does NOT clean up that grant in this scope. Cleanup is a later phase.
No UI or old verifier is protected by the new marker until N4B.3 integration.

### Retry policy (not wired to N4A yet)

`retry-policy.ts`: immutable injected policy, explicit now/RNG, default 120s lease,
30s external timeout contract, 60s base delay, exponential equal jitter capped at
6h, 8 attempts per recovery generation. The first retry has a 60s floor. Cap,
jitter, invalid RNG, shorter-I/O-than-lease and attempt exhaustion are tested.
A generation tracks generationAttempts and totalAttempts. Explicit trusted
re-verification may authorize a new generation only after exhaustion; totalAttempts
never resets. No worker or authorization endpoint is implemented. N4A's existing
runtime constants remain unchanged until its N4B.3 wiring, avoiding a partial refactor.

### Next phase prerequisites

N4B.3 must route N3 and N4A through these readers/writer contracts, provision account
markers/registry only from validated Auth, fence ack completion by account generation
and lifecycle revision in addition to its lease, and persist/inject the retry policy.
Then prove mixed legacy/v2 recovery and every old regression before using common
storage. No automatic creation of ACTIVE markers for deleted/unknown accounts.
Real deletion cleanup, refund/revoke/RTDN and scheduling remain later work.

## N4B.3: unified verification and acknowledgment (current behavior)

This section supersedes the earlier N4B.1/.2 note about separate legacy writers.
PurchaseVerifier now validates Auth/request/Play/binding, reads the account generation
and lifecycle revision before external lookup, then delegates to LifecycleStore.commit.
It has no Firestore mutations. PurchaseAcknowledger performs bounded external I/O
only; claimAck and completeAck are transactions in the same LifecycleStore. Ledger,
PLAY_PURCHASE grant and effective entitlement writes therefore have one store owner.
Identity/hash helpers moved to purchase-identity.ts; verifier re-exports them for
source compatibility, with no circular store/verifier dependency.

Account marker and binding registry must already be established by trusted account
setup. Verification never silently creates ACTIVE markers or resurrects tombstones.
A missing marker/registry fails closed, including for legacy ledgers: rollout must
explicitly provision these from verified Auth, not infer active users from receipts.
No production transport or provisioning/migration job is implemented.

Verification reads v1/v2, uses authoritative fake lookup outside the transaction,
and compares the pre-lookup generation/revision in the common writer. A concurrent
identical request can return staleLifecycleRevision rather than success; the durable
result still has exactly one grant and no extra entitlement revision. A caller must
recheck/retry explicitly, not retry an old observation with a new revision. Sequential
identical replay may refresh operational timestamps but not lifecycle/effective
revision. Source-list changes ARE effective changes under N1/N2: PLAY+PROMO -> PLAY
increments effective revision even if active stays true. Timestamp-only changes do not.

Ack delivery schema v2 reads legacy v1 safely in memory. It adds recoveryGeneration,
totalAttempts, accountGeneration and lifecycleRevision; attemptCount means attempts
within the current generation. Legacy counters map to generation 1 and keep their
attempt total. Legacy active leases are respected until expiry, then re-claimed with
current validated fences. Legacy non-permanent failed records map to recoverable
exhaustion. Account/registry documents retain their own schemaVersion 1; this is not
an incompatibility with purchase/delivery v2.

Claim checks ACTIVE account, binding owner/version, durable permanent Play grant,
effective Pro and usable purchase. It captures account generation, lifecycle revision,
random lease identity and recovery generation. Completion checks all four again,
plus the current grant/effective/binding. A deletion/terminal/newer revision or newer
claim prevents completion. Operational ledger timestamps no longer invalidate an ack
because fencing uses lifecycleRevision rather than Firestore updateTime.

Ack success goes through the pure lifecycle decision and atomically records ledger
ACKNOWLEDGED + completed delivery; it never changes grant/effective state. Ack retry,
permanent failure and exhaustion write delivery metadata only. Permanent failure is
acknowledgmentFailed; budget exhaustion is acknowledgmentExhausted, keeping Pro and
attempt counters. No reset endpoint or exhausted-task worker exists. The tested pure
newRecoveryGeneration contract is reserved for later authoritative reconciliation.

RetryPolicy is injected into the running ack service: lease, I/O timeout, exponential
jittered delay and per-generation budget. RNG/clock are injectable; RNG is sampled once
per logical completion so transaction retries do not change the retry decision. No
separate production retry constants remain in the ack implementation. The I/O deadline
aborts the supplied AbortSignal and ignores late results; a future real adapter MUST
honor that signal to terminate actual network I/O. There is no real network adapter here.

Structured results distinguish accountDeleting/accountDeleted, staleAccountGeneration,
staleLifecycleRevision, invalidLifecycleTransition, existing bindingConflict/
accountBindingMismatch/tokenAlreadyBound, verificationRejected, acknowledgmentExhausted
and internalConflict. Error messages never include tokens or underlying SDK exceptions.

Regression fixtures now explicitly provision account/binding state. Tests retain all
previous behavioral assertions, adapting expected stale codes and operational timestamp
updates to the new contract. New integration tests cover delete during lookup/ack,
terminal revision, operational updates during ack, old recovery/lease, injected backoff,
AbortSignal timeout, actual completion failure after fake Play success, v1 ledger+lease
recovery and effective source-list changes. No revoke/refund/RTDN/scheduler/deletion
cleanup/Auth trigger/Flutter Billing integration was added.

N4B.4 prerequisites: preserve the shared-store invariant for future terminal writers,
use account generation + lifecycle revision in every new transition, and retain the
non-reactivation contract. Account setup, real Play/transport and deployment remain
separately authorized work. Local tests do not prove live Play behavior.

## N4B.4: terminal revoke / voided lifecycle (local only)

PurchaseRevoker is an INTERNAL backend operation, not a client endpoint. It reads
owner, lifecycleRevision and account generation before a fresh VoidedPurchaseApi
lookup. No production Play HTTP adapter exists. The strict minimal DTO contains
package/product/token identity, testPurchase, authoritative and the semantic state.
These are supplied by a trusted server adapter; `authoritative: true` from a client
or an RTDN/financial event is never proof. A future adapter must establish actual
entitlement revocation from authenticated Play evidence, not infer it from a refund
amount, an event timestamp, absence, or a transport error. Identity fields may need
resolution from the authenticated query rather than the raw voided API response.

financialRefund returns refundWithoutRevoke. Unknown, non-authoritative, missing or
malformed observations return recheckRequired. Temporary failures return
voidedLookupUnavailable; permission/configuration failures return
voidedLookupConfigError. Those outcomes do not mutate durable purchase/grant/access
state, do not downgrade, and have no automatic retry. They are sanitized return
values for the future caller/operator integration; no monitoring/scheduler exists.

Confirmed entitlementRevoked and pendingCanceled go through decideTransition and
LifecycleStore.commitVoided. All reads precede all writes in one transaction:
ledger terminal state + the specific deterministic PLAY grant + effective entitlement
+ cancellation of unfinished acknowledgment delivery. Pending cancellation is only
valid for a pending purchase without a Play grant; it does not create or alter an
effective entitlement. Cancellation of an already purchased record is a conflict,
not evidence of revocation. A confirmed revoke uses CANCELED + revokedAt + the safe
ENTITLEMENT_REVOKED reason; pending cancellation has null revokedAt and
PENDING_CANCELED. No parallel lifecycle state machine or writer was introduced.

The ledger stays BOUND with owner/token intact: terminal purchase status is separate
from retention/minimalization. Retiring owner data, deletion cleanup and raw-token
retention are later work. Only the token-specific PLAY grant is marked REVOKED;
other Play/PROMO/ADMIN/TEST grants are not mutated. Verification and revoke share
effectiveUpdate (active + validUntil + source set); source changes increment revision
but unchanged effective access/timestamps do not. Replays do not refresh terminal
timestamps or revisions. Missing owner/marker or corrupt state fails closed for
future reconciliation/support instead of guessing a user.

DELETING/DELETED accounts can finish a negative transition with a CURRENT generation.
Revoke never changes the account marker. Effective aggregation for an inactive
account yields no access even when untouched promo grant records remain. This is
not grant cleanup; it prevents a negative worker from activating a deleted account.
An account-generation change DURING lookup returns staleObservation; retry requires
a fresh lookup. Newer lifecycle revisions also fence the response. Neither a stale
PURCHASED lookup nor an ack completion can revive terminal state.

Unfinished ack state becomes acknowledgmentCanceled, with lease and retry cleared,
failure cleared, and all attempt/generation history retained. Completed ack history
remains acknowledged. Late completion is stale; new claims reject terminal ledgers.
Both pure transition and transactional checks enforce this, including v1-to-v2 reads.
No preliminary migration is performed. No rules/client permissions were changed.

Offline tests cover refund/absence/API/config/malformed no-downgrade, token identity,
pending cancellation, terminal replay, other grant sources, account states, concurrent
verify/ack/revoke, stale observations, legacy v1, and failure after transaction writes
are queued but before commit. That injected transaction exception proves all four
documents roll back together; a fresh attempt completes safely. External lookup
success followed by process loss is also recoverable by a fresh lookup.

N4B.5 prerequisites: an independently authorized RTDN transport must authenticate and
validate events, resolve trusted identity, then perform fresh authoritative lookup
through this contract; it must handle stale/recheck/config outcomes explicitly.
Do not relabel old observations with new fences. Unknown owners and minimized ledger
tombstones need later binding/deletion coordination. Real Play mapping, bounded I/O,
RTDN, polling, scheduler, cleanup and production rollout remain outside N4B.4.

N4B.4 validation (2026-10-07, local/fake only):
- TypeScript build: pass.
- Backend unit: 64 pass (23 new N4B.4).
- Rules/Admin/lifecycle emulator: 143 pass (30 new N4B.4).
- N1 targeted Flutter: 42 pass (also included in full suite).
- Full Flutter: 759 pass / 1 existing skipped.
- Flutter analyze --no-pub: clean.
- git diff --check and untracked-file whitespace check: clean (Windows CRLF accepted).
- Writer audit: purchase mutations only in LifecycleStore; no writes in revoker,
  verifier or acknowledger orchestration. Rules and Flutter code unchanged by N4B.4.
- A simulated pre-writer process failure exposed a missing awaited rejection at the
  new orchestration boundary; corrected and the complete backend suite rerun green.
- Production Firebase changes: NONE. Play Console changes: NONE. Deploy: NONE.

## N4B.5: local RTDN core, durable inbox and safe replay

Only transport-neutral services exist; there is NO Pub/Sub/Functions endpoint,
subscription, RTDN console setup or scheduler. Future transport MUST authenticate
its delivery and supply an allowlisted source identity. A JSON `source` field alone
is not authentication. RTDN is only a recheck signal, never purchase truth.

Envelope parsing follows the official reference checked 2026-10-07:
https://developer.android.com/google/play/billing/rtdn-reference
Supported v1.0 categories: one-time product (types 1/2), one-time voided purchase
(productType 2, refundType 1/2), and test. Voided bodies have no sku/version field;
product identity is resolved through the fixed backend lookup context. Subscription,
future type/version/product notifications are controlled unsupported results.
Exactly one *Notification body is required. Canonical base64, fatal UTF-8, JSON,
package, required identities and timestamps are validated. Decoded payload max 32 KiB
is a local defensive bound, not a claim about Pub/Sub limits. Oversized or unkeyable
transport input is rejected before persistence; keyed malformed payloads become
FAILED_TERMINAL inbox records without payload/token. No financial event means revoke.

rtdnInbox/{SHA256(JSON([source,messageId]))} is backend-only. Schema v1 stores source,
message ID, payload fingerprint (hash only), received/publish/event timestamps,
category/type, tokenHash, status, attemptCount, lease ID/deadline, processedAt,
nextRetryAt and safe lastOutcome. No raw payload, order ID, UID or Play response is
stored. Same key/different fingerprint is messageConflict and cannot replace data.
Package is implicit in this Kuktam-only validated inbox. Additive body fields are
ignored and not persisted; unknown schema versions/types never run a lifecycle path.

Statuses: RECEIVED, PROCESSING, PROCESSED, RETRY, UNRESOLVED, IGNORED,
FAILED_TERMINAL. Claims use injected retry/lease policy and clock (current shared
default 120s lease, 8-attempt local budget); backoff/jitter are shared with N4B.1.
No loop runs. Active lease gives busyLease, future retry gives retryDeferred, expired
lease permits takeover. Exhaustion leaves UNRESOLVED/recoveryRequired with counters
intact. Config/permission failure is UNRESOLVED with permanentConfigurationFailure,
no retry timestamp; even duplicate delivery cannot restart it automatically. Operator
recovery authorization/generation reset belongs to N4B.6, not this phase.

Known purchase: resolve existing ledger owner and token. Unknown token: fresh Play
lookup supplies opaque account binding; strict registry + HMAC checks resolve UID.
Discovery never grants. PurchaseVerifier then captures its own current fences and
performs a SECOND fresh lookup before normal LifecycleStore commit. Do not reuse a
cached discovery reply. Tombstones never transfer/reactivate. Account setup remains
explicit; no ACTIVE marker is created. Unknown voided purchases without a ledger
remain UNRESOLVED even if binding resolves: no fake ledger or temporary Pro grant is
invented just to revoke it. Later reconciliation must coordinate that case.

Positive notifications call existing PurchaseVerifier; notification type does not
decide Pro. Pending grants nothing. Canceled/absent replies can only invoke N4B.4
PurchaseRevoker for separate authoritative negative evidence; they cannot downgrade
on their own. Voided notifications call PurchaseRevoker directly. Refund-only leaves
access intact. Terminal purchases cannot be reactivated by late positive messages;
no eventTime ordering shortcut is used. Test notifications finalize IGNORED without
Play calls. Structured Play config errors were added to the existing adapter/verifier
contract so an unavailable/configured-wrong backend is not treated as purchase truth.

LifecycleStore gained an OPTIONAL transaction read guard, supplied only by RTDN.
It reads the inbox lease in the SAME purchase transaction. Replaced/expired workers
cannot write a purchase, even if their external lookup finishes after takeover. The
existing account generation/lifecycleRevision fences still apply. Verifier now allows
store injection; default behavior is unchanged. Inbox finish independently fences its
lease. Ledger/grant/effective writes remain exclusively in LifecycleStore. Inbox store
writes ONLY rtdnInbox. No Flutter behavior, grant aggregation policy or account cleanup
was changed. Local rules explicitly deny all client access to rtdnInbox.

Raw token handling: if available in ledger, do not duplicate it. Unknown tokens need
a transientToken in the backend-only inbox to survive crash/replay without retaining
raw payload. Purge on PROCESSED/IGNORED/FAILED_TERMINAL. RETRY/UNRESOLVED retain it while
needed (including operator-blocked configuration errors). No retention worker or
arbitrary time limit was added. Pending operators need a later lifecycle-based cleanup
policy. Public handler/replay results expose only hashed inbox key and fixed outcome;
no token, UID, upstream exception or response. No logging implementation was added.
Internal parser/claim DTOs contain token data and MUST NOT be logged by future transport.

Crash cases tested: claim before lookup, lookup before lifecycle commit, and lifecycle
commit before inbox completion. Replay re-queries truth and lifecycle idempotency
prevents grant/revision duplication. Lease takeover and old completion are separately
fenced. Permanent malformed records do not retry. A stale lifecycle/account result is
RETRY with staleNoOp, requiring fresh observation on the next explicit attempt.

N4B.6 prerequisites: design authorized operator/recovery generation handling for
UNRESOLVED/config/exhausted events; schedule RETRY/expired leases only after separate
authorization; retain fresh lookup and both inbox/purchase fencing. Define unresolved
unknown-voided-owner and tombstone coordination, transient-token lifecycle retention,
and reconcile gaps. Production transport authentication, bounded/cancellable Play I/O,
real evidence mapping and live integration QA remain later infrastructure work.

N4B.5 final local validation (2026-10-07):
- Backend unit: 91 pass (27 new parser tests).
- Rules/Admin/emulator: 190 pass (46 RTDN integration/inbox/concurrency + 1 rules test added).
- N4B.5 adds 74 tests; all N2-N4B.4 regressions remain in the same offline suites.
- N1 targeted: 42 pass. Full Flutter: 759 pass / 1 existing skipped (N1 included).
- TypeScript build PASS; Flutter analyze --no-pub clean; whitespace/diff check clean.
- Final-attempt crash explicitly clears expired processing lease into UNRESOLVED;
  later operator recovery can distinguish it from a live processing worker.
- Writer audit: parser has no I/O; inbox writes only rtdnInbox; processor delegates
  purchase changes to PurchaseVerifier/PurchaseRevoker and guarded LifecycleStore.
- Local rules deny RTDN inbox get/list/create/update/delete/nested writes for all
  clients; real Admin SDK emulator writes succeed. No client permission broadened.
- No production changes, deploy, real Play, Pub/Sub resource or scheduler added.

## N4B.6 local maintenance core

Entry point: `new Maintenance(db, dependencies, clock, policy, rng).run({now,
only?, cursors?})`. No Functions/Scheduler transport or deployed resources exist.
Only injected Play/voided/feed/ack adapters are used. Production adapters remain
out of scope. `now` is the due-query snapshot; the injected clock is checked again
at transaction/lease boundaries. Supply the same clock source for both.

Work order: acknowledgment, expired inbox leases, due inbox retry, unresolved
inbox, voided feed, normal purchase recheck, grant boundaries, token minimization.
Each category scans at most policy.pageSize document IDs (default 50, max 100),
returns a document-path cursor, and isolates item failures. Cursor wraps to null
at the end. Preserve returned cursors between invocations; items inserted before
a cursor are seen on the next wrap. No unbounded database query or migration is
used by due-work discovery. This deliberately includes legacy records without
nextCheckAt and avoids composite indexes. It is a bounded scan, NOT a selective
indexed due queue: production cost/latency and caller cursor persistence need
load validation. `only` supports independently invoking categories to prevent a
busy high-priority category starving lower categories. Unvisited cursors survive
runtime-budget exhaustion. Runtime budget is a soft boundary between work items;
an in-flight item has separately bounded external I/O. Future adapter MUST honor
AbortSignal to cancel underlying I/O. Firestore transport timeout is SDK-owned.

`billingMaintenance/{sha256(kind, identity)}` stores ONLY lease, schedule, safe
outcome, failure/attempt counters, optional grant fingerprint and fixed feed-window
cursor. Local rules deny all client read/write. Live leases cannot be stolen;
LifecycleStore reads this lease in its transactions as well. No new client
permissions, indexes, packages, production config or Flutter changes were needed.

RTDN inbox reader now supports v1 and v2. V2 adds recoveryGeneration, totalAttempts,
lastAttemptAt and operatorRequired. Retry uses existing injected equal-jitter
backoff; unresolved uses a separately configured 30-minute base and daily cap.
Expired processing claims are recoverable. After budget exhaustion, a cooldown
and bounded number of recovery rounds apply (default 1 hour, 3 total generations).
Total attempts never reset. Permanent configuration holds and exhausted rounds
require explicit operator action; no operator UI or automatic hold reset exists.

Exhausted ack recovery is authorized inside the SAME fresh verification transaction
that checks account generation and lifecycleRevision. It creates acknowledgmentReady
with zero attempts in the new generation but retains totalAttempts. A cooldown is
checked in that transaction too, so the active recheck entry cannot bypass it.
Already-acknowledged Play truth needs no extra ack API call. Revoke/account deletion
fence recovery; uncertain/config failures keep grants intact. A ready generation
can safely be acknowledged/canceled before its first attempt (crash recovery).

Active purchases default to a daily nextCheckAt with injected +/-20% jitter.
Unchanged observations update lastCheckedAt/nextCheckAt without lifecycle or
entitlement revision churn. A canceled/missing purchase still requires separate
fresh authoritative revoke evidence. Financial refund alone cannot downgrade.
Configuration failures hold operational work; transient failures back off while
existing entitlement is preserved. Ledger operational scheduling and work metadata
are distinct: work.nextAt additionally controls ack/retry rounds, while ledger
nextCheckAt is the normal authoritative purchase recheck schedule.

VoidedPurchaseFeed is discovery only. It returns bounded pages of token identity
and voided time, never authority to revoke. The fixed window/page cursor advances
only after EVERY page item has a durable inbox entry. Partial crash replays dedupe;
a crash after checkpoint is recovered through RECEIVED inbox discovery. Processing
uses existing RtdnProcessor -> PurchaseRevoker with fresh per-token evidence.
Unknown owner stays unresolved; tombstone cannot transfer entitlement. Feed failure
does not advance checkpoint. Default six-hour interval / maximum 30-day lookback
is a technical API window, NOT a retention period. Very long outages beyond the
provider window require separate operator policy; nothing is silently inferred.

Grant boundaries require maintenance because effective entitlement is a persisted
snapshot. Due grant rows invoke LifecycleStore.recomputeGrants; it reads the account
marker and all grants with a 500-grant safety bound, fails rather than aggregating a
partial set, and only writes semantic effective changes. Future starts and expiries
are both handled. This does not add a recipe/shopping limit. Grant fingerprint
changes reopen completed recompute work. No separate entitlement writer exists.

Transient token copies are removed on final inbox completion or once an equivalent
ledger token makes the copy redundant. RETRY/UNRESOLVED, including operator holds,
retain a token only while it is the necessary replay source. No arbitrary age-based
retention or deletion cleanup is implemented. Internal feed/claim DTOs and document
path cursors must not be logged; public item outcomes contain hashed keys and fixed
categories, never upstream exceptions or raw tokens.

Suggested future invocation cadence (configuration, NOT deployed jobs):
- ack/retry/expired leases: around 5 minutes;
- unresolved/pending: around 30 minutes;
- exhausted rounds: hourly;
- active purchases: daily with jitter;
- voided feed: every 6 hours, successive pages via subsequent bounded invocations;
- grant boundaries: around 5 minutes.
Current purchase DTO has no trusted purchase completion time. ackDeadline(null)
returns null: verifiedAt is never substituted. Ack gets category priority, but
within-category deadline sorting awaits authoritative completion timestamps.

Writer audit: jobs/maintenance.ts has no Firestore mutation. MaintenanceStore writes
only billingMaintenance. Inbox writes stay in RtdnInboxStore. Purchase/grant/effective
writes, ack recovery and grant boundary recompute stay in guarded LifecycleStore.
N4B.7 prerequisites: coordinate account deletion markers, all worker generations,
ledger/binding tombstones and minimal retention with these lease/recovery contracts.
No N4B.7 cleanup, Auth trigger, production scheduler/Play/PubSub, UI or gate added.

N4B.6 final local validation (2026-10-07):
- Backend unit: 101 pass (10 N4B.6 policy/contract tests).
- Rules/Admin/emulator/concurrency: 241 pass (50 new maintenance integration tests
  plus 1 new backend-only rules test; all earlier suites included).
- Total N4B.6 additions: 61 tests. Backend total: 342 pass.
- N1 targeted: 42 pass. Full Flutter: 759 pass / 1 existing skipped; N1 included.
- TypeScript build PASS. Flutter analyze --no-pub: no issues.
- Tracked and all 66 untracked source/config files whitespace-checked clean.
- Recovery-ready crash before first attempt covered for both acknowledged and revoke.
- No production changes, deploy, IAM/API/Play changes, commit or push.

## N4B.7 account deletion coordination (local core only)

### Existing Flutter deletion audit
`lib/features/auth/data/repositories/account_deletion_repository.dart` currently:
1. Prevents duplicate local submissions; requires a current authenticated user.
2. Reauthenticates using the existing password/Google flow.
3. Checks the current UID before every destructive stage.
4. Deletes `users/{uid}/recipes` in server-read batches of 200, then `shopping`.
5. Reads/deletes the user root document, then calls `user.delete()` (Firebase Auth).
6. Performs best-effort Google provider cleanup after successful Auth deletion.
Firestore and Auth are not atomic. Failures propagate, `_deleting` resets in finally,
and replay re-reads remaining documents. Already deleted content is not restored.
Deleting the root does NOT delete subcollections: grants/effective entitlement,
ledger, binding, inbox and work records would remain without backend coordination.
Flutter code is unchanged in N4B.7.

### Trusted API and integration boundary
`AccountDeletionService.beginAccountDeletion({uid})` starts the barrier;
`resume(uid, maxSteps=10, pageSize=50)` performs bounded cleanup;
`handleAuthUserDeleted(uid, maxSteps=10)` is the trusted fallback core. No production
Auth adapter, callable or Auth trigger exists. The injected fake is used in tests.
Future transport must authenticate the caller, bind UID to that identity, enforce
recent-auth policy, and never accept arbitrary client-selected UID/Auth-gone flags.
No fake reauthentication is implemented in the domain core.

Future normal integration order: reauth -> backend begin barrier -> existing user
content deletion -> backend resume (including Auth deletion). Billing core must NOT
be mistaken for a complete recipe/shopping deletion service. A future deployed Auth
fallback covers legacy direct Auth deletion; until deployment it provides NO live
protection. External admin Auth deletion may leave recipe/shopping data; that separate
user-data cleanup remains an explicitly required integration/operational step.
Deletion UI later needs the no-transfer/no-auto-restore/Play-ownership warning.

### Barrier and stages
All writes are owned by LifecycleStore. The service orchestrates only.
The first transaction reads account, operation and effective snapshot, increments
ACTIVE generation once, writes DELETING and a canonical random operation ID, and
inactivates effective access. Replays preserve both generation and effective revision.
A missing legacy marker is created directly DELETING; it is never initialized ACTIVE.
Existing legacy DELETING/DELETED markers without completed billing cleanup are repaired
without backwards lifecycle transitions. DELETED+DONE replays are no-ops.

`accountDeletions/{uid}` is backend-only: schemaVersion, operationId, generation,
stage, authGone, Auth lease identity/expiry, nextAt, safe lastOutcome, updatedAt.
Stages: BINDINGS_MARK -> GRANTS -> PURCHASES -> BINDINGS -> AUTH -> DONE.
- BINDINGS_MARK converts bounded ACTIVE owner bindings to DELETING. The account
  marker already fences workers before this paged conversion. RTDN treats either
  DELETING or TOMBSTONED binding as non-transferable.
- GRANTS removes ALL sources under the exact owner path, in bounded pages, plus
  their known maintenance records. No source can later re-enable this account.
- PURCHASES reads one remaining bound ledger, drains bounded inbox pages for its
  exact token hash, then atomically retires the ledger and removes its known ack
  state and purchase maintenance record. Ownerless unrelated inboxes are untouched.
- BINDINGS replaces remaining owner mappings with UID-free TOMBSTONED records,
  preserving keyVersion and existing lifecycle timestamps.
- AUTH uses a durable claim with operation/generation/lease fencing around external
  I/O. Success and notFound are success. Temporary failure leaves DELETING, inactive
  access and retry time; permanent failure is a support hold. Trusted Auth fallback
  marks authGone and can finish without looking up or calling a missing Auth user.
- Final transaction removes the inactive client snapshot and advances to DELETED,
  leaving only the existing small account barrier and DONE technical operation.

Pages re-query the first remaining rows, so deleting rows cannot skip a cursor.
Stage advancement and each cleanup page are atomic; multiple workers can safely
cooperate. No unbounded cleanup loop: max 50 steps/invocation, page max 100; default
10 steps/50 rows. A transaction with malformed ledger/binding data fails closed
without destructive guessing; that account needs repair/support, while other accounts
remain independent. This is intentionally safer than skipping a corrupt ownership row
and declaring the account fully cleaned. No raw backend exception escapes the service.

### Tombstones and retention
The existing strict v2 retired-purchase shape is reused, with bindingState
ACCOUNT_DELETED, reconciliationRequired=false and lifecycleRevision incremented once.
Document ID stays tokenHash. Raw purchaseToken, boundUid, accountBinding, account
fence references and scheduling fields are removed/reset. Existing package/product,
purchase/ack state and verification/revocation evidence remain for schema-compatible
technical support; no name/email/profile/payment/raw response is retained.
Play purchase state is NOT changed to CANCELED and no revoke is fabricated. Existing
real Play revoke evidence is preserved. New UID token replay is rejected by the
existing tokenAlreadyBound contract before Play lookup. Unknown tokens using an old
binding are rejected through its tombstone. There is no automatic transfer.

Ack state is removed only after account fencing; stale ack completion cannot restore
it or grant access. Known-owner inbox rows may be deleted while cleaning that ledger;
late deliveries see the durable token/binding barrier and finalize without access.
Their temporary raw token is purged by the existing inbox finalization contract.
No owner is guessed for unresolved events. No arbitrary months/years retention or
production purge job was introduced. Technical barriers remain necessary to prevent
replay; any later deletion of these barriers requires explicit compliance/security
review rather than an invented expiry. Account deletion is NOT a refund/Play revoke.

### Maintenance and failure recovery
Maintenance has an OPTIONAL injected deletion resumer and a bounded `deletion`
category. It scans operation IDs with the existing stable cursor mechanism, skips
DONE/support holds/not-yet-due retries, and advances one step per item. Without an
injected resumer old behavior is unchanged. Suggested later invocation: ~5 minutes;
no scheduler is created. Default Auth claim lease 120 seconds, I/O timeout 30 seconds,
retry 5 minutes are injectable policy values. Total processing is bounded per run.

Crash after barrier/pages/tombstone/Auth success can replay. Auth success before the
local marker commit retries through notFound or the fallback's authGone fact. Old
Auth lease results cannot overwrite takeover or DONE. Account generation,
lifecycleRevision and existing inbox/maintenance leases fence verify, ack, revoke,
RTDN and reconciliation. Negative Play events may finalize while DELETING but cannot
activate access; after ledger retirement the token tombstone is terminal.

### Rules and writer audit
Local rules deny all client get/list/create/update/delete under accountDeletions;
existing accountLifecycle, billingAccountBindings, ledger/ack and maintenance denies
remain. No permissions were broadened. Deletion service/maintenance orchestrator have
no direct purchase/grant/effective writes. LifecycleStore owns barrier, grant cleanup,
ledger retirement and effective cleanup. No production transport or Auth SDK call was
added. Existing account lifecycle initializer/register refuse non-ACTIVE accounts.

N4B.8 prerequisites: review the now-integrated local lifecycle contracts, test evidence,
remaining malformed-record operator repair contract, real transport recent-auth checks,
legacy Auth fallback deployment and user-data deletion integration. No closure audit,
production adapter/deploy, Play resource, Flutter billing/UI/gate work began here.

N4B.7 final local validation (2026-10-07):
- Backend unit: 109 pass (8 new deletion contract/policy tests).
- Rules/Admin/emulator/concurrency: 295 pass (53 new deletion integration tests
  and 1 new rules test). All N2-N4B.6 suites included, zero failed/skipped.
- N4B.7 adds 62 tests; total backend: 404 pass.
- N1 targeted: 42 pass. Full Flutter: 759 pass / 1 existing skipped (N1 included).
- TypeScript build PASS. Flutter analyze --no-pub: no issues.
- Diff check: tracked and all 71 untracked files clean.
- Covered: atomic concurrent begin, all grant sources, no-transfer token/binding
  replay, lookup/ack/RTDN/maintenance deletion races, paged grant/purchase cleanup,
  Auth timeout/retry/permanent/notFound/fallback, checkpoint crash replay,
  Auth success before local completion, real transaction rollback injection,
  legacy v1 ledger and DELETED marker repair. Known user content remains untouched.
- New files: src/accounts/deletion-contract.ts, src/accounts/account-deletion.ts,
  test/deletion-core.test.ts, test/deletion.test.ts, test/fake-auth-deletion-api.ts.
- Modified: src/billing/lifecycle-store.ts, src/accounts/binding-registry.ts,
  src/billing/rtdn/processor.ts, src/jobs/maintenance.ts, maintenance-policy.ts,
  test/maintenance-policy.test.ts, test/rules.test.ts, package.json,
  scripts/emulator-tests.cjs, README.md and ../firestore.rules.
- No Flutter source, production Firebase/Play/IAM/API, deployment, real Auth deletion,
  commit or push. N4B.8 was not started.

## N4B.8 closure amendments

See [N4B-CLOSURE.md](N4B-CLOSURE.md) for findings, writer/race matrix, tests and N5 boundary.
Account marker advance now shares LifecycleStore effective deactivation. Normal Auth
cleanup waits for recipes/shopping/root removal; LOCAL rules prohibit content create/update
while DELETING/DELETED and preserve read/delete. No Flutter deletion change or deploy.
Maintenance callers must persist both cursors and nextCategory for bounded-run fairness.
Ack completion checks lease expiry; cleanup validates records before removal.
