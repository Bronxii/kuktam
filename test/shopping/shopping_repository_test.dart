import 'package:kuktam/shopping/presentation/widgets/shopping_item_dialog.dart';
import 'package:kuktam/households/household_gateway.dart';
import '../support/feature_access.dart';
// Test-only SDK doubles; these never enter production or access the network.
// ignore_for_file: subtype_of_sealed_class
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:kuktam/shopping/data/mutations/production_shopping_coordinator.dart';
import 'package:kuktam/shopping/data/mutations/shopping_coordinator.dart';
import 'shopping_client_fixture.dart';
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

class _Functions implements FirebaseFunctions {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
  bool queueLocal = false;
  Completer<void>? remoteAck;
  final pendingPaths = <String>{};
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
    if (i.memberName == #snapshots) return _snapshots();
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

  Stream<DocumentSnapshot<Map<String, dynamic>>> _snapshots() async* {
    yield _SnapshotDoc(
      this,
      db.records[path] ?? {},
      db.pendingPaths.contains(path),
    );
    await for (final _ in db.events.stream) {
      yield _SnapshotDoc(
        this,
        db.records[path] ?? {},
        db.pendingPaths.contains(path),
      );
    }
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
  _SnapshotDoc(this.reference, [this.values = const {}, this.pending = false]);
  final bool pending;
  @override
  SnapshotMetadata get metadata => _Metadata(pending);
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

class _Metadata implements SnapshotMetadata {
  _Metadata(this.hasPendingWrites);
  @override
  final bool hasPendingWrites;
  @override
  bool get isFromCache => true;
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
      if (db.queueLocal) {
        for (final op in pending) {
          db.records[op.path] = Map.of(op.data);
          db.pendingPaths.add(op.path);
        }
        db.events.add(null);
      }
      return db.remoteAck?.future ?? Future<void>.value();
    }
    return super.noSuchMethod(i);
  }
}

void main() {
  test(
    'shopping reads tolerate server revision and retain legacy decoding',
    () async {
      final db = _Db();
      final backend = FirestoreShoppingCoordinatorBackend(
        db,
        _Auth(),
        _Functions(),
      );
      addTearDown(db.events.close);
      for (final id in ['legacy', 'revisioned']) {
        db.records['households/home-user-1/shoppingItems/$id'] = {
          'name': 'milk',
          'quantity': 2,
          'unit': 'db',
          'isChecked': false,
          'createdAt': Timestamp.fromMillisecondsSinceEpoch(1),
          if (id == 'revisioned') 'revision': 123,
        };
      }
      final items = await backend.items('user-1', 'home-user-1').first;
      expect(items.map((i) => i.id), containsAll(['legacy', 'revisioned']));
      expect(items.every((i) => i.quantity == 2 && !i.isChecked), true);
      expect(items.singleWhere((i) => i.id == 'legacy').revision, 0);
      expect(items.singleWhere((i) => i.id == 'revisioned').revision, 123);
      expect(db.operations, isEmpty);
    },
  );
  for (final mode in ['online', 'pending', 'failure']) {
    testWidgets('real repository add dialog $mode releases correctly', (
      tester,
    ) async {
      final fixture = ClientFixture();
      await tester.runAsync(fixture.open);
      addTearDown(() => tester.runAsync(fixture.close));
      if (mode == 'failure') await tester.runAsync(() => fixture.bind(null));
      final repo = fixture.repository;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showShoppingItemDialog(
                  context: context,
                  shoppingRepository: repo,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'offline bread');
      final submit = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Hozzáadás'))
          .onPressed!;
      await tester.runAsync(() async {
        final first = (submit as dynamic)() as Future<void>;
        await (submit as dynamic)();
        await first;
      });
      await tester.pumpAndSettle();
      final pending = await tester.runAsync(() => fixture.box.entries('A'));
      if (mode == 'failure') {
        expect(find.text('Nem sikerült menteni a tételt.'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(pending, isEmpty);
      } else {
        expect(find.byType(AlertDialog), findsNothing);
        expect(pending, hasLength(1));
        expect(pending!.single.request.context.householdId, 'home-A');
        // A new presentation facade observes the same durable session owner.
        expect(
          (await tester.runAsync(
            () => ShoppingRepository(
              firebaseAuth: fixture.auth,
              coordinator: Future.value(fixture.client),
            ).watchShoppingItems().first,
          ))!.single.name,
          'offline bread',
        );
        if (mode == 'pending') {
          await tester.runAsync(
            () => fixture.receipt(
              pending.single.request,
              'REJECTED_UNAUTHORIZED',
            ),
          );
          expect(fixture.client.notice, isNotNull);
          expect(fixture.client.items, isEmpty);
          expect(
            await tester.runAsync(() => fixture.box.notices('A')),
            hasLength(1),
          );
        }
      }
    });
  }

  test(
    'offline cached household supports shopping reads and queues writes on the confirmed path',
    () async {
      final fixture = ClientFixture();
      await fixture.open();
      addTearDown(fixture.close);
      await fixture.canonical([canonicalItem(id: 'saved')]);
      fixture.backend.offline = true;
      await fixture.restart();
      final repo = fixture.repository;
      expect((await repo.getShoppingItems()).single.id, 'saved');
      expect((await repo.watchShoppingItems().first).single.id, 'saved');
      final observed = fixture.client.items.single;
      await repo.addOrMergeItem(name: 'bread', quantity: 1, unit: 'db');
      await repo.setItemChecked(
        id: 'saved',
        observed: observed,
        isChecked: true,
      );
      final requests = await fixture.box.entries('A');
      expect(requests, hasLength(2));
      expect(
        requests.every((r) => r.request.context.householdId == 'home-A'),
        true,
      );
      final ids = requests.map((r) => r.request.mutationId).toList();
      await fixture.restart();
      expect(
        (await fixture.box.entries('A')).map((r) => r.request.mutationId),
        ids,
      );
      expect(
        fixture.client.items.singleWhere((i) => i.id == 'saved').isChecked,
        true,
      );
    },
  );

  test('shopping session identity is independent of entitlement', () {
    final auth = _Auth();
    final repo = _repository(firestore: _Db(), firebaseAuth: auth);
    final check = repo.captureSessionCheck();
    expect(check(), isTrue);
    auth.uid = 'other';
    expect(check(), isFalse);
    auth.signedIn = false;
    expect(check(), isFalse);
  });
  for (final factor in ['0.5', '1', '2']) {
    testWidgets(
      'multiplier $factor reaches real repository with one durable bulk intent',
      (tester) async {
        final fixture = ClientFixture();
        await tester.runAsync(fixture.open);
        addTearDown(() => tester.runAsync(fixture.close));
        final repo = fixture.repository;
        final accepted = Completer<void>();
        await openMultiplier(tester, (items) async {
          await tester.runAsync(() => repo.addOrMergeItems(items));
          accepted.complete();
        });
        await tester.enterText(find.byType(TextField), factor);
        await tester.tap(find.text('Hozzáadás'));
        await tester.pump();
        await accepted.future;
        await tester.pumpAndSettle();
        final pending = await tester.runAsync(() => fixture.box.entries('A'));
        expect(pending, hasLength(1));
        final children = pending!.single.request.children;
        expect(children, hasLength(2));
        expect(children.map((o) => o.quantity), [
          500 * double.parse(factor),
          750 * double.parse(factor),
        ]);
        expect(children.map((o) => o.unit), ['g', 'ml']);
      },
    );
  }
  testWidgets(
    'target scaling batch lookup failure writes nothing; retry commits all once',
    (tester) async {
      final fixture = ClientFixture();
      await tester.runAsync(fixture.open);
      addTearDown(() => tester.runAsync(fixture.close));
      await tester.runAsync(() => fixture.bind(null));
      final repo = fixture.repository;
      await tester.pumpWidget(
        withProAccess(
          MaterialApp(
            home: RecipeDetailsScreen(
              recipe: original,
              addScalingShoppingItems: repo.addOrMergeItems,
            ),
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
      expect(await tester.runAsync(() => fixture.box.entries('A')), isEmpty);
      expect(find.byType(RecipeScalingDialog), findsOneWidget);
      await tester.runAsync(() => fixture.bind('A'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(button);
      await tester.runAsync(() async {
        final callback = tester.widget<FilledButton>(button).onPressed!;
        await (callback as dynamic)();
      });
      await tester.pumpAndSettle();
      final pending = await tester.runAsync(() => fixture.box.entries('A'));
      expect(pending, hasLength(1));
      expect(pending!.single.request.children.map((o) => o.quantity), [
        750.0,
        1130.0,
      ]);
    },
  );
  test(
    'manual add uses validated batch merge and retains target checked metadata',
    () async {
      final fixture = ClientFixture();
      await fixture.open();
      addTearDown(fixture.close);
      await fixture.canonical([canonicalItem(checked: true)]);
      final repo = fixture.repository;
      await repo.addOrMergeItem(name: ' TeJ ', quantity: 1, unit: 'l');
      final pending = await fixture.box.entries('A');
      expect(pending, hasLength(1));
      final child = pending.single.request.children.single;
      expect(child.name, 'tej');
      expect(child.quantity, 1000);
      expect(child.unit, 'ml');
      expect(
        fixture.client.items.singleWhere((i) => i.id == 'tea').isChecked,
        true,
      );
      for (final invalid in [double.nan, double.infinity, 0.0, -1.0]) {
        await expectLater(
          repo.addOrMergeItem(name: 'x', quantity: invalid, unit: 'db'),
          throwsArgumentError,
        );
      }
      expect(await fixture.box.entries('A'), hasLength(1));
    },
  );
  test(
    'edit collision atomically increments target and deletes source; failure retry',
    () async {
      final fixture = ClientFixture();
      await fixture.open();
      addTearDown(fixture.close);
      await fixture.canonical([canonicalItem(id: 'source', revision: 7)]);
      final observed = fixture.client.items.single;
      final repo = fixture.repository;
      Future<void> save() => repo.updateItem(
        id: 'source',
        observed: observed,
        name: ' LISZT ',
        quantity: .5,
        unit: 'kg',
      );
      await fixture.bind(null);
      await expectLater(save(), throwsStateError);
      expect(await fixture.box.entries('A'), isEmpty);
      await fixture.bind('A');
      await save();
      final child = (await fixture.box.entries(
        'A',
      )).single.request.children.single;
      expect(child.itemId, 'source');
      expect(child.expectedRevision, 7);
      expect(child.name, 'liszt');
      expect(child.quantity, 500);
      expect(child.unit, 'g');
      // Actual collision/merge is exclusively transactional on the server.
    },
  );
  test(
    'edit own name preserves id and checked state; invalid update never writes',
    () async {
      final fixture = ClientFixture();
      await fixture.open();
      addTearDown(fixture.close);
      await fixture.canonical([canonicalItem(id: 'self', checked: true)]);
      final repo = fixture.repository, observed = fixture.client.items.single;
      await repo.updateItem(
        id: 'self',
        observed: observed,
        name: 'TEJ',
        quantity: 2,
        unit: 'l',
      );
      final child = (await fixture.box.entries(
        'A',
      )).single.request.children.single;
      expect(child.itemId, 'self');
      expect(child.name, 'tej');
      expect(child.quantity, 2000);
      expect(child.unit, 'ml');
      expect(fixture.client.items.single.isChecked, true);
      await expectLater(
        repo.updateItem(
          id: 'self',
          observed: observed,
          name: 'tej',
          quantity: double.nan,
          unit: 'l',
        ),
        throwsArgumentError,
      );
      expect(await fixture.box.entries('A'), hasLength(1));
    },
  );
  test(
    'checked partition stable across reload; CRUD paths stay within current user',
    () async {
      final fixture = ClientFixture();
      await fixture.open();
      addTearDown(fixture.close);
      final originals = [
        for (var i = 0; i < 40; i++) canonicalItem(id: '$i', checked: i.isEven),
      ];
      await fixture.canonical(originals);
      final repo = fixture.repository;
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
      fixture.backend.canonical = [];
      await fixture.bind('B');
      expect(await repo.getShoppingItems(), isEmpty);
      await repo.addOrMergeItem(name: 'tej', quantity: 1, unit: 'l');
      await fixture.canonical([canonicalItem(id: 'own')]);
      final own = fixture.client.items.singleWhere((i) => i.id == 'own');
      await repo.setItemChecked(id: 'own', observed: own, isChecked: true);
      await repo.deleteItem(
        'own',
        observed: fixture.client.items.singleWhere((i) => i.id == 'own'),
      );
      expect(
        (await fixture.box.projectionRows(
          'B',
        )).every((r) => (r['draft'] as String).contains('home-B')),
        true,
      );
      fixture.backend.canonical = originals;
      await fixture.bind('A');
      expect(await repo.getShoppingItems(), hasLength(40));
      await repo.clearShoppingList(observed: fixture.client.items);
      final clear = (await fixture.box.entries('A')).single.request;
      expect(clear.children, hasLength(40));
      expect(clear.children.map((c) => c.itemId), expected);
      expect(clear.context.householdId, 'home-A');
    },
  );
  test('batch cap rejects entire action before lookup or commit', () async {
    final fixture = ClientFixture();
    await fixture.open();
    addTearDown(fixture.close);
    final repo = fixture.repository;
    await expectLater(
      repo.addOrMergeItems(
        List.generate(201, (i) => (name: '$i', quantity: 1.0, unit: 'db')),
      ),
      throwsArgumentError,
    );
    expect(await fixture.box.entries('A'), isEmpty);
    expect(fixture.transport.sent, isEmpty);
  });
  test(
    'groups canonical targets, reuses increment and metadata, one commit',
    () async {
      final fixture = ClientFixture();
      await fixture.open();
      addTearDown(fixture.close);
      final repo = fixture.repository;
      await repo.addOrMergeItems([
        (name: ' Alma ', quantity: 1.0, unit: 'kg'),
        (name: 'alma', quantity: 500.0, unit: 'g'),
        (name: 'Tej', quantity: 1.234, unit: 'l'),
        (name: 'tej', quantity: 66.0, unit: 'ml'),
        (name: 'Tej', quantity: 2.5, unit: 'db'),
      ]);
      final pending = await fixture.box.entries('A');
      expect(pending, hasLength(1));
      expect(pending.single.request.children, hasLength(5));
      expect(pending.single.request.context.householdId, 'home-A');
      expect(fixture.client.items, hasLength(3));
      expect(
        fixture.client.items.singleWhere((i) => i.name == 'alma').quantity,
        1500,
      );
      expect(
        fixture.client.items
            .singleWhere((i) => i.name == 'tej' && i.unit == 'ml')
            .quantity,
        1300,
      );
      expect(
        fixture.client.items
            .singleWhere((i) => i.name == 'tej' && i.unit == 'db')
            .quantity,
        2.5,
      );
      expect(fixture.client.items.every((i) => !i.isChecked), true);
    },
  );
  test('later invalid bulk child never accepts earlier children', () async {
    final fixture = ClientFixture();
    await fixture.open();
    addTearDown(fixture.close);
    final repo = fixture.repository;
    await expectLater(
      repo.addOrMergeItems([
        (name: 'a', quantity: 1.0, unit: 'db'),
        (name: 'b', quantity: double.nan, unit: 'db'),
      ]),
      throwsArgumentError,
    );
    expect(await fixture.box.entries('A'), isEmpty);
    expect(fixture.client.items, isEmpty);
  });
  test(
    'local acceptance error propagates; explicit retry accepts exactly once',
    () async {
      final fixture = ClientFixture();
      await fixture.open();
      addTearDown(fixture.close);
      final repo = fixture.repository;
      await fixture.bind(null);
      final items = [(name: 'a', quantity: 1.0, unit: 'db')];
      await expectLater(repo.addOrMergeItems(items), throwsStateError);
      expect(await fixture.box.entries('A'), isEmpty);
      await fixture.bind('A');
      await repo.addOrMergeItems(items);
      expect(await fixture.box.entries('A'), hasLength(1));
    },
  );
  test(
    'invalid input and normalization overflow reject before writes',
    () async {
      final fixture = ClientFixture();
      await fixture.open();
      addTearDown(fixture.close);
      final repo = fixture.repository;
      for (final item in [
        (name: '', quantity: 1.0, unit: 'db'),
        (name: 'a', quantity: 0.0, unit: 'db'),
        (name: 'a', quantity: double.nan, unit: 'db'),
        (name: 'a', quantity: 1.0, unit: 'karton'),
        (name: 'a', quantity: double.maxFinite, unit: 'kg'),
      ]) {
        await expectLater(repo.addOrMergeItems([item]), throwsArgumentError);
      }
      expect(await fixture.box.entries('A'), isEmpty);
      expect(fixture.transport.sent, isEmpty);
    },
  );
  test(
    'session changes while household resolves cannot write or expose old data',
    () async {
      final fixture = ClientFixture();
      await fixture.open();
      addTearDown(fixture.close);
      final pending = Completer<ShoppingCoordinator>();
      final repo = ShoppingRepository(
        firebaseAuth: fixture.auth,
        coordinator: pending.future,
      );
      final result = repo.addOrMergeItem(name: 'milk', quantity: 1, unit: 'l');
      await fixture.bind(null);
      pending.complete(fixture.client);
      await expectLater(result, throwsStateError);
      expect(await fixture.box.entries('A'), isEmpty);
      expect(fixture.client.items, isEmpty);
    },
  );
  test('empty input does nothing and missing user cannot write', () async {
    final fixture = ClientFixture();
    await fixture.open();
    addTearDown(fixture.close);
    await fixture.bind(null);
    final repo = fixture.repository;
    await repo.addOrMergeItems([]);
    await expectLater(
      repo.addOrMergeItems([(name: 'a', quantity: 1.0, unit: 'db')]),
      throwsStateError,
    );
    expect(await fixture.box.entries('A'), isEmpty);
  });
}

class _Homes implements HouseholdGateway {
  _Homes(this.auth);
  final FirebaseAuth auth;
  @override
  Future<String> ensure() async => 'home-${auth.currentUser!.uid}';
}

ShoppingRepository _repository({
  required FirebaseFirestore firestore,
  required FirebaseAuth firebaseAuth,
}) => ShoppingRepository(
  firestore: firestore,
  firebaseAuth: firebaseAuth,
  householdGateway: _Homes(firebaseAuth),
);
