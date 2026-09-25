import '../models/recipe_import_draft.dart';
import '../models/recipe_import_review_metadata.dart';
import '../models/web_import_issue.dart';
import '../models/web_import_quality.dart';
import 'recipe_json_ld_extractor.dart';
import 'web_import_domain_policy.dart';

/// Structural P6.1 gate. Never estimates ground truth or silently repairs data.
class WebImportQualityGate {
  const WebImportQualityGate();

  /// Handoff is distinct from Save: retain repairable rows alongside usable ones.
  /// No warning-ratio threshold. Any number of review issues remains editable.
  WebImportQualityResult evaluateDraft({
    required RecipeImportDraft draft,
    required RecipeImportReviewMetadata review,
  }) {
    final issues = review.unresolved.toList();
    final usable = review.rows.where(
      (r) => !r.issues.any((i) => i.severity == WebImportSeverity.blocking),
    );
    if (draft.title.trim().isEmpty) {
      issues.add(
        const WebImportIssue(
          WebImportIssueCode.missingTitle,
          WebImportSeverity.blocking,
        ),
      );
    }
    if (draft.preparationText.trim().isEmpty) {
      issues.add(
        const WebImportIssue(
          WebImportIssueCode.missingPreparation,
          WebImportSeverity.blocking,
        ),
      );
    }
    if (usable.isEmpty) {
      issues.add(
        const WebImportIssue(
          WebImportIssueCode.missingIngredients,
          WebImportSeverity.blocking,
        ),
      );
    }
    final fail = issues.any(
      (i) => i.rowId == null && i.severity == WebImportSeverity.blocking,
    );
    return WebImportQualityResult(
      fail
          ? WebImportQuality.fail
          : issues.isNotEmpty
          ? WebImportQuality.review
          : WebImportQuality.pass,
      issues,
    );
  }

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
        : issues.any((i) => i.severity == WebImportSeverity.review)
        ? WebImportQuality.review
        : WebImportQuality.pass;
    return WebImportQualityResult(quality, issues);
  }
}
