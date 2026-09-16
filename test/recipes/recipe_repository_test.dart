// Test-only SDK doubles; no Firebase/network calls.
// ignore_for_file: subtype_of_sealed_class
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/recipes/data/repositories/recipe_repository.dart';
import 'package:kuktam/recipes/domain/models/recipe.dart';
import 'package:kuktam/core/domain/services/import_quantity_parser.dart';

class RecipeTestUser implements User {
  RecipeTestUser(this.uid);
  @override
  final String uid;
  @override
  bool get emailVerified => true;
  @override
  List<UserInfo> get providerData => [];
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class RecipeTestAuth implements FirebaseAuth {
  @override
  User? currentUser = RecipeTestUser('A');
  final changes = StreamController<User?>.broadcast();
  @override
  Stream<User?> authStateChanges() => changes.stream;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class RecipeTestDb implements FirebaseFirestore {
  final data = <String, Map<String, dynamic>>{};
  final events = StreamController<void>.broadcast();
  final paths = <String>[];
  int nextId = 0;
  bool fail = false;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(this, path);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Document implements DocumentReference<Map<String, dynamic>> {
  _Document(this.db, this.path);
  final RecipeTestDb db;
  @override
  final String path;
  @override
  String get id => path.split('/').last;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(db, '${this.path}/$path');
  @override
  Future<void> update(Map<Object, Object?> values) async {
    if (db.fail) throw StateError('offline');
    if (!db.data.containsKey(path)) throw StateError('not-found');
    db.paths.add(path);
    db.data[path]!.addAll(values.cast<String, dynamic>());
    db.events.add(null);
  }

  @override
  Future<void> delete() async {
    if (db.fail) throw StateError('offline');
    db.paths.add(path);
    db.data.remove(path);
    db.events.add(null);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Collection implements CollectionReference<Map<String, dynamic>> {
  _Collection(this.db, this.path);
  final RecipeTestDb db;
  @override
  final String path;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _Document(db, '${this.path}/${path ?? db.nextId++}');
  @override
  Future<DocumentReference<Map<String, dynamic>>> add(
    Map<String, dynamic> data,
  ) async {
    if (db.fail) throw StateError('offline');
    final reference = doc();
    db.paths.add(reference.path);
    db.data[reference.path] = Map.of(data);
    db.events.add(null);
    return reference;
  }

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    if (db.fail) throw StateError('offline');
    db.paths.add(path);
    return _Snapshot(
      db.data.entries
          .where((e) => e.key.startsWith('$path/'))
          .map((e) => _SnapshotDoc(e.key.split('/').last, Map.of(e.value)))
          .toList(),
    );
  }

  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) async* {
    yield await get();
    await for (final _ in db.events.stream) {
      yield await get();
    }
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Snapshot implements QuerySnapshot<Map<String, dynamic>> {
  _Snapshot(this.docs);
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _SnapshotDoc implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _SnapshotDoc(this.id, this.values);
  @override
  final String id;
  final Map<String, dynamic> values;
  @override
  Map<String, dynamic> data() => values;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Recipe sample({String? id, String name = 'Leves'}) => Recipe(
  id: id,
  name: name,
  ingredients: const [RecipeIngredient(name: 'Víz', quantity: .125, unit: 'l')],
  spices: const [],
  preparation: 'Első.\n\nMásodik őű 😊',
);

void main() {
  test(
    'real repository CRUD serializes data, document ids and timestamps; user isolation A B A',
    () async {
      final db = RecipeTestDb();
      final auth = RecipeTestAuth();
      final repo = RecipeRepository(firestore: db, firebaseAuth: auth);
      addTearDown(db.events.close);
      addTearDown(auth.changes.close);
      expect(await repo.getRecipes(), isEmpty);
      await repo.saveRecipe(sample());
      final first = (await repo.getRecipes()).single;
      expect(first.id, '0');
      expect(first.toMap(), sample().toMap());
      expect(db.data['users/A/recipes/0']!['createdAt'], isA<FieldValue>());
      await repo.updateRecipe(sample(id: first.id, name: 'Új név'));
      expect(db.data.length, 1);
      expect(db.data.values.single['updatedAt'], isA<FieldValue>());
      auth.currentUser = RecipeTestUser('B');
      expect(await repo.getRecipes(), isEmpty);
      expect(await repo.recipeNameExists(name: 'új név'), isFalse);
      await repo.saveRecipe(sample(name: 'B receptje'));
      auth.currentUser = RecipeTestUser('A');
      expect((await repo.getRecipes()).single.name, 'Új név');
      await repo.deleteRecipe(first.id!);
      expect(await repo.getRecipes(), isEmpty);
      expect(db.data.keys.single, 'users/B/recipes/1');
    },
  );

  test('unique names trim/case, own exclusion, delete then reuse', () async {
    final db = RecipeTestDb();
    final auth = RecipeTestAuth();
    addTearDown(db.events.close);
    addTearDown(auth.changes.close);
    final repo = RecipeRepository(firestore: db, firebaseAuth: auth);
    await repo.saveRecipe(sample(name: '  Áfonyás süti  '));
    expect(await repo.recipeNameExists(name: 'ÁFONYÁS SÜTI'), isTrue);
    expect(
      await repo.recipeNameExists(name: 'áfonyás süti', excludedRecipeId: '0'),
      isFalse,
    );
    await repo.deleteRecipe('0');
    expect(await repo.recipeNameExists(name: 'Áfonyás süti'), isFalse);
  });

  test(
    'both repository list paths use Hungarian sorting for accents and prefixes',
    () async {
      final db = RecipeTestDb();
      final auth = RecipeTestAuth();
      addTearDown(db.events.close);
      addTearDown(auth.changes.close);
      final repo = RecipeRepository(firestore: db, firebaseAuth: auth);
      for (final name in ['Zöld', 'alma leves', 'Áfonyás', 'Alma']) {
        await repo.saveRecipe(sample(name: name));
      }
      expect((await repo.getRecipes()).map((r) => r.name), [
        'Alma',
        'alma leves',
        'Áfonyás',
        'Zöld',
      ]);
      expect((await repo.watchRecipes().first).map((r) => r.name), [
        'Alma',
        'alma leves',
        'Áfonyás',
        'Zöld',
      ]);
    },
  );

  test(
    'signed out and missing update id fail without writes; SDK errors propagate',
    () async {
      final db = RecipeTestDb();
      final auth = RecipeTestAuth();
      addTearDown(db.events.close);
      addTearDown(auth.changes.close);
      final repo = RecipeRepository(firestore: db, firebaseAuth: auth);
      await expectLater(repo.updateRecipe(sample()), throwsStateError);
      auth.currentUser = null;
      await expectLater(repo.saveRecipe(sample()), throwsStateError);
      await expectLater(repo.getRecipes(), throwsStateError);
      await expectLater(repo.deleteRecipe('0'), throwsStateError);
      expect(db.data, isEmpty);
      auth.currentUser = RecipeTestUser('A');
      db.fail = true;
      await expectLater(repo.saveRecipe(sample()), throwsStateError);
      await expectLater(repo.updateRecipe(sample(id: '0')), throwsStateError);
      await expectLater(repo.getRecipes(), throwsStateError);
      await expectLater(repo.deleteRecipe('0'), throwsStateError);
    },
  );

  test(
    'model roundtrip accepts integer quantity, empty optional content and no timestamp/id',
    () {
      final map = sample().toMap();
      (map['ingredients'] as List).single['quantity'] = 2;
      final restored = Recipe.fromMap(map);
      expect(restored.id, isNull);
      expect(restored.ingredients.single.quantity, 2.0);
      expect(restored.spices, isEmpty);
      expect(restored.preparation, sample().preparation);
      expect(restored.toMap().keys, [
        'name',
        'ingredients',
        'spices',
        'preparation',
      ]);
    },
  );

  for (final quantity in [0.00000001, 1e25, 1.5, 2.0]) {
    test('editor quantity formatting roundtrips $quantity without loss', () {
      final ingredient = RecipeIngredient(
        name: 'Liszt',
        quantity: quantity,
        unit: 'g',
      );
      expect(
        const ImportQuantityParser().parse(ingredient.formattedQuantity),
        quantity,
      );
    });
  }
}
