import 'package:flutter/material.dart';

import 'package:kuktam/recipes/data/repositories/recipe_repository.dart';
import 'package:kuktam/recipes/domain/models/recipe.dart';
import 'package:kuktam/recipes/presentation/screens/recipe_details_screen.dart';

import '../../domain/services/recipe_matcher.dart';
import '../widgets/ingredient_input_field.dart';
import '../widgets/selected_ingredients_box.dart';
import '../widgets/what_to_cook_recipe_tile.dart';
class WhatToCookScreen extends StatefulWidget {
  const WhatToCookScreen({super.key});

  @override
  State<WhatToCookScreen> createState() => _WhatToCookScreenState();
}

class _WhatToCookScreenState extends State<WhatToCookScreen> {
  final RecipeRepository _recipeRepository = RecipeRepository();
  final RecipeMatcher _recipeMatcher = const RecipeMatcher();

  final List<String> _selectedIngredients = [];

  late final Stream<List<Recipe>> _recipesStream;

  @override
  void initState() {
    super.initState();

    _recipesStream = _recipeRepository.watchRecipes();
  }

  void _addIngredient(String ingredient) {
    final normalizedIngredient =
    _recipeMatcher.normalizeIngredient(ingredient);

    final alreadySelected = _selectedIngredients.any(
          (selectedIngredient) =>
      _recipeMatcher.normalizeIngredient(selectedIngredient) ==
          normalizedIngredient,
    );

    if (alreadySelected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'A(z) „$ingredient” alapanyagot már hozzáadtad.',
          ),
        ),
      );

      return;
    }

    setState(() {
      _selectedIngredients.add(ingredient.trim());
    });
  }

  void _removeIngredient(String ingredient) {
    setState(() {
      _selectedIngredients.remove(ingredient);
    });
  }

  void _openRecipeDetails(Recipe recipe) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => RecipeDetailsScreen(
          recipe: recipe,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Milyen alapanyagok vannak otthon?',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Add meg az alapanyagokat, és megmutatjuk azokat a '
                'recepteket, amelyek mindegyiket tartalmazzák.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          IngredientInputField(
            onIngredientAdded: _addIngredient,
          ),
          const SizedBox(height: 12),
          SelectedIngredientsBox(
            ingredients: _selectedIngredients,
            onIngredientRemoved: _removeIngredient,
          ),
          const SizedBox(height: 24),
          Expanded(
            child: StreamBuilder<List<Recipe>>(
              stream: _recipesStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Nem sikerült betölteni a recepteket.\n'
                          '${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                final recipes = snapshot.data ?? [];

                final matchingRecipes =
                _recipeMatcher.findMatchingRecipes(
                  recipes: recipes,
                  selectedIngredients: _selectedIngredients,
                );

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _buildResultTitle(matchingRecipes.length),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    const Divider(),
                    Expanded(
                      child: _buildRecipeList(
                        allRecipes: recipes,
                        matchingRecipes: matchingRecipes,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _buildResultTitle(int resultCount) {
    if (_selectedIngredients.isEmpty) {
      return 'Összes recept ($resultCount)';
    }

    return 'Találatok ($resultCount)';
  }

  Widget _buildRecipeList({
    required List<Recipe> allRecipes,
    required List<Recipe> matchingRecipes,
  }) {
    if (allRecipes.isEmpty) {
      return const _EmptyResult(
        icon: Icons.menu_book_rounded,
        title: 'Még nincsenek receptjeid',
        message: 'Először adj hozzá legalább egy receptet.',
      );
    }

    if (matchingRecipes.isEmpty) {
      return const _EmptyResult(
        icon: Icons.search_off_rounded,
        title: 'Nincs megfelelő recept',
        message:
        'Nincs olyan recept, amely az összes megadott alapanyagot '
            'tartalmazza.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(
        top: 4,
        bottom: 20,
      ),
      itemCount: matchingRecipes.length,
      itemBuilder: (context, index) {
        final recipe = matchingRecipes[index];

        return WhatToCookRecipeTile(
          recipe: recipe,
          onTap: () {
            _openRecipeDetails(recipe);
          },
        );
      },
    );
  }
}

class _EmptyResult extends StatelessWidget {
  const _EmptyResult({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color:
                Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}