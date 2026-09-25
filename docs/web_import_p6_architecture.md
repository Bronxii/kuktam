# Web import P6 architecture update (P6.1)

## Final product decisions
Text import, web import and cloud sync are FREE. No Pro gate is introduced.
Future recipe count limits belong to the existing explicit Save path.
Every syntactically valid HTTP/HTTPS URL can be considered for a generic attempt,
subject to network security. Known domains are NOT an access allowlist.
Unknown domains receive REVIEW metadata. Nosalty receives a quantity-review
notice; Mindmegette exposes its exact title suffix for P6.2 normalization.

## Boundaries
Input classifier -> URL/security validator -> cancellable GET -> shared JSON-LD
extractor -> structural quality gate. P6.2 will add normalization and parser
warning diagnostics before editor handoff. There is no UI hookup or persistence
in P6.1. FAIL must never hand off; PASS/REVIEW must use the existing editable
editor and explicit Save. Structural PASS alone is not full draft approval.

## File map and shared core
- lib/recipes/domain/models/web_recipe_candidate.dart: immutable candidate facade.
- lib/recipes/domain/models/web_import_issue.dart: typed failures and issues.
- lib/recipes/domain/models/web_import_quality.dart: quality result and handoff guard.
- lib/recipes/domain/services/recipe_import_input_classifier.dart: URL/text routing.
- lib/recipes/domain/services/web_import_url_validator.dart: URL and DNS restrictions.
- lib/recipes/domain/services/web_import_domain_policy.dart: source metadata only.
- lib/recipes/domain/services/recipe_json_ld_extractor.dart: production facade.
- lib/recipes/domain/services/web_import_quality_gate.dart: pure structural gate.
- lib/recipes/data/services/web_recipe_fetcher.dart: injectable native I/O fetcher.
- packages/recipe_json_ld_core/: pure Dart extractor and immutable candidate.
- tool/web_import_poc/lib/extractor.dart: adapter to that same shared core.
- test/recipes/web_import_services_test.dart and web_recipe_fetcher_test.dart.

The separate pure Dart package is necessary because the standalone Dart POC
cannot depend on the Flutter application package. There is one extractor
implementation; historical snapshots/reports and benchmark logic stay in POC.
html 0.15.7 provides actual HTML parsing, with csslib transitive dependency.
No scraping framework, backend, AI, cookies, authentication or browser execution.

## Network security and limits
GET only, 20-second connection timeout, 30-second whole-operation timeout,
5 redirects maximum, 5 MiB decompressed body maximum. HTML/XHTML MIME required.
Every redirect receives URL and DNS checks; HTTPS-to-HTTP downgrade fails.
IP literals, credentials, non-default ports, local/private/link-local and
non-public address ranges are rejected. Mixed public/private DNS answers fail.
Sockets connect to the validated DNS address; original hostname remains the
HTTP/TLS identity. System proxy is disabled, TLS certificate validation remains.
A per-operation HttpClient is force-closed on cancel/timeout; connecting socket
tasks are cancelled. An OS DNS lookup cannot itself be cancelled through Dart,
but late completion cannot initiate network I/O after cancellation.
403 and 429 have distinct typed failures; all other non-2xx statuses also fail.
No retries. Original URL and final successful URL remain separate metadata.
Decoding: UTF-8 BOM, then HTTP charset, HTML charset, strict UTF-8 default.
Unknown encodings fail explicitly; this is not a universal browser decoder.
Only the first validated DNS address is attempted; no automatic address retries.
No global Android cleartext exception is enabled. Release INTERNET permission
was confirmed in the existing merged release manifest; no native change needed.

## Quality gate
FAIL: fetch failure, absent/invalid recipe, absent title/ingredients/preparation,
multiple candidates, or explicit blocking diagnostic.
Conservatively, malformed companion JSON-LD or invalid candidate entries fail;
no guessing among valid/invalid candidate combinations.
REVIEW: unknown domain, known source risk, review diagnostic/structure notice.
PASS: complete known-source structure without issues.
No warning-count/accuracy threshold is introduced. Review warnings alone never
become FAIL. P6.2 must classify usable ingredients and critical ambiguities.
Nosalty notice: Az automatikus import nem minden esetben egyezik pontosan az
oldalon lathato recepttel. Mentes elott ellenorizd a mennyisegeket.
(The production metadata contains the accented Hungarian text.)

