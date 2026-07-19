import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:kuktam/recipes/domain/models/recipe.dart';

class RecipeRepository {
  RecipeRepository({
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

Future<void> saveRecipe(Recipe recipe) async {
  final data = recipe.toMap();

  data['createdAt'] = FieldValue.serverTimestamp();

  await _firestore.collection('recipes').add(data);
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

    await _firestore.collection('recipes').doc(id).update(data);
  }
  Future<void> deleteRecipe(String id) async {
    await _firestore.collection('recipes').doc(id).delete();
  }
  Future<List<Recipe>> getRecipes() async {
    final snapshot = await _firestore
        .collection('recipes')
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