import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:kuktam/recipes/domain/models/recipe.dart';

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
  Future<bool> recipeNameExists({
    required String name,
    String? excludedRecipeId,
  }) async {
    final normalizedName = name.trim().toLowerCase();
    final recipes = await getRecipes();

    return recipes.any((recipe) {
      final isSameRecipe = recipe.id == excludedRecipeId;
      final hasSameName =
          recipe.name.trim().toLowerCase() == normalizedName;

      return !isSameRecipe && hasSameName;
    });
  }
Future<void> saveRecipe(Recipe recipe) async {
  final data = recipe.toMap();

  data['createdAt'] = FieldValue.serverTimestamp();

  await _recipesCollection.add(data);
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
  }
  Future<void> deleteRecipe(String id) async {
    await _recipesCollection.doc(id).delete();
  }
  Future<List<Recipe>> getRecipes() async {
    final snapshot = await _recipesCollection.get();

    final recipes = snapshot.docs
        .map(
          (document) => Recipe.fromMap(
        document.data(),
        id: document.id,
      ),
    )
        .toList();

    recipes.sort(
          (a, b) => a.name.toLowerCase().compareTo(
        b.name.toLowerCase(),
      ),
    );

    return recipes;
  }
  Stream<List<Recipe>> watchRecipes() {
    return _recipesCollection.snapshots().map(
          (snapshot) {
        final recipes = snapshot.docs
            .map(
              (document) => Recipe.fromMap(
            document.data(),
            id: document.id,
          ),
        )
            .toList();

        recipes.sort(
              (a, b) => a.name.toLowerCase().compareTo(
            b.name.toLowerCase(),
          ),
        );

        return recipes;
      },
    );
  }
}