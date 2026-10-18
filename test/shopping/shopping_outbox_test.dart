import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kuktam/shopping/data/mutations/shopping_outbox.dart';
import 'package:kuktam/shopping/domain/shopping_mutation.dart';
import 'shopping_mutation_contract_test.dart' show testContext;

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late ShoppingOutbox outbox;
  late String path;
  ShoppingMutationRequest request([String uid = 'a']) =>
      ShoppingMutationRequest.create(
        context: testContext(uid),
        children: [
          ShoppingMutationChild.add(name: 'tea', quantity: 1, unit: 'db'),
        ],
      );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('kuktam-outbox-test-');
    path = '${directory.path}/outbox.db';
    outbox = await ShoppingOutbox.open(factory: databaseFactoryFfi, path: path);
  });
  tearDown(() async {
    await outbox.close();
    await directory.delete(recursive: true);
  });
  test('database uses FULL synchronous durability', () async {
    final setting = await outbox.database.rawQuery('PRAGMA synchronous');
    expect(setting.single.values.single, 2);
  });
  test(
    'notices are bounded, UID-scoped and advance after acknowledgement',
    () async {
      final a = request(), b = request('b');
      await outbox.enqueue(a);
      await outbox.enqueue(b);
      await outbox.recordResult(
        'a',
        a.mutationId,
        ShoppingMutationStatus.rejectedStale,
      );
      await outbox.recordResult(
        'b',
        b.mutationId,
        ShoppingMutationStatus.rejectedStale,
      );
      expect(
        (await outbox.notices('a', limit: 1)).single.request.mutationId,
        a.mutationId,
      );
      await outbox.acknowledgeNotice('a', a.mutationId);
      expect(await outbox.notices('a'), isEmpty);
      expect(await outbox.notices('b'), hasLength(1));
    },
  );
  test('enqueue commits durably and reopen preserves exact request', () async {
    final r = request();
    await outbox.enqueue(r);
    await outbox.close();
    outbox = await ShoppingOutbox.open(factory: databaseFactoryFfi, path: path);
    final entry = (await outbox.entries('a')).single;
    expect(entry.request.toJson(), r.toJson());
    expect(entry.status, ShoppingMutationStatus.pending);
  });
  test('repeated and concurrent enqueue uses one immutable identity', () async {
    final r = request();
    await Future.wait(List.generate(10, (_) => outbox.enqueue(r)));
    expect(await outbox.entries('a'), hasLength(1));
    final altered = ShoppingMutationRequest.restore({
      ...r.toJson(),
      'payloadJson': '{"type":"ADD","name":"other","quantity":5,"unit":"g"}',
    });
    await expectLater(outbox.enqueue(altered), throwsStateError);
    expect(
      (await outbox.entries('a')).single.request.payloadJson,
      r.payloadJson,
    );
  });
  test('A / B / A keeps payloads and contexts isolated', () async {
    await outbox.enqueue(request('a'));
    await outbox.enqueue(request('b'));
    await outbox.saveContext(testContext('a', 'home-a'));
    await outbox.saveContext(testContext('b', 'home-b'));
    expect((await outbox.entries('a')).single.request.context.uid, 'a');
    expect((await outbox.entries('b')).single.request.context.uid, 'b');
    expect(await outbox.entries('c'), isEmpty);
    expect((await outbox.readContext('a'))!.householdId, 'home-a');
    expect((await outbox.readContext('b'))!.householdId, 'home-b');
    await outbox.clearContext('a');
    expect(await outbox.readContext('a'), isNull);
    expect(await outbox.entries('a'), hasLength(1));
  });
  test(
    'terminal result survives reopen and cannot regress to pending',
    () async {
      final r = request();
      await outbox.enqueue(r);
      await outbox.recordResult(
        'a',
        r.mutationId,
        ShoppingMutationStatus.rejectedStale,
      );
      await outbox.recordResult(
        'a',
        r.mutationId,
        ShoppingMutationStatus.failedRetryable,
      );
      await outbox.close();
      outbox = await ShoppingOutbox.open(
        factory: databaseFactoryFfi,
        path: path,
      );
      expect(await outbox.entries('a'), isEmpty);
      final entry = (await outbox.entries('a', includeTerminal: true)).single;
      expect(entry.status, ShoppingMutationStatus.rejectedStale);
      expect(entry.noticeAcknowledged, false);
    },
  );
  test(
    'queue full rejects before accepting and never evicts accepted work',
    () async {
      for (var i = 0; i < ShoppingOutbox.maxPending; i++) {
        await outbox.enqueue(request());
      }
      await expectLater(outbox.enqueue(request()), throwsStateError);
      expect(await outbox.entries('a'), hasLength(ShoppingOutbox.maxPending));
      await outbox.enqueue(request('b'));
      expect(await outbox.entries('b'), hasLength(1));
    },
  );
  test('retention cleanup cannot remove pending or unseen failure', () async {
    final pending = request(), failed = request(), applied = request();
    for (final r in [pending, failed, applied]) {
      await outbox.enqueue(r);
    }
    await outbox.recordResult(
      'a',
      failed.mutationId,
      ShoppingMutationStatus.rejectedStale,
    );
    await outbox.recordResult(
      'a',
      applied.mutationId,
      ShoppingMutationStatus.applied,
    );
    await outbox.prune(
      'a',
      testContext().expiresAt.add(const Duration(days: 8)),
    );
    expect(await outbox.entries('a', includeTerminal: true), hasLength(2));
    await outbox.acknowledgeNotice('a', failed.mutationId);
    await outbox.prune(
      'a',
      testContext().expiresAt.add(const Duration(days: 8)),
    );
    expect(
      (await outbox.entries(
        'a',
        includeTerminal: true,
      )).single.request.mutationId,
      pending.mutationId,
    );
  });
}
