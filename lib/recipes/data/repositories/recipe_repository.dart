import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:kuktam/recipes/domain/models/recipe.dart';

class RecipeRepository {
  RecipeRepository({
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

Future<void> saveRecipe(Recipe recipe) async {
  await _firestore.collection('recipes').add({
    'name': recipe.name,
    'ingredients': recipe.ingredients
        .map(
          (ingredient) => {
        'name': ingredient.name,
        'quantity': ingredient.quantity,
        'unit': ingredient.unit,
      },
    )
        .toList(),
    'spices': recipe.spices
        .map(
          (spice) => {
        'name': spice.name,
      },
    )
        .toList(),
    'preparation': recipe.preparation,
    'createdAt': FieldValue.serverTimestamp(),
  });
}
  Future<List<Recipe>> getRecipes() async {
    final snapshot = await _firestore
        .collection('recipes')
        .orderBy('createdAt', descending: true)
        .get();

    return snapshot.docs.map((document) {
      final data = document.data();

      return Recipe(
        name: data['name'] as String,
        ingredients: const [],
        spices: const [],
        preparation: data['preparation'] as String,
      );
    }).toList();
  }
}