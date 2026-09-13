enum ShoppingImportIssue { invalidQuantity, missingName, ambiguous }

/// Local parser output only. Raw input survives even an ambiguous parse.
class ShoppingImportDraft {
  const ShoppingImportDraft({
    required this.rawSegment,
    required this.sourceIndex,
    required this.name,
    required this.quantityText,
    required this.quantity,
    required this.unit,
    required this.quantityWasMissing,
    this.issue,
  });

  final String rawSegment;

  /// Zero-based segment position, including skipped empty segments.
  final int sourceIndex;
  final String name;
  final String quantityText;
  final double? quantity;
  final String unit;
  final bool quantityWasMissing;
  final ShoppingImportIssue? issue;
  bool get hasError => issue != null;
}
