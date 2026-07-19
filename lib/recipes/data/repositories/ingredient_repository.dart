import 'package:cloud_firestore/cloud_firestore.dart';

class IngredientRepository {
  IngredientRepository();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> saveIngredient(String name) async {
    final normalizedName = name.trim().toLowerCase();

    if (normalizedName.isEmpty) {
      return;
    }

    await _firestore
        .collection('ingredients')
        .doc(normalizedName)
        .set({
      'name': normalizedName,
    });
  }

  Future<List<String>> getIngredients() async {
    final snapshot = await _firestore
        .collection('ingredients')
        .orderBy('name')
        .get();

    return snapshot.docs
        .map((document) => document['name'] as String)
        .toList();
  }
}