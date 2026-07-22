import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'package:kuktam/recipes/domain/models/recipe.dart';
import 'package:kuktam/recipes/presentation/screens/add_recipe_screen.dart';
import 'package:kuktam/recipes/data/repositories/recipe_repository.dart';
import 'package:kuktam/shopping/data/repositories/shopping_repository.dart';

class RecipeDetailsScreen extends StatelessWidget {
  const RecipeDetailsScreen({
    required this.recipe,
    super.key,
  });

  final Recipe recipe;

  String _formatQuantity(double quantity) {
    if (quantity == quantity.roundToDouble()) {
      return quantity.toInt().toString();
    }

    return quantity.toString();
  }

  String _buildRecipeShareText(Recipe recipe) {
    final buffer = StringBuffer();

    buffer.writeln(recipe.name);
    buffer.writeln();

    buffer.writeln('Hozzávalók:');

    for (final ingredient in recipe.ingredients) {
      buffer.writeln(
        '• ${ingredient.name} – '
            '${_formatQuantity(ingredient.quantity)} '
            '${ingredient.unit}',
      );
    }

    if (recipe.spices.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Fűszerek:');

      for (final spice in recipe.spices) {
        buffer.writeln('• ${spice.name}');
      }
    }

    if (recipe.preparation.trim().isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Elkészítés:');
      buffer.writeln(recipe.preparation.trim());
    }

    buffer.writeln();
    buffer.writeln('──────────────');
    buffer.writeln('Készült a Kuktám alkalmazással');

    return buffer.toString().trim();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
appBar: AppBar(
title: Text(recipe.name),
actions: [
  IconButton(
    tooltip: 'Megosztás',
    icon: const Icon(Icons.share_outlined),
    onPressed: () async {
      await SharePlus.instance.share(
        ShareParams(
          text: _buildRecipeShareText(recipe),
        ),
      );
    },
  ),
IconButton(
tooltip: 'Szerkesztés',
icon: const Icon(Icons.edit_outlined),
onPressed: () async {
final updatedRecipe = await Navigator.of(context).push<Recipe>(
MaterialPageRoute<Recipe>(
builder: (context) => AddRecipeScreen(
recipe: recipe,
),
),
);

if (updatedRecipe == null || !context.mounted) {
  return;
}

Navigator.of(context).pop(true);
},
),
  IconButton(
    tooltip: 'Törlés',
    icon: const Icon(Icons.delete_outline),
    onPressed: () async {
      final shouldDelete = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Recept törlése'),
            content: Text(
              'Biztosan törölni szeretnéd ezt a receptet?\n\n${recipe.name}',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop(false);
                },
                child: const Text('Mégse'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop(true);
                },
                child: const Text('Törlés'),
              ),
            ],
          );
        },
      );

      if (shouldDelete != true) {
        return;
      }

      await RecipeRepository().deleteRecipe(recipe.id!);

      if (!context.mounted) {
        return;
      }

      Navigator.of(context).pop(true);
    },
  ),
],
),

body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Hozzávalók',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          ...recipe.ingredients.map(
                (ingredient) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.circle,
                    size: 8,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: Text(
                      ingredient.name,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      '${ingredient.formattedQuantity} ${ingredient.unit}',
                      textAlign: TextAlign.left,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Fűszerek',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          ...recipe.spices.map(
                (spice) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.circle, size: 8),
              title: Text(spice.name),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Elkészítés',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Text(recipe.preparation),
          const SizedBox(height: 32),

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () async {
                final multiplierController = TextEditingController(text: '1.0');
                double currentMultiplier = 1.0;
                String? errorText;

                final multiplier = await showDialog<double>(
                  context: context,
                  builder: (dialogContext) {
                    return StatefulBuilder(
                      builder: (context, setDialogState) {
                        void updateMultiplier(double newValue) {
                          if (newValue < 0.1) {
                            return;
                          }

                          setDialogState(() {
                            currentMultiplier =
                                double.parse(newValue.toStringAsFixed(1));
                            multiplierController.text =
                                currentMultiplier.toStringAsFixed(1);
                            errorText = null;
                          });
                        }

                        return AlertDialog(
                          icon: const Icon(
                            Icons.shopping_cart_outlined,
                            size: 40,
                          ),
                          title: const Text(
                            'Bevásárlólistához adás',
                            textAlign: TextAlign.center,
                          ),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Hányszoros adagot szeretnél?',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 24),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton.filledTonal(
                                    onPressed: () {
                                      updateMultiplier(currentMultiplier - 0.1);
                                    },
                                    icon: const Icon(Icons.remove),
                                    iconSize: 30,
                                    padding: const EdgeInsets.all(14),
                                  ),
                                  const SizedBox(width: 16),
                                  SizedBox(
                                    width: 90,
                                    child: TextField(
                                      controller: multiplierController,
                                      keyboardType: const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                      inputFormatters: [
                                        FilteringTextInputFormatter.allow(
                                          RegExp(r'^\d*[.,]?\d*$'),
                                        ),
                                      ],
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context).textTheme.headlineSmall,
                                      decoration: InputDecoration(
                                        errorText: errorText,
                                        suffixText: '×',
                                      ),
                                      onChanged: (value) {
                                        final parsedValue = double.tryParse(
                                          value.replaceAll(',', '.'),
                                        );

                                        if (parsedValue != null && parsedValue > 0) {
                                          currentMultiplier = parsedValue;

                                          if (errorText != null) {
                                            setDialogState(() {
                                              errorText = null;
                                            });
                                          }
                                        }
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  IconButton.filledTonal(
                                    onPressed: () {
                                      updateMultiplier(currentMultiplier + 0.1);
                                    },
                                    icon: const Icon(Icons.add),
                                    iconSize: 30,
                                    padding: const EdgeInsets.all(14),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Navigator.of(dialogContext).pop();
                              },
                              child: const Text('Mégse'),
                            ),
                            FilledButton(
                              onPressed: () {
                                final parsedMultiplier = double.tryParse(
                                  multiplierController.text.replaceAll(',', '.'),
                                );

                                if (parsedMultiplier == null || parsedMultiplier <= 0) {
                                  setDialogState(() {
                                    errorText = 'Adj meg pozitív értéket!';
                                  });
                                  return;
                                }

                                Navigator.of(dialogContext).pop(parsedMultiplier);
                              },
                              child: const Text('Hozzáadás'),
                            ),
                          ],
                        );
                      },
                    );
                  },
                );

                if (multiplier == null) {
                  return;
                }

                final shoppingRepository = ShoppingRepository();

                for (final ingredient in recipe.ingredients) {
                  await shoppingRepository.addOrMergeItem(
                    name: ingredient.name,
                    quantity: ingredient.quantity * multiplier,
                    unit: ingredient.unit,
                  );
                }

                if (!context.mounted) {
                  return;
                }

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'A hozzávalók ${multiplier.toStringAsFixed(1)}× mennyiséggel '
                          'felkerültek a bevásárlólistára.',
                    ),
                  ),
                );
                Navigator.of(context).pop();
              },
              icon: const Icon(Icons.shopping_cart_outlined),
              label: const Text('Bevásárlólistához adás'),
            ),
          ),
        ],
      ),
    );
  }
}