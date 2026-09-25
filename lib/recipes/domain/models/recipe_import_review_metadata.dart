import 'dart:convert';
import '../../../core/domain/measurement_units.dart';
import 'recipe_import_draft.dart';
import 'web_import_issue.dart';

String ingredientRevision(RecipeImportIngredientDraft v) =>
    jsonEncode([v.name, v.quantity?.toString(), v.unit, v.rawQuantityText]);

/// Temporary, immutable review data. Never serialized into a saved Recipe.
class WebIngredientReview {
  WebIngredientReview({
    required this.id,
    required this.original,
    required this.value,
    required Iterable<WebImportIssue> issues,
    this.acceptedRevision,
  }) : issues = List.unmodifiable(issues);
  final String id;
  final RecipeImportIngredientDraft original, value;
  final List<WebImportIssue> issues;
  final String? acceptedRevision;
  String get revision => jsonEncode([
    id,
    ingredientRevision(value),
    original.rawText,
    issues.map((i) => [i.identity, i.severity.name, i.evidence]).toList(),
  ]);
  bool get accepted => acceptedRevision == revision;
  Iterable<WebImportIssue> get unresolved => issues.where(
    (i) =>
        i.severity == WebImportSeverity.blocking ||
        i.severity == WebImportSeverity.review && !accepted,
  );
  WebIngredientReview accept() => WebIngredientReview(
    id: id,
    original: original,
    value: value,
    issues: issues,
    acceptedRevision: revision,
  );
}

class RecipeImportReviewMetadata {
  RecipeImportReviewMetadata({
    required this.title,
    required this.preparation,
    required Iterable<WebIngredientReview> rows,
    Iterable<WebImportIssue> issues = const [],
    this.acceptedRecipeRevision,
  }) : rows = List.unmodifiable(rows),
       issues = List.unmodifiable(issues) {
    if (this.rows.map((r) => r.id).toSet().length != this.rows.length) {
      throw ArgumentError('Duplicate review row id');
    }
  }
  final String title, preparation;
  final List<WebIngredientReview> rows;
  final List<WebImportIssue> issues;
  final String? acceptedRecipeRevision;
  String get revision => jsonEncode([
    title,
    preparation,
    rows.map((r) => r.revision).toList(),
    issues.map((i) => [i.identity, i.severity.name, i.evidence]).toList(),
  ]);
  Iterable<WebImportIssue> get unresolved sync* {
    for (final issue in issues) {
      if (issue.severity == WebImportSeverity.blocking ||
          issue.severity == WebImportSeverity.review &&
              acceptedRecipeRevision != revision) {
        yield issue;
      }
    }
    for (final row in rows) {
      yield* row.unresolved;
    }
  }

  /// Additional web-review readiness; normal editor validation still applies.
  bool get canSave =>
      title.trim().isNotEmpty &&
      preparation.trim().isNotEmpty &&
      rows.isNotEmpty &&
      rows.every(
        (r) =>
            r.value.name.trim().isNotEmpty &&
            r.value.quantity != null &&
            r.value.quantity!.isFinite &&
            r.value.quantity! > 0 &&
            MeasurementUnits.values.contains(r.value.unit),
      ) &&
      unresolved.isEmpty;
  RecipeImportReviewMetadata acceptRecipe() => RecipeImportReviewMetadata(
    title: title,
    preparation: preparation,
    rows: rows,
    issues: issues,
    acceptedRecipeRevision: revision,
  );
  RecipeImportReviewMetadata acceptRow(String id) => RecipeImportReviewMetadata(
    title: title,
    preparation: preparation,
    rows: rows.map((r) => r.id == id ? r.accept() : r),
    issues: issues,
    acceptedRecipeRevision: acceptedRecipeRevision,
  );
  RecipeImportReviewMetadata withRows(Iterable<WebIngredientReview> values) =>
      RecipeImportReviewMetadata(
        title: title,
        preparation: preparation,
        rows: values,
        issues: issues,
      );
  RecipeImportReviewMetadata removeRow(String id) =>
      withRows(rows.where((r) => r.id != id));
  RecipeImportReviewMetadata withContent({
    required String title,
    required String preparation,
  }) => RecipeImportReviewMetadata(
    title: title,
    preparation: preparation,
    rows: rows,
    issues: issues,
  );
}
