import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:kuktam/shopping/data/repositories/shopping_repository.dart';
import 'package:kuktam/shopping/domain/shopping_mutation.dart';
import 'shopping_mutation_e2e_test.dart' show DeviceClient, fixture;
import 'shopping_h2a_e2e_test.dart' show ids, seed, item;

const uid = 'client-a';
List<ShoppingItemInput> inputs(int n) => List.generate(
  n,
  (i) => switch (i) {
    0 => (name: 'milk$n', quantity: 300.0, unit: 'ml'),
    1 => (name: ' MILK$n ', quantity: 2.0, unit: 'l'),
    2 => (name: 'milk$n', quantity: 500.0, unit: 'ml'),
    3 => (name: 'milk$n', quantity: 1.0, unit: 'db'),
    _ => (name: 'bulk${n}item$i', quantity: i + 0.25, unit: 'db'),
  },
);

Future<Map<String, Object?>> row(DeviceClient a, String id) async =>
    (await a.box.database.query(
      'mutations',
      where: 'uid=? AND id=?',
      whereArgs: [uid, id],
    )).single;
Future<void> receipt(DeviceClient a, String id, int count) async {
  Future<bool> ready() async =>
      (jsonDecode((await row(a, id))['result'] as String? ?? '[]') as List)
          .length ==
      count;
  if (await ready()) return;
  await a.client.changes
      .asyncMap((_) => ready())
      .firstWhere((v) => v)
      .timeout(const Duration(seconds: 90));
}

Future<void> serverCommand(DeviceClient a, String id) async {
  await a.db
      .doc('users/$uid/shoppingMutations/$id')
      .snapshots(includeMetadataChanges: true)
      .firstWhere(
        (d) =>
            d.exists && !d.metadata.isFromCache && !d.metadata.hasPendingWrites,
      )
      .timeout(const Duration(seconds: 45));
}

