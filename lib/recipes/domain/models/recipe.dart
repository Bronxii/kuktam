class RecipeIngredient {
  const RecipeIngredient({
    required this.name,
    required this.quantity,
    required this.unit,
  });

  final String name;
  final double quantity;
  final String unit;

  factory RecipeIngredient.fromMap(Map<String, dynamic> map) {
    return RecipeIngredient(
      name: map['name'] as String,
      quantity: (map['quantity'] as num).toDouble(),
      unit: map['unit'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'quantity': quantity,
      'unit': unit,
    };
  }

  String get formattedQuantity {
    if (quantity == quantity.toInt()) {
      return quantity.toInt().toString();
    }

    return quantity.toString();
  }
}

class RecipeSpice {
const RecipeSpice({
required this.name,
});

final String name;

factory RecipeSpice.fromMap(Map<String, dynamic> map) {
return RecipeSpice(
name: map['name'] as String,
);
}

Map<String, dynamic> toMap() {
  return {
    'name': name,
  };
}
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

  factory Recipe.fromMap(Map<String, dynamic> map) {
    return Recipe(
      name: map['name'] as String,
      ingredients: (map['ingredients'] as List<dynamic>)
          .map(
            (ingredient) => RecipeIngredient.fromMap(
          ingredient as Map<String, dynamic>,
        ),
      )
          .toList(),
      spices: (map['spices'] as List<dynamic>)
          .map(
            (spice) => RecipeSpice.fromMap(
          spice as Map<String, dynamic>,
        ),
      )
          .toList(),
      preparation: map['preparation'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'ingredients': ingredients
          .map(
            (ingredient) => ingredient.toMap(),
      )
          .toList(),
      'spices': spices
          .map(
            (spice) => spice.toMap(),
      )
          .toList(),
      'preparation': preparation,
    };
  }
}