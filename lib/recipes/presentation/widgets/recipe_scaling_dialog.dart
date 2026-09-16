import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../../shopping/data/repositories/shopping_repository.dart';

import '../../domain/models/recipe.dart';
import '../../domain/services/recipe_scaler.dart';

typedef AddScalingShoppingItems = Future<void> Function(List<ShoppingItemInput> items);

class RecipeScalingDialog extends StatefulWidget {
  const RecipeScalingDialog({
    super.key,
    required this.ingredients,
    this.addShoppingItems,
  });

  final List<RecipeIngredient> ingredients;
  final AddScalingShoppingItems? addShoppingItems;

  @override
  State<RecipeScalingDialog> createState() => _RecipeScalingDialogState();
}

class _RecipeScalingDialogState extends State<RecipeScalingDialog> {
  static const _scaler = RecipeScaler();
  late final List<RecipeIngredient> _originalIngredients;
  late List<RecipeIngredient> _scaledIngredients;
  late final List<_ScalingRowState> _rows;
  Timer? _debounce;
  int _revision = 0;
  ({int index, int revision, String text, String unit})? _pending;
  bool _isConfirmingClose = false;
  bool _isAdding = false;
  String? _shoppingError;

  Future<void> _addToShopping() async {
    if (_isAdding || _isConfirmingClose || _rows.isEmpty) return;
    _processPending();
    for (final row in _rows) {
      _finishEditing(row);
    }
    if (_rows.any((row) => row.error != null || row.initialDisplay == null)) {
      return;
    }
    final items = <({String name, double quantity, String unit})>[];
    for (final row in _rows) {
      final ingredient = _scaledIngredients[row.index];
      final shopping = _scaler.normalizeForShopping(
        quantity: ingredient.quantity,
        unit: ingredient.unit,
      );
      items.add((
        name: row.original.name,
        quantity: shopping.quantity,
        unit: shopping.unit,
      ));
    }
    final snapshot =
        List<({String name, double quantity, String unit})>.unmodifiable(items);
    setState(() {
      _isAdding = true;
      _shoppingError = null;
    });
    FocusScope.of(context).unfocus();
    try {
      final add = widget.addShoppingItems ?? ShoppingRepository().addOrMergeItems;
      await add(snapshot);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isAdding = false;
        _shoppingError =
            'Nem sikerült hozzáadni a tételeket a bevásárlólistához. Ellenőrizd a listát, majd próbáld újra.';
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _originalIngredients = List.unmodifiable(widget.ingredients);
    _scaledIngredients = _originalIngredients;
    _rows = List.unmodifiable([
      for (var i = 0; i < _originalIngredients.length; i++)
        _ScalingRowState(index: i, original: _originalIngredients[i]),
    ]);
    for (final row in _rows) {
      row.focusListener = () {
        if (!row.focusNode.hasFocus) _finishEditing(row);
      };
      row.focusNode.addListener(row.focusListener);
    }
  }

  @override
  void dispose() {
    _cancelPending();
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  void _reset() {
    _cancelPending();
    _scaledIngredients = _originalIngredients;
    setState(() {
      for (final row in _rows) {
        row.reset();
      }
    });
    FocusScope.of(context).unfocus();
  }

  void _cancelPending() {
    _debounce?.cancel();
    _debounce = null;
    _pending = null;
    _revision++;
  }

  void _onChanged(_ScalingRowState row, String text) {
    _cancelPending();
    final revision = _revision;
    setState(() {
      row.hasUserDraft = true;
      row.error = null;
    });
    _pending = (
      index: row.index,
      revision: revision,
      text: text,
      unit: row.displayUnit,
    );
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted && _pending?.revision == revision) _processPending();
    });
  }

  void _processPending() {
    final pending = _pending;
    if (pending == null || !mounted) return;
    // Consume before processing: Done followed by blur cannot scale twice.
    _cancelPending();
    final basis = _rows[pending.index];
    final parsed = _scaler.parseQuantity(pending.text);
    if (parsed == null) {
      setState(() {
        basis.error = 'Adj meg 0-nál nagyobb érvényes mennyiséget.';
      });
      return;
    }
    try {
      final target = _scaler.convertQuantity(
        quantity: parsed,
        fromUnit: pending.unit,
        toUnit: basis.original.unit,
      );
      final scaled = _scaler.scale(
        originalIngredients: _originalIngredients,
        basisIndex: pending.index,
        targetQuantity: target,
      );
      // Prepare every display value before changing the last successful state.
      final displays = [
        for (final ingredient in scaled)
          _scaler.normalizeForDisplay(
            quantity: ingredient.quantity,
            unit: ingredient.unit,
          ),
      ];
      setState(() {
        _scaledIngredients = scaled;
        for (final row in _rows) {
          row.error = null;
          if (row == basis && row.focusNode.hasFocus) {
            // Preserve the active raw text, selection, composing range and unit.
            row.displayQuantity = parsed;
          } else {
            row.showDisplay(displays[row.index]);
          }
        }
      });
    } on ArgumentError {
      setState(() {
        basis.error = 'A megadott mennyiséggel a recept nem számítható át.';
      });
    }
  }

  void _finishEditing(_ScalingRowState row) {
    if (!mounted) return;
    if (_pending?.index == row.index) _processPending();
    if (!row.hasUserDraft || row.error != null) return;
    // A debounce may already have calculated this draft. Only format it here.
    final ingredient = _scaledIngredients[row.index];
    setState(() {
      row.showDisplay(
        _scaler.normalizeForDisplay(
          quantity: ingredient.quantity,
          unit: ingredient.unit,
        ),
      );
    });
  }

  Future<void> _requestClose() async {
    if (_isConfirmingClose || _isAdding) return;
    _isConfirmingClose = true;
    FocusScope.of(context).unfocus();
    final shouldClose = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (confirmationContext) => AlertDialog(
        title: const Text('Kilépsz az átszámításból?'),
        content: const SingleChildScrollView(
          child: Text('Az átszámított értékek elvesznek.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(confirmationContext).pop(false),
            child: const Text('Mégsem'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(confirmationContext).pop(true),
            child: const Text('Kilépés'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    _isConfirmingClose = false;
    if (shouldClose == true) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _requestClose();
      },
      child: Dialog(
        insetPadding: const EdgeInsets.all(16),
        constraints: const BoxConstraints(minWidth: 0, maxWidth: 640),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Dialog already subtracts keyboard viewInsets and safe margins.
            return SizedBox(
              width: constraints.maxWidth,
              height: math.min(720, constraints.maxHeight * 0.9),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Átszámítás',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Bezárás',
                          onPressed: _isAdding ? null : _requestClose,
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Az átszámítás ideiglenes, az eredeti recept nem változik.',
                    ),
                    const SizedBox(height: 20),
                    if (_rows.isEmpty)
                      const Text('A recept nem tartalmaz hozzávalókat.'),
                    for (final row in _rows)
                      Padding(
                        key: ValueKey('scaling-row-${row.index}'),
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _buildRow(row),
                      ),
                    const SizedBox(height: 8),
                    OverflowBar(
                      alignment: MainAxisAlignment.end,
                      overflowAlignment: OverflowBarAlignment.end,
                      spacing: 8,
                      overflowSpacing: 8,
                      children: [
                        TextButton(
                          onPressed: _isAdding ? null : _reset,
                          child: const Text('Visszaállítás'),
                        ),
                        FilledButton(
                          onPressed: _isAdding || _rows.isEmpty
                              ? null
                              : _addToShopping,
                          child: const Text('Bevásárlólistához adás'),
                        ),
                      ],
                    ),
                    if (_shoppingError != null)
                      Text(
                        _shoppingError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildRow(_ScalingRowState row) {
    final amount = TextField(
      key: ValueKey('scaling-quantity-${row.index}'),
      controller: row.controller,
      focusNode: row.focusNode,
      enabled: !_isAdding && row.initialDisplay != null,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.done,
      onChanged: (text) => _onChanged(row, text),
      onSubmitted: (_) => _finishEditing(row),
      decoration: InputDecoration(
        labelText: 'Mennyiség',
        border: const OutlineInputBorder(),
        errorText: row.initialDisplay == null
            ? 'Érvénytelen mennyiség'
            : row.error,
        errorMaxLines: 3,
      ),
    );
    final name = Text(row.original.name);
    final unit = Text(row.displayUnit);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < 400 ||
            MediaQuery.textScalerOf(context).scale(16) > 20;
        final quantityAndUnit = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: amount),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: unit,
              ),
            ),
          ],
        );
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [name, const SizedBox(height: 8), quantityAndUnit],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: name),
            const SizedBox(width: 16),
            Expanded(child: quantityAndUnit),
          ],
        );
      },
    );
  }
}

