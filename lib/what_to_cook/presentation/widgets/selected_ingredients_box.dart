import 'package:flutter/material.dart';

class SelectedIngredientsBox extends StatelessWidget {
  const SelectedIngredientsBox({
    required this.ingredients,
    required this.onIngredientRemoved,
    super.key,
  });

  final List<String> ingredients;
  final ValueChanged<String> onIngredientRemoved;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(
          color: colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ingredients.isEmpty
          ? Text(
        'A hozzáadott alapanyagok itt jelennek meg.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      )
          : Wrap(
        spacing: 8,
        runSpacing: 8,
        children: ingredients.map((ingredient) {
          return InputChip(
            label: Text(ingredient),
            onDeleted: () {
              onIngredientRemoved(ingredient);
            },
            deleteIcon: const Icon(
              Icons.close,
              size: 24,
            ),
            deleteButtonTooltipMessage: '$ingredient eltávolítása',
            padding: const EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 8,
            ),
            visualDensity: VisualDensity.standard,
          );
        }).toList(),
      ),
    );
  }
}