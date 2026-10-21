import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:kuktam/shopping/data/mutations/shopping_coordinator.dart';
import 'package:kuktam/shopping/data/mutations/shopping_mutation_dispatcher.dart';
import 'package:kuktam/shopping/data/mutations/shopping_outbox.dart';
import 'package:kuktam/shopping/data/repositories/shopping_repository.dart';
import 'package:kuktam/shopping/domain/models/shopping_item.dart';
import 'package:kuktam/shopping/domain/shopping_mutation.dart';
import 'shopping_mutation_e2e_test.dart' show DeviceClient, fixture;
import 'shopping_h2c1_e2e_test.dart' show SessionBackend, SessionTransport;

class OnlineBackend extends SessionBackend {
  OnlineBackend(super.firestore, super.auth, super.functions);
  Completer<void>? canonicalRelease;
  Completer<void>? canonicalArrived;
  void holdCanonical() {
    canonicalRelease = Completer<void>();
    canonicalArrived = Completer<void>();
  }

  void releaseCanonical() {
    canonicalRelease!.complete();
    canonicalRelease = null;
  }

  @override
  Stream<List<ShoppingItem>> items(String uid, String hid) =>
      super.items(uid, hid).asyncMap((rows) async {
        final gate = canonicalRelease;
        if (gate != null) {
          if (!canonicalArrived!.isCompleted) canonicalArrived!.complete();
          await gate.future;
        }
        return rows;
      });
}

class OnlineClient extends DeviceClient {
  late OnlineBackend measured;
  late SessionTransport transport;
  @override
  Future<void> open(String name, String uid, {bool offline = false}) async {
    expect(offline, isFalse);
    app = await Firebase.initializeApp(
      name: name,
      options: const FirebaseOptions(
        apiKey: 'local-emulator-only',
        appId: '1:123456789:android:abc123',
        messagingSenderId: '123456789',
        projectId: 'demo-kuktam-local',
      ),
    );
    db = FirebaseFirestore.instanceFor(app: app)
      ..useFirestoreEmulator('10.0.2.2', 8088);
    auth = FirebaseAuth.instanceFor(app: app);
    await auth.useAuthEmulator('10.0.2.2', 9098);
    await auth.signInWithEmailAndPassword(
      email: '$uid@example.invalid',
      password: 'local-emulator-only-123',
    );
    expect(auth.currentUser!.uid, uid);
    box = await ShoppingOutbox.open(
      path: '${await getDatabasesPath()}/$name.db',
    );
    measured = OnlineBackend(
      db,
      auth,
      FirebaseFunctions.instanceFor(app: app, region: 'europe-west1'),
    );
    backend = measured;
    transport = SessionTransport(db, () => auth.currentUser?.uid);
    client = ShoppingCoordinator(
      outbox: box,
      dispatcher: ShoppingMutationDispatcher(
        outbox: box,
        transport: transport,
        currentUid: () => auth.currentUser?.uid,
      ),
      backend: measured,
      currentUid: () => auth.currentUser?.uid,
    );
    repository = ShoppingRepository(
      firebaseAuth: auth,
      coordinator: Future.value(client),
    );
    await client.bind(uid);
    await visible(() => client.context != null);
    expect(client.context!.householdId, 'test-family');
  }

  String get uid => auth.currentUser!.uid;
  Future<Command> accept(Future<void> Function() action) async {
    await action();
    final entry = (await box.entries(uid, includeTerminal: true)).last;
    expect(entry.request.context.uid, uid);
    // One-shot TEST barrier, not a production permanent command listener.
    await db
        .doc('users/$uid/shoppingMutations/${entry.request.mutationId}')
        .snapshots(includeMetadataChanges: true)
        .firstWhere(
          (d) =>
              d.exists &&
              !d.metadata.isFromCache &&
              !d.metadata.hasPendingWrites,
        )
        .timeout(const Duration(seconds: 45));
    return Command(this, entry.request.mutationId);
  }

  Future<Command> add(String name, double quantity, String unit) => accept(
    () => repository.addOrMergeItem(name: name, quantity: quantity, unit: unit),
  );
  void listeners() {
    measured.canonical.only(uid, count: 1);
    final n = transport.receipts.active.values.fold(0, (a, b) => a + b);
    transport.receipts.only(uid, count: n);
    expect(n, lessThanOrEqualTo(1));
  }

  @override
  Future<void> close() async {
    await super.close();
    measured.canonical.only(null, count: 0);
    transport.receipts.only(null, count: 0);
    await measured.ensured.close();
  }
}

class Command {
  Command(this.client, this.id);
  final OnlineClient client;
  final String id;
  Map<String, String> get ref => {'uid': client.uid, 'id': id};
}