/// A stable original snapshot and independent display draft for one row.
class _ScalingRowState {
  _ScalingRowState({required this.index, required this.original}) {
    try {
      initialDisplay = _scaler.normalizeForDisplay(
        quantity: original.quantity,
        unit: original.unit,
      );
    } on ArgumentError {
      // Existing malformed recipes must not crash the new dialog.
      initialDisplay = null;
    }
    reset();
  }

  static const _scaler = RecipeScaler();
  final int index;
  final RecipeIngredient original;
  late final ({double quantity, String unit})? initialDisplay;
  double? displayQuantity;
  late String displayUnit;
  final controller = TextEditingController();
  final focusNode = FocusNode();
  late final VoidCallback focusListener;
  String? error;
  bool hasUserDraft = false;

  void showDisplay(({double quantity, String unit}) display) {
    displayQuantity = display.quantity;
    displayUnit = display.unit;
    hasUserDraft = false;
    final text = _scaler.formatQuantity(display.quantity, unit: display.unit);
    if (controller.text != text) {
      controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  void reset() {
    error = null;
    hasUserDraft = false;
    displayQuantity = initialDisplay?.quantity;
    displayUnit = initialDisplay?.unit ?? original.unit;
    final text = displayQuantity == null
        ? ''
        : _scaler.formatQuantity(displayQuantity!, unit: displayUnit);
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void dispose() {
    focusNode.removeListener(focusListener);
    controller.dispose();
    focusNode.dispose();
  }
}
