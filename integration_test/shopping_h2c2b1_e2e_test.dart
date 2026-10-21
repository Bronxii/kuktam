import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kuktam/shopping/data/mutations/shopping_outbox.dart';
import 'package:kuktam/shopping/domain/models/shopping_item.dart';
import 'package:kuktam/shopping/domain/shopping_mutation.dart';
import 'shopping_mutation_e2e_test.dart' show fixture;
import 'shopping_h2c2a_e2e_test.dart'
    show OnlineClient, Command, process, converge, view;

/// Preserve the proven independent native topology. Only acceptance differs:
/// offline acceptance is the SQLite commit, not a wait for server delivery.
class ReconnectClient extends OnlineClient {
  final originals = <String, Map<String, Object?>>{};
  @override
  Future<Command> accept(Future<void> Function() action) async {
    await action();
    final entry = (await box.entries(uid, includeTerminal: true)).last;
    expect(entry.request.context.uid, uid);
    expect(originals.containsKey(entry.request.mutationId), isFalse);
    originals[entry.request.mutationId] = entry.request.toJson();
    return Command(this, entry.request.mutationId);
  }

  Future<void> unchanged() async {
    final rows = await box.entries(uid, includeTerminal: true);
    expect(
      rows.map((r) => r.request.mutationId).toSet(),
      originals.keys.toSet(),
    );
    for (final row in rows) {
      expect(row.request.toJson(), originals[row.request.mutationId]);
    }
  }
}

Future<void> arrived(Command command) async {
  // One-shot harness barrier only. The dispatcher creates the command unaided.
  await command.client.db
      .doc('users/${command.client.uid}/shoppingMutations/${command.id}')
      .snapshots(includeMetadataChanges: true)
      .firstWhere(
        (d) =>
            d.exists && !d.metadata.isFromCache && !d.metadata.hasPendingWrites,
      )
      .timeout(const Duration(seconds: 45));
}

ShoppingItem item(ReconnectClient c, String name) =>
    c.client.items.singleWhere((i) => i.name == name);

Future<ShoppingOutboxEntry> row(Command c) async => (await c.client.box.entries(
  c.client.uid,
  includeTerminal: true,
)).singleWhere((r) => r.request.mutationId == c.id);

Future<void> seed(
  ReconnectClient a,
  ReconnectClient b,
  String name,
  double quantity,
  String unit,
) async {
  final command = await a.add(name, quantity, unit);
  await arrived(command);
  expect((await process([command])).single['status'], 'APPLIED');
  await converge(a, b);
}

Future<void> offlineBoth(ReconnectClient a, ReconnectClient b) async {
  expect(view(a), view(b));
  final ca = a.client.context!, cb = b.client.context!;
  expect(ca.householdId, cb.householdId);
  expect(ca.epoch, cb.epoch);
  await Future.wait([a.db.disableNetwork(), b.db.disableNetwork()]);
  expect(a.client.context!.sameAs(ca), isTrue);
  expect(b.client.context!.sameAs(cb), isTrue);
  expect((await a.box.readContext(a.uid))!.sameAs(ca), isTrue);
  expect((await b.box.readContext(b.uid))!.sameAs(cb), isTrue);
}

Future<void> cachedCanonical(ReconnectClient c, ShoppingItem original) async {
  final cached = await c.db
      .doc('households/test-family/shoppingItems/${original.id}')
      .get(const GetOptions(source: Source.cache));
  expect(cached.get('quantity'), original.quantity);
  expect(cached.get('revision'), original.revision);
  expect(cached.get('isChecked'), original.isChecked);
}

