import '../../domain/models/web_recipe_import_handoff.dart';
import 'package:flutter/material.dart';
import 'package:kuktam/core/domain/measurement_units.dart';
import 'package:kuktam/core/domain/services/import_quantity_parser.dart';

import 'package:kuktam/recipes/presentation/widgets/ingredient_row.dart';
import 'package:kuktam/recipes/presentation/widgets/spice_row.dart';
import 'package:kuktam/recipes/domain/models/recipe.dart';
import 'package:kuktam/recipes/domain/models/recipe_import_draft.dart';
import 'package:kuktam/recipes/data/repositories/recipe_repository.dart';

class AddRecipeScreen extends StatefulWidget {
  const AddRecipeScreen({
    this.recipe,
    this.initialImport,
    this.webImport,
    this.recipeRepository,
    super.key,
  }) : assert(recipe == null || initialImport == null);

  final Recipe? recipe;
  final RecipeImportDraft? initialImport;
  /// P6.3 plumbing only; review UI/acceptance belongs to P6.4.
  final WebRecipeImportHandoff? webImport;
  final RecipeRepository? recipeRepository;

  @override
  State<AddRecipeScreen> createState() => _AddRecipeScreenState();
}

class _AddRecipeScreenState extends State<AddRecipeScreen> {
  final TextEditingController _recipeNameController =
  TextEditingController();

  final TextEditingController _preparationController =
  TextEditingController();

  final List<IngredientRowData> _ingredients = [
    IngredientRowData(),
  ];

  final List<SpiceRowData> _spices = [
    SpiceRowData(),
  ];

  late final RecipeRepository _recipeRepository;

  late String _initialFormState;
  bool _allowPop = false;
  bool _saving = false;
  bool _confirmingLeave = false;

  static const List<String> _units = MeasurementUnits.values;

  @override
  void initState() {
    super.initState();
    _recipeRepository = widget.recipeRepository ?? RecipeRepository();

    final recipe = widget.recipe;

    if (recipe != null) {
      _recipeNameController.text = recipe.name;
      _preparationController.text = recipe.preparation;

      for (final ingredient in _ingredients) {
        ingredient.dispose();
      }

      _ingredients
        ..clear()
        ..addAll(
          recipe.ingredients.map(
                (ingredient) =>
                    IngredientRowData(
                      name: ingredient.name,
                      quantity: ingredient.formattedQuantity,
                      unit: ingredient.unit == 'kk' ? 'tk' : ingredient.unit,
                    ),
          ),
        );

      for (final spice in _spices) {
        spice.dispose();
      }

      _spices
        ..clear()
        ..addAll(
          recipe.spices.map(
                (spice) =>
                SpiceRowData(
                  name: spice.name,
                ),
          ),
        );
    }

    final imported = widget.initialImport;
    if (imported != null) {
      _recipeNameController.text = imported.title;
      _preparationController.text = imported.preparationText;
      for (final ingredient in _ingredients) {
        ingredient.dispose();
      }
      _ingredients
        ..clear()
        ..addAll(imported.ingredients.map((draft) => IngredientRowData(
          name: draft.name,
          quantity: _importQuantityText(draft),
          unit: draft.unit,
          importDraft: draft,
        )));
      if (_ingredients.isEmpty) _ingredients.add(IngredientRowData());
      for (final spice in _spices) {
        spice.dispose();
      }
      _spices.clear();
    }

    _initialFormState = _createFormStateSnapshot();
  }

  String _importQuantityText(RecipeImportIngredientDraft draft) {
    final quantity = draft.quantity;
    if (quantity != null) {
      // Reuse the editor's existing non-rounding ingredient formatting.
      return RecipeIngredient(name: draft.name, quantity: quantity, unit: draft.unit)
          .formattedQuantity.replaceAll('.', ',');
    }
    final raw = draft.rawQuantityText ?? '';
    // Conversion overflow may leave a parseable raw number in the old unit.
    // A null draft must not silently become a valid quantity during prefill.
    return const ImportQuantityParser().parse(raw) == null ? raw : '';
  }

  @override
  void dispose() {
    _recipeNameController.dispose();
    _preparationController.dispose();

    for (final ingredient in _ingredients) {
      ingredient.dispose();
    }
    for (final spice in _spices) {
      spice.dispose();
    }
    super.dispose();
  }

