class RecipeIngredient {
  const RecipeIngredient({
    required this.name,
    required this.quantity,
    required this.unit,
  });

  final String name;
  final double quantity;
  final String unit;
}
class RecipeSpice {
  const RecipeSpice({
    required this.name,
  });

  final String name;
}
class Recipe {
  const Recipe({
    required this.name,
    required this.ingredients,
    required this.spices,
    required this.preparation,
  });

  final String name;
  final List<RecipeIngredient> ingredients;
  final List<RecipeSpice> spices;
  final String preparation;
}