Future<void> assertBulk(DeviceClient a, int n) async {
  final parent = (await a.box.entries(
    uid,
    includeTerminal: true,
  )).singleWhere((e) => e.request.children.length == n);
  final results = jsonDecode(parent.resultJson!) as List;
  final expectedRevision = <String, Object?>{
    for (final r in results) r['itemId'] as String: r['revision'],
  };
  final collection = a.db.collection(
    'households/${a.client.context!.householdId}/shoppingItems',
  );
  final all = await collection.get(const GetOptions(source: Source.server));
  final rows = all.docs
      .where(
        (d) =>
            d.get('name') == 'milk$n' ||
            (d.get('name') as String).startsWith('bulk${n}item'),
      )
      .toList();
  expect(rows, hasLength(n - 2));
  for (final d in rows) {
    final name = d.get('name') as String;
    if (name == 'milk$n') {
      expect(d.get('quantity'), d.get('unit') == 'ml' ? 2800 : 1);
    } else {
      final index = int.parse(name.split('item').last);
      expect(d.get('quantity'), index + 0.25);
    }
    expect(
      d.get('revision'),
      expectedRevision[d.id],
      reason:
          'Canonical revision must match the last actual receipt for this target',
    );
  }
  await a.visible(
    () =>
        a.client.items
                .where(
                  (i) =>
                      i.name == 'milk$n' || i.name.startsWith('bulk${n}item'),
                )
                .length ==
            n - 2 &&
        a.client.items
            .where(
              (i) => i.name == 'milk$n' || i.name.startsWith('bulk${n}item'),
            )
            .every((i) => !i.pending),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const phase = String.fromEnvironment('SHOPPING_E2E_PHASE');
  testWidgets('H2B real bulk $phase', (tester) async {
    final a = DeviceClient();
    if (phase == 'death-queued') await fixture('setup');
    await a.open(
      'h2b',
      uid,
      offline: phase == 'death-partial' || phase == 'complete',
    );
    final manifest = File('${await getDatabasesPath()}/h2b.json');
    if (phase == 'death-queued') {
      await a.db.disableNetwork();
      for (final n in [50, 200]) {
        await a.repository.addOrMergeItems(inputs(n));
        final entries = await a.box.entries(uid);
        expect(entries.last.request.children, hasLength(n));
        expect(entries.last.request.type.wire, 'BULK');
        await a.visible(
          () =>
              a.client.items
                  .where(
                    (i) =>
                        i.name == 'milk$n' || i.name.startsWith('bulk${n}item'),
                  )
                  .length ==
              n - 2,
        );
        expect(
          a.client.items
              .where((i) => i.name == 'milk$n' && i.unit == 'ml')
              .single
              .quantity,
          2800,
        );
      }
      final entries = await a.box.entries(uid);
      expect(entries, hasLength(2));
      await manifest.writeAsString(
        jsonEncode({
          'requests': entries.map((e) => e.request.toJson()).toList(),
          'ids': await ids(a),
        }),
        flush: true,
      );
      await fixture('crash-ready');
      await Completer<void>().future;
    }
    final saved = jsonDecode(await manifest.readAsString()) as Map;
    final parentIds = (saved['ids'] as List).cast<String>();
    if (phase != 'reopen') {
      expect(await ids(a), parentIds);
      final entries = await a.box.entries(uid);
      expect(
        entries.map((e) => e.request.toJson()).toList(),
        saved['requests'],
      );
      for (final pair in [(50, 0), (200, 1)]) {
        final n = pair.$1, id = parentIds[pair.$2];
        expect((await row(a, id))['terminal'], 0);
        await a.visible(
          () =>
              a.client.items
                  .where(
                    (i) =>
                        i.name == 'milk$n' || i.name.startsWith('bulk${n}item'),
                  )
                  .length ==
              n - 2,
        );
      }
    }
    if (phase == 'death-partial') {
      await a.db.enableNetwork();
      await a.client.recover();
      for (final pair in [(parentIds[0], 17), (parentIds[1], 73)]) {
        await serverCommand(a, pair.$1);
        final response = await fixture('step', {
          'id': pair.$1,
          'steps': pair.$2,
        });
        expect(response['cursor'], pair.$2);
        expect(response['status'], 'PROCESSING');
        await receipt(a, pair.$1, pair.$2);
      }
      // Prove canonical/APPLIED prefix is not projected again; suffix stays visible.
      for (final n in [50, 200]) {
        await a.visible(
          () => a.client.items.any(
            (i) => i.name == 'bulk${n}item4' && !i.pending,
          ),
        );
        expect(
          a.client.items.singleWhere((i) => i.name == 'bulk${n}item4').quantity,
          4.25,
        );
        expect(
          a.client.items
              .singleWhere((i) => i.name == 'bulk${n}item${n - 1}')
              .pending,
          true,
        );
      }
      saved['partial'] = [
        await row(a, parentIds[0]),
        await row(a, parentIds[1]),
      ];
      await manifest.writeAsString(jsonEncode(saved), flush: true);
      await a.db.disableNetwork();
      await fixture('crash-ready');
      await Completer<void>().future;
    }
    if (phase == 'complete') {
      for (var i = 0; i < 2; i++) {
        expect(await row(a, parentIds[i]), (saved['partial'] as List)[i]);
      }
      await a.db.enableNetwork();
      await a.client.recover();
      // One event-gated flap while partial; no polling or elapsed-time split.
      await serverCommand(a, parentIds[0]);
      await a.db.disableNetwork();
      await fixture('step', {'id': parentIds[0], 'steps': 1});
      await a.db.enableNetwork();
      await a.client.recover();
      await receipt(a, parentIds[0], 18);
      await fixture('resume');
      await a.done();
      expect(await ids(a), parentIds);
      for (final pair in [(50, parentIds[0]), (200, parentIds[1])]) {
        final r = await row(a, pair.$2);
        expect(r['status'], 'APPLIED');
        expect(r['terminal'], 1);
        expect(jsonDecode(r['result'] as String), hasLength(pair.$1));
        await assertBulk(a, pair.$1);
      }
      // Mixed results through the existing clear-list facade, no forged commands.
      expect(
        (await a.db
                .doc('households/${a.client.context!.householdId}')
                .get(const GetOptions(source: Source.server)))
            .get('shoppingRevision'),
        250,
      );
      for (var i = 0; i < 2; i++) {
        final earlier =
            jsonDecode((saved['partial'] as List)[i]['result'] as String)
                as List;
        final current =
            jsonDecode((await row(a, parentIds[i]))['result'] as String)
                as List;
        expect(current.take(earlier.length).toList(), earlier);
      }
      for (final name in [
        'mixed-ok',
        'mixed-stale',
        'mixed-gone',
        'mixed-context',
      ]) {
        await seed(a, name);
      }
      final observed = [
        'mixed-ok',
        'mixed-stale',
        'mixed-gone',
        'mixed-context',
      ].map((n) => item(a, n)).toList();
      await fixture('pause');
      await a.db.disableNetwork();
      await a.repository.clearShoppingList(observed: observed);
      final mixed = (await a.box.entries(uid)).single.request.mutationId;
      await fixture('add', {'name': 'mixed-stale', 'quantity': 500});
      await fixture('delete', {'name': 'mixed-gone'});
      await a.db.enableNetwork();
      await serverCommand(a, mixed);
      await fixture('step', {'id': mixed, 'steps': 3});
      await receipt(a, mixed, 3);
      expect((await row(a, mixed))['terminal'], 0);
      expect(
        (jsonDecode((await row(a, mixed))['result'] as String) as List)
            .map((r) => r['code'])
            .toList(),
        ['APPLIED', 'REJECTED_STALE', 'REJECTED_NOT_FOUND'],
      );
      await fixture('epoch');
      await fixture('step', {'id': mixed, 'steps': 1});
      await a.done();
      final result = await row(a, mixed);
      expect(result['status'], 'PARTIAL');
      expect(result['terminal'], 1);
      expect(
        (jsonDecode(result['result'] as String) as List).last['code'],
        'REJECTED_CONTEXT_CHANGED',
      );
      await a.visible(
        () => a.client.items.any(
          (i) => i.name == 'mixed-stale' && i.quantity == 501 && !i.pending,
        ),
      );
      expect(a.client.items.any((i) => i.name == 'mixed-ok'), false);
      await a.visible(() => a.client.notice != null);
      saved['finalIds'] = await ids(a);
      await manifest.writeAsString(jsonEncode(saved), flush: true);
    }
    if (phase == 'reopen') {
      expect(await ids(a), saved['finalIds']);
      expect(await a.box.entries(uid), isEmpty);
      await assertBulk(a, 50);
      await assertBulk(a, 200);
      for (final id in parentIds) {
        expect((await row(a, id))['status'], 'APPLIED');
      }
    }
    await a.close();
  }, timeout: const Timeout(Duration(minutes: 10)));
}
