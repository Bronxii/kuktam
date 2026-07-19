import 'package:flutter/material.dart';

import 'package:kuktam/recipes/domain/models/recipe.dart';
import 'package:kuktam/recipes/presentation/screens/add_recipe_screen.dart';

class RecipeDetailsScreen extends StatelessWidget {
  const RecipeDetailsScreen({
    required this.recipe,
    super.key,
  });

  final Recipe recipe;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
appBar: AppBar(
title: Text(recipe.name),
actions: [
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
        ],
      ),
    );
  }
}