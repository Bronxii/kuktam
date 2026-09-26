import 'package:flutter/foundation.dart';
import '../../../core/domain/services/import_quantity_parser.dart';
import '../../domain/models/recipe_import_review_metadata.dart';
import '../../domain/models/web_import_issue.dart';
import '../../domain/services/web_recipe_import_service.dart';
import 'ingredient_row.dart';

/// Presentation binding only: domain metadata is the review source of truth.
/// Row signals isolate warning rebuilds; existing editor controllers stay owned by editor.
class WebImportReviewController {
  WebImportReviewController(RecipeImportReviewMetadata initial)
    : metadata = ValueNotifier(initial);
  final ValueNotifier<RecipeImportReviewMetadata> metadata;
  final _ids = <IngredientRowData, String>{};
  final _signals = <String, ValueNotifier<WebIngredientReview>>{};
  final _listeners = <IngredientRowData, VoidCallback>{};
  final _snapshots = <IngredientRowData, String>{};
  int revision = 0;

  /// Read-only review gate. Normal field validation remains the editor's job.
  String? get saveBlockMessage {
    var rowReview = false;
    var recipeReview = false;
    for (final issue in metadata.value.unresolved) {
      if (issue.severity == WebImportSeverity.blocking) {
        return 'Javítsd a hibás importált adatokat a mentéshez.';
      }
      if (issue.severity == WebImportSeverity.review) {
        if (issue.rowId == null) {
          recipeReview = true;
        } else {
          rowReview = true;
        }
      }
    }
    if (rowReview) {
      return 'Mentés előtt ellenőrizd a megjelölt importált adatokat.';
    }
    if (recipeReview) {
      return 'Mentés előtt erősítsd meg, hogy ellenőrizted az importált receptet.';
    }
    return null;
  }

  String? idFor(IngredientRowData data) => _ids[data];
  ValueNotifier<WebIngredientReview> signal(String id) => _signals[id]!;
  String _snapshot(IngredientRowData d) =>
      '${d.nameController.text}\u0000${d.amountController.text}\u0000${d.selectedUnit}';
  void watch(IngredientRowData data, {String? id}) {
    if (id != null) {
      _ids[data] = id;
      _signals[id] = ValueNotifier(
        metadata.value.rows.singleWhere((r) => r.id == id),
      );
    }
    _snapshots[data] = _snapshot(data);
    void changed() => update(data);
    _listeners[data] = changed;
    data.nameController.addListener(changed);
    data.amountController.addListener(changed);
  }

  void update(IngredientRowData data) {
    final snapshot = _snapshot(data);
    if (_snapshots[data] == snapshot) return;
    _snapshots[data] = snapshot;
    final id = _ids[data];
    if (id == null) {
      metadata.value = metadata.value.withRows(metadata.value.rows);
    } else {
      metadata.value = const WebRecipeImportService().editRow(
        metadata.value,
        id,
        name: data.nameController.text,
        quantity: const ImportQuantityParser().parse(
          data.amountController.text,
        ),
        unit: data.selectedUnit,
      );
      _signals[id]!.value = metadata.value.rows.singleWhere((r) => r.id == id);
    }
    revision++;
  }

  void contentChanged(String title, String preparation) {
    if (metadata.value.title == title &&
        metadata.value.preparation == preparation) {
      return;
    }
    metadata.value = metadata.value.withContent(
      title: title,
      preparation: preparation,
    );
    revision++;
  }

  void acceptRow(String id, WebImportIssue issue) {
    metadata.value = metadata.value.acceptRowIssue(id, issue);
    _signals[id]!.value = metadata.value.rows.singleWhere((r) => r.id == id);
    revision++;
  }

  void acceptRecipe(WebImportIssue issue) {
    metadata.value = metadata.value.acceptRecipeIssue(issue);
    revision++;
  }

  void added(IngredientRowData data) {
    watch(data);
    metadata.value = metadata.value.withRows(metadata.value.rows);
    revision++;
  }

  void remove(IngredientRowData data) {
    final listener = _listeners.remove(data);
    if (listener != null) {
      data.nameController.removeListener(listener);
      data.amountController.removeListener(listener);
    }
    _snapshots.remove(data);
    final id = _ids.remove(data);
    if (id != null) {
      metadata.value = metadata.value.removeRow(id);
      _signals.remove(id)?.dispose();
    } else {
      metadata.value = metadata.value.withRows(metadata.value.rows);
    }
    revision++;
  }

  void dispose() {
    for (final e in _listeners.entries) {
      e.key.nameController.removeListener(e.value);
      e.key.amountController.removeListener(e.value);
    }
    for (final signal in _signals.values) {
      signal.dispose();
    }
    metadata.dispose();
  }
}
