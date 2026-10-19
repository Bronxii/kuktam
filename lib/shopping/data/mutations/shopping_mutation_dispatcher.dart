import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/shopping_mutation.dart';
import 'shopping_mutation_transport.dart';
import 'shopping_outbox.dart';
import 'shopping_intent_queue.dart';

/// The app owns one dispatcher. UID changes invalidate callbacks immediately;
/// SQLite work remains UID-bound. Network retries keep the original identity.
class ShoppingMutationDispatcher {
  ShoppingMutationDispatcher({
    required this.outbox,
    required this.transport,
    required this.currentUid,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;
  final ShoppingOutbox outbox;
  final ShoppingMutationTransport transport;
  final String? Function() currentUid;
  final DateTime Function() clock;
  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;
  StreamSubscription<ShoppingReceiptSnapshot>? _observer;
  String? _uid;
  int _generation = 0;
  String _observedKey = '';
  final _sending = <String>{};
  Future<void> _tail = Future.value();
  bool _closed = false;

  /// Allows lifecycle owners/tests to await already-delivered local receipt work.
  /// This does not wait for the network or trigger a request.
  Future<void> get settled => _tail;

  bool _current(String uid, int generation) =>
      !_closed &&
      generation == _generation &&
      uid == _uid &&
      currentUid() == uid;

  Future<void> bind(String? uid) async {
    _generation++;
    _uid = uid;
    _observedKey = '';
    _sending.clear();
    final previous = _observer;
    _observer = null;
    await previous?.cancel();
    if (!_closed) _changes.add(null);
    if (uid != null) {
      await ShoppingIntentQueue(outbox).materialize(uid);
      await refresh();
    }
  }

  Future<void> enqueue(ShoppingMutationRequest request) async {
    final uid = request.context.uid, generation = _generation;
    if (!_current(uid, generation)) {
      throw StateError('Shopping session changed');
    }
    await outbox.enqueue(request);
    // If auth changed during durable commit, retain A's action, never expose it
    // to B or turn it into a new action. The UI sees session cancellation.
    if (!_current(uid, generation)) {
      throw StateError('Shopping session changed');
    }
    _changes.add(null);
    try {
      await refresh();
    } catch (_) {
      // Enqueue already committed. A listener-start failure must not turn this
      // into a failed submission and tempt the UI to create a second action.
      // Explicit lifecycle recovery reopens observation of the same journal.
      _observedKey = '';
    }
  }

  Future<void> recoverObservation() async {
    _observedKey = '';
    await refresh();
  }

  Future<void> enqueueIntent(
    ShoppingMutationRequest draft, {
    Map<int, ShoppingIntentDependency> dependencies = const {},
    List<Map<String, Object?>?> observations = const [],
  }) async {
    final uid = draft.context.uid, generation = _generation;
    if (!_current(uid, generation)) {
      throw StateError('Shopping session changed');
    }
    await ShoppingIntentQueue(
      outbox,
    ).enqueue(draft, dependencies: dependencies, observations: observations);
    if (!_current(uid, generation)) {
      throw StateError('Shopping session changed');
    }
    _changes.add(null);
    try {
      await refresh();
    } catch (_) {
      _observedKey = '';
    }
  }

  Future<void> enqueueIntents(
    List<
      ({
        ShoppingMutationRequest draft,
        Map<int, ShoppingIntentDependency> dependencies,
        List<Map<String, Object?>?> observations,
      })
    >
    actions,
  ) async {
    if (actions.isEmpty) return;
    final uid = actions.first.draft.context.uid, generation = _generation;
    if (!_current(uid, generation) ||
        actions.any((a) => a.draft.context.uid != uid)) {
      throw StateError('Shopping session changed');
    }
    await ShoppingIntentQueue(outbox).enqueueMany(actions);
    if (!_current(uid, generation)) {
      throw StateError('Shopping session changed');
    }
    _changes.add(null);
    try {
      await refresh();
    } catch (_) {
      _observedKey = '';
    }
  }

  Future<void> refresh() async {
    final uid = _uid, generation = _generation;
    if (uid == null || !_current(uid, generation)) return;
    final pending = (await outbox.entries(uid)).take(10).toList();
    if (!_current(uid, generation)) return;
    final ids = pending.map((e) => e.request.mutationId).toList();
    final key = ids.join('/');
    if (key == _observedKey) return;
    _observedKey = key;
    await _observer?.cancel();
    if (!_current(uid, generation) || key != _observedKey) return;
    _observer = null;
    if (ids.isEmpty) return;
    _observer = transport
        .observe(uid, ids)
        .listen(
          (snapshot) {
            // Serial local receipt commits; listener events never race terminal state.
            _tail = _tail
                .then((_) => _consume(uid, generation, pending, snapshot))
                .catchError((Object _) {
                  // Storage/protocol failure leaves immutable work intact for recovery.
                  // No raw Firebase errors or shopping payloads are logged.
                });
          },
          onError: (Object _) {
            // A stream error is not evidence of write rejection. Durable work survives.
            // Rebinding on a new authenticated session is safe and does not change IDs.
          },
        );
  }

  Future<void> _consume(
    String uid,
    int generation,
    List<ShoppingOutboxEntry> entries,
    ShoppingReceiptSnapshot snapshot,
  ) async {
    if (!_current(uid, generation)) return;
    final stillPending = (await outbox.entries(
      uid,
    )).map((e) => e.request.mutationId).toSet();
    var changed = false;
    for (final entry in entries) {
      if (!_current(uid, generation)) return;
      if (!stillPending.contains(entry.request.mutationId)) continue;
      final r = entry.request,
          data = snapshot.documents[entry.request.mutationId];
      if (data != null) {
        // Local pending writes are not authoritative receipts.
        if (!snapshot.fromServer) continue;
        final hash = data['requestHash'];
        final same =
            data['actorUid'] == uid &&
            data['householdId'] == r.context.householdId &&
            data['epoch'] == r.context.epoch &&
            data['mutationId'] == r.mutationId &&
            data['schemaVersion'] == 1 &&
            data['kind'] == r.type.wire &&
            (hash != null
                ? hash == r.requestHash
                : data['payloadJson'] == r.payloadJson);
        if (!same) {
          await outbox.recordResult(
            uid,
            r.mutationId,
            ShoppingMutationStatus.failedTerminal,
          );
          _sending.remove(r.mutationId);
        } else {
          ShoppingMutationStatus status;
          try {
            status = ShoppingMutationStatusContract.parse(
              data['status'] as String?,
            );
          } catch (_) {
            status = ShoppingMutationStatus.failedTerminal;
          }
          await outbox.recordResult(
            uid,
            r.mutationId,
            status,
            resultJson: jsonEncode(data['results'] ?? []),
          );
          if (status.terminal) _sending.remove(r.mutationId);
        }
        changed = true;
      } else if (snapshot.fromServer) {
        if (!r.context.expiresAt.isAfter(clock())) {
          // Cannot distinguish never applied from a receipt cleaned long ago.
          await outbox.recordResult(
            uid,
            r.mutationId,
            ShoppingMutationStatus.resultExpired,
          );
          changed = true;
        } else if (_sending.add(r.mutationId)) {
          // Do not await remote acknowledgement: local enqueue already committed.
          unawaited(_send(uid, generation, r));
        }
      }
    }
    if (changed && _current(uid, generation)) {
      await ShoppingIntentQueue(outbox).materialize(uid);
      _changes.add(null);
      await refresh();
    }
  }

  Future<void> _send(
    String uid,
    int generation,
    ShoppingMutationRequest request,
  ) async {
    try {
      if (!_current(uid, generation)) return;
      await transport.create(request);
    } catch (error) {
      if (!_current(uid, generation)) return;
      if (error is FirebaseException &&
          [
            'unavailable',
            'deadline-exceeded',
            'network-request-failed',
          ].contains(error.code)) {
        // Only a subsequent authoritative network snapshot may retry. No timer,
        // no busy loop, and the exact persisted request is reused.
        _sending.remove(request.mutationId);
        return;
      }
      // A duplicate-create rejection can race a successful delivery. Do not turn
      // permission-denied into a terminal failure without checking the receipt.
      // The next authoritative query snapshot resolves the existing result.
      if (error is FirebaseException && error.code == 'permission-denied') {
        try {
          final receipt = await transport.lookup(uid, [request.mutationId]);
          if (!_current(uid, generation)) return;
          if (receipt.documents.containsKey(request.mutationId)) {
            await _consume(uid, generation, [
              ShoppingOutboxEntry(
                request,
                ShoppingMutationStatus.pending,
                null,
                false,
              ),
            ], receipt);
          } else {
            var outcome = ShoppingMutationStatus.rejectedUnauthorized;
            final inspector = transport;
            if (inspector is ShoppingRejectedContextInspector &&
                await (inspector as ShoppingRejectedContextInspector)
                    .contextChanged(request)) {
              outcome = ShoppingMutationStatus.rejectedContextChanged;
            }
            if (!_current(uid, generation)) return;
            await outbox.recordResult(uid, request.mutationId, outcome);
            if (_current(uid, generation)) {
              await ShoppingIntentQueue(outbox).materialize(uid);
              _changes.add(null);
              await refresh();
            }
          }
        } catch (_) {
          // Uncertain historical result remains pending; never mint a new ID.
        }
      }
    }
  }

  Future<void> close() async {
    _closed = true;
    _generation++;
    await _observer?.cancel();
    await _tail;
    await _changes.close();
  }
}
