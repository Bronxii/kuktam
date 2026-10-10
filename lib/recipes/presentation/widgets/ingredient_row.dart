import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../domain/models/recipe_import_draft.dart';

class IngredientRowData {
  IngredientRowData({
    String name = '',
    String quantity = '',
    String unit = 'g',
    this.importDraft,
  }) : nameController = TextEditingController(text: name),
       amountController = TextEditingController(text: quantity),
       selectedUnit = unit;

  final TextEditingController nameController;
  final TextEditingController amountController;
  final RecipeImportIngredientDraft? importDraft;

  String selectedUnit;

  void dispose() {
    nameController.dispose();
    amountController.dispose();
  }
}

class IngredientRow extends StatefulWidget {
  const IngredientRow({
    required this.data,
    required this.units,
    required this.suggestions,
    required this.onRemove,
    super.key,
  });

  final IngredientRowData data;
  final List<String> units;
  final List<String> suggestions;
  final VoidCallback onRemove;

  @override
  State<IngredientRow> createState() => _IngredientRowState();
}

class _IngredientRowState extends State<IngredientRow> {
  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.bodyLarge!;
    final label = TextPainter(
      text: TextSpan(text: 'Mennyiség', style: labelStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    // Floating labels use 75% of their normal size; retain decoration padding.
    final quantityWidth = (label.width * 0.75 + 24).ceilToDouble();
    label.dispose();
    final unitText = TextPainter(
      text: TextSpan(text: 'ml', style: labelStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    // Keep a wider control even with narrow device fonts; include icon/insets.
    final unitWidth = math.max(84.0, (unitText.width + 52).ceilToDouble());
    unitText.dispose();
    return LayoutBuilder(
      builder: (context, constraints) {
        final controlsWidth = quantityWidth + unitWidth + 8 + 48;
        final stacked = constraints.maxWidth < controlsWidth + 8 + 96;
        return Wrap(
          spacing: 8,
          runSpacing: 12,
          children: [
            SizedBox(
              width: stacked
                  ? constraints.maxWidth
                  : constraints.maxWidth - controlsWidth - 8,
              child: Autocomplete<String>(
                initialValue: widget.data.nameController.value,
                optionsBuilder: (textEditingValue) {
                  final query = textEditingValue.text.trim().toLowerCase();

                  if (query.isEmpty) {
                    return const Iterable<String>.empty();
                  }

                  return widget.suggestions.where(
                    (ingredient) => ingredient.toLowerCase().startsWith(query),
                  );
                },
                onSelected: (selection) {
                  widget.data.nameController.text = selection;
                },
                fieldViewBuilder:
                    (
                      context,
                      textEditingController,
                      focusNode,
                      onFieldSubmitted,
                    ) {
                      textEditingController.addListener(() {
                        widget.data.nameController.text =
                            textEditingController.text;
                      });

                      return TextField(
                        controller: textEditingController,
                        focusNode: focusNode,
                        decoration: const InputDecoration(
                          labelText: 'Hozzávaló',
                          border: OutlineInputBorder(),
                        ),
                        textCapitalization: TextCapitalization.sentences,
                      );
                    },
              ),
            ),
            SizedBox(
              width: stacked ? constraints.maxWidth : controlsWidth,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: widget.data.amountController,
                      decoration: const InputDecoration(
                        labelText: 'Mennyiség',
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                        contentPadding: EdgeInsets.fromLTRB(8, 20, 8, 12),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: unitWidth,
                    child: DropdownButtonFormField<String>(
                      initialValue: widget.data.selectedUnit,
                      isExpanded: true,
                      // 8px top padding + five 48px rows + half of the next row.
                      menuMaxHeight: 8 + 5.5 * kMinInteractiveDimension,
                      decoration: const InputDecoration(
                        labelText: 'Egység',
                        contentPadding: EdgeInsets.fromLTRB(8, 20, 8, 12),
                        border: OutlineInputBorder(),
                      ),
                      items: widget.units
                          .map(
                            (unit) => DropdownMenuItem<String>(
                              value: unit,
                              child: Text(unit),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }

                        setState(() {
                          widget.data.selectedUnit = value;
                        });
                      },
                    ),
                  ),
                  IconButton(
                    onPressed: widget.onRemove,
                    tooltip: 'Hozzávaló törlése',
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
