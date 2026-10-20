import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/shopping/domain/models/shopping_item.dart';
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
  test(
    'clear over 200 observations commits bounded requests atomically and survives restart',
    () async {
      await f.canonical([
        for (var i = 0; i < 250; i++) canonicalItem(id: 'row-$i'),
      ]);
      await f.repository.clearShoppingList(observed: f.client.items);
      final queued = await f.box.entries('A');
      expect(queued.map((e) => e.request.children.length), [200, 50]);
      expect(
        queued
            .expand((e) => e.request.children)
            .map((c) => c.itemId)
            .toSet()
            .length,
        250,
      );
      expect(f.client.items, isEmpty);
      final ids = queued.map((e) => e.request.mutationId).toList();
      await f.restart();
      expect((await f.box.entries('A')).map((e) => e.request.mutationId), ids);
      expect(f.client.items, isEmpty);
    },
  );
  test(
    'multi-page clear rolls back all chunks when shared queue capacity is exhausted',
    () async {
      for (var i = 0; i < 99; i++) {
        await f.repository.addOrMergeItem(
          name: 'queued-$i',
          quantity: 1,
          unit: 'db',
        );
      }
      await f.canonical([
        for (var i = 0; i < 250; i++) canonicalItem(id: 'row-$i'),
      ]);
      final observed = f.client.items.where((i) => !i.pending).toList();
      await expectLater(
        f.repository.clearShoppingList(observed: observed),
        throwsStateError,
      );
      expect(await f.box.entries('A'), hasLength(99));
      expect((await f.box.projectionRows('A')).length, 99);
      expect(f.client.items.where((i) => !i.pending), hasLength(250));
    },
  );
  test(
    'manual add accepts SQLite commit without remote acknowledgement',
    () async {
      await f.repository.addOrMergeItem(name: ' TeA ', quantity: 2, unit: 'kg');
      final request = (await f.box.entries('A')).single.request;
      expect(request.children.single.name, 'tea');
      expect(request.children.single.quantity, 2000);
      expect(request.children.single.unit, 'g');
      expect(f.transport.sent, isEmpty);
      expect(f.client.items.single.quantity, 2000);
      expect(f.client.items.single.pending, true);
    },
  );
  test(
    'pending ADD baseline 5 + 2 never becomes 9 when canonical arrives first',
    () async {
      await f.canonical([canonicalItem()]);
      await f.repository.addOrMergeItem(name: 'tea', quantity: 2, unit: 'db');
      expect(f.client.items.single.quantity, 7);
      final r = (await f.box.entries('A')).single.request;
      await f.canonical([canonicalItem(quantity: 7, revision: 2)]);
      expect(f.client.items.single.quantity, 7);
      await f.receipt(r, 'APPLIED', itemId: 'tea', revision: 2, created: false);
      expect(f.client.items.single.quantity, 7);
      expect(f.client.items.single.pending, false);
    },
  );
  test(
    'receipt before canonical hands off immediately to canonical state',
    () async {
      await f.canonical([canonicalItem()]);
      await f.repository.addOrMergeItem(name: 'tea', quantity: 2, unit: 'db');
      final r = (await f.box.entries('A')).single.request;
      await f.receipt(r, 'APPLIED', itemId: 'tea', revision: 2, created: false);
      expect(f.client.items.single.quantity, 5);
      await f.canonical([canonicalItem(quantity: 7, revision: 2)]);
      expect(f.client.items.single.quantity, 7);
      expect(f.client.items.single.pending, false);
    },
  );
  test(
    'ambiguous concurrent canonical update never duplicates pending delta',
    () async {
      await f.canonical([canonicalItem()]);
      await f.repository.addOrMergeItem(name: 'tea', quantity: 2, unit: 'db');
      await f.canonical([canonicalItem(quantity: 10, revision: 2)]);
      expect(f.client.items.single.quantity, 10);
    },
  );
  for (final kind in ['edit', 'delete', 'check']) {
    test(
      'stale $kind restores authoritative +500 and persistent notice',
      () async {
        await f.canonical([canonicalItem()]);
        final item = f.client.items.single;
        switch (kind) {
          case 'edit':
            await f.repository.updateItem(
              id: item.id,
              observed: item,
              name: 'tea',
              quantity: 3,
              unit: 'db',
            );
          case 'delete':
            await f.repository.deleteItem(item.id, observed: item);
          case 'check':
            await f.repository.setItemChecked(
              id: item.id,
              observed: item,
              isChecked: true,
            );
        }
        final r = (await f.box.entries('A')).single.request;
        expect(r.children.single.expectedRevision, 1);
        await f.canonical([canonicalItem(quantity: 505, revision: 2)]);
        await f.receipt(r, 'REJECTED_STALE');
        expect(f.client.items.single.quantity, 505);
        expect(f.client.items.single.isChecked, false);
        expect(f.client.notice, isNotNull);
        await f.restart();
        expect(f.client.notice, isNotNull);
        await f.client.acknowledgeNotice();
        await f.client.settled;
        expect(f.client.notice, isNull);
      },
    );
  }
  test('rapid check-uncheck waits for actual predecessor revision', () async {
    await f.canonical([canonicalItem()]);
    var item = f.client.items.single;
    await f.repository.setItemChecked(
      id: item.id,
      observed: item,
      isChecked: true,
    );
    item = f.client.items.single;
    expect(item.isChecked, true);
    await f.repository.setItemChecked(
      id: item.id,
      observed: item,
      isChecked: false,
    );
    expect(f.client.items.single.isChecked, false);
    final a = (await f.box.entries('A')).single.request;
    await f.receipt(a, 'APPLIED', itemId: 'tea', revision: 7);
    final b = (await f.box.entries('A')).single.request;
    expect(b.children.single.expectedRevision, 7);
    expect(b.children.single.isChecked, false);
  });
  for (final kind in ['edit', 'check', 'delete']) {
    test('pending new ADD->$kind waits for actual target proof', () async {
      await f.repository.addOrMergeItem(name: 'tea', quantity: 2, unit: 'db');
      final item = f.client.items.single;
      switch (kind) {
        case 'edit':
          await f.repository.updateItem(
            id: item.id,
            observed: item,
            name: 'tea',
            quantity: 3,
            unit: 'db',
          );
        case 'delete':
          await f.repository.deleteItem(item.id, observed: item);
        case 'check':
          await f.repository.setItemChecked(
            id: item.id,
            observed: item,
            isChecked: true,
          );
      }
      final a = (await f.box.entries('A')).single.request;
      await f.receipt(
        a,
        'APPLIED',
        itemId: 'actual-id',
        revision: 9,
        created: true,
      );
      final b = (await f.box.entries('A')).single.request;
      expect(b.children.single.itemId, 'actual-id');
      expect(b.children.single.expectedRevision, 9);
      // The ADD target was deleted before the list ever observed it. Its
      // dependent operation must consume the rejection, never recreate ADD.
      await f.receipt(b, 'REJECTED_NOT_FOUND', itemId: 'actual-id');
      expect(f.client.items, isEmpty);
      expect(f.client.notice, isNotNull);
      await f.restart();
      expect(f.client.items, isEmpty);
      expect(await f.box.entries('A'), isEmpty);
      expect(f.transport.sent, isEmpty);
    });
  }
  for (final n in [10, 50, 200]) {
    test(
      'bulk $n keeps stable normalized parent across offline reopen',
      () async {
        await f.repository.addOrMergeItems(
          List.generate(n, (i) => (name: 'item$i', quantity: 1.25, unit: 'l')),
        );
        final before = (await f.box.entries('A')).single.request;
        expect(before.children, hasLength(n));
        expect(before.children.first.quantity, 1250);
        f.backend.offline = true;
        await f.restart();
        final after = (await f.box.entries('A')).single.request;
        expect(after.toJson(), before.toJson());
        expect(f.client.items, hasLength(n));
      },
    );
  }
  test(
    'clear binds confirmed observed IDs and revisions, not unseen new items',
    () async {
      await f.canonical([canonicalItem()]);
      final observed = List<ShoppingItem>.of(f.client.items);
      await f.canonical([
        canonicalItem(quantity: 505, revision: 2),
        canonicalItem(id: 'new'),
      ]);
      await f.repository.clearShoppingList(observed: observed);
      final r = (await f.box.entries('A')).single.request;
      expect(r.children, hasLength(1));
      expect(r.children.single.itemId, 'tea');
      expect(r.children.single.expectedRevision, 1);
    },
  );
  test('missing observation and invalid bulk fail before acceptance', () async {
    await expectLater(f.repository.deleteItem('tea'), throwsStateError);
    await expectLater(f.repository.clearShoppingList(), throwsStateError);
    await expectLater(
      f.repository.addOrMergeItems(
        List.generate(201, (i) => (name: 'i$i', quantity: 1.0, unit: 'db')),
      ),
      throwsArgumentError,
    );
    await expectLater(
      f.repository.addOrMergeItem(name: 'x', quantity: double.nan, unit: 'db'),
      throwsArgumentError,
    );
    expect(await f.box.entries('A'), isEmpty);
  });
  test(
    'A-signout-B-A preserves IDs without leaking overlay or notices',
    () async {
      await f.repository.addOrMergeItem(name: 'tea', quantity: 2, unit: 'db');
      final id = (await f.box.entries('A')).single.request.mutationId;
      final observed = f.client.items.single;
      await f.bind(null);
      expect(f.client.items, isEmpty);
      await f.bind('B');
      expect(f.client.items, isEmpty);
      expect(f.client.notice, isNull);
      await expectLater(
        f.repository.deleteItem(observed.id, observed: observed),
        throwsStateError,
      );
      await f.bind('A');
      expect(f.client.items.single.quantity, 2);
      expect((await f.box.entries('A')).single.request.mutationId, id);
      expect(await f.box.entries('B'), isEmpty);
    },
  );
  test('multiple UI subscriptions share one canonical listener', () async {
    final a = f.repository.watchShoppingItems().listen((_) {});
    final b = f.repository.watchShoppingItems().listen((_) {});
    await f.canonical([canonicalItem()]);
    expect(f.backend.activeListeners, 1);
    expect(f.backend.maxListeners, 1);
    await a.cancel();
    await b.cancel();
    expect(f.backend.activeListeners, 1);
  });
}
