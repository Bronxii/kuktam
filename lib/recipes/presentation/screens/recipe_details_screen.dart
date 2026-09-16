import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../widgets/recipe_scaling_dialog.dart';
import '../../domain/services/recipe_scaler.dart';

import 'package:kuktam/recipes/domain/models/recipe.dart';
import 'package:kuktam/recipes/presentation/screens/add_recipe_screen.dart';
import 'package:kuktam/recipes/data/repositories/recipe_repository.dart';
import 'package:kuktam/shopping/data/repositories/shopping_repository.dart';

class RecipeDetailsScreen extends StatefulWidget {
  const RecipeDetailsScreen({
    required this.recipe,
    this.addScalingShoppingItem,
    this.addMultiplierShoppingItem,
    this.recipeRepository,
    super.key,
  });

  final Recipe recipe;
  final AddScalingShoppingItem? addScalingShoppingItem;
  final AddScalingShoppingItem? addMultiplierShoppingItem;
  final RecipeRepository? recipeRepository;

  @override
  State<RecipeDetailsScreen> createState() => _RecipeDetailsScreenState();
}

class _RecipeDetailsScreenState extends State<RecipeDetailsScreen> {
  Recipe get recipe => widget.recipe;
  AddScalingShoppingItem? get addScalingShoppingItem => widget.addScalingShoppingItem;
  AddScalingShoppingItem? get addMultiplierShoppingItem => widget.addMultiplierShoppingItem;
  late final RecipeRepository _repository = widget.recipeRepository ?? RecipeRepository();
  bool _deleting = false;
  bool _confirmingDelete = false;
  bool _multiplierFlowActive = false;
  bool _addingMultiplier = false;
  final _multiplierController = TextEditingController();

  @override
  void dispose() {
    _multiplierController.dispose();
    super.dispose();
  }

  Future<void> _deleteRecipe() async {
    if (_deleting || _confirmingDelete) return;
    _confirmingDelete = true;
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Recept törlése'),
        content: Text('Biztosan törölni szeretnéd ezt a receptet?\n\n${recipe.name}'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Mégse')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Törlés')),
        ],
      ),
    );
    _confirmingDelete = false;
    if (!mounted || shouldDelete != true) return;
    setState(() => _deleting = true);
    try {
      final id = recipe.id;
      if (id == null) throw StateError('Missing recipe id');
      await _repository.deleteRecipe(id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Nem sikerült törölni a receptet. Próbáld újra.'),
      ));
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

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
    return PopScope(
      canPop: !_deleting && !_addingMultiplier,
      child: AbsorbPointer(
        absorbing: _deleting || _addingMultiplier,
        child: Scaffold(
appBar: AppBar(
title: Text(_deleting ? 'Törlés folyamatban…' : recipe.name),
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
recipeRepository: _repository,
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
    onPressed: _deleting ? null : _deleteRecipe,
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
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: () async {
                final added = await showDialog<bool>(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => RecipeScalingDialog(
                    ingredients: recipe.ingredients,
                    addShoppingItem: addScalingShoppingItem,
                  ),
                );
                if (added != true || !context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('A hozzávalók felkerültek a bevásárlólistára.'),
                ));
                Navigator.of(context).pop();
              },
              child: const Text('Átszámítás'),
            ),
          ),
          ...recipe.ingredients.map(
                (ingredient) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 7),
                        child: Icon(
                          Icons.circle,
                          size: 8,
                        ),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 88,
                        child: Text(
                          '${ingredient.formattedQuantity} ${ingredient.unit}',
                          textAlign: TextAlign.right,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          ingredient.name,
                          style: Theme.of(context).textTheme.bodyLarge,
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
              onPressed: _addingMultiplier ? null : () async {
                if (_multiplierFlowActive || _deleting) return;
                _multiplierFlowActive = true;
                try {
                final multiplierController = _multiplierController;
                multiplierController.text = '1.0';
                double currentMultiplier = 1.0;
                String? errorText;
                bool submitted = false;

                final multiplier = await showDialog<double>(
                  context: context,
                  builder: (dialogContext) {
                    return StatefulBuilder(
                      builder: (context, setDialogState) {
                        void updateMultiplier(double newValue) {
                          if (!newValue.isFinite || newValue < 0.1) {
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
                                        final parsedValue = const RecipeScaler().parseQuantity(value);

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
                                if (submitted) return;
                                final parsedMultiplier = const RecipeScaler().parseQuantity(
                                  multiplierController.text,
                                );

                                if (parsedMultiplier == null || parsedMultiplier <= 0) {
                                  setDialogState(() {
                                    errorText = 'Adj meg pozitív értéket!';
                                  });
                                  return;
                                }

                                submitted = true;
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

                if (!mounted || multiplier == null) {
                  return;
                }

                // Validate every scaled value before the first repository write.
                final items = [
                  for (final ingredient in recipe.ingredients)
                    (name: ingredient.name, amount: const RecipeScaler().normalizeForShopping(
                      quantity: ingredient.quantity * multiplier,
                      unit: ingredient.unit,
                    )),
                ];
                if (items.isEmpty) return;
                setState(() => _addingMultiplier = true);
                final add = addMultiplierShoppingItem ?? ShoppingRepository().addOrMergeItem;

                for (final item in items) {
                  await add(
                    name: item.name,
                    quantity: item.amount.quantity,
                    unit: item.amount.unit,
                  );
                }

                if (!context.mounted) {
                  return;
                }

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'A hozzávalók ${multiplier.toString().replaceFirst(RegExp(r'\.0$'), '').replaceAll('.', ',')}× mennyiséggel '
                          'felkerültek a bevásárlólistára.',
                    ),
                  ),
                );
                Navigator.of(context).pop();
                } on ArgumentError {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(_addingMultiplier
                        ? 'Nem sikerült minden tételt hozzáadni a bevásárlólistához. Ellenőrizd a listát.'
                        : 'A megadott mennyiséggel a recept nem számítható át.'),
                  ));
                } catch (_) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Nem sikerült minden tételt hozzáadni a bevásárlólistához. Ellenőrizd a listát.'),
                  ));
                } finally {
                  _multiplierFlowActive = false;
                  if (mounted) setState(() => _addingMultiplier = false);
                }
              },
              icon: const Icon(Icons.shopping_cart_outlined),
              label: Text(_addingMultiplier ? 'Hozzáadás folyamatban…' : 'Bevásárlólistához adás'),
            ),
          ),
        ],
      ),
    ),
    ),
    );
  }
}
