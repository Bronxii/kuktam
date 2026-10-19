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
import 'package:kuktam/shopping/data/mutations/production_shopping_coordinator.dart';
import 'package:kuktam/shopping/data/mutations/shopping_coordinator.dart';
import 'package:kuktam/shopping/data/mutations/shopping_mutation_dispatcher.dart';
import 'package:kuktam/shopping/data/mutations/shopping_mutation_transport.dart';
import 'package:kuktam/shopping/data/mutations/shopping_outbox.dart';
import 'package:kuktam/shopping/data/repositories/shopping_repository.dart';
import 'package:kuktam/shopping/domain/shopping_mutation.dart';

Future<Map<String, dynamic>> fixture(
  String route, [
  Map<String, Object?> body = const {},
]) async {
  final http = HttpClient();
  try {
    final request = await http.postUrl(
      Uri.parse('http://10.0.2.2:8099/$route'),
    );
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    if (response.statusCode != 200) {
      throw StateError('Local fixture failed: $text');
    }
    return Map<String, dynamic>.from(jsonDecode(text) as Map);
  } finally {
    http.close();
  }
}

class EmulatorBackend extends FirestoreShoppingCoordinatorBackend {
  EmulatorBackend(
    super.firestore,
    super.auth,
    super.functions,
    this.cachedHousehold,
  );
  final String? cachedHousehold;
  @override
  Stream<String> households(String uid) async* {
    if (cachedHousehold != null) yield cachedHousehold!;
    yield* firestore
        .doc('users/$uid')
        .snapshots()
        .where((d) => d.data()?['activeHouseholdId'] is String)
        .map((d) => d.data()!['activeHouseholdId'] as String);
  }

  @override
  Future<ShoppingMutationContext> ensureContext(String uid) async {
    final data = await fixture('context', {'uid': uid});
    return ShoppingMutationContext(
      uid: uid,
      householdId: data['householdId'] as String,
      epoch: data['epoch'] as String,
    );
  }
}

class DeviceClient {
  late FirebaseApp app;
  late FirebaseFirestore db;
  late FirebaseAuth auth;
  late ShoppingOutbox box;
  late ShoppingCoordinator client;
  late ShoppingRepository repository;
  Future<void> open(String name, String uid, {bool offline = false}) async {
    app = await Firebase.initializeApp(
      name: name,
      options: const FirebaseOptions(
        apiKey: 'local-emulator-only',
        appId: '1:123456789:android:abc123',
        messagingSenderId: '123456789',
        projectId: 'demo-kuktam-local',
      ),
    );
    db = FirebaseFirestore.instanceFor(app: app);
    db.useFirestoreEmulator('10.0.2.2', 8088);
    auth = FirebaseAuth.instanceFor(app: app);
    await auth.useAuthEmulator('10.0.2.2', 9098);
    if (offline) await db.disableNetwork();
    if (!offline) {
      await auth.signInWithEmailAndPassword(
        email: '$uid@example.invalid',
        password: 'local-emulator-only-123',
      );
    }
    expect(auth.currentUser?.uid, uid);
    box = await ShoppingOutbox.open(
      path: '${await getDatabasesPath()}/s1b-e2e-$name.db',
    );
    if (offline) {
      expect(
        await box.readContext(uid),
        isNotNull,
        reason: 'Restart must retain the verified SQLite context',
      );
      expect(
        await box.entries(uid),
        isNotEmpty,
        reason: 'Restart must retain accepted offline intents',
      );
    }
    final dispatcher = ShoppingMutationDispatcher(
      outbox: box,
      transport: FirestoreShoppingMutationTransport(
        db,
        () => auth.currentUser?.uid,
      ),
      currentUid: () => auth.currentUser?.uid,
    );
    client = ShoppingCoordinator(
      outbox: box,
      dispatcher: dispatcher,
      backend: EmulatorBackend(
        db,
        auth,
        FirebaseFunctions.instanceFor(app: app, region: 'europe-west1'),
        (await box.readContext(uid))?.householdId,
      ),
      currentUid: () => auth.currentUser?.uid,
    );
    repository = ShoppingRepository(
      firebaseAuth: auth,
      coordinator: Future.value(client),
    );
    final ready = client.changes
        .firstWhere((_) => client.context != null)
        .timeout(const Duration(seconds: 30));
    await client.bind(uid);
    await ready;
    await client.settled;
  }

