// Test-only SDK doubles; these never enter production or access the network.
// ignore_for_file: subtype_of_sealed_class
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/shopping/data/repositories/shopping_repository.dart';

// Small SDK doubles: exercise the real repository without Firebase/network.
class _Auth implements FirebaseAuth {
  bool signedIn = true;
  @override
  dynamic noSuchMethod(Invocation i) => i.memberName == #currentUser
      ? (signedIn ? _User() : null)
      : super.noSuchMethod(i);
}

class _User implements User {
  @override
  dynamic noSuchMethod(Invocation i) =>
      i.memberName == #uid ? 'user-1' : super.noSuchMethod(i);
}

class _Db implements FirebaseFirestore {
  final existing = <String, String>{};
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
  dynamic noSuchMethod(Invocation i) {
    if (i.memberName == #collection) {
      return _Collection(db, '$path/${i.positionalArguments.single}');
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
    return super.noSuchMethod(i);
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
  _SnapshotDoc(this.reference);
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
