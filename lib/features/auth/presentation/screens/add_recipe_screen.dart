import 'package:flutter/material.dart';

class AddRecipeScreen extends StatefulWidget {
  const AddRecipeScreen({super.key});

  @override
  State<AddRecipeScreen> createState() => _AddRecipeScreenState();
}

class _AddRecipeScreenState extends State<AddRecipeScreen> {
  final TextEditingController _recipeNameController =
  TextEditingController();

  final List<IngredientRowData> _ingredients = [
    IngredientRowData(),
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

    for (final ingredient in _ingredients) {
      ingredient.dispose();
    }

    super.dispose();
  }

  void _addIngredient() {
    setState(() {
      _ingredients.add(IngredientRowData());
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

class IngredientRowData {
  IngredientRowData()
      : nameController = TextEditingController(),
        amountController = TextEditingController();

  final TextEditingController nameController;
  final TextEditingController amountController;

  String selectedUnit = 'g';

  void dispose() {
    nameController.dispose();
    amountController.dispose();
  }
}

class IngredientRow extends StatefulWidget {
  const IngredientRow({
    required this.data,
    required this.units,
    required this.onRemove,
    super.key,
  });

  final IngredientRowData data;
  final List<String> units;
  final VoidCallback onRemove;

  @override
  State<IngredientRow> createState() => _IngredientRowState();
}

class _IngredientRowState extends State<IngredientRow> {
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: TextField(
            controller: widget.data.nameController,
            decoration: const InputDecoration(
              labelText: 'Hozzávaló',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: TextField(
            controller: widget.data.amountController,
            decoration: const InputDecoration(
              labelText: 'Mennyiség',
              border: OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 76,
          child: DropdownButtonFormField<String>(
            initialValue: widget.data.selectedUnit,
            decoration: const InputDecoration(
              labelText: 'Egység',
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
    );
  }
}