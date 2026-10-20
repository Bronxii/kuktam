// H2A only. Run through shopping-client-e2e.cjs with KUKTAM_E2E_SCOPE=H2A.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:kuktam/shopping/domain/models/shopping_item.dart';
import 'package:kuktam/shopping/presentation/widgets/shopping_item_dialog.dart';

import 'shopping_mutation_e2e_test.dart' show DeviceClient, fixture;

const uid = 'client-a';

Future<List<String>> ids(DeviceClient a) async => (await a.box.database.query(
  'shoppingIntents',
  columns: ['id'],
  where: 'uid=?',
  whereArgs: [uid],
  orderBy: 'sequence',
)).map((r) => r['id']! as String).toList();

Future<String> status(DeviceClient a, String id) async =>
    (await a.box.database.query(
          'mutations',
          where: 'uid=? AND id=?',
          whereArgs: [uid, id],
        )).single['status']!
        as String;

ShoppingItem item(DeviceClient a, String name) =>
    a.client.items.singleWhere((i) => i.name == name);

Future<void> canonical(DeviceClient a, String name, double quantity) async {
  await a.visible(
    () => a.client.items.any(
      (i) => i.name == name && i.quantity == quantity && !i.pending,
    ),
  );
  expect(a.client.items.where((i) => i.name == name), hasLength(1));
  final server = await a.db
      .collection('households/${a.client.context!.householdId}/shoppingItems')
      .where('name', isEqualTo: name)
      .get(const GetOptions(source: Source.server));
  expect(server.docs, hasLength(1));
  expect(server.docs.single.get('quantity'), quantity);
}

Future<void> seed(DeviceClient a, String name, [double quantity = 1]) async {
  await a.repository.addOrMergeItem(name: name, quantity: quantity, unit: 'db');
  await a.done();
  await canonical(a, name, quantity);
}

Future<void> reconnect(DeviceClient a, List<String> before) async {
  await a.db.enableNetwork();
  await a.client.recover();
  await a.done();
  expect(
    await ids(a),
    before,
    reason: 'Recovery must never allocate another ID',
  );
}