  void _addIngredient() {
    setState(() {
      _ingredients.add(IngredientRowData());
    });
  }

  void _addSpice() {
    setState(() {
      _spices.add(SpiceRowData());
    });
  }

  void _removeIngredient(int index) {
    if (_ingredients.length == 1 && widget.initialImport != null) {
      setState(() {
        _ingredients.single.dispose();
        _ingredients[0] = IngredientRowData();
      });
      return;
    }
    if (_ingredients.length == 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Legalább egy hozzávalósor maradjon!'),
        ),
      );
      return;
    }

    setState(() {
      _ingredients[index].dispose();
      _ingredients.removeAt(index);
    });
  }

  void _removeSpice(int index) {
    if (_spices.length == 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Legalább egy fűszer sort hagyj meg.'),
        ),
      );
      return;
    }

    setState(() {
      _spices[index].dispose();
      _spices.removeAt(index);
    });
  }

  String _createFormStateSnapshot() {
    final ingredientState = _ingredients.map((ingredient) {
      return [
        ingredient.nameController.text.trim(),
        ingredient.amountController.text.trim(),
        ingredient.selectedUnit,
      ].join('|');
    }).join('||');

    final spiceState = _spices.map((spice) {
      return spice.nameController.text.trim();
    }).join('||');

    return [
      _recipeNameController.text.trim(),
      ingredientState,
      spiceState,
      _preparationController.text.trim(),
    ].join('###');
  }

  bool get _hasUnsavedChanges {
    return widget.initialImport != null ||
        _createFormStateSnapshot() != _initialFormState;
  }

  String _warningText(RecipeImportWarning warning) => switch (warning) {
    RecipeImportWarning.unknownUnit =>
      'A mértékegységet nem sikerült felismerni. Ellenőrzés szükséges.',
    RecipeImportWarning.missingQuantity =>
      'A mennyiséget nem sikerült felismerni. Ellenőrzés szükséges.',
    RecipeImportWarning.invalidQuantity =>
      'A mennyiség hibás vagy nem értelmezhető. Módosítás szükséges.',
    RecipeImportWarning.ambiguousIngredient =>
      'Ezt a hozzávalósort nem sikerült egyértelműen felismerni. Ellenőrzés szükséges.',
  };

  Widget _ingredientEditor(IngredientRowData ingredient, int index) {
    final row = IngredientRow(
      data: ingredient,
      units: _units,
      suggestions: const [],
      onRemove: () => _removeIngredient(index),
    );
    final draft = ingredient.importDraft;
    if (draft == null || draft.warnings.isEmpty) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row,
        const SizedBox(height: 4),
        Text(
          '${draft.warnings.map(_warningText).join('\n')}\nEredeti: ${draft.rawText}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.error,
          ),
        ),
      ],
    );
  }

  Future<bool> _confirmLeaveWithoutSaving() async {
    if (!_hasUnsavedChanges) {
      return true;
    }

    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Kilépés mentés nélkül?'),
          content: const Text(
            'A nem mentett módosítások elvesznek.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Mégsem'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Kilépés'),
            ),
          ],
        );
      },
    );

    return shouldLeave ?? false;
  }

  Recipe _buildRecipe(List<double> quantities) {
    return Recipe(
      id: widget.recipe?.id,
      name: _recipeNameController.text.trim(),
      ingredients: _ingredients.asMap().entries
          .map(
            (entry) =>
            RecipeIngredient(
              name: entry.value.nameController.text.trim(),
              quantity: quantities[entry.key],
              unit: entry.value.selectedUnit,
            ),
      )
          .toList(),
      spices: _spices
          .map(
            (spice) =>
            RecipeSpice(
              name: spice.nameController.text.trim(),
            ),
      )
          .toList(),
      preparation: _preparationController.text.trim(),
    );
  }

  Future<void> _saveRecipe() async {
    if (_saving) return;
    final String recipeName = _recipeNameController.text.trim();
    if (recipeName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add meg a recept nevét!'),
        ),
      );
      return;
    }

    final bool hasEmptyIngredient = _ingredients.any(
          (ingredient) =>
      ingredient.nameController.text
          .trim()
          .isEmpty ||
          ingredient.amountController.text
              .trim()
              .isEmpty,
    );

    if (hasEmptyIngredient) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Minden hozzávalónál add meg a nevet és a mennyiséget!'),
        ),
      );
      return;
    }
    final quantities = <double>[];
    for (final ingredient in _ingredients) {
      final quantity = const ImportQuantityParser().parse(
        ingredient.amountController.text,
      );
      if (quantity == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(
            'Minden hozzávalónál adj meg érvényes, pozitív mennyiséget!',
          )),
        );
        return;
      }
      quantities.add(quantity);
    }
    final recipe = _buildRecipe(quantities);

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _saving = true);
    try {
      final recipeAlreadyExists = await _recipeRepository.recipeNameExists(
        name: recipe.name,
        excludedRecipeId: widget.recipe?.id,
      );

      if (recipeAlreadyExists) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Már létezik ilyen nevű recept!'),
          ),
        );

        return;
      }

      if (!mounted) return;
      if (widget.recipe == null) {
        await _recipeRepository.saveRecipe(recipe);
      } else {
        await _recipeRepository.updateRecipe(recipe);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Recept sikeresen elmentve!'),
        ),
      );
      setState(() {
        _allowPop = true;
      });
      Navigator.of(context).pop(recipe);
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nem sikerült elmenteni a receptet. Próbáld újra.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _saving || _confirmingLeave) {
          return;
        }

        final navigator = Navigator.of(context);

        _confirmingLeave = true;
        final shouldLeave = await _confirmLeaveWithoutSaving();
        _confirmingLeave = false;

        if (!mounted || !shouldLeave) {
          return;
        }

        setState(() {
          _allowPop = true;
        });

        navigator.pop();
      },
      child: Scaffold(
          appBar: AppBar(
            title: const Text('Új recept'),
          ),
          body: SafeArea(
              child: AbsorbPointer(
                absorbing: _saving,
                child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                TextField(
                controller: _recipeNameController,
                decoration: const InputDecoration(
                  labelText: 'Recept neve',
                  hintText: 'Például: Burgonyás pogácsa',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 32),
              if (widget.initialImport?.unprocessedSegments.isNotEmpty ?? false)
                ExpansionTile(
                  title: const Text('A recept egyes részeit nem sikerült felismerni.'),
                  childrenPadding: const EdgeInsets.only(bottom: 16),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(widget.initialImport!.unprocessedSegments.join('\n')),
                    ),
                  ],
                ),
              Text(
                'Hozzávalók',
                style: Theme
                    .of(context)
                    .textTheme
                    .titleLarge,
              ),
              const SizedBox(height: 16),
                  ...List.generate(
                    _ingredients.length,
                        (index) {
                      final ingredient = _ingredients[index];

                      return Padding(
                        key: ObjectKey(ingredient),
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ingredientEditor(ingredient, index),
                      );
                    },
                  ),
    OutlinedButton.icon(
    onPressed: _addIngredient,
    icon: const Icon(Icons.add),
    label: const Text('Hozzávaló hozzáadása'),
    ),
    const SizedBox(height: 32),
    Text(
    'Fűszerek',
    style: Theme.of(context).textTheme.titleLarge,
    ),
    const SizedBox(height: 16),

                  ...List.generate(
                    _spices.length,
                        (index) {
                      final spice = _spices[index];

                      return Padding(
                        key: ObjectKey(spice),
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SpiceRow(
                          data: spice,
                          onRemove: () => _removeSpice(index),
                        ),
                      );
                    },
                  ),

    OutlinedButton.icon(
    onPressed: _addSpice,
    icon: const Icon(Icons.add),
    label: const Text('Fűszer hozzáadása'),
    ),

    const SizedBox(height: 32),

    Text(
    'Elkészítés',
    style: Theme.of(context).textTheme.titleLarge,
    ),
    const SizedBox(height: 16),
    TextField(
    controller: _preparationController,
    minLines: 5,
    maxLines: null,
    keyboardType: TextInputType.multiline,
    textCapitalization: TextCapitalization.sentences,
    decoration: const InputDecoration(
    labelText: 'Elkészítés menete',
    hintText: 'Írd le lépésről lépésre a recept elkészítését...',
    border: OutlineInputBorder(),
    alignLabelWithHint: true,
    ),
    ),
    const SizedBox(height: 32),

                  FilledButton.icon(
                    onPressed: _saving ? null : _saveRecipe,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Mentés folyamatban…' : 'Mentés'),
                  ),
    ],
    ),
    ),
    ),
    ),
    );
  }
}