## Next scope (not implemented)
P6.2: safe domain-bound title/instruction normalization, production parser
adapter, row-level unsupported/silent-db-fallback diagnostics, severity and
usable-draft checks. Preserve raw source, do not invent missing quantities.
Later UI: keep input on failure, offer text import, never auto-save, cancel stale
requests on route/account changes. Live-device TLS/HTTP/cancellation validation
and pathological HTML resource/performance checks remain release QA work.


## P6.2 implementation
The pure offline WebRecipeImportService accepts extraction plus final source URL
and a caller-owned import-session ID. WebRecipeNormalizer retains raw title and
rows, normalizes entities/whitespace and joins step headings to their bodies.
Only the exact Mindmegette suffix is removed on known Mindmegette hosts.
RecipeTextParser is invoked unchanged once per normalized ingredient using an
explicit ingredient section; JSON-LD title/preparation bypass free-text guessing.
Unrecognized/skipped parser rows remain as blocking repairable rows, never vanish.

WebImportWarningDetector audits existing output; its bounded risk vocabulary is
NOT a canonical unit dictionary. Specific range/multiplier/fraction/textual
quantity evidence and existing parser warnings drive issues. Ordinary Hungarian
size adjectives do not trigger unknown-unit guesses. This detector cannot promise
to recognize every unfamiliar unit or detect hidden visible-page/JSON-LD changes.
Nosalty always gets recipe-level KNOWN_SOURCE_RISK; generic sources receive
UNVERIFIED_SOURCE. No source scraping or automatic quantity repair is performed.

WebRecipeImportResult wraps the existing RecipeImportDraft plus immutable review
metadata; RecipeImportDraft itself and editor/text-import behavior are unchanged.
Rows have import-session/source-index IDs, original parser evidence, current
values, issue origin/field/evidence/message key and value-bound acceptance.
Editing re-audits the row and revokes acceptance; deletion drops row review state.
Recipe-level acceptance is bound to title, preparation, row values and issues.
BLOCKING issues cannot be dismissed by acceptance. canSave is additional review
readiness, never a substitute for the editor's validation/name uniqueness rules.

Gate: empty title/preparation, zero usable rows or recipe-level blocking issues
FAIL. A mixture of usable and blocking repairable rows yields REVIEW and may be
edited; it cannot be saved until repaired. Any number of unsupported REVIEW rows
remains REVIEW. INFO does not block. No runtime accuracy/ratio claim is made.
Structural P6.1 checks still precede parser adaptation. No UI/fetch orchestration
is added, and no metadata is written to Firestore.

Next P6.3: shared text/URL input, cancellable loading/error state and retained
input, dispatch to existing text flow or web pipeline. Review-aware editor handoff
must carry the wrapper metadata; do not discard it and allow blind saving.
The editor's visual warning/acceptance work requires its separately approved phase.


## P6.3 shared dialog and async orchestration
RecipeImportDialog remains the single multiline entry point. The existing
classifier selects exactly-one-URL versus unchanged text parsing, retaining the
20,000-code-point input limit (downloaded HTML uses the fetcher's separate cap).
WebRecipeImportLoader composes the cancellable fetcher with the shared extractor
and P6.2 service. No allowlist/Pro gate, retries or browser fallback is introduced.

During a request, input and processing are disabled and a live-region loading
indicator is shown. Each operation has a session/operation ID and cancellation
token. Cancel/Back immediately cancels I/O before the existing discard confirmation;
keeping the dialog afterward permits retry. Dispose and MainScreen account-subtree
replacement invalidate the operation. Late success/error cannot pop or hand off.
The parent lifetime token also removes a surviving root-navigator dialog route.

PASS hands off once. REVIEW displays a recipe-level notice and a Continue-to-editor
button; it does NOT accept or resolve any review issue. Nosalty explicitly asks
for quantity checking. FAIL/error keeps the URL and dialog open with a short
Hungarian message, allowing retry or pasted text instead. Raw errors are hidden.

WebRecipeImportHandoff extends the old RecipeImportDraft route contract and retains
WebRecipeImportResult, original URL, final URL and source metadata. MainScreen
passes the same object as initialImport and webImport to AddRecipeScreen. The latter
is plumbing only: there is no editor review UI or acceptance enforcement yet.
This intermediate P6.3 state is NOT release-ready for review enforcement; P6.4 must
bind metadata to edits/deletions and Save validation before production release.
The existing text branch, parser, editor controls and Firestore schema are unchanged.

Next P6.4: row-level warning presentation, recipe/source notices, explicit review
acceptance, re-audit after edits/deletions and Save readiness integration. No AI,
monetization, candidate chooser or source scraping belongs to that work.
