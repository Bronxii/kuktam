import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/models/recipe.dart';
import '../../domain/services/recipe_scaler.dart';

class RecipeScalingDialog extends StatefulWidget {
  const RecipeScalingDialog({super.key, required this.ingredients});

  final List<RecipeIngredient> ingredients;

  @override
  State<RecipeScalingDialog> createState() => _RecipeScalingDialogState();
}

class _RecipeScalingDialogState extends State<RecipeScalingDialog> {
  late final List<_ScalingRowState> _rows;
  bool _isConfirmingClose = false;

  @override
  void initState() {
    super.initState();
    _rows = List.unmodifiable([
      for (var i = 0; i < widget.ingredients.length; i++)
        _ScalingRowState(index: i, original: widget.ingredients[i]),
    ]);
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  void _reset() {
    FocusScope.of(context).unfocus();
    setState(() {
      for (final row in _rows) {
        row.reset();
      }
    });
  }

  Future<void> _requestClose() async {
    if (_isConfirmingClose) return;
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
                          onPressed: _requestClose,
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
                          onPressed: _reset,
                          child: const Text('Visszaállítás'),
                        ),
                        const FilledButton(
                          onPressed: null,
                          child: Text('Bevásárlólistához adás'),
                        ),
                      ],
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
      enabled: row.initialDisplay != null,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: 'Mennyiség',
        border: const OutlineInputBorder(),
        errorText: row.initialDisplay == null ? 'Érvénytelen mennyiség' : null,
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

  void reset() {
    displayQuantity = initialDisplay?.quantity;
    displayUnit = initialDisplay?.unit ?? original.unit;
    final text = displayQuantity == null
        ? ''
        : _scaler.formatQuantity(displayQuantity!);
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void dispose() {
    controller.dispose();
    focusNode.dispose();
  }
}
