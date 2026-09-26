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
    Iterable<String> acceptedIssues = const [],
  }) : issues = List.unmodifiable(issues),
       acceptedIssues = Set.unmodifiable(acceptedIssues);
  final String id;
  final RecipeImportIngredientDraft original, value;
  final List<WebImportIssue> issues;
  final String? acceptedRevision;
  final Set<String> acceptedIssues;
  String get revision => jsonEncode([
    id,
    ingredientRevision(value),
    original.rawText,
    issues.map((i) => [i.identity, i.severity.name, i.evidence]).toList(),
  ]);
  bool isAccepted(WebImportIssue issue) =>
      issue.severity == WebImportSeverity.review &&
      acceptedRevision == revision &&
      acceptedIssues.contains(issue.identity);
  bool get accepted =>
      issues
          .where((i) => i.severity == WebImportSeverity.review)
          .every(isAccepted) &&
      acceptedRevision == revision;
  WebIngredientReview acceptIssue(WebImportIssue issue) => WebIngredientReview(
    id: id,
    original: original,
    value: value,
    issues: issues,
    acceptedRevision: revision,
    acceptedIssues: {
      ...(acceptedRevision == revision ? acceptedIssues : <String>{}),
      if (issue.severity == WebImportSeverity.review && issues.contains(issue))
        issue.identity,
    },
  );
  Iterable<WebImportIssue> get unresolved => issues.where(
    (i) =>
        i.severity == WebImportSeverity.blocking ||
        i.severity == WebImportSeverity.review && !isAccepted(i),
  );
  WebIngredientReview accept() => WebIngredientReview(
    id: id,
    original: original,
    value: value,
    issues: issues,
    acceptedRevision: revision,
    acceptedIssues: issues
        .where((i) => i.severity == WebImportSeverity.review)
        .map((i) => i.identity),
  );
}

class RecipeImportReviewMetadata {
  RecipeImportReviewMetadata({
    required this.title,
    required this.preparation,
    required Iterable<WebIngredientReview> rows,
    Iterable<WebImportIssue> issues = const [],
    this.acceptedRecipeRevision,
    Iterable<String> acceptedRecipeIssues = const [],
  }) : rows = List.unmodifiable(rows),
       issues = List.unmodifiable(issues),
       acceptedRecipeIssues = Set.unmodifiable(acceptedRecipeIssues) {
    if (this.rows.map((r) => r.id).toSet().length != this.rows.length) {
      throw ArgumentError('Duplicate review row id');
    }
  }
  final String title, preparation;
  final List<WebIngredientReview> rows;
  final List<WebImportIssue> issues;
  final String? acceptedRecipeRevision;
  final Set<String> acceptedRecipeIssues;
  bool isRecipeIssueAccepted(WebImportIssue issue) =>
      issue.severity == WebImportSeverity.review &&
      acceptedRecipeRevision == revision &&
      acceptedRecipeIssues.contains(issue.identity);
  RecipeImportReviewMetadata acceptRecipeIssue(WebImportIssue issue) =>
      RecipeImportReviewMetadata(
        title: title,
        preparation: preparation,
        rows: rows,
        issues: issues,
        acceptedRecipeRevision: revision,
        acceptedRecipeIssues: {
          ...(acceptedRecipeRevision == revision
              ? acceptedRecipeIssues
              : <String>{}),
          if (issue.severity == WebImportSeverity.review &&
              issues.contains(issue))
            issue.identity,
        },
      );
  RecipeImportReviewMetadata acceptRowIssue(String id, WebImportIssue issue) =>
      RecipeImportReviewMetadata(
        title: title,
        preparation: preparation,
        rows: rows.map((r) => r.id == id ? r.acceptIssue(issue) : r),
        issues: issues,
        acceptedRecipeRevision: acceptedRecipeRevision,
        acceptedRecipeIssues: acceptedRecipeIssues,
      );
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
              !isRecipeIssueAccepted(issue)) {
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
    acceptedRecipeIssues: issues
        .where((i) => i.severity == WebImportSeverity.review)
        .map((i) => i.identity),
  );
  RecipeImportReviewMetadata acceptRow(String id) => RecipeImportReviewMetadata(
    title: title,
    preparation: preparation,
    rows: rows.map((r) => r.id == id ? r.accept() : r),
    issues: issues,
    acceptedRecipeRevision: acceptedRecipeRevision,
    acceptedRecipeIssues: acceptedRecipeIssues,
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
