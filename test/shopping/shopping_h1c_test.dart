import 'dart:convert';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/shopping/data/mutations/shopping_intent_queue.dart';
import 'package:kuktam/shopping/domain/shopping_mutation.dart';
import 'shopping_client_fixture.dart';

void main() {
  late ClientFixture f;
  setUp(() async {
    f = ClientFixture();
    await f.open();
  });
  tearDown(() async {
    await f.close();
  });

  for (final failure in [
    'REJECTED_STALE',
    'REJECTED_CONTEXT_CHANGED',
    'REJECTED_NOT_FOUND',
    'FAILED_TERMINAL',
  ]) {
    test('chain $failure resolves held children with durable notice', () async {
      await f.repository.addOrMergeItem(name: 'tea', quantity: 1, unit: 'db');
      var item = f.client.items.single;
      await f.repository.updateItem(
        id: item.id,
        observed: item,
        name: 'tea',
        quantity: 2,
        unit: 'db',
      );
      item = f.client.items.single;
      await f.repository.setItemChecked(
        id: item.id,
        observed: item,
        isChecked: true,
      );
      final a = (await f.box.entries('A')).single.request;
      await f.receipt(a, failure);
      expect(await f.box.entries('A'), isEmpty);
      expect(
        await f.box.database.query('shoppingIntents', where: 'materialized=0'),
        isEmpty,
      );
      expect(await f.box.notices('A'), isNotEmpty);
      await f.restart();
      expect(f.client.items, isEmpty);
    });
  }

  test(
    'partial bulk retires applied and failed children without hiding pending siblings',
    () async {
      await f.repository.addOrMergeItems(
        List.generate(6, (i) => (name: 'item$i', quantity: 1.0, unit: 'db')),
      );
      final r = (await f.box.entries('A')).single.request;
      await f.box.recordResult(
        'A',
        r.mutationId,
        ShoppingMutationStatus.processing,
        resultJson: jsonEncode([
          {'code': 'APPLIED', 'itemId': 'gone', 'revision': 1, 'created': true},
          {'code': 'REJECTED_STALE'},
          {'code': 'REJECTED_CONTEXT_CHANGED'},
          {'code': 'REJECTED_NOT_FOUND'},
          {'code': 'FAILED_TERMINAL'},
        ]),
      );
      await f.canonical([]);
      expect(f.client.items.map((i) => i.name), ['item5']);
      expect(await f.box.entries('A'), hasLength(1));
      await f.restart();
      expect(f.client.items.map((i) => i.name), ['item5']);
    },
  );

  test(
    'clear 250 partial page receipt survives reopen without claiming all complete',
    () async {
      await f.canonical([
        for (var i = 0; i < 250; i++) canonicalItem(id: 'row$i'),
      ]);
      await f.repository.clearShoppingList(observed: f.client.items);
      final pages = await f.box.entries('A');
      await f.box.recordResult(
        'A',
        pages.first.request.mutationId,
        ShoppingMutationStatus.applied,
        resultJson: jsonEncode([
          for (final c in pages.first.request.children)
            {'code': 'APPLIED', 'itemId': c.itemId},
        ]),
      );
      await f.canonical([
        for (var i = 200; i < 250; i++) canonicalItem(id: 'row$i'),
      ]);
      expect(f.client.items, isEmpty);
      expect(
        (await f.box.entries('A')).single.request.mutationId,
        pages.last.request.mutationId,
      );
      await f.restart();
      expect((await f.box.entries('A')).single.request.children, hasLength(50));
      expect(f.client.items, isEmpty);
    },
  );

  test(
    'new pending ADD merged by server never retargets held delete',
    () async {
      await f.repository.addOrMergeItem(name: 'tea', quantity: 2, unit: 'db');
      final row = f.client.items.single;
      await f.repository.deleteItem(row.id, observed: row);
      final add = (await f.box.entries('A')).single.request;
      await f.canonical([canonicalItem(quantity: 7, revision: 2)]);
      await f.receipt(
        add,
        'APPLIED',
        itemId: 'tea',
        revision: 2,
        created: false,
      );
      expect(f.client.items.single.quantity, 7);
      expect(f.client.items.single.pending, false);
      expect(await f.box.entries('A'), isEmpty);
      expect(await f.box.notices('A'), isNotEmpty);
    },
  );

  for (final version in [1, 2, 3, 4, 5]) {
    test(
      'v$version upgrade preserves accepted IDs, bindings and terminal notice',
      () async {
        await f.repository.addOrMergeItem(
          name: 'pending',
          quantity: 2,
          unit: 'db',
        );
        await f.repository.addOrMergeItem(
          name: 'terminal',
          quantity: 1,
          unit: 'db',
        );
        final before = await f.box.entries('A');
        await f.receipt(before.last.request, 'REJECTED_STALE');
        await f.client.close();
        final db = f.box.database;
        await db.execute('DROP TRIGGER projection_result');
        await db.execute('DROP TRIGGER projection_insert');
        await db.execute('DROP INDEX pending_notices');
        await db.execute('DROP TABLE deletedShoppingUids');
        await db.execute('DROP INDEX projection_work');
        await db.execute(
          'ALTER TABLE shoppingIntents DROP COLUMN projectionState',
        );
        if (version < 3) {
          await db.execute('DROP TABLE shoppingObservations');
        } else if (version == 3) {
          await db.execute(
            'ALTER TABLE shoppingObservations DROP COLUMN absenceProof',
          );
        }
        if (version == 1) {
          await db.execute('DROP TABLE shoppingIntents');
        }
        // Real older foundation work can lack an intent even when table exists.
        else {
          await db.delete(
            'shoppingIntents',
            where: 'id=?',
            whereArgs: [before.first.request.mutationId],
          );
        }
        await db.setVersion(version);
        await f.box.close();
        // restart() normally closes the coordinator; reopen directly instead.
        await f.reopenDatabase();
        final after = await f.box.entries('A');
        expect(after.single.request.toJson(), before.first.request.toJson());
        expect(f.client.items.map((i) => i.name), ['pending']);
        expect(await f.box.notices('A'), hasLength(1));
        await f.restart();
        expect(
          (await f.box.entries('A')).single.request.mutationId,
          before.first.request.mutationId,
        );
      },
    );
  }

  test(
    '250 historical receipts cannot hide active and held work; indexed plan',
    () async {
      for (var i = 0; i < 250; i++) {
        final r = ShoppingMutationRequest.create(
          context: f.client.requireContext(),
          children: [
            ShoppingMutationChild.add(
              name: 'history$i',
              quantity: 1,
              unit: 'db',
            ),
          ],
        );
        await f.box.enqueue(r);
        await f.box.recordResult(
          'A',
          r.mutationId,
          ShoppingMutationStatus.applied,
          resultJson: jsonEncode([
            {
              'code': 'APPLIED',
              'itemId': 'gone',
              'revision': 1,
              'created': true,
            },
          ]),
        );
      }
      await f.repository.addOrMergeItem(name: 'new', quantity: 1, unit: 'db');
      final item = f.client.items.singleWhere((i) => i.name == 'new');
      await f.repository.updateItem(
        id: item.id,
        observed: item,
        name: 'new',
        quantity: 4,
        unit: 'db',
      );
      final rows = await f.box.projectionRows('A');
      expect(rows.length, lessThanOrEqualTo(200));
      expect(
        rows.where((r) => r['status'] == null || r['status'] == 'PENDING'),
        hasLength(2),
      );
      expect(f.client.items.single.quantity, 4);
      final plan = await f.box.database.rawQuery(
        'EXPLAIN QUERY PLAN SELECT * FROM shoppingIntents WHERE uid=? AND projectionState=0 ORDER BY sequence LIMIT 100',
        ['A'],
      );
      expect(plan.toString(), contains('projection_work'));
    },
  );

  test(
    'local deletion isolates B and blocks stale enqueue/context after reopen',
    () async {
      await f.repository.addOrMergeItem(name: 'a', quantity: 1, unit: 'db');
      final old = (await f.box.entries('A')).single.request;
      await f.bind('B');
      await f.repository.addOrMergeItem(name: 'b', quantity: 2, unit: 'db');
      final b = (await f.box.entries('B')).single.request;
      await f.client.deleteLocalAccount('A');
      expect((await f.box.entries('B')).single.request.toJson(), b.toJson());
      expect(f.client.items.single.name, 'b');
      await expectLater(f.box.enqueue(old), throwsStateError);
      await expectLater(
        ShoppingIntentQueue(f.box).enqueue(old),
        throwsStateError,
      );
      await expectLater(f.box.saveContext(old.context), throwsStateError);
      await expectLater(
        f.box.recordResult('A', old.mutationId, ShoppingMutationStatus.applied),
        throwsStateError,
      );
      await f.restart(waitForContext: false);
      expect(await f.box.isDeletedUid('A'), true);
      expect(await f.box.projectionRows('A'), isEmpty);
      expect(await f.box.notices('A'), isEmpty);
      expect(
        (await f.box.entries('B')).single.request.mutationId,
        b.mutationId,
      );
    },
  );

  for (final reverse in [false, true]) {
    test(
      'multiple ADD receipts reverse=$reverse reconcile independently',
      () async {
        await f.canonical([canonicalItem()]);
        await f.repository.addOrMergeItem(name: 'tea', quantity: 2, unit: 'db');
        await f.repository.addOrMergeItem(name: 'tea', quantity: 3, unit: 'db');
        expect(f.client.items.single.quantity, 10);
        final pending = await f.box.entries('A');
        final first = pending[reverse ? 1 : 0].request,
            second = pending[reverse ? 0 : 1].request;
        await f.receipt(
          first,
          'APPLIED',
          itemId: 'tea',
          revision: 2,
          created: false,
        );
        expect(f.client.items.single.quantity, reverse ? 7 : 8);
        await f.canonical([
          canonicalItem(quantity: reverse ? 8 : 7, revision: 2),
        ]);
        expect(f.client.items.single.quantity, reverse ? 8 : 7);
        await f.receipt(
          second,
          'APPLIED',
          itemId: 'tea',
          revision: 3,
          created: false,
        );
        await f.canonical([canonicalItem(quantity: 10, revision: 3)]);
        expect(f.client.items.single.quantity, 10);
        expect(f.client.items.single.pending, false);
      },
    );
  }

  for (final end in ['check', 'delete']) {
    test(
      'offline ADD EDIT $end chain survives reopen and uses actual receipts',
      () async {
        await f.repository.addOrMergeItem(name: 'tea', quantity: 2, unit: 'db');
        var item = f.client.items.single;
        await f.repository.updateItem(
          id: item.id,
          observed: item,
          name: 'tea',
          quantity: 3,
          unit: 'db',
        );
        item = f.client.items.single;
        if (end == 'check') {
          await f.repository.setItemChecked(
            id: item.id,
            observed: item,
            isChecked: true,
          );
        } else {
          await f.repository.deleteItem(item.id, observed: item);
        }
        final a = (await f.box.entries('A')).single.request;
        await f.restart();
        await f.receipt(
          a,
          'APPLIED',
          itemId: 'actual',
          revision: 7,
          created: true,
        );
        final b = (await f.box.entries('A')).single.request;
        expect(b.children.single.itemId, 'actual');
        expect(b.children.single.expectedRevision, 7);
        await f.receipt(b, 'APPLIED', itemId: 'actual', revision: 8);
        final c = (await f.box.entries('A')).single.request;
        expect(c.children.single.itemId, 'actual');
        expect(c.children.single.expectedRevision, 8);
        await f.receipt(c, 'REJECTED_NOT_FOUND');
        expect(await f.box.entries('A'), isEmpty);
        expect(await f.box.notices('A'), isNotEmpty);
      },
    );
  }
}
