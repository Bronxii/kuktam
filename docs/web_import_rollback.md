# Webimport rollback — completed

Reference: 0595b89 (fix(ui): make unit dropdown scrolling more discoverable).
Initial working tree: clean. Four later commits introduced webimport.
No reset, commit or push performed.

Production verification: git diff --exit-code 0595b89 -- lib android pubspec.yaml pubspec.lock
returned no differences. This preserves all prior text-import, keyboard/scroll,
unit dropdown, scaling/performance, shopping, auth and release configuration.
RecipeTextParser, RecipeImportDraft and Recipe/Firestore schema are unchanged.

Restored existing files:
- lib/home/presentation/screens/main_screen.dart
- lib/recipes/presentation/screens/add_recipe_screen.dart
- lib/recipes/presentation/widgets/ingredient_row.dart
- lib/recipes/presentation/widgets/recipe_import_dialog.dart
- pubspec.yaml; pubspec.lock regenerated with flutter pub get --offline

Removed files:
- lib/recipes/data/services/web_recipe_fetcher.dart
- lib/recipes/data/services/web_recipe_import_loader.dart
- lib/recipes/domain/models/recipe_import_review_metadata.dart
- lib/recipes/domain/models/web_import_issue.dart
- lib/recipes/domain/models/web_import_quality.dart
- lib/recipes/domain/models/web_recipe_candidate.dart
- lib/recipes/domain/models/web_recipe_import_handoff.dart
- lib/recipes/domain/services/recipe_import_input_classifier.dart
- lib/recipes/domain/services/recipe_json_ld_extractor.dart
- lib/recipes/domain/services/web_import_domain_policy.dart
- lib/recipes/domain/services/web_import_quality_gate.dart
- lib/recipes/domain/services/web_import_url_validator.dart
- lib/recipes/domain/services/web_import_warning_detector.dart
- lib/recipes/domain/services/web_recipe_import_service.dart
- lib/recipes/domain/services/web_recipe_normalizer.dart
- lib/recipes/presentation/widgets/web_import_error_message.dart
- lib/recipes/presentation/widgets/web_import_review.dart
- lib/recipes/presentation/widgets/web_import_review_controller.dart
- test/recipes/recipe_web_import_dialog_test.dart
- test/recipes/web_import_e2e_test.dart
- test/recipes/web_import_editor_review_test.dart
- test/recipes/web_import_error_hardening_test.dart
- test/recipes/web_import_save_gate_test.dart
- test/recipes/web_import_services_test.dart
- test/recipes/web_recipe_fetcher_test.dart
- test/recipes/web_recipe_import_service_test.dart

Dependencies: html, csslib and recipe_json_ld_core removed from app graph.
The shared package remains tool-only with its own resolved dependencies/lock.
No app production imports or build dependency point to it.

Archive: POC, reports, snapshots and corpus retained. Architecture, POC README,
integration fixture README and shared package README explicitly marked cancelled/archived.
Historical reports retain their original findings and are not an active roadmap.
CHANGELOG.md contains no webimport feature; unchanged.

Verification:
- Full Flutter suite: 716 passed, 1 skipped.
- Additional URL-as-text regression: passed (text import suite 15/15).
- POC tests: 62/62.
- Flutter analyzer, POC analyzer, standalone extractor analyzer: clean.
- No webimport references in lib or production pubspec/lock.
- git diff --check: clean.
The retained recipe_text_parser_web_test.dart predates webimport production work:
it tests text/Markdown hardening, so it is intentionally preserved.