Future<void> edit(DeviceClient a, ShoppingItem observed, double quantity) =>
    a.repository.updateItem(
      id: observed.id,
      observed: observed,
      name: observed.name,
      quantity: quantity,
      unit: observed.unit,
    );

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const phase = String.fromEnvironment('SHOPPING_E2E_PHASE');
  testWidgets('H2A real native $phase', (tester) async {
    final a = DeviceClient();
    final resume = phase.startsWith('resume-');
    if (phase == 'single') await fixture('setup');
    await a.open('h2a', uid, offline: resume);

    if (phase.startsWith('death-')) {
      if (phase == 'death-edit') {
        for (final name in [
          'death-edit',
          'death-check',
          'death-uncheck',
          'death-delete',
        ]) {
          await seed(a, name);
        }
        final observed = item(a, 'death-uncheck');
        await a.repository.setItemChecked(
          id: observed.id,
          observed: observed,
          isChecked: true,
        );
        await a.done();
        await a.visible(
          () =>
              item(a, 'death-uncheck').isChecked &&
              !item(a, 'death-uncheck').pending,
        );
      }
      await a.db.disableNetwork();
      if (phase == 'death-add') {
        await a.repository.addOrMergeItem(
          name: 'death-add',
          quantity: 4,
          unit: 'db',
        );
        await a.visible(() => a.client.items.any((i) => i.name == 'death-add'));
        await edit(a, item(a, 'death-add'), 9);
        await a.visible(() => item(a, 'death-add').quantity == 9);
        final observed = item(a, 'death-add');
        await a.repository.setItemChecked(
          id: observed.id,
          observed: observed,
          isChecked: true,
        );
      } else {
        await edit(a, item(a, 'death-edit'), 9);
        for (final name in ['death-check', 'death-uncheck']) {
          final observed = item(a, name);
          await a.repository.setItemChecked(
            id: observed.id,
            observed: observed,
            isChecked: name == 'death-check',
          );
        }
        final observed = item(a, 'death-delete');
        await a.repository.deleteItem(observed.id, observed: observed);
      }
      await a.visible(() => a.client.items.any((i) => i.pending));
      final pending = await a.box.entries(uid);
      expect(pending, hasLength(phase == 'death-add' ? 1 : 4));
      final manifest = {
        'ids': await ids(a),
        'requests': pending.map((e) => e.request.toJson()).toList(),
        'intents': await a.box.database.query(
          'shoppingIntents',
          where: 'uid=? AND projectionState=0',
          whereArgs: [uid],
          orderBy: 'sequence',
        ),
      };
      await File(
        '${await getDatabasesPath()}/h2a-death.json',
      ).writeAsString(jsonEncode(manifest), flush: true);
      await fixture('crash-ready');
      // The host kills this process here, with SQLite/coordinator still open.
      // A normal test return is deliberately impossible in these two phases.
      await Completer<void>().future;
      fail('Process-death phase must not return');
    }

    if (resume) {
      final manifest =
          jsonDecode(
                await File(
                  '${await getDatabasesPath()}/h2a-death.json',
                ).readAsString(),
              )
              as Map;
      expect(await ids(a), manifest['ids']);
      final pending = await a.box.entries(uid);
      expect(pending, hasLength(phase == 'resume-add' ? 1 : 4));
      expect(
        pending.map((e) => e.request.toJson()).toList(),
        manifest['requests'],
      );
      expect(
        await a.box.database.query(
          'shoppingIntents',
          where: 'uid=? AND projectionState=0',
          whereArgs: [uid],
          orderBy: 'sequence',
        ),
        manifest['intents'],
      );
      final name = phase == 'resume-add' ? 'death-add' : 'death-edit';
      const quantity = 9.0;
      await a.visible(
        () => a.client.items.any(
          (i) => i.name == name && i.pending && i.quantity == quantity,
        ),
      );
      for (final entry in pending) {
        expect(await status(a, entry.request.mutationId), 'PENDING');
      }
      if (phase == 'resume-edit') {
        await a.visible(
          () =>
              item(a, 'death-check').isChecked &&
              !item(a, 'death-uncheck').isChecked &&
              a.client.items.every((i) => i.name != 'death-delete'),
        );
      }
      await reconnect(a, (manifest['ids'] as List).cast<String>());
      await canonical(a, name, quantity);
      for (final entry in pending) {
        expect(await status(a, entry.request.mutationId), 'APPLIED');
      }
      if (phase == 'resume-add') {
        expect(item(a, name).isChecked, true);
      } else {
        await a.visible(
          () =>
              item(a, 'death-check').isChecked &&
              !item(a, 'death-check').pending &&
              !item(a, 'death-uncheck').isChecked &&
              !item(a, 'death-uncheck').pending,
        );
        final server = await a.db
            .collection(
              'households/${a.client.context!.householdId}/shoppingItems',
            )
            .where('name', isEqualTo: 'death-delete')
            .get(const GetOptions(source: Source.server));
        expect(server.docs, isEmpty);
        // Another actor creates the logical destination while this client has
        // a new pending ADD. Its dependent DELETE must not retarget that row.
        await a.repository.acknowledgeNotice();
        await a.db.disableNetwork();
        await a.repository.addOrMergeItem(
          name: 'ambiguous',
          quantity: 2,
          unit: 'db',
        );
        await a.visible(() => a.client.items.any((i) => i.name == 'ambiguous'));
        final projected = item(a, 'ambiguous');
        await a.repository.deleteItem(projected.id, observed: projected);
        final heldId = (await ids(a)).last;
        await fixture('add', {'name': 'ambiguous', 'quantity': 500});
        await reconnect(a, await ids(a));
        await canonical(a, 'ambiguous', 502);
        expect(await status(a, heldId), isNot('APPLIED'));
        await a.visible(() => a.client.notice != null);
      }
      await a.close();
      return;
    }

    // Real production dialog: SQLite acceptance must release its busy state
    // with networking disabled, before any server acknowledgement.
    await a.db.disableNetwork();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () => showShoppingItemDialog(
                  context: context,
                  shoppingRepository: a.repository,
                ),
                child: const Text('open'),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'offline-add');
    await tester.tap(find.text('Hozzáadás'));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(find.byType(AlertDialog), findsNothing);
    await a.visible(
      () => a.client.items.any((i) => i.name == 'offline-add' && i.pending),
    );
    await reconnect(a, await ids(a));
    await canonical(a, 'offline-add', 1);

    await a.db.disableNetwork();
    final original = item(a, 'offline-add');
    await edit(a, original, 7);
    await a.visible(() => item(a, 'offline-add').quantity == 7);
    final pendingEdit = (await a.box.entries(uid)).single;
    expect(
      pendingEdit.request.children.single.expectedRevision,
      original.revision,
    );
    await reconnect(a, await ids(a));
    await canonical(a, 'offline-add', 7);
    for (final checked in [true, false]) {
      await a.db.disableNetwork();
      final observed = item(a, 'offline-add');
      await a.repository.setItemChecked(
        id: observed.id,
        observed: observed,
        isChecked: checked,
      );
      await a.visible(() => item(a, 'offline-add').isChecked == checked);
      await reconnect(a, await ids(a));
      await a.visible(
        () =>
            !item(a, 'offline-add').pending &&
            item(a, 'offline-add').isChecked == checked,
      );
    }
    await a.db.disableNetwork();
    final deleted = item(a, 'offline-add');
    await a.repository.deleteItem(deleted.id, observed: deleted);
    await a.visible(() => a.client.items.every((i) => i.name != 'offline-add'));
    await reconnect(a, await ids(a));
    expect(
      (await a.db
              .doc(
                'households/${deleted.context!.householdId}/shoppingItems/${deleted.id}',
              )
              .get(const GetOptions(source: Source.server)))
          .exists,
      false,
    );

    for (final chain in ['edit', 'check', 'delete', 'edit-check']) {
      final name = 'chain-$chain';
      await a.db.disableNetwork();
      await a.repository.addOrMergeItem(name: name, quantity: 1, unit: 'db');
      await a.visible(() => a.client.items.any((i) => i.name == name));
      if (chain.startsWith('edit')) {
        await edit(a, item(a, name), 3);
        await a.visible(() => item(a, name).quantity == 3);
      }
      if (chain.contains('check')) {
        final observed = item(a, name);
        await a.repository.setItemChecked(
          id: observed.id,
          observed: observed,
          isChecked: true,
        );
      } else if (chain == 'delete') {
        final observed = item(a, name);
        await a.repository.deleteItem(observed.id, observed: observed);
      }
      await reconnect(a, await ids(a));
      if (chain == 'delete') {
        await a.visible(() => a.client.items.every((i) => i.name != name));
      } else {
        await canonical(a, name, chain.startsWith('edit') ? 3 : 1);
        expect(item(a, name).isChecked, chain.contains('check'));
      }
    }

    for (final kind in ['edit', 'delete']) {
      final name = 'stale-$kind';
      await seed(a, name);
      final observed = item(a, name);
      await a.db.disableNetwork();
      if (kind == 'edit') {
        await edit(a, observed, 2);
      } else {
        await a.repository.deleteItem(observed.id, observed: observed);
      }
      final id = (await a.box.entries(uid)).single.request.mutationId;
      await fixture('add', {'name': name, 'quantity': 500});
      await reconnect(a, await ids(a));
      expect(await status(a, id), 'REJECTED_STALE');
      await canonical(a, name, 501);
      await a.visible(() => a.client.notice != null);
      await a.repository.acknowledgeNotice();
    }
    await a.db.disableNetwork();
    await a.repository.addOrMergeItem(
      name: 'old-epoch',
      quantity: 2,
      unit: 'db',
    );
    final old = (await a.box.entries(uid)).single.request;
    await fixture('epoch');
    await reconnect(a, await ids(a));
    expect(await status(a, old.mutationId), 'REJECTED_CONTEXT_CHANGED');
    expect(a.client.items.where((i) => i.name == 'old-epoch'), isEmpty);
    expect(a.client.context!.epoch, isNot(old.context.epoch));

    // Event-gated flap: command exists, processor deliberately paused. No sleep
    // decides when the network changes, and no new client ID is generated.
    await fixture('pause');
    await a.db.disableNetwork();
    await a.repository.addOrMergeItem(name: 'flap', quantity: 6, unit: 'db');
    final flap = (await a.box.entries(uid)).single.request.mutationId;
    final stableIds = await ids(a);
    await a.db.enableNetwork();
    await a.db
        .doc('users/$uid/shoppingMutations/$flap')
        .snapshots()
        .firstWhere(
          (d) =>
              d.exists &&
              !d.metadata.isFromCache &&
              !d.metadata.hasPendingWrites,
        )
        .timeout(const Duration(seconds: 45));
    await a.db.disableNetwork();
    await fixture('resume');
    await reconnect(a, stableIds);
    await canonical(a, 'flap', 6);
    expect(await status(a, flap), 'APPLIED');

    // Real Firestore stream, with only target-containing query deliveries held
    // at the backend/coordinator boundary to deterministically force H1A's race.
    a.backend.withheldItemName = 'ghost';
    await fixture('pause');
    await a.repository.addOrMergeItem(name: 'ghost', quantity: 2, unit: 'db');
    final ghost = (await a.box.entries(uid)).single.request.mutationId;
    await fixture('resume');
    await a.done();
    expect(await status(a, ghost), 'APPLIED');
    await a.visible(() => a.client.items.every((i) => i.name != 'ghost'));
    await fixture('delete', {'name': 'ghost'});
    final ghostServer = await a.db
        .collection('households/${a.client.context!.householdId}/shoppingItems')
        .where('name', isEqualTo: 'ghost')
        .get(const GetOptions(source: Source.server));
    expect(ghostServer.docs, isEmpty);
    expect(a.client.items.where((i) => i.name == 'ghost'), isEmpty);
    expect(await a.box.entries(uid), isEmpty);
    a.backend.withheldItemName = null;
    await a.close();
  }, timeout: const Timeout(Duration(minutes: 8)));
}
