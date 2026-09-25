import '../../../core/domain/measurement_units.dart';
import '../models/recipe_import_draft.dart';
import '../models/recipe_import_review_metadata.dart';
import '../models/web_import_issue.dart';
import '../models/web_import_quality.dart';
import 'recipe_json_ld_extractor.dart';
import 'recipe_text_parser.dart';
import 'web_import_domain_policy.dart';
import 'web_import_quality_gate.dart';
import 'web_import_warning_detector.dart';
import 'web_recipe_normalizer.dart';

class WebRecipeImportResult {
  const WebRecipeImportResult({
    required this.quality,
    this.draft,
    this.review,
    this.normalized,
  });
  final WebImportQualityResult quality;
  final RecipeImportDraft? draft;
  final RecipeImportReviewMetadata? review;
  final NormalizedWebRecipe? normalized;
  RecipeImportDraft? get editorDraft => quality.allowsHandoff ? draft : null;
}

/// Offline P6.2 adapter. Fetch orchestration and UI are intentionally separate.
class WebRecipeImportService {
  const WebRecipeImportService({this.parser = const RecipeTextParser()});
  final RecipeTextParser parser;
  static const _gate = WebImportQualityGate();
  static const _detector = WebImportWarningDetector();

  WebRecipeImportResult prepare(
    Extraction extraction, {
    required Uri sourceUrl,
    required String importId,
  }) {
    if (importId.isEmpty) throw ArgumentError.value(importId, 'importId');
    final source = const WebImportDomainPolicy().identify(sourceUrl);
    final structural = _gate.evaluate(extraction: extraction, source: source);
    if (!structural.allowsHandoff) {
      return WebRecipeImportResult(quality: structural);
    }
    final normalized = const WebRecipeNormalizer().normalize(
      extraction.recipeCandidates.single,
      source,
    );
    final rows = <WebIngredientReview>[];
    for (var i = 0; i < normalized.ingredients.length; i++) {
      // Section wrapper invokes the existing parser once per source row.
      // Title/preparation bypass free-text classification because JSON-LD knows them.
      final parsed = parser.parse('Hozzávalók:\n${normalized.ingredients[i]}');
      final p = parsed.ingredients.length == 1
          ? parsed.ingredients.single
          : null;
      final value = RecipeImportIngredientDraft(
        sourceOrder: i,
        rawText: normalized.rawIngredients[i],
        name: p?.name ?? normalized.ingredients[i],
        quantity: p?.quantity,
        rawQuantityText: p?.rawQuantityText,
        unit: p?.unit ?? MeasurementUnits.db,
        warnings: p?.warnings ?? [RecipeImportWarning.ambiguousIngredient],
      );
      final id = '$importId:$i';
      rows.add(
        WebIngredientReview(
          id: id,
          original: value,
          value: value,
          issues: _detector.detect(rowId: id, original: value, value: value),
        ),
      );
    }
    final sourceIssues = structural.issues.map(
      (i) => WebImportIssue(
        i.code == WebImportIssueCode.unknownDomain
            ? WebImportIssueCode.unverifiedSource
            : i.code,
        i.severity,
        origin: WebImportIssueOrigin.source,
        field: 'recipe',
        evidence: sourceUrl.host,
      ),
    );
    return evaluate(
      RecipeImportReviewMetadata(
        title: normalized.title,
        preparation: normalized.preparation,
        rows: rows,
        issues: sourceIssues,
      ),
      normalized: normalized,
    );
  }

  RecipeImportReviewMetadata editRow(
    RecipeImportReviewMetadata review,
    String id, {
    required String name,
    required double? quantity,
    required String unit,
  }) {
    if (!review.rows.any((r) => r.id == id)) {
      throw ArgumentError.value(id, 'rowId');
    }
    return review.withRows(
      review.rows.map((r) {
        if (r.id != id) return r;
        final value = RecipeImportIngredientDraft(
          sourceOrder: r.value.sourceOrder,
          rawText: r.original.rawText,
          name: name,
          quantity: quantity,
          rawQuantityText: r.original.rawQuantityText,
          unit: unit,
          warnings: r.original.warnings,
        );
        return WebIngredientReview(
          id: r.id,
          original: r.original,
          value: value,
          issues: _detector.detect(
            rowId: r.id,
            original: r.original,
            value: value,
          ),
        );
      }),
    );
  }

  WebRecipeImportResult evaluate(
    RecipeImportReviewMetadata review, {
    NormalizedWebRecipe? normalized,
  }) {
    final draft = RecipeImportDraft(
      originalText: review.rows.map((r) => r.original.rawText).join('\n'),
      title: review.title,
      ingredients: review.rows.map((r) => r.value),
      preparationText: review.preparation,
      unprocessedSegments: const [],
    );
    return WebRecipeImportResult(
      draft: draft,
      review: review,
      normalized: normalized,
      quality: _gate.evaluateDraft(draft: draft, review: review),
    );
  }
}
