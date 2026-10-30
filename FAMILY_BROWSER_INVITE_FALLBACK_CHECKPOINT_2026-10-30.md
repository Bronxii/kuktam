# Family browser invite fallback — 2026-10-30

Status: **LOCAL PASS — AWAITING EXPLICIT HOSTING DEPLOYMENT GO**.

## Scope and behavior

The previous public browser observation for `https://kuktam-67768.web.app/family/invite?token=test` was 404. No public HTTP recheck or deployment was performed in this phase; this checkpoint proves the local implementation only.

New `hosting/family-invite.html` is a small Hungarian informational page with semantic main/h1, responsive viewport, system fonts, and existing product colors from `lib/core/theme/app_colors.dart`: Forest Green `#2E7D32`, Cream `#FAF5EE`, text `#222222`. Text branding avoids any new asset dependency. It explains opening the original invitation on an Android device with Kuktám installed, or installing and reopening it. It does not promise automatic opening or restoration. No Store button is included because no verified listing is needed for this informational fallback.

`firebase.json` adds exactly one rewrite:

```json
{"source":"/family/invite","destination":"/family-invite.html"}
```

The exact rewrite keeps the canonical no-trailing-slash path without a directory redirect or a global clean-URL change. It is not a catch-all or SPA rewrite. Existing site `kuktam-67768`, public root `hosting`, ignore rules and DAL Content-Type header are unchanged. All non-Hosting configuration is unchanged. The static destination is also directly addressable as `/family-invite.html` and contains the same harmless information.

## Security boundary

Zero JavaScript, external assets, network libraries, forms, outgoing links or analytics. No query reading, token echo, logging, persistence, backend preview, JOIN or login. Page content does not classify invitations as valid, expired, used or revoked. Every query receives identical HTML. The inbound URL can naturally remain in the browser address bar; the page performs no additional transmission of its contents. This is a page-code guarantee, not a claim about the Hosting provider's infrastructure-level request logging.

`lang="hu"`, meaningful title, responsive text/layout and semantic heading are present. No controls require keyboard interaction. A `no-referrer` meta policy avoids forwarding the inbound URL as a referrer; `noindex, nofollow` requests no indexing. No broad security-header/cache configuration or CSP changes were introduced.

Android App Links/native configuration and `hosting/.well-known/assetlinks.json` are untouched. Package remains `com.bronxii.kuktam`; Play certificate remains `AF:21:94:5C:B6:95:4A:D8:F1:8A:00:D4:85:78:FF:B0:AD:60:58:77:A5:9E:3A:D0:96:6E:91:6D:23:A2:E5:CD`.

## Local validation

Used the installed Firebase CLI's own `superstatic` static serving engine, configured with the actual Hosting section and public root, bound only to `127.0.0.1` on an ephemeral port. This is local static Hosting resolution, not a live deployment or a full Firebase emulator-suite claim. No Functions/Flutter tests or Android build ran.

- Seven requests: no query; `token=test`; empty token; synthetic expired/revoked/used strings; malformed-looking plus duplicate token query. All HTTP 200, no redirect, byte-identical HTML.
- `test` is absent from the served HTML.
- Static checks reject scripts, event handlers, query/token logic, fetch/XHR, console/analytics, storage/cookies, forms, outgoing links and CSS/external resource URLs. PASS.
- DAL: HTTP 200, application/json, bytes equal the pre-edit file; exact relation/package/certificate validated. PASS.
- DAL file SHA-256: `aee6e62cd558688d9e31012bf30dd538b0b5f4f29d0203fadde9e18bc5760385` (file digest, not certificate fingerprint).
- `/unrelated-route` remains HTTP 404. Configuration comparison proves the exact rewrite is the only firebase.json change. No `.firebaserc` created.
- Initial harness invocation needed a local-server callback correction and permission to make loopback HTTP requests; no product defect was involved. Corrected validation exited 0.

Bounded temporary validator: `C:/Users/gabor/AppData/Local/Temp/validate-family-fallback.cjs`. No test framework/package dependency was added to the repository.

## Files changed

1. `firebase.json` — exact invite-path rewrite only.
2. `hosting/family-invite.html` — new static informational page.
3. This checkpoint.

No application/backend/native/rules source changes. DAL unchanged. No production data access, deploy, commit or push.

## Deployment gate

Await separate explicit user GO. Prepared command from `C:/Users/gabor/kuktam`:

```powershell
node .\functions\node_modules\firebase-tools\lib\bin\firebase.js deploy --only hosting --project kuktam-67768
```

The sole Hosting configuration explicitly selects site `kuktam-67768`. Expected effect: publish the static fallback and its exact route rewrite while preserving the existing DAL asset. No Functions/rules deployment or Family rollout. No deploy was executed.

After explicit GO and Hosting-only deployment: verify the public canonical route with and without a synthetic query returns identical HTML without redirect; recheck DAL HTTP 200/JSON/body and certificate. Until then the browser release item is locally implemented but not live-closed. Play-signed device verification and production activation planning remain separate blockers.
