import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:kuktam/recipes/domain/models/recipe.dart';
import 'package:kuktam/recipes/data/repositories/ingredient_repository.dart';

class RecipeRepository {
  RecipeRepository({
FirebaseFirestore? firestore,
FirebaseAuth? firebaseAuth,
})  : _firestore = firestore ?? FirebaseFirestore.instance,
_firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
final FirebaseAuth _firebaseAuth;

CollectionReference<Map<String, dynamic>> get _recipesCollection {
  final user = _firebaseAuth.currentUser;

  if (user == null) {
    throw StateError(
      'Receptek csak bejelentkezett felhasználóhoz érhetők el.',
    );
  }

  return _firestore
      .collection('users')
      .doc(user.uid)
      .collection('recipes');
}
  final IngredientRepository _ingredientRepository =
  IngredientRepository();

Future<void> saveRecipe(Recipe recipe) async {
  final data = recipe.toMap();

  data['createdAt'] = FieldValue.serverTimestamp();

  await _recipesCollection.add(data);
  for (final ingredient in recipe.ingredients) {
    await _ingredientRepository.saveIngredient(ingredient.name);
  }
}
  Future<void> updateRecipe(Recipe recipe) async {
    final id = recipe.id;

    if (id == null) {
      throw StateError(
        'A recept nem frissíthető Firestore dokumentumazonosító nélkül.',
      );
    }

    final data = recipe.toMap();

    data['updatedAt'] = FieldValue.serverTimestamp();

    await _recipesCollection.doc(id).update(data);
    for (final ingredient in recipe.ingredients) {
      await _ingredientRepository.saveIngredient(ingredient.name);
    }
  }
  Future<void> deleteRecipe(String id) async {
    await _recipesCollection.doc(id).delete();
  }
  Future<List<Recipe>> getRecipes() async {
    final snapshot = await _recipesCollection
        .orderBy('createdAt', descending: true)
        .get();

    return snapshot.docs
        .map(
          (document) => Recipe.fromMap(
        document.data(),
        id: document.id,
      ),
    )
        .toList();
  }
}