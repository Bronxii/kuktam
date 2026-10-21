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
import 'package:kuktam/shopping/data/mutations/shopping_coordinator_registry.dart';
import 'package:kuktam/shopping/data/mutations/shopping_mutation_dispatcher.dart';
import 'package:kuktam/shopping/data/mutations/shopping_mutation_transport.dart';
import 'package:kuktam/shopping/data/mutations/shopping_outbox.dart';
import 'package:kuktam/shopping/data/repositories/shopping_repository.dart';
import 'package:kuktam/shopping/domain/models/shopping_item.dart';
import 'package:kuktam/shopping/domain/shopping_mutation.dart';
import 'shopping_mutation_e2e_test.dart'
    show DeviceClient, EmulatorBackend, fixture;

const aUid = 'client-a', bUid = 'client-b';

// Instrument real subscriptions without substituting any Firestore data.
class Subscriptions {
  final active = <String, int>{};
  int maximum = 0;
  Stream<T> track<T>(String uid, Stream<T> source) {
    late StreamController<T> controller;
    StreamSubscription<T>? subscription;
    controller = StreamController<T>(
      onListen: () {
        active[uid] = (active[uid] ?? 0) + 1;
        final total = active.values.fold(0, (a, b) => a + b);
        if (total > maximum) maximum = total;
        subscription = source.listen(
          controller.add,
          onError: controller.addError,
        );
      },
      onCancel: () async {
        await subscription?.cancel();
        active[uid] = active[uid]! - 1;
      },
    );
    return controller.stream;
  }

  void only(String? uid, {required int count}) {
    expect(active.values.fold(0, (a, b) => a + b), count);
    expect(
      active.entries.where((e) => e.value != 0).map((e) => e.key),
      count == 0 ? isEmpty : [uid],
    );
    expect(maximum, lessThanOrEqualTo(1));
  }
}

class ContextGate {
  final captured = Completer<ShoppingMutationContext>();
  final release = Completer<void>();
  final returned = Completer<void>();
}

class SessionBackend extends EmulatorBackend {
  SessionBackend(
    FirebaseFirestore firestore,
    FirebaseAuth auth,
    FirebaseFunctions functions, {
    super.offlineStartup,
  }) : super(firestore, auth, functions, null);
  final canonical = Subscriptions();
  final household = Subscriptions();
  final authority = Subscriptions();
  final ensured = StreamController<void>.broadcast();
  ContextGate? nextGate;
  @override
  Stream<String> households(String uid) =>
      household.track(uid, super.households(uid));
  @override
  Stream<List<ShoppingItem>> items(String uid, String hid) =>
      canonical.track(uid, super.items(uid, hid));
  @override
  Stream<ShoppingMutationContext> contexts(String uid, String hid) =>
      authority.track(uid, super.contexts(uid, hid));
  @override
  Future<ShoppingMutationContext> ensureContext(String uid) async {
    final gate = nextGate;
    nextGate = null;
    try {
      final actual = await super.ensureContext(uid);
      if (gate != null) {
        gate.captured.complete(actual);
        await gate.release.future;
        gate.returned.complete();
      }
      return actual;
    } catch (error) {
      // Preserve the actual local store's definitive gate error classification.
      if (error.toString().contains('FEATURE_DISABLED')) {
        throw FirebaseException(
          plugin: 'cloud_functions',
          code: 'failed-precondition',
        );
      }
      rethrow;
    } finally {
      ensured.add(null);
    }
  }
}

class SessionTransport extends FirestoreShoppingMutationTransport {
  SessionTransport(super.firestore, super.currentUid);
  final receipts = Subscriptions();
  @override
  Stream<ShoppingReceiptSnapshot> observe(String uid, List<String> ids) {
    expect(ids.length, inInclusiveRange(1, 10));
    return receipts.track(uid, super.observe(uid, ids));
  }
}

