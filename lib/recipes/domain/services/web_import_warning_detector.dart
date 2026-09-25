import '../../../core/domain/measurement_units.dart';
import '../../../core/domain/services/import_unit_normalizer.dart';
import '../models/recipe_import_draft.dart';
import '../models/web_import_issue.dart';

/// Risk recognition only: no quantity parsing, conversions or new unit aliases.
class WebImportWarningDetector {
  const WebImportWarningDetector();
  static final _unit = RegExp(
    r'(?<![\p{L}])(?:kis\s+kanál|fej|gerezd|csipet|csokor|mokkáskanál|kávéskanál|tbsp|tsp|cloves?|bunch|handful|rashers?|sticks?|sprigs?|cans?|tins?|pieces?|knob|slices?|cups?|oz|lbs?)(?![\p{L}])',
    caseSensitive: false,
    unicode: true,
  );
  static final _expression = RegExp(
    r'\d+(?:[.,]\d+)?\s*[-–]\s*\d+|\d+\s*[x×]\s*\d+|\d+\s+\d+/\d+|(?<![\p{L}])(?:half|quarter)(?![\p{L}])',
    caseSensitive: false,
    unicode: true,
  );
  static final _quantityInName = RegExp(
    r'(?<![\p{L}\d])(?:\d+(?:[.,/]\d+)*|[\u00bc-\u00be\u2150-\u215e])(?![\p{L}\d])',
    unicode: true,
  );

  List<WebImportIssue> detect({
    required String rowId,
    required RecipeImportIngredientDraft original,
    required RecipeImportIngredientDraft value,
  }) {
    final issues = <WebImportIssue>[];
    void add(
      WebImportIssueCode code,
      WebImportSeverity severity,
      String field, {
      WebImportIssueOrigin origin = WebImportIssueOrigin.webAudit,
    }) {
      if (issues.any((i) => i.code == code)) return;
      issues.add(
        WebImportIssue(
          code,
          severity,
          row: value.sourceOrder,
          rowId: rowId,
          origin: origin,
          field: field,
          evidence: original.rawText,
        ),
      );
    }

    final validQuantity =
        value.quantity != null &&
        value.quantity!.isFinite &&
        value.quantity! > 0;
    if (!validQuantity) {
      add(
        WebImportIssueCode.invalidQuantity,
        WebImportSeverity.blocking,
        'quantity',
        origin: original.warnings.contains(RecipeImportWarning.invalidQuantity)
            ? WebImportIssueOrigin.parser
            : WebImportIssueOrigin.webAudit,
      );
    }
    if (value.name.trim().isEmpty ||
        !RegExp(r'\p{L}', unicode: true).hasMatch(value.name) ||
        !MeasurementUnits.values.contains(value.unit)) {
      add(
        WebImportIssueCode.invalidIngredient,
        WebImportSeverity.blocking,
        'ingredient',
      );
    }
    final sameQuantity = original.quantity == value.quantity;
    final sameUnit = original.unit == value.unit;
    for (final warning in original.warnings) {
      switch (warning) {
        case RecipeImportWarning.invalidQuantity:
          if (!validQuantity) {
            add(
              WebImportIssueCode.invalidQuantity,
              WebImportSeverity.blocking,
              'quantity',
              origin: WebImportIssueOrigin.parser,
            );
          }
        case RecipeImportWarning.ambiguousIngredient:
          if (!validQuantity || _quantityInName.hasMatch(value.name)) {
            add(
              WebImportIssueCode.ambiguousIngredient,
              validQuantity
                  ? WebImportSeverity.review
                  : WebImportSeverity.blocking,
              'ingredient',
              origin: WebImportIssueOrigin.parser,
            );
          }
        case RecipeImportWarning.unknownUnit:
          if (sameUnit) {
            add(
              WebImportIssueCode.unknownUnit,
              WebImportSeverity.review,
              'unit',
              origin: WebImportIssueOrigin.parser,
            );
          }
        case RecipeImportWarning.missingQuantity:
          if (sameQuantity) {
            add(
              WebImportIssueCode.missingQuantity,
              WebImportSeverity.review,
              'quantity',
              origin: WebImportIssueOrigin.parser,
            );
          }
      }
    }
    final unsupported =
        _unit.hasMatch(original.rawText) &&
        (_unit.hasMatch(value.name) ||
            sameUnit && value.unit == MeasurementUnits.db);
    if (unsupported) {
      add(WebImportIssueCode.unsupportedUnit, WebImportSeverity.review, 'unit');
    }
    final unresolved =
        _quantityInName.hasMatch(value.name) ||
        _expression.hasMatch(original.rawText) && sameQuantity;
    if (unresolved) {
      add(
        WebImportIssueCode.unresolvedQuantityExpression,
        WebImportSeverity.review,
        'quantity',
      );
    }
    // Recognize existing canonical/alias tokens using the shared helper only.
    final explicitUnit = original.rawText.split(RegExp(r'\s+')).any((t) {
      final unit = const ImportUnitNormalizer().recognize(t);
      return unit != null && unit.unit != MeasurementUnits.db;
    });
    if (original.warnings.isEmpty &&
        value.unit == MeasurementUnits.db &&
        (unsupported || unresolved || explicitUnit && sameUnit)) {
      add(
        WebImportIssueCode.silentDbFallbackRisk,
        WebImportSeverity.review,
        'unit',
      );
    }
    return List.unmodifiable(issues);
  }
}
