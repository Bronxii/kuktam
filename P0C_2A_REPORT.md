# P0C.2A – Production adapters, local source only

Verdict: READY FOR P0C.2B (local source/mock readiness; production activation remains blocked).

## Scope and files
New:
- functions/src/adapters/config.ts
- functions/src/adapters/play-rest.ts
- functions/src/adapters/google-play.ts
- functions/src/adapters/firebase-auth.ts
- functions/src/billing/binding-key-provider.ts
- functions/test/production-adapters.test.ts
Modified:
- functions/src/billing/account-binding.ts (versioned runtime key provider, v1 compatibility)
- functions/package.json and functions/package-lock.json (direct existing Google Auth dependency; unit test registration)
- P0C_2A_REPORT.md (this report)
No Flutter, rules, Functions root export, runtime trigger or deployment configuration changes in this phase. Existing unrelated working-tree changes were preserved.

## GOOGLE PLAY API CONTRACT
- API version: Android Publisher REST v3.
- Lookup: purchases.productsv2.getproductpurchasev2, GET applications/{packageName}/purchases/productsv2/tokens/{token}.
- Acknowledgment: purchases.products.acknowledge, POST applications/{packageName}/purchases/products/{productId}/tokens/{token}:acknowledge, empty JSON body.
- Voided: purchases.voidedpurchases.list, GET applications/{packageName}/purchases/voidedpurchases.
- Credential model: Application Default Credentials, runtime service identity, androidpublisher OAuth scope.
- Later permissions: enable Android Publisher API in the runtime project; invite the service identity to the specific Play app with purchase/financial read and order management rights needed for verification/acknowledgment. No Owner/Editor role required. Final Play permission smoke test belongs to infrastructure QA.
- No live API call performed. Only public official documentation was read.