// Same real Auth instance, SQLite database, registry and coordinator throughout
// transitions. The test replaces callable delivery only, with the actual local
// S1A store behind the loopback fixture; no mock mutation/context results.
class Session extends DeviceClient {
  final registry = ShoppingCoordinatorRegistry();
  late SessionBackend measured;
  late SessionTransport transport;
  StreamSubscription<User?>? authSubscription;
  final bound = StreamController<String?>.broadcast();
  int opens = 0;
  @override
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
    db = FirebaseFirestore.instanceFor(app: app)
      ..useFirestoreEmulator('10.0.2.2', 8088);
    auth = FirebaseAuth.instanceFor(app: app);
    await auth.useAuthEmulator('10.0.2.2', 9098);
    if (offline) await db.disableNetwork();
    box = await ShoppingOutbox.open(
      path: '${await getDatabasesPath()}/h2c1.db',
    );
    measured = SessionBackend(
      db,
      auth,
      FirebaseFunctions.instanceFor(app: app, region: 'europe-west1'),
      offlineStartup: offline,
    );
    backend = measured;
    transport = SessionTransport(db, () => auth.currentUser?.uid);
    client = await registry.get(auth, () async {
      opens++;
      return ShoppingCoordinator(
        outbox: box,
        dispatcher: ShoppingMutationDispatcher(
          outbox: box,
          transport: transport,
          currentUid: () => auth.currentUser?.uid,
        ),
        backend: measured,
        currentUid: () => auth.currentUser?.uid,
      );
    });
    repository = ShoppingRepository(
      firebaseAuth: auth,
      coordinator: Future.value(client),
    );
    final initial = bound.stream.first;
    authSubscription = auth
        .authStateChanges()
        .distinct((a, b) => a?.uid == b?.uid)
        .listen((user) async {
          await client.bind(user?.uid);
          bound.add(user?.uid);
        });
    await initial.timeout(const Duration(seconds: 30));
    if (auth.currentUser == null) {
      await login(uid);
    } else {
      expect(auth.currentUser!.uid, uid);
      if (!offline) await visible(() => client.context?.uid == uid);
    }
  }

  Future<void> login(String uid) async {
    final binding = bound.stream.firstWhere((v) => v == uid);
    await auth.signInWithEmailAndPassword(
      email: '$uid@example.invalid',
      password: 'local-emulator-only-123',
    );
    await binding.timeout(const Duration(seconds: 30));
    await visible(() => client.context?.uid == uid);
    await client.settled;
  }

  Future<void> logout() async {
    final binding = bound.stream.firstWhere((v) => v == null);
    await auth.signOut();
    await binding.timeout(const Duration(seconds: 30));
    expect(client.context, isNull);
    expect(client.items, isEmpty);
    expect(client.notice, isNull);
    measured.canonical.only(null, count: 0);
    measured.household.only(null, count: 0);
    transport.receipts.only(null, count: 0);
  }

  Future<void> counts(String uid) async {
    expect(
      await registry.get(auth, () => throw StateError('Duplicate opener')),
      same(client),
    );
    expect(opens, 1);
    measured.canonical.only(uid, count: 1);
    measured.household.only(uid, count: 1);
    measured.authority.only(uid, count: 1);
    final count = transport.receipts.active.values.fold(0, (a, b) => a + b);
    transport.receipts.only(uid, count: count);
    expect(count, lessThanOrEqualTo(1));
  }

  Future<String> add(String name) async {
    await repository.addOrMergeItem(name: name, quantity: 3, unit: 'db');
    return (await box.entries(
      auth.currentUser!.uid,
      includeTerminal: true,
    )).last.request.mutationId;
  }

  Future<void> terminal(String id) async {
    Future<bool> complete() async =>
        (await box.entries(auth.currentUser!.uid, includeTerminal: true))
            .singleWhere((e) => e.request.mutationId == id)
            .status
            .name
            .startsWith('rejected');
    if (await complete()) return;
    await client.changes
        .asyncMap((_) => complete())
        .firstWhere((v) => v)
        .timeout(const Duration(seconds: 45));
  }

  @override
  Future<void> close() async {
    await authSubscription?.cancel();
    await super.close();
    await bound.close();
    await measured.ensured.close();
  }
}

