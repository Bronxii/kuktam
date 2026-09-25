import '../models/web_import_issue.dart';
import '../models/web_import_quality.dart';
import 'recipe_json_ld_extractor.dart';
import 'web_import_domain_policy.dart';

/// Structural P6.1 gate. Never estimates ground truth or silently repairs data.
class WebImportQualityGate {
  const WebImportQualityGate();
  WebImportQualityResult evaluate({
    Extraction? extraction,
    WebImportFailure? failure,
    required WebImportSourceMetadata source,
    Iterable<WebImportIssue> diagnostics = const [],
  }) {
    final issues = <WebImportIssue>[...diagnostics];
    void block(WebImportIssueCode c) =>
        issues.add(WebImportIssue(c, WebImportSeverity.blocking));
    if (failure != null) issues.add(failure.issue);
    if (extraction == null) {
      if (failure == null) block(WebImportIssueCode.noRecipe);
    } else {
      final candidates = extraction.recipeCandidates;
      // Conservative MVP: even one valid plus one invalid candidate is ambiguous.
      if (candidates.length > 1) block(WebImportIssueCode.multipleRecipes);
      if (candidates.isEmpty) block(WebImportIssueCode.noRecipe);
      if (extraction.status != Status.success && candidates.length <= 1) {
        block(WebImportIssueCode.invalidRecipe);
      }
      if (candidates.length == 1) {
        final c = candidates.single;
        if (!c.valid) block(WebImportIssueCode.invalidRecipe);
        if (c.title?.trim().isNotEmpty != true) {
          block(WebImportIssueCode.missingTitle);
        }
        if (!c.ingredients.any((s) => s.trim().isNotEmpty)) {
          block(WebImportIssueCode.missingIngredients);
        }
        if (c.preparation.trim().isEmpty) {
          block(WebImportIssueCode.missingPreparation);
        }
      }
    }
    if (source.unknownDomain) {
      issues.add(
        const WebImportIssue(
          WebImportIssueCode.unknownDomain,
          WebImportSeverity.review,
        ),
      );
    }
    if (source.requiresQuantityReview) {
      issues.add(
        const WebImportIssue(
          WebImportIssueCode.knownSourceRisk,
          WebImportSeverity.review,
        ),
      );
    }
    final quality = issues.any((i) => i.severity == WebImportSeverity.blocking)
        ? WebImportQuality.fail
        : issues.isNotEmpty
        ? WebImportQuality.review
        : WebImportQuality.pass;
    return WebImportQualityResult(quality, issues);
  }
}