  Future<void> visible(bool Function() condition) async {
    if (condition()) return;
    await client.changes
        .firstWhere((_) => condition())
        .timeout(const Duration(seconds: 45));
  }

  Future<void> done() async {
    Future<bool> complete() async =>
        (await box.entries(auth.currentUser!.uid)).isEmpty &&
        (await box.database.query(
          'shoppingIntents',
          where: 'uid=? AND materialized=0',
          whereArgs: [auth.currentUser!.uid],
        )).isEmpty;
    if (await complete()) return;
    await client.changes
        .asyncMap((_) => complete())
        .firstWhere((v) => v)
        .timeout(const Duration(seconds: 90));
  }

  Future<void> close() async {
    await client.close();
    await box.close();
    await db.terminate();
    await app.delete();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const phase = String.fromEnvironment(
    'SHOPPING_E2E_PHASE',
    defaultValue: 'main',
  );
  testWidgets(
    'native FlutterFire SQLite S1A end-to-end $phase',
    (tester) async {
      final a = DeviceClient();
      if (phase == 'restart') {
        await a.open('primary', 'client-a', offline: true);
        final pending = await a.box.entries('client-a');
        expect(pending, isNotEmpty);
        final manifest = File('${await getDatabasesPath()}/s1b-restart.json');
        final ids = (jsonDecode(await manifest.readAsString()) as List)
            .cast<String>();
        expect(pending.map((e) => e.request.mutationId).toList(), ids);
        await a.visible(
          () => a.client.items.any(
            (i) => i.name == 'restart-offline' && i.pending,
          ),
        );
        await a.db.enableNetwork();
        await a.done();
        await a.visible(
          () => a.client.items.any(
            (i) => i.name == 'restart-offline' && !i.pending,
          ),
        );
        expect(
          a.client.items.where((i) => i.name == 'restart-offline'),
          hasLength(1),
        );
        await a.close();
        return;
      }
      await fixture('setup');
      await a.open('primary', 'client-a');
      await a.repository.addOrMergeItem(name: 'tea', quantity: 5, unit: 'db');
      await a.done();
      await a.visible(
        () => a.client.items.any((i) => i.name == 'tea' && !i.pending),
      );
      var item = a.client.items.singleWhere((i) => i.name == 'tea');
      expect(item.quantity, 5);
      await a.repository.updateItem(
        id: item.id,
        observed: item,
        name: 'tea',
        quantity: 7,
        unit: 'db',
      );
      await a.done();
      await a.visible(
        () => a.client.items.any(
          (i) => i.name == 'tea' && i.quantity == 7 && !i.pending,
        ),
      );
      item = a.client.items.singleWhere((i) => i.name == 'tea');
      await a.repository.setItemChecked(
        id: item.id,
        observed: item,
        isChecked: true,
      );
      await a.done();
      await a.visible(
        () => a.client.items.any(
          (i) => i.name == 'tea' && i.isChecked && !i.pending,
        ),
      );
      item = a.client.items.singleWhere((i) => i.name == 'tea');
      await a.repository.deleteItem(item.id, observed: item);
      await a.done();
      await a.visible(() => a.client.items.isEmpty);
      await a.repository.addOrMergeItems(
        List.generate(10, (i) => (name: 'bulk$i', quantity: 1.25, unit: 'l')),
      );
      await a.done();
      await a.visible(
        () =>
            a.client.items.length == 10 &&
            a.client.items.every((i) => !i.pending),
      );
      expect(a.client.items.every((i) => i.quantity == 1250), true);
      await a.repository.clearShoppingList(observed: List.of(a.client.items));
      await a.done();
      await a.visible(() => a.client.items.isEmpty);
      // Offline request rejected by rules after epoch advancement; context proof
      // maps its local durable result without manufacturing a server receipt.
      await a.db.disableNetwork();
      await a.repository.addOrMergeItem(
        name: 'old-epoch',
        quantity: 2,
        unit: 'db',
      );
      final old = (await a.box.entries('client-a')).single.request.mutationId;
      await fixture('epoch');
      await a.db.enableNetwork();
      await a.done();
      final oldRow = await a.box.database.query(
        'mutations',
        where: 'uid=? AND id=?',
        whereArgs: ['client-a', old],
      );
      expect(oldRow.single['status'], 'REJECTED_CONTEXT_CHANGED');
      expect(a.client.items.where((i) => i.name == 'old-epoch'), isEmpty);
      // Revision-bound EDIT/DELETE must preserve the newer server +500.
      for (final kind in ['edit', 'delete']) {
        await a.repository.addOrMergeItem(
          name: 'loss-$kind',
          quantity: 1,
          unit: 'db',
        );
        await a.done();
        await a.visible(
          () => a.client.items.any((i) => i.name == 'loss-$kind' && !i.pending),
        );
        item = a.client.items.singleWhere((i) => i.name == 'loss-$kind');
        await fixture('pause');
        if (kind == 'edit') {
          await a.repository.updateItem(
            id: item.id,
            observed: item,
            name: item.name,
            quantity: 2,
            unit: 'db',
          );
        } else {
          await a.repository.deleteItem(item.id, observed: item);
        }
        final stale = (await a.box.entries(
          'client-a',
        )).single.request.mutationId;
        await fixture('add', {'name': item.name, 'quantity': 500});
        await fixture('resume');
        await a.done();
        final row = await a.box.database.query(
          'mutations',
          where: 'uid=? AND id=?',
          whereArgs: ['client-a', stale],
        );
        expect(row.single['status'], 'REJECTED_STALE');
        await a.visible(
          () => a.client.items.any(
            (i) => i.name == 'loss-$kind' && i.quantity == 501 && !i.pending,
          ),
        );
      }
      final second = DeviceClient();
      await second.open('second', 'client-a');
      await Future.wait([
        a.repository.addOrMergeItem(
          name: 'concurrent',
          quantity: 2,
          unit: 'db',
        ),
        second.repository.addOrMergeItem(
          name: 'concurrent',
          quantity: 3,
          unit: 'db',
        ),
      ]);
      await Future.wait([a.done(), second.done()]);
      await a.visible(
        () => a.client.items.any(
          (i) => i.name == 'concurrent' && i.quantity == 5 && !i.pending,
        ),
      );
      expect(a.client.items.where((i) => i.name == 'concurrent'), hasLength(1));
      final b = DeviceClient();
      await b.open('other', 'client-b');
      expect(b.client.items, isEmpty);
      await fixture('family');
      await a.visible(() => a.client.context?.householdId == 'test-family');
      await b.visible(() => b.client.context?.householdId == 'test-family');
      await Future.wait([
        a.repository.addOrMergeItem(name: 'family', quantity: 2, unit: 'db'),
        b.repository.addOrMergeItem(name: 'family', quantity: 3, unit: 'db'),
      ]);
      await Future.wait([a.done(), b.done()]);
      await a.visible(
        () => a.client.items.any(
          (i) => i.name == 'family' && i.quantity == 5 && !i.pending,
        ),
      );
      expect(a.client.items.where((i) => i.name == 'family'), hasLength(1));
      await second.close();
      await b.close();
      await a.db.disableNetwork();
      await a.repository.addOrMergeItem(
        name: 'restart-offline',
        quantity: 4,
        unit: 'db',
      );
      final ids = (await a.box.entries(
        'client-a',
      )).map((e) => e.request.mutationId).toList();
      await File(
        '${await getDatabasesPath()}/s1b-restart.json',
      ).writeAsString(jsonEncode(ids), flush: true);
      // The harness ends this native test process and launches a second test APK
      // session. No local database deletion or generated replacement IDs.
      await a.close();
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
