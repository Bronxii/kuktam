import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kuktam/shopping/data/mutations/shopping_intent_queue.dart';
import 'package:kuktam/shopping/data/mutations/shopping_outbox.dart';
import 'package:kuktam/shopping/domain/shopping_mutation.dart';
import 'shopping_mutation_contract_test.dart' show testContext;

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late ShoppingOutbox box;
  late ShoppingIntentQueue queue;
  late String path;
  ShoppingMutationRequest action(ShoppingMutationChild c, [String uid = 'a']) =>
      ShoppingMutationRequest.create(context: testContext(uid), children: [c]);
  ShoppingMutationChild edit() => ShoppingMutationChild.edit(
    itemId: 'tea',
    expectedRevision: 2,
    name: 'tea',
    quantity: 3,
    unit: 'db',
  );
  ShoppingMutationChild check(bool value) => ShoppingMutationChild.setChecked(
    itemId: 'tea',
    expectedRevision: 2,
    isChecked: value,
  );
  Future<void> applied(
    ShoppingMutationRequest r,
    int revision, {
    String id = 'tea',
  }) => box.recordResult(
    r.context.uid,
    r.mutationId,
    ShoppingMutationStatus.applied,
    resultJson: jsonEncode([
      {'code': 'APPLIED', 'itemId': id, 'revision': revision},
    ]),
  );
  Future<void> reopen() async {
    await box.close();
    box = await ShoppingOutbox.open(factory: databaseFactoryFfi, path: path);
    queue = ShoppingIntentQueue(box);
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('shopping-intents-');
    path = '${directory.path}/queue.db';
    box = await ShoppingOutbox.open(factory: databaseFactoryFfi, path: path);
    queue = ShoppingIntentQueue(box);
  });
  tearDown(() async {
    await box.close();
    await directory.delete(recursive: true);
  });
  test(
    'version one database upgrades without replacing accepted requests',
    () async {
      final r = action(edit());
      await box.enqueue(r);
      await box.database.execute('DROP TABLE shoppingIntents');
      await box.database.setVersion(1);
      await reopen();
      expect((await box.entries('a')).single.request.toJson(), r.toJson());
      final b = action(check(true));
      await queue.enqueue(
        b,
        dependencies: {0: ShoppingIntentDependency(r.mutationId)},
      );
      await applied(r, 7);
      await queue.materialize('a');
      expect(
        (await box.entries(
          'a',
        )).single.request.children.single.expectedRevision,
        7,
      );
    },
  );
  test('pruning preserves predecessor proof while held work exists', () async {
    final a = action(edit()), b = action(check(true));
    await queue.enqueue(a);
    await queue.enqueue(
      b,
      dependencies: {0: ShoppingIntentDependency(a.mutationId)},
    );
    await applied(a, 9);
    await box.prune('a', DateTime.utc(2040));
    await queue.materialize('a');
    expect(
      (await box.entries('a')).single.request.children.single.expectedRevision,
      9,
    );
    await applied(b, 10);
    await box.prune('a', DateTime.utc(2040));
    expect(await box.entries('a', includeTerminal: true), isEmpty);
    expect(await box.database.query('shoppingIntents'), isEmpty);
  });
  for (final kind in ['check', 'edit', 'delete']) {
    test('edit then $kind waits durably for exact receipt revision', () async {
      final a = action(edit());
      final b = action(switch (kind) {
        'check' => check(true),
        'edit' => edit(),
        _ => ShoppingMutationChild.delete(itemId: 'tea', expectedRevision: 2),
      });
      await queue.enqueue(a);
      await queue.enqueue(
        b,
        dependencies: {0: ShoppingIntentDependency(a.mutationId)},
      );
      expect((await box.entries('a')).map((e) => e.request.mutationId), [
        a.mutationId,
      ]);
      await reopen();
      await queue.materialize('a');
      expect(await box.entries('a'), hasLength(1));
      await applied(a, 19);
      await queue.materialize('a');
      final pending = (await box.entries('a')).single.request;
      expect(pending.mutationId, b.mutationId);
      expect(pending.children.single.expectedRevision, 19);
      await reopen();
      await queue.materialize('a');
      expect(
        (await box.entries('a')).single.request.toJson(),
        pending.toJson(),
      );
    });
  }
  test(
    'check-uncheck-edit chain progresses one authoritative edge at a time',
    () async {
      final a = action(check(true)),
          b = action(check(false)),
          c = action(edit());
      await queue.enqueue(a);
      await queue.enqueue(
        b,
        dependencies: {0: ShoppingIntentDependency(a.mutationId)},
      );
      await queue.enqueue(
        c,
        dependencies: {0: ShoppingIntentDependency(b.mutationId)},
      );
      await applied(a, 5);
      await queue.materialize('a');
      expect((await box.entries('a')).single.request.mutationId, b.mutationId);
      await applied(b, 8);
      await queue.materialize('a');
      expect(
        (await box.entries(
          'a',
        )).single.request.children.single.expectedRevision,
        8,
      );
    },
  );
  test(
    'stale predecessor rejects descendants with persistent notices',
    () async {
      final a = action(edit()), b = action(check(true)), c = action(edit());
      await queue.enqueue(a);
      await queue.enqueue(
        b,
        dependencies: {0: ShoppingIntentDependency(a.mutationId)},
      );
      await queue.enqueue(
        c,
        dependencies: {0: ShoppingIntentDependency(b.mutationId)},
      );
      await box.recordResult(
        'a',
        a.mutationId,
        ShoppingMutationStatus.rejectedStale,
      );
      await queue.materialize('a');
      expect(await box.entries('a'), isEmpty);
      expect(await box.notices('a'), hasLength(3));
    },
  );
  test(
    'merge destination does not retarget dependent delete to unseen data',
    () async {
      final a = action(edit());
      final b = action(
        ShoppingMutationChild.delete(itemId: 'tea', expectedRevision: 2),
      );
      await queue.enqueue(a);
      await queue.enqueue(
        b,
        dependencies: {0: ShoppingIntentDependency(a.mutationId)},
      );
      await applied(a, 10, id: 'anotherRow');
      await queue.materialize('a');
      expect(await box.entries('a'), isEmpty);
      expect(
        (await box.notices('a')).single.status,
        ShoppingMutationStatus.rejectedStale,
      );
    },
  );
  test('different UID cannot depend on or materialize A work', () async {
    final a = action(edit()), b = action(check(true), 'b');
    await queue.enqueue(a);
    await expectLater(
      queue.enqueue(
        b,
        dependencies: {0: ShoppingIntentDependency(a.mutationId)},
      ),
      throwsStateError,
    );
    await queue.materialize('b');
    expect(await box.entries('b'), isEmpty);
    expect((await box.entries('a')).single.request.mutationId, a.mutationId);
  });
  test(
    'same action enqueue concurrently never duplicates held or materialized work',
    () async {
      final a = action(edit()), b = action(check(true));
      await queue.enqueue(a);
      await Future.wait(
        List.generate(
          10,
          (_) => queue.enqueue(
            b,
            dependencies: {0: ShoppingIntentDependency(a.mutationId)},
          ),
        ),
      );
      await applied(a, 4);
      await Future.wait(List.generate(10, (_) => queue.materialize('a')));
      expect((await box.entries('a')).single.request.mutationId, b.mutationId);
    },
  );
  test('cycle / forward reference denied before acceptance', () async {
    final a = action(edit()), b = action(check(true));
    await expectLater(
      queue.enqueue(
        a,
        dependencies: {0: ShoppingIntentDependency(b.mutationId)},
      ),
      throwsStateError,
    );
    expect(await box.entries('a'), isEmpty);
  });
  test(
    'ordinary enqueue cannot bypass a held dependency using its draft ID',
    () async {
      final a = action(edit()), b = action(check(true));
      await queue.enqueue(a);
      await queue.enqueue(
        b,
        dependencies: {0: ShoppingIntentDependency(a.mutationId)},
      );
      await expectLater(box.enqueue(b), throwsStateError);
      expect((await box.entries('a')).single.request.mutationId, a.mutationId);
      await applied(a, 6);
      await queue.materialize('a');
      expect(
        (await box.entries(
          'a',
        )).single.request.children.single.expectedRevision,
        6,
      );
    },
  );
  test('queue capacity includes held actions', () async {
    final a = action(edit());
    await queue.enqueue(a);
    for (var i = 0; i < 99; i++) {
      await queue.enqueue(
        action(check(true)),
        dependencies: {0: ShoppingIntentDependency(a.mutationId)},
      );
    }
    await expectLater(queue.enqueue(action(edit())), throwsStateError);
    await expectLater(box.enqueue(action(edit())), throwsStateError);
  });
  test('dependency cannot cross household or epoch', () async {
    final a = action(edit());
    await queue.enqueue(a);
    for (final context in [
      testContext('a', 'other'),
      ShoppingMutationContext(
        uid: 'a',
        householdId: 'home',
        epoch: '1999999999999-${'b' * 32}',
      ),
    ]) {
      final b = ShoppingMutationRequest.create(
        context: context,
        children: [check(true)],
      );
      await expectLater(
        queue.enqueue(
          b,
          dependencies: {0: ShoppingIntentDependency(a.mutationId)},
        ),
        throwsStateError,
      );
    }
  });
  test(
    'partial bulk predecessor resolves the specific successful child only',
    () async {
      final a = ShoppingMutationRequest.create(
        context: testContext(),
        children: [edit(), check(true)],
        bulk: true,
      );
      final b = action(check(false)), c = action(edit());
      await queue.enqueue(a);
      await queue.enqueue(
        b,
        dependencies: {0: ShoppingIntentDependency(a.mutationId)},
      );
      await queue.enqueue(
        c,
        dependencies: {
          0: ShoppingIntentDependency(a.mutationId, childIndex: 1),
        },
      );
      await box.recordResult(
        'a',
        a.mutationId,
        ShoppingMutationStatus.partial,
        resultJson: jsonEncode([
          {'code': 'APPLIED', 'itemId': 'tea', 'revision': 7},
          {'code': 'REJECTED_STALE'},
        ]),
      );
      await queue.materialize('a');
      expect((await box.entries('a')).single.request.mutationId, b.mutationId);
      expect(
        (await box.entries(
          'a',
        )).single.request.children.single.expectedRevision,
        7,
      );
      expect((await box.notices('a')).last.request.mutationId, c.mutationId);
    },
  );
  for (final invalid in ['not-json', '{}', '[]', '[{"code":"APPLIED"}]']) {
    test('malformed prerequisite receipt fails closed: $invalid', () async {
      final a = action(edit()), b = action(check(true));
      await queue.enqueue(a);
      await queue.enqueue(
        b,
        dependencies: {0: ShoppingIntentDependency(a.mutationId)},
      );
      await box.recordResult(
        'a',
        a.mutationId,
        ShoppingMutationStatus.applied,
        resultJson: invalid,
      );
      await queue.materialize('a');
      expect(await box.entries('a'), isEmpty);
      expect(
        (await box.notices('a')).single.status,
        ShoppingMutationStatus.rejectedStale,
      );
    });
  }
  test('changing dependencies under the same action ID fails closed', () async {
    final a = action(edit()), b = action(check(true));
    await queue.enqueue(a);
    await queue.enqueue(
      b,
      dependencies: {0: ShoppingIntentDependency(a.mutationId)},
    );
    await expectLater(queue.enqueue(b), throwsStateError);
  });
  test('context changed predecessor does not silently rebind child', () async {
    final a = action(edit()), b = action(check(true));
    await queue.enqueue(a);
    await queue.enqueue(
      b,
      dependencies: {0: ShoppingIntentDependency(a.mutationId)},
    );
    await box.recordResult(
      'a',
      a.mutationId,
      ShoppingMutationStatus.rejectedContextChanged,
    );
    await queue.materialize('a');
    expect(
      (await box.notices('a')).last.status,
      ShoppingMutationStatus.rejectedContextChanged,
    );
  });
}
