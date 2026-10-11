import '../../recipes/domain/models/recipe.dart';

class ExportFailure implements Exception {
  const ExportFailure(this.code);
  final String code;
  @override
  String toString() => 'ExportFailure($code)';
}

/// Explicit content-only DTO. No document identity or backend map is retained.
class ExportRecipe {
  ExportRecipe({
    required this.name,
    required List<RecipeIngredient> ingredients,
    required List<RecipeSpice> spices,
    required this.preparation,
  }) : ingredients = List.unmodifiable(ingredients),
       spices = List.unmodifiable(spices) {
    if (ingredients.any((i) => !i.quantity.isFinite)) {
      throw const ExportFailure('malformed');
    }
  }
  factory ExportRecipe.fromRecipe(Recipe recipe) => ExportRecipe(
    name: recipe.name,
    ingredients: recipe.ingredients,
    spices: recipe.spices,
    preparation: recipe.preparation,
  );
  final String name;
  final List<RecipeIngredient> ingredients;
  final List<RecipeSpice> spices;
  final String preparation;
  Map<String, Object> toJson(String textFile) => {
    'textFile': textFile,
    ...toContentJson(),
  };
  Map<String, Object> toContentJson() => {
    'name': name,
    'ingredients': [
      for (final i in ingredients)
        {'name': i.name, 'quantity': i.quantity, 'unit': i.unit},
    ],
    'spices': [
      for (final s in spices) {'name': s.name},
    ],
    'preparation': preparation,
  };
}
