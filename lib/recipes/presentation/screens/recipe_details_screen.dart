import 'package:flutter/material.dart';

import 'package:kuktam/recipes/domain/models/recipe.dart';

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
                (ingredient) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.circle, size: 8),
              title: Text(ingredient.name),
              trailing: Text(
                '${ingredient.quantity} ${ingredient.unit}',
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