Future<List<dynamic>> process(
  List<Command> commands, {
  bool ordered = false,
}) async {
  final response = await fixture('process-selected', {
    'mode': ordered ? 'ordered' : 'concurrent',
    'commands': commands.map((c) => c.ref).toList(),
  });
  final receipts = response['receipts'] as List;
  for (var i = 0; i < commands.length; i++) {
    expect(receipts[i]['id'], commands[i].id);
    expect(receipts[i]['actorUid'], commands[i].client.uid);
  }
  return receipts;
}

List<Object?> itemFields(ShoppingItem i) => [
  i.id,
  i.name,
  i.quantity,
  i.unit,
  i.isChecked,
  i.revision,
];
String view(OnlineClient c) {
  if (c.client.items.any((i) => i.pending)) return 'PENDING';
  final items = c.client.items.toList()..sort((a, b) => a.id.compareTo(b.id));
  return jsonEncode(items.map(itemFields).toList());
}

Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> converge(
  OnlineClient a,
  OnlineClient b,
) async {
  await Future.wait([a.done(), b.done()]);
  final server = await a.db
      .collection('households/test-family/shoppingItems')
      .get(const GetOptions(source: Source.server));
  final docs = server.docs.toList()..sort((a, b) => a.id.compareTo(b.id));
  final expected = jsonEncode(
    docs
        .map(
          (d) => [
            d.id,
            d.get('name'),
            (d.get('quantity') as num).toDouble(),
            d.get('unit'),
            d.get('isChecked'),
            d.get('revision'),
          ],
        )
        .toList(),
  );
  await Future.wait([
    a.visible(() => view(a) == expected),
    b.visible(() => view(b) == expected),
  ]);
  expect(view(a), expected);
  expect(view(b), expected);
  a.listeners();
  b.listeners();
  return docs;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'H2C2A online independent native clients',
    (tester) async {
      await fixture('setup');
      await fixture('family');
      final a = OnlineClient(), b = OnlineClient();
      await a.open('h2c2a-a', 'client-a');
      await b.open('h2c2a-b', 'client-b');
      expect(identical(a.app, b.app), isFalse);
      expect(identical(a.auth, b.auth), isFalse);
      expect(identical(a.db, b.db), isFalse);
      expect(identical(a.client, b.client), isFalse);
      expect(a.box.database.path, isNot(b.box.database.path));

      List<Command> replay = [];
      for (final order in ['concurrent', 'a-first', 'b-first']) {
        final name = 'milk $order';
        final commands = await Future.wait([
          a.add('  MILK $order ', 300, 'ml'),
          b.add(name, 2, 'l'),
        ]);
        expect(commands[0].id, isNot(commands[1].id));
        final submitted = order == 'b-first'
            ? commands.reversed.toList()
            : commands;
        final receipts = await process(
          submitted,
          ordered: order != 'concurrent',
        );
        expect(receipts.map((r) => r['status']), everyElement('APPLIED'));
        final created = receipts
            .map((r) => r['results'][0]['created'])
            .toList();
        expect(created.where((v) => v == true), hasLength(1));
        expect(created.where((v) => v == false), hasLength(1));
        if (order != 'concurrent') expect(created, [true, false]);
        final docs = await converge(a, b);
        final milk = docs.where((d) => d.get('name') == name).single;
        expect(milk.get('quantity'), 2300);
        expect(milk.get('unit'), 'ml');
        if (order == 'concurrent') replay = commands;
      }

      // Exact same terminal command IDs, actual at-least-once processor delivery.
      final before = view(a);
      final revision =
          (await a.db
                  .doc('households/test-family')
                  .get(const GetOptions(source: Source.server)))
              .get('shoppingRevision');
      await process(replay);
      await converge(a, b);
      expect(view(a), before);
      expect(
        (await a.db
                .doc('households/test-family')
                .get(const GetOptions(source: Source.server)))
            .get('shoppingRevision'),
        revision,
      );

      final three = await Future.wait([
        a.add('milk three', 300, 'ml'),
        b.add('milk three', 2, 'l'),
      ]);
      three.add(await a.add('milk three', 500, 'ml'));
      await process(three);
      var docs = await converge(a, b);
      expect(
        docs.where((d) => d.get('name') == 'milk three').single.get('quantity'),
        2800,
      );

      await process(
        await Future.wait([
          a.add('distinct milk', 2, 'l'),
          b.add('distinct flour', 500, 'g'),
        ]),
      );
      docs = await converge(a, b);
      expect(
        docs
            .where((d) => d.get('name') == 'distinct milk')
            .single
            .get('quantity'),
        2000,
      );
      expect(
        docs
            .where((d) => d.get('name') == 'distinct flour')
            .single
            .get('quantity'),
        500,
      );
      await process(
        await Future.wait([
          a.add('unit milk', 2, 'l'),
          b.add('unit milk', 1, 'db'),
        ]),
      );
      docs = await converge(a, b);
      final units = docs.where((d) => d.get('name') == 'unit milk').toList();
      expect(units, hasLength(2));
      expect(
        {for (final d in units) d.get('unit'): d.get('quantity')},
        {'ml': 2000, 'db': 1},
      );

      await process([await a.add('conflict', 1, 'db')]);
      await converge(a, b);
      for (final kind in ['EDIT', 'DELETE', 'CHECK']) {
        final observed = b.client.items.singleWhere(
          (i) => i.name == 'conflict',
        );
        expect(
          a.client.items.singleWhere((i) => i.name == 'conflict').revision,
          observed.revision,
        );
        b.measured.holdCanonical();
        await process([await a.add('conflict', 500, 'db')]);
        await a.done();
        await a.visible(
          () => a.client.items.any(
            (i) =>
                i.name == 'conflict' &&
                !i.pending &&
                i.quantity == observed.quantity + 500,
          ),
        );
        await b.measured.canonicalArrived!.future.timeout(
          const Duration(seconds: 30),
        );
        final newer = a.client.items.singleWhere((i) => i.name == 'conflict');
        expect(
          b.client.items.singleWhere((i) => i.id == observed.id).revision,
          observed.revision,
        );
        expect(newer.quantity, observed.quantity + 500);
        expect(newer.revision, greaterThan(observed.revision));
        final stale = await b.accept(
          () => switch (kind) {
            'EDIT' => b.repository.updateItem(
              id: observed.id,
              observed: observed,
              name: observed.name,
              quantity: 12,
              unit: observed.unit,
            ),
            'DELETE' => b.repository.deleteItem(
              observed.id,
              observed: observed,
            ),
            _ => b.repository.setItemChecked(
              id: observed.id,
              observed: observed,
              isChecked: true,
            ),
          },
        );
        if (kind == 'DELETE') {
          expect(b.client.items.any((i) => i.id == observed.id), isFalse);
        } else {
          final pending = b.client.items.singleWhere(
            (i) => i.id == observed.id,
          );
          expect(pending.pending, isTrue);
          if (kind == 'EDIT') expect(pending.quantity, 12);
          if (kind == 'CHECK') expect(pending.isChecked, isTrue);
        }
        final receipt = (await process([stale])).single;
        expect(receipt['status'], 'REJECTED_STALE');
        await b.done();
        b.measured.releaseCanonical();
        await converge(a, b);
        expect(
          itemFields(b.client.items.singleWhere((i) => i.id == observed.id)),
          itemFields(newer),
        );
        await b.visible(() => b.client.notice != null);
        expect(await a.box.notices(a.uid), isEmpty);
        expect(a.client.notice, isNull);
        expect(
          (await b.box.notices(b.uid)).single.request.mutationId,
          stale.id,
        );
        await b.client.acknowledgeNotice();
        await b.visible(() => b.client.notice == null);
      }

      final observedA = a.client.items.singleWhere((i) => i.name == 'conflict');
      final observedB = b.client.items.singleWhere((i) => i.name == 'conflict');
      expect(observedA.revision, observedB.revision);
      final checks = await Future.wait([
        a.accept(
          () => a.repository.setItemChecked(
            id: observedA.id,
            observed: observedA,
            isChecked: true,
          ),
        ),
        b.accept(
          () => b.repository.setItemChecked(
            id: observedB.id,
            observed: observedB,
            isChecked: true,
          ),
        ),
      ]);
      final results = await process(checks);
      expect(
        results.map((r) => r['status']),
        unorderedEquals(['APPLIED', 'REJECTED_STALE']),
      );
      await converge(a, b);
      expect(
        a.client.items.singleWhere((i) => i.name == 'conflict').isChecked,
        isTrue,
      );

      final allIds = <String>{};
      for (final c in [a, b]) {
        final rows = await c.box.entries(c.uid, includeTerminal: true);
        expect(
          await c.box.entries(c == a ? b.uid : a.uid, includeTerminal: true),
          isEmpty,
        );
        final server = await c.db
            .collection('users/${c.uid}/shoppingMutations')
            .get(const GetOptions(source: Source.server));
        expect(
          server.docs.map((d) => d.id).toSet(),
          rows.map((r) => r.request.mutationId).toSet(),
        );
        for (final r in rows) {
          expect(r.request.context.uid, c.uid);
          expect(allIds.add(r.request.mutationId), isTrue);
          expect(r.status.terminal, isTrue);
          final d = server.docs.singleWhere(
            (d) => d.id == r.request.mutationId,
          );
          expect(d.get('actorUid'), c.uid);
          expect(jsonDecode(r.resultJson!), d.get('results'));
        }
      }
      await a.close();
      await b.close();
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
