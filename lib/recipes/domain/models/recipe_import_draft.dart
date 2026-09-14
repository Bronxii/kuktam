/// Import hints only; not editor validation errors or persisted recipe data.
enum RecipeImportWarning {
  unknownUnit,
  missingQuantity,
  invalidQuantity,
  ambiguousIngredient,
}

class RecipeImportIngredientDraft {
  RecipeImportIngredientDraft({
    required this.sourceOrder,
    required this.rawText,
    required this.name,
    required this.quantity,
    required this.rawQuantityText,
    required this.unit,
    Iterable<RecipeImportWarning> warnings = const [],
  }) : warnings = List.unmodifiable(warnings);

  /// Zero-based source line index, including headings and empty lines.
  final int sourceOrder;
  final String rawText;
  final String name;

  /// P1-normalized quantity in [unit], or null when repair is required.
  final double? quantity;

  /// Original quantity token (before conversion); null means missing/ambiguous.
  /// Do not use this as editor text for the normalized unit.
  final String? rawQuantityText;
  final String unit;
  final List<RecipeImportWarning> warnings;
}

/// Immutable, temporary parser output. No persistence or UI dependencies.
class RecipeImportDraft {
  RecipeImportDraft({
    required this.originalText,
    required this.title,
    required Iterable<RecipeImportIngredientDraft> ingredients,
    required this.preparationText,
    required Iterable<String> unprocessedSegments,
  }) : ingredients = List.unmodifiable(ingredients),
       unprocessedSegments = List.unmodifiable(unprocessedSegments);

  final String originalText;
  final String title;
  final List<RecipeImportIngredientDraft> ingredients;
  final String preparationText;

  /// Unclassified lines, including metadata/export footer, in source order.
  final List<String> unprocessedSegments;
}
