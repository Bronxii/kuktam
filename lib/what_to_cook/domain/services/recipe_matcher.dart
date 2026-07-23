import '../../../recipes/domain/models/recipe.dart';

class RecipeMatcher {
  const RecipeMatcher();

  List<Recipe> findMatchingRecipes({
    required List<Recipe> recipes,
    required List<String> selectedIngredients,
  }) {
    if (selectedIngredients.isEmpty) {
      final sortedRecipes = [...recipes];

      sortedRecipes.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );

      return sortedRecipes;
    }

    final normalizedIngredients = selectedIngredients
        .map(_normalize)
        .toSet();

    final matchingRecipes = recipes.where((recipe) {
      final recipeIngredients = recipe.ingredients
          .map((ingredient) => _normalize(ingredient.name))
          .toSet();

      return normalizedIngredients.every(
        recipeIngredients.contains,
      );
    }).toList();

    matchingRecipes.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );

    return matchingRecipes;
  }

  String normalizeIngredient(String ingredient) {
    return _normalize(ingredient);
  }

  String _normalize(String value) {
    return value.trim().toLowerCase();
  }
}