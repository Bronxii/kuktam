// Local-only two-client process death. Both clients share the killed OS process,
// never a FirebaseApp, Auth instance, SQLite store or mutation coordinator.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
import 'package:kuktam/shopping/domain/shopping_mutation.dart';
import 'shopping_mutation_e2e_test.dart' show fixture;
import 'shopping_h2c1_e2e_test.dart' show SessionTransport;
import 'shopping_h2c2a_e2e_test.dart'
    show OnlineBackend, Command, process, converge;
import 'shopping_h2c2b1_e2e_test.dart'
    show ReconnectClient, arrived, item, row, seed, offlineBoth, connect;

class RestartBackend extends OnlineBackend {
  RestartBackend(super.firestore, super.auth, super.functions);
  @override
  Future<ShoppingMutationContext> ensureContext(String uid) async =>
      throw FirebaseException(plugin: 'cloud_functions', code: 'unavailable');
}

class RestartClient extends ReconnectClient {
  @override
  Future<void> open(String name, String uid, {bool offline = false}) async {
    if (!offline) return super.open(name, uid);
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
    await db.disableNetwork();
    auth = FirebaseAuth.instanceFor(app: app);
    await auth.useAuthEmulator('10.0.2.2', 9098);
    expect(
      auth.currentUser?.uid,
      uid,
    ); // Persisted native Auth, no new sign-in.
    box = await ShoppingOutbox.open(
      path: '${await getDatabasesPath()}/$name.db',
    );
    expect(await box.readContext(uid), isNotNull);
    measured = RestartBackend(
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
}

Future<File> manifest() async =>
    File('${await getDatabasesPath()}/h2c2b2.json');

Future<void> die(
  RestartClient a,
  RestartClient b,
  Map<String, dynamic> state,
) async {
  await a.unchanged();
  await b.unchanged();
  state['a'] = a.originals;
  state['b'] = b.originals;
  await (await manifest()).writeAsString(jsonEncode(state), flush: true);
  a.listeners();
  b.listeners();
  // No close/dispose: host verifies PID disappearance after am force-stop.
  await fixture('crash-ready');
  await Completer<void>().future;
}

Future<void> restored(
  RestartClient a,
  RestartClient b,
  Map<String, dynamic> state,
) async {
  for (final entry in [(a, 'a'), (b, 'b')]) {
    final c = entry.$1;
    for (final e in (state[entry.$2] as Map<String, dynamic>).entries) {
      c.originals[e.key] = Map<String, Object?>.from(e.value as Map);
    }
    await c
        .unchanged(); // Full payload includes original UID, household, epoch, ID.
    expect(
      await c.box.entries(c == a ? b.uid : a.uid, includeTerminal: true),
      isEmpty,
    );
    c.listeners();
  }
  expect(identical(a.app, b.app), isFalse);
  expect(identical(a.auth, b.auth), isFalse);
  expect(identical(a.db, b.db), isFalse);
  expect(identical(a.client, b.client), isFalse);
  expect(a.box.database.path, isNot(b.box.database.path));
}

Future<void> pendingMilk(RestartClient a, RestartClient b, String name) async {
  await a.visible(
    () => a.client.items.any(
      (i) => i.name == name && i.pending && i.quantity == 1300,
    ),
  );
  await b.visible(
    () => b.client.items.any(
      (i) => i.name == name && i.pending && i.quantity == 3000,
    ),
  );
  expect(item(a, name).quantity, 1300);
  expect(item(b, name).quantity, 3000);
}

Future<void> total(RestartClient a, RestartClient b, String name) async {
  final docs = await converge(a, b);
  final milk = docs.where((d) => d.get('name') == name).single;
  expect(milk.get('quantity'), 3300);
  expect(milk.get('unit'), 'ml');
  await a.unchanged();
  await b.unchanged();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const phase = String.fromEnvironment('SHOPPING_E2E_PHASE');
  testWidgets('H2C2B2 $phase', (tester) async {
    final a = RestartClient(), b = RestartClient();
    if (phase == 'death-offline') {
      await fixture('setup');
      await fixture('family');
      await a.open('h2c2b2-a', 'client-a');
      await b.open('h2c2b2-b', 'client-b');
      await seed(a, b, 'death milk', 1000, 'ml');
      for (final kind in ['edit', 'delete', 'check']) {
        await seed(a, b, kind, 10, 'db');
      }
      await offlineBoth(a, b);
      final ac = await a.add('death milk', 300, 'ml');
      final bc = await b.add('death milk', 2, 'l');
      final conflicts = <Map<String, String>>[];
      for (final kind in ['edit', 'delete', 'check']) {
        final ai = item(a, kind), bi = item(b, kind);
        expect(ai.revision, bi.revision);
        final win = await a.accept(
          () => a.repository.updateItem(
            id: ai.id,
            observed: ai,
            name: ai.name,
            quantity: 510,
            unit: ai.unit,
          ),
        );
        final lose = await b.accept(
          () => switch (kind) {
            'edit' => b.repository.updateItem(
              id: bi.id,
              observed: bi,
              name: bi.name,
              quantity: 12,
              unit: bi.unit,
            ),
            'delete' => b.repository.deleteItem(bi.id, observed: bi),
            _ => b.repository.setItemChecked(
              id: bi.id,
              observed: bi,
              isChecked: true,
            ),
          },
        );
        conflicts.add({'kind': kind, 'a': win.id, 'b': lose.id});
      }
      await pendingMilk(a, b, 'death milk');
      expect(await a.box.entries(a.uid), hasLength(4));
      expect(await b.box.entries(b.uid), hasLength(4));
      await die(a, b, {'milkA': ac.id, 'milkB': bc.id, 'conflicts': conflicts});
      return;
    }

    final state =
        jsonDecode(await (await manifest()).readAsString())
            as Map<String, dynamic>;
    await a.open('h2c2b2-a', 'client-a', offline: true);
    await b.open('h2c2b2-b', 'client-b', offline: true);
    await restored(a, b, state);

    if (phase == 'death-uncertain') {
      await pendingMilk(a, b, 'death milk');
      expect(await a.box.entries(a.uid), hasLength(4));
      expect(await b.box.entries(b.uid), hasLength(4));
      await a.visible(
        () => a.client.items.any((i) => i.name == 'edit' && i.quantity == 510),
      );
      await b.visible(
        () => b.client.items.any((i) => i.name == 'edit' && i.quantity == 12),
      );
      expect(b.client.items.any((i) => i.name == 'delete'), isFalse);
      expect(item(b, 'check').isChecked, isTrue);
      final am = Command(a, state['milkA']), bm = Command(b, state['milkB']);
      await connect(am);
      expect((await process([am])).single['status'], 'APPLIED');
      // All A commands arrived via the real dispatcher; no manual refresh.
      for (final conflict in state['conflicts'] as List) {
        final win = Command(a, conflict['a']);
        await arrived(win);
        expect((await process([win])).single['status'], 'APPLIED');
      }
      await a.done();
      await connect(bm);
      expect((await process([bm])).single['status'], 'APPLIED');
      for (final conflict in state['conflicts'] as List) {
        final lose = Command(b, conflict['b']);
        await arrived(lose);
        expect((await process([lose])).single['status'], 'REJECTED_STALE');
      }
      await total(a, b, 'death milk');
      for (final kind in ['edit', 'delete', 'check']) {
        expect(item(a, kind).quantity, 510);
        expect(item(b, kind).quantity, 510);
        expect(item(b, kind).pending, isFalse);
        expect(item(b, kind).isChecked, isFalse);
      }
      expect(await a.box.notices(a.uid), isEmpty);
      expect(
        (await b.box.notices(b.uid)).map((r) => r.request.mutationId).toSet(),
        (state['conflicts'] as List).map((c) => c['b']).toSet(),
      );

      await seed(a, b, 'uncertain milk', 1000, 'ml');
      await offlineBoth(a, b);
      final ac = await a.add('uncertain milk', 300, 'ml');
      final bc = await b.add('uncertain milk', 2, 'l');
      await connect(ac); // Authoritative command-exists barrier.
      await a.db.disableNetwork();
      final receipt = (await process([ac])).single;
      expect(receipt['status'], 'APPLIED');
      await a.client.settled;
      expect((await row(ac)).status.terminal, isFalse);
      expect((await row(bc)).status.terminal, isFalse);
      await pendingMilk(a, b, 'uncertain milk');
      state['uncertainA'] = ac.id;
      state['uncertainB'] = bc.id;
      state['receipt'] = receipt;
      await die(a, b, state);
      return;
    }

    expect(phase, 'complete');
    await pendingMilk(a, b, 'uncertain milk');
    final ac = Command(a, state['uncertainA']),
        bc = Command(b, state['uncertainB']);
    expect((await row(ac)).status.terminal, isFalse);
    expect((await row(bc)).status.terminal, isFalse);
    expect(await a.box.entries(a.uid), hasLength(1));
    expect(await b.box.entries(b.uid), hasLength(1));
    // A already APPLIED server-side: no process/replay call for A after restart.
    await a.db.enableNetwork();
    await a.done();
    expect(
      jsonDecode((await row(ac)).resultJson!),
      state['receipt']['results'],
    );
    await connect(bc);
    expect((await process([bc])).single['status'], 'APPLIED');
    await total(a, b, 'uncertain milk');
    await total(a, b, 'death milk');
    expect(await a.box.notices(a.uid), isEmpty);
    expect(await b.box.notices(b.uid), hasLength(3));
    final all = <String>{};
    for (final c in [a, b]) {
      final server = await c.db
          .collection('users/${c.uid}/shoppingMutations')
          .get(const GetOptions(source: Source.server));
      expect(server.docs.map((d) => d.id).toSet(), c.originals.keys.toSet());
      for (final local in await c.box.entries(c.uid, includeTerminal: true)) {
        expect(all.add(local.request.mutationId), isTrue);
        expect(local.status.terminal, isTrue);
        final receipt = server.docs.singleWhere(
          (d) => d.id == local.request.mutationId,
        );
        expect(receipt.get('actorUid'), c.uid);
        expect(jsonDecode(local.resultJson!), receipt.get('results'));
      }
      c.listeners();
    }
    expect(all, hasLength(15));
    await a.close();
    await b.close();
  }, timeout: const Timeout(Duration(minutes: 6)));
}
