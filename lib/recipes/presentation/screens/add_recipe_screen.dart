import 'package:flutter/material.dart';

import 'package:kuktam/recipes/presentation/widgets/ingredient_row.dart';
import 'package:kuktam/recipes/presentation/widgets/spice_row.dart';

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
  void _saveRecipe() {
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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$recipeName mentésre kész.'),
      ),
    );
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