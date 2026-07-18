import 'package:flutter/material.dart';

import 'package:kuktam/recipes/presentation/widgets/ingredient_row.dart';
import 'package:kuktam/recipes/presentation/widgets/spice_row.dart';
import 'package:kuktam/recipes/domain/models/recipe.dart';
import 'package:kuktam/recipes/data/repositories/recipe_repository.dart';

class AddRecipeScreen extends StatefulWidget {
  const AddRecipeScreen({super.key});

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

  final RecipeRepository _recipeRepository = RecipeRepository();

  static const List<String> _units = [
    'g',
    'kg',
    'ml',
    'l',
    'db',
    'kk',
    'ek',
  ];

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
  Recipe _buildRecipe() {
    return Recipe(
      name: _recipeNameController.text.trim(),
      ingredients: _ingredients
          .map(
            (ingredient) => RecipeIngredient(
          name: ingredient.nameController.text.trim(),
              quantity:
              double.tryParse(ingredient.amountController.text.trim()) ?? 0,
          unit: ingredient.selectedUnit,
        ),
      )
          .toList(),
      spices: _spices
          .map(
            (spice) => RecipeSpice(
          name: spice.nameController.text.trim(),
        ),
      )
          .toList(),
      preparation: _preparationController.text.trim(),
    );
  }
  Future<void> _saveRecipe() async {
    final String recipeName = _recipeNameController.text.trim();
    final recipe = _buildRecipe();

    debugPrint('Recept neve: ${recipe.name}');

    for (final ingredient in recipe.ingredients) {
      debugPrint(
        'Hozzávaló: ${ingredient.quantity} ${ingredient.unit} ${ingredient.name}',
      );
    }

    for (final spice in recipe.spices) {
      debugPrint('Fűszer: ${spice.name}');
    }

    debugPrint('Elkészítés: ${recipe.preparation}');

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
      ingredient.nameController.text.trim().isEmpty ||
          ingredient.amountController.text.trim().isEmpty,
    );

    if (hasEmptyIngredient) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Minden hozzávalónál add meg a nevet és a mennyiséget!'),
        ),
      );
      return;
    }
try {
await _recipeRepository.saveRecipe(recipe);

if (!mounted) return;

ScaffoldMessenger.of(context).showSnackBar(
const SnackBar(
content: Text('Recept sikeresen elmentve!'),
),
);
} catch (e) {
if (!mounted) return;

ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
content: Text('Mentési hiba: $e'),
),
);
}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Új recept'),
      ),
      body: SafeArea(
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
            Text(
              'Hozzávalók',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            ...List.generate(
              _ingredients.length,
                  (index) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: IngredientRow(
                  data: _ingredients[index],
                  units: _units,
                  onRemove: () => _removeIngredient(index),
                ),
              ),
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
                  (index) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SpiceRow(
                  data: _spices[index],
                  onRemove: () => _removeSpice(index),
                ),
              ),
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
              onPressed: _saveRecipe,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Mentés'),
            ),
          ],
        ),
      ),
    );
  }
}