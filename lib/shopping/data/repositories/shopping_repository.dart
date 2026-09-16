import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../domain/models/shopping_item.dart';
import '../../domain/shopping_units.dart';

typedef ShoppingItemInput = ({String name, double quantity, String unit});

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

      // Stable partition preserves the query's creation order within groups.
      return [
        ...items.where((item) => !item.isChecked),
        ...items.where((item) => item.isChecked),
      ];
    });
  }
  Future<void> addOrMergeItem({
    required String name,
    required double quantity,
    required String unit,
  }) => addOrMergeItems([(name: name, quantity: quantity, unit: unit)]);
  /// All import writes commit together. Query-based target discovery retains
  /// the existing cross-client merge race; it is not a transactional lookup.
  Future<void> addOrMergeItems(List<ShoppingItemInput> items) async {
    if (items.isEmpty) return;
    if (items.length > 200) throw ArgumentError('Legfeljebb 200 tétel adható hozzá.');
    final grouped = <({String name, String unit}), double>{};
    for (final item in items) {
      final name = _normalizeName(item.name);
      if (name.isEmpty || !item.quantity.isFinite || item.quantity <= 0 ||
          !shoppingUnits.contains(item.unit)) {
        throw ArgumentError('Érvénytelen bevásárlólista-tétel.');
      }
      final normalized = _normalizeQuantityAndUnit(quantity: item.quantity, unit: item.unit);
      final key = (name: name, unit: normalized.unit);
      final total = (grouped[key] ?? 0) + normalized.quantity;
      if (!total.isFinite) throw ArgumentError('Túl nagy mennyiség.');
      grouped[key] = total;
    }
    // Capture the user's collection once, before asynchronous queries.
    final collection = _shoppingCollection;
    final batch = _firestore.batch();
    for (final entry in grouped.entries) {
      final existing = await collection
          .where('name', isEqualTo: entry.key.name)
          .where('unit', isEqualTo: entry.key.unit)
          .limit(1).get();
      if (existing.docs.isNotEmpty) {
        batch.update(existing.docs.first.reference, {
          'quantity': FieldValue.increment(entry.value),
        });
      } else {
        batch.set(collection.doc(), {
          'name': entry.key.name,
          'quantity': entry.value,
          'unit': entry.key.unit,
          'isChecked': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    }
    await batch.commit();
  }

  String _normalizeName(String name) => name.trim().toLowerCase();

  Future<void> updateItem({
    required String id,
    required String name,
    required double quantity,
    required String unit,
  }) async {
    if (!quantity.isFinite || quantity <= 0 || name.trim().isEmpty || !shoppingUnits.contains(unit)) {
      throw ArgumentError('A mennyiségnek pozitívnak kell lennie.');
    }

    final normalizedName = name.trim().toLowerCase();
    final normalizedData = _normalizeQuantityAndUnit(
      quantity: quantity,
      unit: unit,
    );

    if (!normalizedData.quantity.isFinite) throw ArgumentError('Túl nagy mennyiség.');
    final collection = _shoppingCollection;
    final matches = await collection
        .where('name', isEqualTo: normalizedName)
        .where('unit', isEqualTo: normalizedData.unit)
        .get();
    final targets = matches.docs.where((document) => document.id != id);
    if (targets.isNotEmpty) {
      final batch = _firestore.batch();
      batch.update(targets.first.reference, {
        'quantity': FieldValue.increment(normalizedData.quantity),
      });
      batch.delete(collection.doc(id));
      await batch.commit();
      return;
    }
    await collection.doc(id).update({
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