Official references inspected for this implementation (2026-10-09):
- [ProductPurchaseV2 lookup](https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.productsv2/getproductpurchasev2)
- [ProductPurchaseV2 resource](https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.productsv2)
- [Acknowledge](https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.products/acknowledge)
- [Voided list](https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.voidedpurchases/list)
- [Voided semantics](https://developers.google.com/android-publisher/voided-purchases)
- [Firebase Admin errors](https://firebase.google.com/docs/auth/admin/errors)

V2 lookup supplies explicit line-item product identity and purchase/acknowledgment state; the older product lookup is unnecessary. Acknowledgment still uses the products method: there is no invented V2 acknowledge endpoint.

## Purchase adapter
- Backend package/product constants: com.bronxii.kuktam / kuktam_pro_lifetime.
- Rejects mismatched context before HTTP. Response product identity must match.
- Strictly accepts one non-consumed, single-quantity, non-rental/non-preorder line item.
- Maps PURCHASED/PENDING/CANCELLED and acknowledgment enums to existing domain contracts.
- Unknown/missing required enums or inconsistent states fail closed; optional unrelated Google response fields are discarded.
- Test purchase context and opaque account identifier are preserved for existing verifier checks.
- Lookup 404 returns no purchase; it never revokes an existing grant.
- Purchase completion time is not added to the domain: verifiedAt remains verification time, not purchase completion time. Ack urgency without trusted completion time remains a documented pre-existing limitation.
- Adapter does not grant Pro and performs no Firestore writes.

## Acknowledgment adapter
- Called only by the existing durable verified/granted claim flow in later composition.
- Fresh lookup checks PURCHASED; an already acknowledged purchase is successful without POST.
- POST success is accepted only as an empty response object.
- On ambiguous POST failure, one fresh lookup can prove acknowledgment succeeded. Otherwise structured failure returns to existing lifecycle retry/lease machinery.
- No consume endpoint, internal retry queue, client acknowledgment or Flutter completePurchase added.

## Voided/refund adapter and feed
- Feed supports window, page token, bounded page size, empty pages and page-local duplicate suppression.
- One-time product filter type=0; quantity-based partial refunds excluded for the single-unit non-consumable contract.
- Google documents a 30-day technical query window. This confirms the previous assumption; it is NOT a retention policy.
- Page-token continuation omits ignored time filters. Returned voidedTime is not used to reject items: the API window concerns when Google observed the void.
- Token lookup joins fresh purchase identity/test flag with a fresh bounded voided list (maximum 10 pages of 100).
- A matching authoritative list record maps to entitlementRevoked. No match maps to non-authoritative unknown, never an inferred revoke or financial refund.
- Refund without access revocation is not present as revocation evidence in this feed. Existing PurchaseRevoker remains the only mutation path.
- Missing purchase identity, exhausted scan, malformed data and API errors preserve entitlement and request recheck/operator handling through existing contracts.

## Firebase Admin deletion
- Injected Admin Auth client, no default app initialization or runtime export.
- Success => deleted; auth/user-not-found => idempotent notFound.
- Network/internal errors => temporaryFailure; permission/config/invalid UID => controlled permanentFailure.
- AccountDeletionService remains the sole orchestration call site after LifecycleStore returns its Auth claim.
- Modern VERIFIED content barrier, account generation and legacy fallback boundaries were not weakened.
- Admin delete cannot be canceled after SDK dispatch. Existing bounded timeout/lease recovery plus user-not-found idempotency handles ambiguous completion.

## Credentials, HMAC and configuration
- google-auth-library 11.1.0 is now an exact direct dependency; it already existed transitively. Offline install, no unrelated upgrade.
- Official library handles ADC token acquisition; native Node fetch implements the small REST surface instead of adding the large googleapis package.
- Node >=22 required by this dependency; use a supported Node 22+ runtime in P0C.2B.
- Transitive OAuth/HTTP dependencies remain part of the supply-chain surface; no new full dependency audit was requested/run.
- Production composition must use runtime identity, not GOOGLE_APPLICATION_CREDENTIALS pointing at a downloaded key. No key file/token persistence implementation exists here.
- Central non-secret adapter config holds package/product, scope/origin, timeout, response cap, voided window/scan bound.
- HMAC currentVersion is an explicit RuntimeBindingKeys configuration argument; no default secret. P0C.2B must inject the selected version plus Secret binding values.
- Provider accepts current and previous version key material, minimum 32 bytes; internal copies and returned copies prevent external mutation. Secrets stay private in memory.
- Existing v1 binding derivation is byte-compatible. New bindings use currentVersion; existing v1/v2 identifiers verify against their corresponding available key.
- Unknown/missing versions fail closed. Old key versions must remain available while their bindings need verification. No automatic rotation or Secret Manager call.

## Error and privacy boundary
- Structured categories: retryableUnavailable, rateLimited, unauthenticatedCredential, permissionDenied, notFound, invalidArgument, malformedResponse, configurationError, permanentPurchaseState.
- HTTP status plus canonical Google status/reason are inspected; e.g. quota errors on 403 remain retryable while SERVICE_DISABLED is configuration.
- Existing domain interfaces deliberately receive their existing coarse unavailable/configuration outcomes; safe diagnostics preserve the finer category.
- Raw exception messages, request URLs, tokens and full responses are never attached to domain errors or diagnostics.
- Diagnostics contain operation/category/retryable only; a failing sink cannot break purchase processing.
- REST permits only the three required methods, fixed origin/package, no redirects, bounded I/O and response size, fatal UTF-8 decoding.
- No adapter imports Firestore or writes ledger/grant/entitlement. No new direct Auth deletion shortcut or callable export.
- Tests disable default fetch and inject fake credentials/transport. Synthetic tokens only.

## Validation
- Strict TypeScript build: PASS.
- Full unit suite: 168 PASS, including 56 new adapter/provider/transport tests.
- Full demo emulator/rules/Admin/concurrency suite: 351 PASS, 0 failures. Total backend: 519 PASS.
- Coverage includes purchase states, error mapping, ack replay/ambiguous success, no consume, voided pagination/window/refund safety, Admin deletion, old/current HMAC keys, response caps and token privacy.
- Full backend regression includes N3, N4A, revoke, maintenance, deletion/P0C.1, rules and concurrency contracts.
- Flutter not rerun: no Flutter source changes in this phase, as requested.
- Diff check: PASS; tracked diff plus explicit whitespace/conflict-marker check of all new/changed phase files.

## Remaining limitations / P0C.2B prerequisites
- Local/mock readiness is not live Play readiness. Real response/permission and purchase/refund tests remain mandatory before paid release.
- Voided evidence is bounded by Google's window and configured scan cap. Missing identity or exhausted scan needs recheck/operator action, not a false downgrade.
- Unsupported future offer shapes fail closed; deliberately do not invent entitlement semantics for rental, preorder or multi-quantity purchases.
- Rotation provider is ready; end-to-end production key loading and registry/bootstrap composition still belong to P0C.2B.
- P0C.2B must wire adapters through existing lifecycle services, preserve verified deletion claims, supply ADC/runtime keys, and add authenticated exports/RTDN/scheduler wrappers separately.
- No current adapter runtime was instantiated against Google. No known P0/P1 identified in local adapter tests; production validation remains outstanding.

PRODUCTION FIREBASE CHANGES: NONE
GOOGLE CLOUD CHANGES: NONE
PLAY CONSOLE CHANGES: NONE
IAM/API CHANGES: NONE
PRODUCTION DEPLOY: NONE
LIVE GOOGLE API CALLS: NONE
REAL PLAY PURCHASE TEST: NOT PERFORMED
BLAZE UPGRADE: NOT PERFORMED
COMMIT: NONE
PUSH: NONE
