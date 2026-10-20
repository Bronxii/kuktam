import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/shopping/data/mutations/shopping_coordinator.dart';
import 'package:kuktam/shopping/domain/models/shopping_item.dart';
import 'package:kuktam/shopping/domain/shopping_mutation.dart';
import 'shopping_client_fixture.dart';

class ProofBackend extends ClientBackend implements ShoppingAbsenceVerifier {
  int lookups = 0;
  final started = StreamController<void>.broadcast(sync: true);
  Future<Set<String>> Function(List<String>)? lookup;
  Object? ensureError;
  @override
  Future<ShoppingMutationContext> ensureContext(String uid) {
    if (ensureError != null) return Future.error(ensureError!);
    return super.ensureContext(uid);
  }

  @override
  Future<Set<String>> absentItems(String uid, String home, List<String> ids) {
    lookups++;
    started.add(null);
    return lookup?.call(ids) ?? Future.value({});
  }
}

void main() {
  late ClientFixture f;
  late ProofBackend backend;
  setUp(() async {
    backend = ProofBackend();
    f = ClientFixture(backend: backend);
    await f.open();
  });
  tearDown(() async {
    await f.close();
    await backend.started.close();
  });

  for (final created in [true, false]) {
    for (final snapshotFirst in [true, false]) {
      test(
        'ADD handoff created=$created snapshotFirst=$snapshotFirst',
        () async {
          if (!created) await f.canonical([canonicalItem()]);
          await f.repository.addOrMergeItem(
            name: 'tea',
            quantity: 2,
            unit: 'db',
          );
          final r = (await f.box.entries('A')).single.request;
          final quantity = created ? 2.0 : 7.0;
          if (snapshotFirst) {
            await f.canonical([canonicalItem(quantity: quantity, revision: 2)]);
          }
          await f.receipt(
            r,
            'APPLIED',
            itemId: 'tea',
            revision: 2,
            created: created,
          );
          if (!snapshotFirst) {
            // Receipt hands off to the current canonical snapshot, even if old.
            expect(f.client.items.map((i) => i.quantity), created ? [] : [5.0]);
          }
          expect(f.client.items.any((i) => i.pending), false);
          await f.canonical([canonicalItem(quantity: quantity, revision: 2)]);
          expect(f.client.items.single.quantity, quantity);
          await f.canonical([
            canonicalItem(quantity: quantity + 500, revision: 3),
          ]);
          expect(f.client.items.single.quantity, quantity + 500);
          await f.canonical([]);
          expect(f.client.items, isEmpty);
          await f.restart();
          expect(f.client.items, isEmpty);
          expect(backend.lookups, 0);
          expect(f.transport.sent, isEmpty);
        },
      );
    }
    test(
      'ADD deleted before any observation created=$created, unavailable lookup irrelevant',
      () async {
        backend.lookup = (_) => Future.error(StateError('must not be called'));
        await f.repository.addOrMergeItem(name: 'tea', quantity: 2, unit: 'db');
        final r = (await f.box.entries('A')).single.request;
        await f.receipt(r, 'APPLIED', created: created);
        expect(f.client.items, isEmpty);
        await f.restart();
        expect(f.client.items, isEmpty);
        expect(backend.lookups, 0);
        expect(f.transport.sent, isEmpty);
      },
    );
  }
  test(
    'persisted APPLIED before projection retirement reopens without ghost',
    () async {
      await f.repository.addOrMergeItem(name: 'tea', quantity: 2, unit: 'db');
      final r = (await f.box.entries('A')).single.request;
      await f.box.recordResult(
        'A',
        r.mutationId,
        ShoppingMutationStatus.applied,
        resultJson: jsonEncode([
          {'code': 'APPLIED', 'itemId': 'gone', 'revision': 1, 'created': true},
        ]),
      );
      await f.restart();
      expect(f.client.items, isEmpty);
      expect(f.transport.sent, isEmpty);
    },
  );
  test('genuinely unresolved ADD survives reopen with original ID', () async {
    await f.repository.addOrMergeItem(name: 'tea', quantity: 2, unit: 'db');
    final r = (await f.box.entries('A')).single.request;
    await f.restart();
    expect(f.client.items.single.quantity, 2);
    expect(f.client.items.single.pending, true);
    expect((await f.box.entries('A')).single.request.mutationId, r.mutationId);
  });
  test(
    'canonical before receipt does not double count or require absence lookup',
    () async {
      await f.repository.addOrMergeItem(name: 'tea', quantity: 2, unit: 'db');
      final r = (await f.box.entries('A')).single.request;
      await f.canonical([canonicalItem(quantity: 2, revision: 2)]);
      await f.receipt(r, 'APPLIED', itemId: 'tea', revision: 2, created: true);
      expect(f.client.items.single.quantity, 2);
      expect(backend.lookups, 0);
    },
  );
  test(
    'rename collision leaves two distinct names until authoritative merge',
    () async {
      await f.canonical([
        canonicalItem(),
        const ShoppingItem(
          id: 'bread',
          name: 'bread',
          quantity: 1,
          unit: 'db',
          isChecked: false,
        ),
      ]);
      final bread = f.client.items.singleWhere((i) => i.id == 'bread');
      await f.repository.updateItem(
        id: bread.id,
        observed: bread,
        name: 'tea',
        quantity: 3,
        unit: 'db',
      );
      expect(f.client.items.map((i) => i.name).toSet().length, 2);
      expect(f.client.items.singleWhere((i) => i.id == 'tea').quantity, 5);
      final r = (await f.box.entries('A')).single.request;
      await f.receipt(r, 'APPLIED', itemId: 'tea', revision: 2);
      await f.canonical([canonicalItem(quantity: 8, revision: 2)]);
      expect(f.client.items.single.quantity, 8);
    },
  );
  for (final code in [
    'permission-denied',
    'failed-precondition',
    'unauthenticated',
    'not-found',
  ]) {
    test('definitive ensure $code invalidates cached write authority', () async {
      backend.ensureError = FirebaseException(plugin: 'test', code: code);
      final invalid = f.client.changes.firstWhere(
        (_) => f.client.context == null,
      );
      await f.client.bind('A');
      await invalid;
      // Wait for the authority request's local invalidation, not a clock delay.
      await f.client.settled;
      await f.client.changes
          .firstWhere((_) => f.client.context == null)
          .timeout(const Duration(seconds: 3));
      expect(await f.box.readContext('A'), isNull);
      await expectLater(
        f.repository.addOrMergeItem(name: 'x', quantity: 1, unit: 'db'),
        throwsStateError,
      );
    });
  }
  test(
    'partial bulk keeps only unresolved child and aggregates conflicts',
    () async {
      await f.repository.addOrMergeItems([
        (name: 'a', quantity: 1.0, unit: 'db'),
        (name: 'b', quantity: 2.0, unit: 'db'),
        (name: 'c', quantity: 3.0, unit: 'db'),
      ]);
      final r = (await f.box.entries('A')).single.request;
      await f.box.recordResult(
        'A',
        r.mutationId,
        ShoppingMutationStatus.processing,
        resultJson: jsonEncode([
          {'code': 'REJECTED_STALE'},
          {'code': 'APPLIED', 'itemId': 'b', 'revision': 1},
        ]),
      );
      await f.canonical([
        const ShoppingItem(
          id: 'b',
          name: 'b',
          quantity: 2,
          unit: 'db',
          isChecked: false,
          revision: 1,
        ),
      ]);
      expect(f.client.items.map((i) => i.name), ['b', 'c']);
      expect(f.client.items.singleWhere((i) => i.name == 'c').pending, true);
    },
  );

  test(
    'positive existence lookup then delete without query observation cannot retain ADD',
    () async {
      // Reproduce the old positive-lookup result; ADD completion no longer uses it.
      backend.lookup = (_) => Future.value({});
      expect(await backend.absentItems('A', 'home-A', ['server-id']), isEmpty);
      await f.repository.addOrMergeItem(name: 'tea', quantity: 2, unit: 'db');
      final r = (await f.box.entries('A')).single.request;
      await f.receipt(r, 'APPLIED', created: true);
      for (var i = 0; i < 3; i++) {
        await f.canonical([]);
      }
      expect(
        backend.lookups,
        1,
      ); // Only the explicit old-protocol fixture read.
      expect(f.client.items, isEmpty);
      expect(await f.box.entries('A'), isEmpty);
      expect(f.transport.sent, isEmpty);
    },
  );
}