Future<void> connect(Command c) async {
  await c.client.db.enableNetwork();
  await arrived(c);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'H2C2B1 two independent offline reconnect clients',
    (tester) async {
      await fixture('setup');
      await fixture('family');
      final a = ReconnectClient(), b = ReconnectClient();
      await a.open('h2c2b1-a', 'client-a');
      await b.open('h2c2b1-b', 'client-b');
      expect(identical(a.app, b.app), isFalse);
      expect(identical(a.auth, b.auth), isFalse);
      expect(identical(a.db, b.db), isFalse);
      expect(identical(a.client, b.client), isFalse);
      expect(a.box.database.path, isNot(b.box.database.path));

      for (final order in ['a-first', 'b-first', 'together', 'flap']) {
        final name = 'offline milk $order';
        await seed(a, b, name, 1000, 'ml');
        final beforeA = item(a, name), beforeB = item(b, name);
        expect(beforeA.revision, beforeB.revision);
        await offlineBoth(a, b);
        final commands = await Future.wait([
          a.add(name, 300, 'ml'),
          b.add(name, 2, 'l'),
        ]);
        final ac = commands[0], bc = commands[1];
        expect(ac.id, isNot(bc.id));
        expect(item(a, name).quantity, 1300);
        expect(item(b, name).quantity, 3000);
        expect(item(a, name).pending, isTrue);
        expect(item(b, name).pending, isTrue);
        expect((await row(ac)).status, ShoppingMutationStatus.pending);
        expect((await row(bc)).status, ShoppingMutationStatus.pending);
        await cachedCanonical(a, beforeA);
        await cachedCanonical(b, beforeB);
        await a.unchanged();
        await b.unchanged();

        if (order == 'together') {
          await Future.wait([connect(ac), connect(bc)]);
          final receipts = await process(commands);
          expect(receipts.map((r) => r['status']), everyElement('APPLIED'));
        } else {
          final first = order == 'b-first' ? bc : ac;
          final second = order == 'b-first' ? ac : bc;
          await connect(first);
          if (order == 'flap') {
            // Command exists, but no result exists yet. Drop only A's Firestore
            // network; server executes while A cannot observe its receipt.
            await a.db.disableNetwork();
            expect((await process([first])).single['status'], 'APPLIED');
            await a.client.settled;
            expect((await row(first)).status.terminal, isFalse);
            expect(item(a, name).pending, isTrue);
            await a.unchanged();
            await a.db.enableNetwork();
          } else {
            expect((await process([first])).single['status'], 'APPLIED');
          }
          await first.client.done();
          await first.client.visible(
            () => first.client.client.items.any(
              (i) =>
                  i.name == name &&
                  !i.pending &&
                  i.quantity == (first == ac ? 1300 : 3000),
            ),
          );
          // Second client remains offline, with its own intent and old canonical cache.
          final stillOffline = second == ac ? a : b;
          expect(item(stillOffline, name).quantity, second == ac ? 1300 : 3000);
          expect(item(stillOffline, name).pending, isTrue);
          await cachedCanonical(stillOffline, second == ac ? beforeA : beforeB);
          await connect(second);
          expect((await process([second])).single['status'], 'APPLIED');
        }
        final docs = await converge(a, b);
        final milk = docs.where((d) => d.get('name') == name).single;
        expect(milk.get('quantity'), 3300);
        expect(milk.get('unit'), 'ml');
        await a.unchanged();
        await b.unchanged();
        expect(await a.box.notices(a.uid), isEmpty);
        expect(await b.box.notices(b.uid), isEmpty);
      }

      // Four independent conflicts; last case makes B win and A become stale.
      for (final scenario in ['edit-a', 'delete-a', 'check-a', 'delete-b']) {
        final name = 'offline $scenario';
        await seed(a, b, name, 10, 'db');
        final winner = scenario.endsWith('-b') ? b : a;
        final loser = winner == a ? b : a;
        final won = item(winner, name), lost = item(loser, name);
        expect(won.revision, lost.revision);
        await offlineBoth(a, b);
        final wc = await winner.accept(
          () => winner.repository.updateItem(
            id: won.id,
            observed: won,
            name: won.name,
            quantity: 510,
            unit: won.unit,
          ),
        );
        final lc = await loser.accept(
          () => switch (scenario.split('-').first) {
            'edit' => loser.repository.updateItem(
              id: lost.id,
              observed: lost,
              name: lost.name,
              quantity: 12,
              unit: lost.unit,
            ),
            'delete' => loser.repository.deleteItem(lost.id, observed: lost),
            _ => loser.repository.setItemChecked(
              id: lost.id,
              observed: lost,
              isChecked: true,
            ),
          },
        );
        expect(
          (await row(wc)).request.children.single.expectedRevision,
          won.revision,
        );
        expect(
          (await row(lc)).request.children.single.expectedRevision,
          lost.revision,
        );
        expect(item(winner, name).quantity, 510);
        expect(item(winner, name).pending, isTrue);
        if (scenario.startsWith('delete')) {
          expect(loser.client.items.any((i) => i.id == lost.id), isFalse);
        } else {
          expect(item(loser, name).pending, isTrue);
          if (scenario.startsWith('edit')) {
            expect(item(loser, name).quantity, 12);
          }
          if (scenario.startsWith('check')) {
            expect(item(loser, name).isChecked, isTrue);
          }
        }
        await cachedCanonical(winner, won);
        await cachedCanonical(loser, lost);
        await connect(wc);
        expect((await process([wc])).single['status'], 'APPLIED');
        await winner.done();
        await winner.visible(
          () => winner.client.items.any(
            (i) =>
                i.id == won.id &&
                i.quantity == 510 &&
                !i.pending &&
                i.revision > won.revision,
          ),
        );
        await cachedCanonical(loser, lost);
        expect((await row(lc)).status.terminal, isFalse);
        await connect(lc);
        expect((await process([lc])).single['status'], 'REJECTED_STALE');
        final docs = await converge(a, b);
        final preserved = docs.singleWhere((d) => d.id == won.id);
        expect(preserved.get('quantity'), 510);
        expect(preserved.get('isChecked'), isFalse);
        expect(item(loser, name).quantity, 510);
        expect(item(loser, name).pending, isFalse);
        await loser.visible(() => loser.client.notice != null);
        expect(winner.client.notice, isNull);
        expect(await winner.box.notices(winner.uid), isEmpty);
        expect(
          (await loser.box.notices(loser.uid)).single.request.mutationId,
          lc.id,
        );
        await a.unchanged();
        await b.unchanged();
        await loser.client.acknowledgeNotice();
        await loser.visible(() => loser.client.notice == null);
      }

      final allIds = <String>{};
      for (final c in [a, b]) {
        await c.unchanged();
        expect(
          await c.box.entries(c == a ? b.uid : a.uid, includeTerminal: true),
          isEmpty,
        );
        final server = await c.db
            .collection('users/${c.uid}/shoppingMutations')
            .get(const GetOptions(source: Source.server));
        expect(server.docs.map((d) => d.id).toSet(), c.originals.keys.toSet());
        for (final local in await c.box.entries(c.uid, includeTerminal: true)) {
          expect(allIds.add(local.request.mutationId), isTrue);
          expect(local.request.context.uid, c.uid);
          expect(local.status.terminal, isTrue);
          final receipt = server.docs.singleWhere(
            (d) => d.id == local.request.mutationId,
          );
          expect(receipt.get('actorUid'), c.uid);
          expect(jsonDecode(local.resultJson!), receipt.get('results'));
        }
        c.listeners();
      }
      expect(allIds, hasLength(24));
      await a.close();
      await b.close();
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
