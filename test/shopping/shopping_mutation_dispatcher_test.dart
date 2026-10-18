import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kuktam/shopping/domain/shopping_mutation.dart';
import 'package:kuktam/shopping/data/mutations/shopping_mutation_dispatcher.dart';
import 'package:kuktam/shopping/data/mutations/shopping_mutation_transport.dart';
import 'package:kuktam/shopping/data/mutations/shopping_outbox.dart';
import 'shopping_mutation_contract_test.dart' show testContext;

class _Transport implements ShoppingMutationTransport {
  bool failObserve = false;
  final events = StreamController<ShoppingReceiptSnapshot>.broadcast(
    sync: true,
  );
  final sent = <ShoppingMutationRequest>[];
  final observed = <(String, List<String>)>[];
  final lookups = <String>[];
  final server = <String, Map<String, dynamic>>{};
  Future<void> Function(ShoppingMutationRequest)? send;
  @override
  Stream<ShoppingReceiptSnapshot> observe(String uid, List<String> ids) {
    if (failObserve) throw StateError('listener unavailable');
    observed.add((uid, ids));
    return events.stream;
  }

  @override
  Future<void> create(ShoppingMutationRequest request) {
    sent.add(request);
    return send?.call(request) ?? Future.value();
  }

  @override
  Future<ShoppingReceiptSnapshot> lookup(String uid, List<String> ids) async {
    lookups.addAll(ids);
    return ShoppingReceiptSnapshot(
      fromServer: true,
      documents: {
        for (final id in ids)
          if (server.containsKey(id)) id: server[id]!,
      },
    );
  }
}

