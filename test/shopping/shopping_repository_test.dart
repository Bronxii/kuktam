// Test-only SDK doubles; these never enter production or access the network.
// ignore_for_file: subtype_of_sealed_class
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:kuktam/shopping/data/repositories/shopping_repository.dart';
import 'package:kuktam/recipes/presentation/widgets/recipe_scaling_dialog.dart';
import 'package:kuktam/recipes/presentation/screens/recipe_details_screen.dart';
import '../recipes/recipe_extra_qa_test.dart' show openMultiplier, original;

// Small SDK doubles: exercise the real repository without Firebase/network.
class _Auth implements FirebaseAuth {
  bool signedIn = true;
  String uid = 'user-1';
  @override
  dynamic noSuchMethod(Invocation i) => i.memberName == #currentUser
      ? (signedIn ? _User(uid) : null)
      : super.noSuchMethod(i);
}

class _User implements User {
  _User(this.uid);
  @override
  final String uid;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Db implements FirebaseFirestore {
  final existing = <String, String>{};
  final records = <String, Map<String, dynamic>>{};
  final events = StreamController<void>.broadcast();
  final queries = <String>[];
  final paths = <String>[];
  final operations =
      <({String path, bool update, Map<String, dynamic> data})>[];
  int commits = 0;
  int ids = 0;
  int? failQuery;
  bool failCommit = false;
  @override
  dynamic noSuchMethod(Invocation i) {
    if (i.memberName == #collection) {
      return _Collection(this, i.positionalArguments.single as String);
    }
    if (i.memberName == #batch) return _Batch(this);
    return super.noSuchMethod(i);
  }
}

class _Doc implements DocumentReference<Map<String, dynamic>> {
  _Doc(this.db, this.path);
  final _Db db;
  @override
  final String path;
  @override
  String get id => path.split('/').last;
  @override
  dynamic noSuchMethod(Invocation i) {
    if (i.memberName == #collection) {
      return _Collection(db, '$path/${i.positionalArguments.single}');
    }
    if (i.memberName == #update || i.memberName == #delete) {
      if (db.failCommit) return Future<void>.error(StateError('write'));
      db.operations.add((
        path: path,
        update: i.memberName == #update,
        data: i.memberName == #delete
            ? {'deleted': true}
            : Map<String, dynamic>.from(i.positionalArguments.single as Map),
      ));
      return Future<void>.value();
    }
    return super.noSuchMethod(i);
  }
}

class _Collection implements CollectionReference<Map<String, dynamic>> {
  _Collection(this.db, this.path);
  final _Db db;
  @override
  final String path;
  @override
  dynamic noSuchMethod(Invocation i) {
    if (i.memberName == #doc) {
      final id = i.positionalArguments.isEmpty
          ? null
          : i.positionalArguments.first;
      return _Doc(db, '$path/${id ?? 'new-${db.ids++}'}');
    }
    if (i.memberName == #where) {
      return _Query(db, path, {
        i.positionalArguments.first as String:
            i.namedArguments[#isEqualTo] as String,
      });
    }
    if (i.memberName == #orderBy) return this;
    if (i.memberName == #get) {
      db.paths.add(path);
      return Future<QuerySnapshot<Map<String, dynamic>>>.value(
        _Snapshot([
          for (final e in db.records.entries.where(
            (e) => e.key.startsWith('$path/'),
          ))
            _SnapshotDoc(_Doc(db, e.key), e.value),
        ]),
      );
    }
    if (i.memberName == #snapshots) return _stream();
    return super.noSuchMethod(i);
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _stream() async* {
    yield await get();
    await for (final _ in db.events.stream) {
      yield await get();
    }
  }
}

class _Query implements Query<Map<String, dynamic>> {
  _Query(this.db, this.path, this.filters);
  final _Db db;
  final String path;
  final Map<String, String> filters;
  @override
  dynamic noSuchMethod(Invocation i) {
    if (i.memberName == #where) {
      return _Query(db, path, {
        ...filters,
        i.positionalArguments.first as String:
            i.namedArguments[#isEqualTo] as String,
      });
    }
    if (i.memberName == #limit) return this;
    if (i.memberName == #get) {
      final key = '${filters['name']}|${filters['unit']}';
      db.queries.add(key);
      db.paths.add(path);
      if (db.failQuery == db.queries.length) {
        return Future<QuerySnapshot<Map<String, dynamic>>>.error(
          StateError('query'),
        );
      }
      final id = db.existing[key];
      return Future<QuerySnapshot<Map<String, dynamic>>>.value(
        _Snapshot(id == null ? [] : [_SnapshotDoc(_Doc(db, '$path/$id'))]),
      );
    }
    return super.noSuchMethod(i);
  }
}

class _Snapshot implements QuerySnapshot<Map<String, dynamic>> {
  _Snapshot(this.docs);
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _SnapshotDoc implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _SnapshotDoc(this.reference, [this.values = const {}]);
  final Map<String, dynamic> values;
  @override
  String get id => reference.id;
  @override
  Map<String, dynamic> data() => values;
  @override
  final DocumentReference<Map<String, dynamic>> reference;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Batch implements WriteBatch {
  _Batch(this.db);
  final _Db db;
  final pending = <({String path, bool update, Map<String, dynamic> data})>[];
  @override
  dynamic noSuchMethod(Invocation i) {
    if (i.memberName == #set || i.memberName == #update) {
      pending.add((
        path: (i.positionalArguments[0] as DocumentReference).path,
        update: i.memberName == #update,
        data: Map<String, dynamic>.from(i.positionalArguments[1] as Map),
      ));
      return null;
    }
    if (i.memberName == #delete) {
      pending.add((
        path: (i.positionalArguments.single as DocumentReference).path,
        update: false,
        data: {'deleted': true},
      ));
      return null;
    }
    if (i.memberName == #commit) {
      db.commits++;
      if (db.failCommit) return Future<void>.error(StateError('commit'));
      db.operations.addAll(pending);
      return Future<void>.value();
    }
    return super.noSuchMethod(i);
  }
}

void main() {
  for (final factor in ['0.5', '1', '2']) {
    testWidgets(
      'multiplier $factor reaches real repository with one atomic batch',
      (tester) async {
        final db = _Db();
        final repo = ShoppingRepository(firestore: db, firebaseAuth: _Auth());
        await openMultiplier(tester, repo.addOrMergeItems);
        await tester.enterText(find.byType(TextField), factor);
        await tester.tap(find.text('Hozzáadás'));
        await tester.pumpAndSettle();
        expect(db.commits, 1);
        expect(db.operations, hasLength(2));
        expect(db.operations.map((o) => o.data['quantity']), [
          500 * double.parse(factor),
          750 * double.parse(factor),
        ]);
        expect(db.operations.map((o) => o.data['unit']), ['g', 'ml']);
      },
    );
  }
  testWidgets(
    'target scaling batch lookup failure writes nothing; retry commits all once',
    (tester) async {
      final db = _Db()..failQuery = 2;
      final repo = ShoppingRepository(firestore: db, firebaseAuth: _Auth());
      await tester.pumpWidget(
        MaterialApp(
          home: RecipeDetailsScreen(
            recipe: original,
            addScalingShoppingItems: repo.addOrMergeItems,
          ),
        ),
      );
      await tester.tap(find.text('Átszámítás'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '750');
      final button = find.descendant(
        of: find.byType(RecipeScalingDialog),
        matching: find.widgetWithText(FilledButton, 'Bevásárlólistához adás'),
      );
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(db.commits, 0);
      expect(db.operations, isEmpty);
      expect(find.byType(RecipeScalingDialog), findsOneWidget);
      db.failQuery = null;
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(db.commits, 1);
      expect(db.operations, hasLength(2));
      expect(db.operations.map((o) => o.data['quantity']), [750.0, 1130.0]);
    },
  );
  test(
    'manual add uses validated batch merge and retains target checked metadata',
    () async {
      final db = _Db()..existing['tej|ml'] = 'checked';
      final repo = ShoppingRepository(firestore: db, firebaseAuth: _Auth());
      await repo.addOrMergeItem(name: ' TeJ ', quantity: 1, unit: 'l');
      expect(db.commits, 1);
      expect(db.operations.single.data, {
        'quantity': FieldValue.increment(1000.0),
      });
      for (final invalid in [double.nan, double.infinity, 0.0, -1.0]) {
        await expectLater(
          repo.addOrMergeItem(name: 'x', quantity: invalid, unit: 'db'),
          throwsArgumentError,
        );
      }
      expect(db.commits, 1);
    },
  );
  test(
    'edit collision atomically increments target and deletes source; failure retry',
    () async {
      final db = _Db()
        ..existing['liszt|g'] = 'target'
        ..failCommit = true;
      final repo = ShoppingRepository(firestore: db, firebaseAuth: _Auth());
      Future<void> save() => repo.updateItem(
        id: 'source',
        name: ' LISZT ',
        quantity: .5,
        unit: 'kg',
      );
      await expectLater(save(), throwsStateError);
      expect(db.operations, isEmpty);
      db.failCommit = false;
      await save();
      expect(db.operations.map((o) => o.path), [
        'users/user-1/shopping/target',
        'users/user-1/shopping/source',
      ]);
      expect(db.operations.first.data, {
        'quantity': FieldValue.increment(500.0),
      });
      expect(db.operations.last.data, {'deleted': true});
    },
  );
  test(
    'edit own name preserves id and checked state; invalid update never writes',
    () async {
      final db = _Db()..existing['tej|ml'] = 'self';
      final repo = ShoppingRepository(firestore: db, firebaseAuth: _Auth());
      await repo.updateItem(id: 'self', name: 'TEJ', quantity: 2, unit: 'l');
      expect(db.operations.single.data, {
        'name': 'tej',
        'quantity': 2000.0,
        'unit': 'ml',
      });
      await expectLater(
        repo.updateItem(
          id: 'self',
          name: 'tej',
          quantity: double.nan,
          unit: 'l',
        ),
        throwsArgumentError,
      );
      expect(db.operations.length, 1);
    },
  );
  test(
    'checked partition stable across reload; CRUD paths stay within current user',
    () async {
      final db = _Db();
      final auth = _Auth();
      final repo = ShoppingRepository(firestore: db, firebaseAuth: auth);
      addTearDown(db.events.close);
      for (var i = 0; i < 40; i++) {
        db.records['users/user-1/shopping/$i'] = {
          'name': 'Tétel $i',
          'quantity': 1,
          'unit': 'db',
          'isChecked': i.isEven,
        };
      }
      final expected = [
        for (var i = 1; i < 40; i += 2) '$i',
        for (var i = 0; i < 40; i += 2) '$i',
      ];
      expect(
        (await repo.watchShoppingItems().first).map((i) => i.id),
        expected,
      );
      expect(
        (await repo.watchShoppingItems().first).map((i) => i.id),
        expected,
      );
      auth.uid = 'B';
      expect(await repo.getShoppingItems(), isEmpty);
      await repo.addOrMergeItem(name: 'tej', quantity: 1, unit: 'l');
      await repo.setItemChecked(id: 'own', isChecked: true);
      await repo.deleteItem('own');
      expect(
        db.operations.every((o) => o.path.startsWith('users/B/shopping/')),
        isTrue,
      );
      auth.uid = 'user-1';
      expect(await repo.getShoppingItems(), hasLength(40));
      await repo.clearShoppingList();
      expect(
        db.operations.where(
          (o) =>
              o.data['deleted'] == true && o.path.startsWith('users/user-1/'),
        ),
        hasLength(40),
      );
    },
  );
  test('batch cap rejects entire action before lookup or commit', () async {
    final db = _Db();
    final repo = ShoppingRepository(firestore: db, firebaseAuth: _Auth());
    await expectLater(
      repo.addOrMergeItems(
        List.generate(201, (i) => (name: '$i', quantity: 1.0, unit: 'db')),
      ),
      throwsArgumentError,
    );
    expect(db.operations, isEmpty);
    expect(db.queries, isEmpty);
  });
  test(
    'groups canonical targets, reuses increment and metadata, one commit',
    () async {
      final db = _Db()..existing['alma|g'] = 'apple';
      final repo = ShoppingRepository(firestore: db, firebaseAuth: _Auth());
      await repo.addOrMergeItems([
        (name: ' Alma ', quantity: 1.0, unit: 'kg'),
        (name: 'alma', quantity: 500.0, unit: 'g'),
        (name: 'Tej', quantity: 1.234, unit: 'l'),
        (name: 'tej', quantity: 66.0, unit: 'ml'),
        (name: 'Tej', quantity: 2.5, unit: 'db'),
      ]);
      expect(db.commits, 1);
      expect(db.queries, ['alma|g', 'tej|ml', 'tej|db']);
      expect(db.paths.toSet(), {'users/user-1/shopping'});
      expect(db.operations, hasLength(3));
      expect(db.operations.first.path, 'users/user-1/shopping/apple');
      expect(db.operations.first.data, {
        'quantity': FieldValue.increment(1500.0),
      });
      expect(db.operations[1].data, {
        'name': 'tej',
        'quantity': 1300.0,
        'unit': 'ml',
        'isChecked': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      expect(db.operations.last.data['quantity'], 2.5);
    },
  );
  test('query failure never commits staged earlier writes', () async {
    final db = _Db()..failQuery = 2;
    final repo = ShoppingRepository(firestore: db, firebaseAuth: _Auth());
    await expectLater(
      repo.addOrMergeItems([
        (name: 'a', quantity: 1.0, unit: 'db'),
        (name: 'b', quantity: 1.0, unit: 'db'),
      ]),
      throwsStateError,
    );
    expect(db.commits, 0);
    expect(db.operations, isEmpty);
  });
  test('commit error propagates, retry builds a fresh batch', () async {
    final db = _Db()..failCommit = true;
    final repo = ShoppingRepository(firestore: db, firebaseAuth: _Auth());
    final items = [(name: 'a', quantity: 1.0, unit: 'db')];
    await expectLater(repo.addOrMergeItems(items), throwsStateError);
    expect(db.operations, isEmpty);
    db.failCommit = false;
    await repo.addOrMergeItems(items);
    expect(db.operations, hasLength(1));
    expect(db.commits, 2);
  });
  test(
    'invalid input and normalization overflow reject before writes',
    () async {
      final db = _Db();
      final repo = ShoppingRepository(firestore: db, firebaseAuth: _Auth());
      for (final item in [
        (name: '', quantity: 1.0, unit: 'db'),
        (name: 'a', quantity: 0.0, unit: 'db'),
        (name: 'a', quantity: double.nan, unit: 'db'),
        (name: 'a', quantity: 1.0, unit: 'karton'),
        (name: 'a', quantity: double.maxFinite, unit: 'kg'),
      ]) {
        await expectLater(repo.addOrMergeItems([item]), throwsArgumentError);
      }
      expect(db.commits, 0);
      expect(db.queries, isEmpty);
    },
  );
  test('empty input does nothing and missing user cannot write', () async {
    final db = _Db();
    final repo = ShoppingRepository(
      firestore: db,
      firebaseAuth: _Auth()..signedIn = false,
    );
    await repo.addOrMergeItems([]);
    await expectLater(
      repo.addOrMergeItems([(name: 'a', quantity: 1.0, unit: 'db')]),
      throwsStateError,
    );
    expect(db.commits, 0);
  });
}
