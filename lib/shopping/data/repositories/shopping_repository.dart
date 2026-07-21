import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../domain/models/shopping_item.dart';

class ShoppingRepository {
  ShoppingRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? firebaseAuth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _firebaseAuth;

  CollectionReference<Map<String, dynamic>> get _shoppingCollection {
    final user = _firebaseAuth.currentUser;

    if (user == null) {
      throw StateError(
        'Bevásárlólista csak bejelentkezett felhasználóhoz érhető el.',
      );
    }

    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('shopping');
  }

  Future<List<ShoppingItem>> getShoppingItems() async {
    final snapshot = await _shoppingCollection.get();

    return snapshot.docs.map((document) {
      final data = document.data();

      return ShoppingItem(
        id: document.id,
        name: data['name'] as String,
        quantity: (data['quantity'] as num).toDouble(),
        unit: data['unit'] as String,
        isChecked: data['isChecked'] as bool,
      );
    }).toList();
  }
  Stream<List<ShoppingItem>> watchShoppingItems() {
    return _shoppingCollection
        .orderBy('createdAt')
        .snapshots()
        .map((snapshot) {
      final items = snapshot.docs.map((document) {
        final data = document.data();

        return ShoppingItem(
          id: document.id,
          name: data['name'] as String,
          quantity: (data['quantity'] as num).toDouble(),
          unit: data['unit'] as String,
          isChecked: data['isChecked'] as bool,
        );
      }).toList();

      items.sort((first, second) {
        if (first.isChecked == second.isChecked) {
          return 0;
        }

        return first.isChecked ? 1 : -1;
      });

      return items;
    });
  }
  Future<void> addOrMergeItem({
    required String name,
    required double quantity,
    required String unit,
  }) async {
    if (quantity <= 0) {
      throw ArgumentError('A mennyiségnek pozitívnak kell lennie.');
    }

    final normalizedName = name.trim().toLowerCase();
    final normalizedData = _normalizeQuantityAndUnit(
      quantity: quantity,
      unit: unit,
    );

    final existingItems = await _shoppingCollection
        .where('name', isEqualTo: normalizedName)
        .where('unit', isEqualTo: normalizedData.unit)
        .limit(1)
        .get();

    if (existingItems.docs.isNotEmpty) {
      await existingItems.docs.first.reference.update({
        'quantity': FieldValue.increment(normalizedData.quantity),
      });

      return;
    }

    await _shoppingCollection.add({
      'name': normalizedName,
      'quantity': normalizedData.quantity,
      'unit': normalizedData.unit,
      'isChecked': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
  Future<void> updateItem({
    required String id,
    required String name,
    required double quantity,
    required String unit,
  }) async {
    if (quantity <= 0) {
      throw ArgumentError('A mennyiségnek pozitívnak kell lennie.');
    }

    final normalizedName = name.trim().toLowerCase();
    final normalizedData = _normalizeQuantityAndUnit(
      quantity: quantity,
      unit: unit,
    );

    await _shoppingCollection.doc(id).update({
      'name': normalizedName,
      'quantity': normalizedData.quantity,
      'unit': normalizedData.unit,
    });
  }
  Future<void> setItemChecked({
    required String id,
    required bool isChecked,
  }) async {
    await _shoppingCollection.doc(id).update({
      'isChecked': isChecked,
    });
  }
  Future<void> deleteItem(String id) async {
    await _shoppingCollection.doc(id).delete();
  }
  Future<void> clearShoppingList() async {
    final snapshot = await _shoppingCollection.get();
    final batch = _firestore.batch();

    for (final document in snapshot.docs) {
      batch.delete(document.reference);
    }

    await batch.commit();
  }
  ({double quantity, String unit}) _normalizeQuantityAndUnit({
    required double quantity,
    required String unit,
  }) {
    switch (unit.trim().toLowerCase()) {
      case 'kg':
        return (
        quantity: quantity * 1000,
        unit: 'g',
        );

      case 'l':
        return (
        quantity: quantity * 1000,
        unit: 'ml',
        );

      default:
        return (
        quantity: quantity,
        unit: unit.trim().toLowerCase(),
        );
    }
  }
}