void main() {
  sqfliteFfiInit();
  late ShoppingOutbox outbox;
  late ShoppingMutationDispatcher dispatcher;
  late _Transport transport;
  String? uid;
  ShoppingMutationRequest request([String actor = 'a']) =>
      ShoppingMutationRequest.create(
        context: testContext(actor),
        children: [
          ShoppingMutationChild.add(name: 'tea', quantity: 1, unit: 'db'),
        ],
      );
  Map<String, dynamic> receipt(
    ShoppingMutationRequest r, [
    String status = 'APPLIED',
  ]) => {
    ...r.toJson(),
    'requestHash': r.requestHash,
    'status': status,
    'results': [
      {'code': status, 'itemId': 'server-item', 'revision': 4},
    ],
  }..remove('payloadJson');
  Future<void> emit(
    Map<String, Map<String, dynamic>> documents, {
    bool server = true,
  }) async {
    transport.events.add(
      ShoppingReceiptSnapshot(fromServer: server, documents: documents),
    );
    await dispatcher.settled;
  }

  setUp(() async {
    uid = 'a';
    transport = _Transport();
    outbox = await ShoppingOutbox.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    dispatcher = ShoppingMutationDispatcher(
      outbox: outbox,
      transport: transport,
      currentUid: () => uid,
      clock: () => DateTime.utc(2026),
    );
    await dispatcher.bind(uid);
  });
  tearDown(() async {
    await dispatcher.close();
    await transport.events.close();
    await outbox.close();
  });
  test(
    'observer start failure cannot undo a successfully accepted enqueue',
    () async {
      final r = request();
      transport.failObserve = true;
      await dispatcher.enqueue(r);
      expect(
        (await outbox.entries('a')).single.request.mutationId,
        r.mutationId,
      );
      transport.failObserve = false;
      await dispatcher.recoverObservation();
      await emit({});
      expect(transport.sent.single.mutationId, r.mutationId);
    },
  );
  test(
    'late queued absence after terminal receipt never replays completed action',
    () async {
      final r = request();
      await dispatcher.enqueue(r);
      transport.events.add(
        ShoppingReceiptSnapshot(
          fromServer: true,
          documents: {r.mutationId: receipt(r)},
        ),
      );
      transport.events.add(
        const ShoppingReceiptSnapshot(fromServer: true, documents: {}),
      );
      await dispatcher.settled;
      expect(transport.sent, isEmpty);
      expect(await outbox.entries('a'), isEmpty);
    },
  );
  test(
    'unknown receipt state fails closed instead of displaying applied',
    () async {
      final r = request();
      await dispatcher.enqueue(r);
      await emit({r.mutationId: receipt(r, 'UNKNOWN')});
      expect(
        (await outbox.entries('a', includeTerminal: true)).single.status,
        ShoppingMutationStatus.failedTerminal,
      );
      expect(transport.sent, isEmpty);
    },
  );
  test('network event retry retains exact mutation bytes', () async {
    final r = request();
    final failed = Completer<void>();
    transport.send = (_) {
      failed.complete();
      return Future.error(
        FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
      );
    };
    await dispatcher.enqueue(r);
    await emit({});
    await failed.future;
    // Drain the Future error callback, without a wall-clock retry timer.
    await Future<void>.value();
    transport.send = (_) => Future.value();
    await emit({});
    expect(transport.sent, hasLength(2));
    expect(transport.sent[0].toJson(), transport.sent[1].toJson());
  });
  test(
    'offline enqueue returns after durable commit without remote acknowledgement',
    () async {
      final blocked = Completer<void>();
      transport.send = (_) => blocked.future;
      final r = request();
      await dispatcher.enqueue(r);
      expect(await outbox.entries('a'), hasLength(1));
      await emit({}, server: false);
      expect(transport.sent, isEmpty);
      await emit({});
      expect(transport.sent.single.mutationId, r.mutationId);
      expect(
        (await outbox.entries('a')).single.status,
        ShoppingMutationStatus.pending,
      );
      blocked.complete();
    },
  );
  test(
    'repeated absence events never submit the same ID twice in one session',
    () async {
      final r = request();
      await dispatcher.enqueue(r);
      await emit({});
      await emit({});
      await emit({});
      expect(transport.sent, hasLength(1));
    },
  );
  test(
    'local pending snapshot cannot be treated as applied server receipt',
    () async {
      final r = request();
      await dispatcher.enqueue(r);
      await emit({r.mutationId: receipt(r)}, server: false);
      expect(await outbox.entries('a'), hasLength(1));
      await emit({r.mutationId: receipt(r)});
      expect(await outbox.entries('a'), isEmpty);
      expect(transport.sent, isEmpty);
    },
  );
  test('altered receipt hash fails closed without replay', () async {
    final r = request();
    await dispatcher.enqueue(r);
    await emit({
      r.mutationId: {...receipt(r), 'requestHash': 'wrong'},
    });
    expect(
      (await outbox.entries('a', includeTerminal: true)).single.status,
      ShoppingMutationStatus.failedTerminal,
    );
    expect(transport.sent, isEmpty);
  });
  test('one result observer has at most ten active parent IDs', () async {
    final requests = List.generate(11, (_) => request());
    for (final r in requests) {
      await dispatcher.enqueue(r);
    }
    expect(transport.observed.last.$2, hasLength(10));
    expect(transport.observed.every((q) => q.$2.length <= 10), true);
    await emit({requests.first.mutationId: receipt(requests.first)});
    expect(transport.observed.last.$2, contains(requests.last.mutationId));
  });
  test(
    'sign out A then B cannot dispatch A; returning A preserves identity',
    () async {
      final a = request();
      await dispatcher.enqueue(a);
      uid = null;
      await dispatcher.bind(null);
      uid = 'b';
      await dispatcher.bind(uid);
      await emit({});
      expect(transport.sent, isEmpty);
      await expectLater(dispatcher.enqueue(a), throwsStateError);
      final b = request('b');
      await dispatcher.enqueue(b);
      await emit({});
      expect(transport.sent.single.context.uid, 'b');
      uid = 'a';
      await dispatcher.bind(uid);
      await emit({});
      expect(transport.sent.last.mutationId, a.mutationId);
      expect(
        (await outbox.entries('a')).single.request.context.householdId,
        'home',
      );
    },
  );
  test('expired missing result never generates replacement command', () async {
    await dispatcher.close();
    dispatcher = ShoppingMutationDispatcher(
      outbox: outbox,
      transport: transport,
      currentUid: () => uid,
      clock: () => DateTime.utc(2040),
    );
    await dispatcher.bind(uid);
    final r = request();
    await dispatcher.enqueue(r);
    await emit({});
    expect(transport.sent, isEmpty);
    expect(
      (await outbox.entries('a', includeTerminal: true)).single.status,
      ShoppingMutationStatus.resultExpired,
    );
  });
  test(
    'FAILED_RETRYABLE stays in durable queue and never mints a new ID',
    () async {
      final r = request();
      await dispatcher.enqueue(r);
      await emit({r.mutationId: receipt(r, 'FAILED_RETRYABLE')});
      expect(
        (await outbox.entries('a')).single.request.mutationId,
        r.mutationId,
      );
      expect(transport.sent, isEmpty);
    },
  );
  for (final code in [
    'REJECTED_STALE',
    'REJECTED_CONTEXT_CHANGED',
    'REJECTED_NOT_FOUND',
    'REJECTED_UNAUTHORIZED',
    'FAILED_TERMINAL',
    'PARTIAL',
  ]) {
    test(
      '$code persists result without automatic rebase/resubmission',
      () async {
        final r = request();
        await dispatcher.enqueue(r);
        await emit({r.mutationId: receipt(r, code)});
        expect(await outbox.entries('a'), isEmpty);
        expect(
          (await outbox.entries(
            'a',
            includeTerminal: true,
          )).single.noticeAcknowledged,
          false,
        );
        expect(transport.sent, isEmpty);
      },
    );
  }
  test(
    'duplicate-create permission denial resolves existing APPLIED receipt',
    () async {
      final r = request();
      transport.server[r.mutationId] = receipt(r);
      final changed = dispatcher.changes.first;
      await dispatcher.enqueue(r);
      await changed;
      transport.send = (_) => Future.error(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
      );
      final result = dispatcher.changes.first;
      await emit({});
      await result;
      expect(transport.lookups, [r.mutationId]);
      expect(
        (await outbox.entries('a', includeTerminal: true)).single.status,
        ShoppingMutationStatus.applied,
      );
    },
  );
}
