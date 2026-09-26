# ARCHIVED — production webimport removed

The integration tests were removed after the feature was cancelled on 2026-09-26.
These fixtures and hashes remain historical evidence only. The Flutter command
below is historical and no longer runnable; no production dependency exists.

---

# P6.6 offline integration fixtures

The tests use unchanged P1 HTML snapshots 01, 03 and 07 directly.
snapshots.json pins their original URL, path and SHA256. No corpus or POC report is rewritten.

Run from the repository root:
- powershell -File test/fixtures/web_import_integration/verify_snapshots.ps1
- flutter test --no-pub test/recipes/web_import_e2e_test.dart

clean.html, review.html and blocking.html are synthetic local fixtures, not modified benchmark evidence.
They isolate clean/generic, unsupported-unit and invalid-quantity states.

The harness injects only DNS/HTTP transport and repository dependencies.
It uses production fetcher, loader, extractor, normalizer, parser, gate, MainScreen, dialog and editor.
Asynchronous stream processing is awaited with WidgetTester.runAsync; no live website is requested.

Mindmegette 01 has an ingredient-level missing-quantity review, but no recipe-level source gate.
The synthetic clean fixture separately asserts known-source PASS.
Nosalty 07 retains its source zero quantity until an explicit test user edit.
Snapshot 03 covers a longer, 14-row recipe with multiple warnings.
