import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:kuktam/shopping/data/mutations/shopping_coordinator_registry.dart';
import 'package:kuktam/shopping/domain/shopping_mutation.dart';
import 'shopping_client_fixture.dart';
import 'shopping_mutation_contract_test.dart' show testContext;

class RaceBackend extends ClientBackend {
  Future<ShoppingMutationContext> Function(String)? ensure;
  final homes = StreamController<String>.broadcast(sync: true);
  final epochs = StreamController<ShoppingMutationContext>.broadcast(
    sync: true,
  );
  @override
  Future<ShoppingMutationContext> ensureContext(String uid) =>
      ensure?.call(uid) ?? super.ensureContext(uid);
  @override
  Stream<String> households(String uid) => Stream.multi((sink) {
    sink.add('home-$uid');
    final sub = homes.stream.listen(sink.add);
    sink.onCancel = sub.cancel;
  });
  @override
  Stream<ShoppingMutationContext> contexts(String uid, String hid) =>
      epochs.stream.where((c) => c.uid == uid && c.householdId == hid);
}

void main() {
  late RaceBackend backend;
  late ClientFixture f;
  setUp(() async {
    backend = RaceBackend();
    f = ClientFixture(backend: backend);
    await f.open();
  });
  tearDown(() async {
    await f.close();
    await backend.homes.close();
    await backend.epochs.close();
  });

  testWidgets('ordinary rebuilds reuse the production session registry', (
    tester,
  ) async {
    final registry = ShoppingCoordinatorRegistry();
    final owner = Object();
    var opens = 0;
    for (var i = 0; i < 5; i++) {
      await tester.pumpWidget(
        Builder(
          builder: (_) {
            registry.get(owner, () async {
              opens++;
              return f.client;
            });
            return const SizedBox();
          },
        ),
      );
    }
    expect(opens, 1);
    expect(backend.activeListeners, 1);
    expect(backend.maxListeners, 1);
  });

  for (final code in [
    'permission-denied',
    'failed-precondition',
    'unauthenticated',
    'not-found',
    'internal',
  ]) {
    test(
      '$code invalidation survives offline reopen and raw epoch stream',
      () async {
        backend.ensure = (_) =>
            Future.error(FirebaseException(plugin: 'test', code: code));
        final invalid = f.client.changes.firstWhere(
          (_) => f.client.context == null && f.client.items.isEmpty,
        );
        await f.client.bind('A');
        await invalid;
        // Await the invalidation write through another canonical projection event.
        final cleared = f.client.changes.firstWhere(
          (_) => f.client.context == null,
        );
        await cleared;
        expect(await f.box.readContext('A'), isNull);
        backend.epochs.add(testContext('A', 'home-A'));
        await f.canonical([]);
        expect(f.client.context, isNull);
        final ensureStarted = Completer<void>();
        backend.ensure = (_) {
          ensureStarted.complete();
          return Future.error(
            FirebaseException(plugin: 'test', code: 'unavailable'),
          );
        };
        await f.restart(waitForContext: false);
        await ensureStarted.future;
        await f.canonical([]);
        backend.epochs.add(testContext('A', 'home-A'));
        await f.canonical([]);
        expect(f.client.context, isNull);
        await expectLater(
          f.repository.addOrMergeItem(name: 'x', quantity: 1, unit: 'db'),
          throwsStateError,
        );
      },
    );
  }

  test('verified offline cache remains usable', () async {
    backend.ensure = (_) =>
        Future.error(FirebaseException(plugin: 'test', code: 'unavailable'));
    await f.bind('A');
    await f.repository.addOrMergeItem(name: 'x', quantity: 1, unit: 'db');
    expect(
      (await f.box.entries('A')).single.request.context.householdId,
      'home-A',
    );
  });
  test(
    'queued canonical callback before signout cannot leak into returning session',
    () async {
      backend.publish([canonicalItem(id: 'old')]);
      await f.bind(null);
      backend.canonical = [];
      await f.bind('A');
      await f.canonical([]);
      expect(f.client.items, isEmpty);
      expect(backend.activeListeners, 1);
    },
  );

  test(
    'late ensure E1 cannot downgrade stream E2; queued E1 stays E1',
    () async {
      await f.repository.addOrMergeItem(name: 'old', quantity: 1, unit: 'db');
      final old = (await f.box.entries('A')).single.request;
      final pending = Completer<ShoppingMutationContext>();
      backend.ensure = (_) => pending.future;
      await f.bind('A');
      final e2 = ShoppingMutationContext(
        uid: 'A',
        householdId: 'home-A',
        epoch: '1999999999999-${'b' * 32}',
      );
      final advanced = f.client.changes.firstWhere(
        (_) => f.client.context?.epoch == e2.epoch,
      );
      backend.epochs.add(e2);
      await advanced;
      pending.complete(testContext('A', 'home-A'));
      await f.canonical([]);
      await f.repository.addOrMergeItem(name: 'new', quantity: 1, unit: 'db');
      final entries = await f.box.entries('A');
      expect(entries.first.request.mutationId, old.mutationId);
      expect(entries.first.request.context.epoch, old.context.epoch);
      expect(entries.last.request.context.epoch, e2.epoch);
      expect((await f.box.readContext('A'))!.epoch, e2.epoch);
    },
  );

  test(
    'A B A delayed ensures cannot resurrect old session authority',
    () async {
      await f.repository.addOrMergeItem(name: 'a', quantity: 1, unit: 'db');
      final id = (await f.box.entries('A')).single.request.mutationId;
      final oldA = Completer<ShoppingMutationContext>();
      backend.ensure = (_) => oldA.future;
      await f.bind('A');
      backend.ensure = null;
      await f.bind(null);
      await f.bind('B');
      expect(f.client.items, isEmpty);
      await f.repository.addOrMergeItem(name: 'b', quantity: 1, unit: 'db');
      final oldB = Completer<ShoppingMutationContext>();
      backend.ensure = (_) => oldB.future;
      await f.bind('B');
      backend.ensure = null;
      await f.bind('A');
      oldA.complete(testContext('A', 'obsolete-A'));
      oldB.complete(testContext('B', 'obsolete-B'));
      await f.canonical([]);
      expect(f.client.context!.householdId, 'home-A');
      expect(f.client.items.single.name, 'a');
      expect((await f.box.entries('A')).single.request.mutationId, id);
      expect(backend.activeListeners, 1);
      expect(backend.maxListeners, 1);
    },
  );

  test(
    'household switch fences delayed ensure and keeps original command context',
    () async {
      await f.repository.addOrMergeItem(name: 'old', quantity: 1, unit: 'db');
      final pending = Completer<ShoppingMutationContext>();
      backend.ensure = (_) => pending.future;
      await f.bind('A');
      backend.ensure = (_) async => testContext('A', 'second');
      final changed = f.client.changes.firstWhere(
        (_) => f.client.context?.householdId == 'second',
      );
      backend.homes.add('second');
      await changed;
      pending.complete(testContext('A', 'home-A'));
      await f.canonical([]);
      expect(f.client.items, isEmpty);
      await f.repository.addOrMergeItem(name: 'new', quantity: 1, unit: 'db');
      final entries = await f.box.entries('A');
      expect(entries.first.request.context.householdId, 'home-A');
      expect(entries.last.request.context.householdId, 'second');
      expect(backend.activeListeners, 1);
    },
  );
}