Future<void> release(ContextGate gate, Session s) async {
  gate.release.complete();
  await gate.returned.future;
  // Drain the returned Future and its coordinator continuation, not a time delay.
  await s.client.settled;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const phase = String.fromEnvironment('SHOPPING_E2E_PHASE');
  testWidgets(
    'H2C1 real session isolation $phase',
    (tester) async {
      final s = Session();
      final manifest = File('${await getDatabasesPath()}/h2c1-manifest.json');
      if (phase == 'death-transition') {
        await fixture('setup');
        await s.open('h2c1', aUid);
        await s.db.disableNetwork();
        final aId = await s.add('a-pending');
        final original = (await s.box.entries(aUid)).single.request.toJson();
        await s.visible(
          () => s.client.items.any((i) => i.name == 'a-pending' && i.pending),
        );
        await s.logout();
        expect((await s.box.entries(aUid)).single.request.mutationId, aId);
        await s.db.enableNetwork();
        await s.login(bUid);
        expect(s.client.items.any((i) => i.name == 'a-pending'), isFalse);
        await fixture('pause');
        final bId = await s.add('b-canonical');
        await s.visible(
          () => s.client.items.any((i) => i.name == 'b-canonical' && i.pending),
        );
        await fixture('resume');
        expect(bId, isNot(aId));
        await s.done();
        await s.visible(
          () =>
              s.client.items.any((i) => i.name == 'b-canonical' && !i.pending),
        );
        expect(await s.box.notices(bUid), isEmpty);
        await s.counts(bUid);
        expect((await s.box.entries(aUid)).single.request.toJson(), original);
        await manifest.writeAsString(
          jsonEncode({'a': original, 'b': bId}),
          flush: true,
        );
        await fixture('crash-ready');
        await Completer<void>()
            .future; // Host kills process with SQLite still open.
        return;
      }

      final saved = jsonDecode(await manifest.readAsString()) as Map;
      if (phase == 'invalid-reopen') {
        final offline = Session();
        await offline.open('h2c1', aUid, offline: true);
        await offline.measured.ensured.stream.first.timeout(
          const Duration(seconds: 30),
        );
        expect(offline.client.context, isNull);
        expect(await offline.box.readContext(aUid), isNull);
        await expectLater(offline.add('cache-resurrection'), throwsStateError);
        // UID-scoped persistent rows still survive normal sign-out and reopen.
        expect(
          (await offline.box.entries(
            bUid,
            includeTerminal: true,
          )).single.request.mutationId,
          saved['b'],
        );
        expect(
          (await offline.box.entries(
            aUid,
            includeTerminal: true,
          )).every((r) => r.request.context.uid == aUid),
          isTrue,
        );
        await offline.close();
        return;
      }
      await s.open('h2c1', bUid);
      expect(s.auth.currentUser!.uid, bUid);
      await s.visible(() => s.client.items.any((i) => i.name == 'b-canonical'));
      expect(s.client.items.any((i) => i.name == 'a-pending'), isFalse);
      expect((await s.box.entries(aUid)).single.request.toJson(), saved['a']);
      expect(await s.box.notices(bUid), isEmpty);
      await s.counts(bUid);
      await s.logout();
      await s.login(aUid);
      await s.done();
      await s.visible(
        () => s.client.items.any((i) => i.name == 'a-pending' && !i.pending),
      );
      expect(s.client.items.where((i) => i.name == 'a-pending'), hasLength(1));
      expect(
        s.client.items.singleWhere((i) => i.name == 'a-pending').quantity,
        3,
      );
      expect(s.client.items.any((i) => i.name == 'b-canonical'), isFalse);
      expect(
        (await s.box.entries(
          aUid,
          includeTerminal: true,
        )).single.request.toJson(),
        saved['a'],
      );

      // Delay an actual ensure result across A -> B, then another across A -> A.
      await s.logout();
      final oldA = ContextGate();
      s.measured.nextGate = oldA;
      await s.login(
        aUid,
      ); // Persisted verified context permits local operation.
      await oldA.captured.future;
      await s.logout();
      await s.login(bUid);
      final bContext = s.client.context!;
      await release(oldA, s);
      expect(s.client.context!.sameAs(bContext), isTrue);
      await s.logout();
      final oldSameA = ContextGate();
      s.measured.nextGate = oldSameA;
      await s.login(aUid);
      final oldSameContext = await oldSameA.captured.future;
      await fixture('pause');
      final reloginId = await s.add('same-uid-pending');
      await s.logout();
      await s.login(aUid);
      await fixture('epoch');
      await s.visible(() => s.client.context?.epoch != oldSameContext.epoch);
      final newA = s.client.context!;
      await release(oldSameA, s);
      expect(s.client.context!.sameAs(newA), isTrue);
      expect((await s.box.entries(aUid)).single.request.mutationId, reloginId);
      await fixture('resume');
      await s.done();
      expect(
        (await s.box.entries(
          aUid,
          includeTerminal: true,
        )).singleWhere((r) => r.request.mutationId == reloginId).status,
        ShoppingMutationStatus.rejectedContextChanged,
      );
      await s.counts(aUid);

      // B's delayed completion must also be fenced when A returns.
      await s.logout();
      final oldB = ContextGate();
      s.measured.nextGate = oldB;
      await s.login(bUid);
      await oldB.captured.future;
      await s.logout();
      await s.login(aUid);
      final returnedA = s.client.context!;
      await release(oldB, s);
      expect(s.client.context!.sameAs(returnedA), isTrue);
      await s.counts(aUid);

      // Hold E1 ensure result; real server stream advances E2 first.
      await s.logout();
      final oldEpoch = ContextGate();
      s.measured.nextGate = oldEpoch;
      await s.login(aUid);
      final e1 = await oldEpoch.captured.future;
      await fixture('pause');
      final staleEpochId = await s.add('old-epoch');
      await fixture('epoch');
      await s.visible(() => s.client.context?.epoch != e1.epoch);
      final e2 = s.client.context!;
      await release(oldEpoch, s);
      expect(s.client.context!.sameAs(e2), isTrue);
      final e2Id = await s.add('new-epoch');
      await fixture('resume');
      await s.done();
      final epochRows = await s.box.entries(aUid, includeTerminal: true);
      expect(
        epochRows
            .singleWhere((r) => r.request.mutationId == staleEpochId)
            .request
            .context
            .epoch,
        e1.epoch,
      );
      expect(
        epochRows
            .singleWhere((r) => r.request.mutationId == staleEpochId)
            .status,
        ShoppingMutationStatus.rejectedContextChanged,
      );
      expect(
        epochRows
            .singleWhere((r) => r.request.mutationId == e2Id)
            .request
            .context
            .epoch,
        e2.epoch,
      );
      expect(s.client.items.any((i) => i.name == 'old-epoch'), isFalse);
      await s.visible(() => s.client.notice != null);
      final notices = (await s.box.notices(
        aUid,
      )).map((e) => e.request.mutationId).toList();
      await s.logout();
      await s.login(bUid);
      expect(s.client.notice, isNull);
      expect(await s.box.notices(bUid), isEmpty);
      await s.logout();
      await s.login(aUid);
      await s.visible(() => s.client.notice != null);
      expect(
        (await s.box.notices(aUid)).map((e) => e.request.mutationId),
        notices,
      );

      // Keep H1 work immutable while actual server-owned pointers move to H2.
      await s.logout();
      final oldHousehold = ContextGate();
      s.measured.nextGate = oldHousehold;
      await s.login(aUid);
      final h1 = await oldHousehold.captured.future;
      await fixture('pause');
      final h1Id = await s.add('old-household');
      await fixture('family');
      await s.visible(() => s.client.context?.householdId == 'test-family');
      final h2 = s.client.context!;
      await release(oldHousehold, s);
      expect(s.client.context!.sameAs(h2), isTrue);
      expect(s.client.items.any((i) => i.name == 'old-household'), isFalse);
      final h2Id = await s.add('new-household');
      await fixture('resume');
      await s.done();
      final rows = await s.box.entries(aUid, includeTerminal: true);
      expect(
        rows
            .singleWhere((r) => r.request.mutationId == h1Id)
            .request
            .context
            .sameAs(h1),
        isTrue,
      );
      expect(
        rows.singleWhere((r) => r.request.mutationId == h1Id).status,
        ShoppingMutationStatus.rejectedContextChanged,
      );
      expect(
        rows
            .singleWhere((r) => r.request.mutationId == h2Id)
            .request
            .context
            .sameAs(h2),
        isTrue,
      );
      final server = await s.db
          .collection('households/test-family/shoppingItems')
          .get(const GetOptions(source: Source.server));
      expect(server.docs.map((d) => d.get('name')), ['new-household']);
      await s.counts(aUid);

      // Real gate denial clears persisted authority. Offline rebind cannot revive it.
      await fixture('gate', {'enabled': false});
      final ensured = s.measured.ensured.stream.first;
      await s.client.bind(aUid);
      await ensured;
      await s.visible(() => s.client.context == null);
      await s.client.settled;
      expect(await s.box.readContext(aUid), isNull);
      await expectLater(s.add('gate-denied'), throwsStateError);
      await s.close();
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
