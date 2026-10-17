import 'dart:async';
import 'dart:convert';
import 'household_gateway.dart';

abstract interface class HouseholdContextStorage {
  Future<String?> read(String uid);
  Future<void> write(String uid, String value);
  Future<void> clear(String uid);
}

class HouseholdSessionChanged implements Exception {}

/// Cache is a routing hint, never membership authorization. Server rules decide
/// whether cached/offline-queued operations may commit on reconnect.
class CachedHouseholdGateway implements ObservableHouseholdGateway {
  CachedHouseholdGateway({
    required this.currentUid,
    required this.sessions,
    required this.authoritative,
    required this.storage,
    required this.isTransient,
    required this.serverChanges,
  });
  final String? Function() currentUid;
  final Stream<String?> sessions;
  final HouseholdGateway authoritative;
  final HouseholdContextStorage storage;
  final bool Function(Object) isTransient;
  // Only server-confirmed metadata changes, never pending/cache snapshots.
  final Stream<String?> Function(String uid) serverChanges;
  final _events = StreamController<({String uid, String? id})>.broadcast(
    sync: true,
  );
  final _flights = <String, Future<String>>{};
  final _blocked = <String>{};
  final _backgroundChecks = <String>{};
  String? _lastEnsureUid;
  final _remoteStreams = <String, Stream<String?>>{};

  // Gate and repository share one native root subscription. Release it when
  // the last consumer leaves; a later session gets a fresh subscription.
  Stream<String?> _remoteFor(String uid) => _remoteStreams.putIfAbsent(uid, () {
    late StreamController<String?> controller;
    StreamSubscription<String?>? subscription;
    controller = StreamController<String?>.broadcast(
      sync: true,
      onListen: () {
        subscription = serverChanges(
          uid,
        ).listen(controller.add, onError: controller.addError);
      },
      onCancel: () {
        _remoteStreams.remove(uid);
        unawaited(subscription?.cancel());
      },
    );
    return controller.stream;
  });

  String? _decode(String? raw, String uid) {
    try {
      final value = jsonDecode(raw ?? '');
      if (value is Map &&
          value.length == 3 &&
          value['version'] == 1 &&
          value['uid'] == uid &&
          value['householdId'] is String &&
          RegExp(
            r'^[a-zA-Z0-9_-]{1,128}$',
          ).hasMatch(value['householdId'] as String)) {
        return value['householdId'] as String;
      }
    } catch (_) {
      /* Invalid local state cannot authorize first use. */
    }
    return null;
  }

  Future<T> _session<T>(
    Future<T> Function(String, void Function()) action,
  ) async {
    final uid = currentUid();
    if (uid == null) throw HouseholdSessionChanged();
    var changed = false;
    final sub = sessions.listen((u) {
      if (u != uid) {
        changed = true;
        _backgroundChecks.remove(uid);
      }
    });
    void check() {
      if (changed || currentUid() != uid) throw HouseholdSessionChanged();
    }

    try {
      check();
      return await action(uid, check);
    } finally {
      unawaited(sub.cancel());
    }
  }

  @override
  Future<String> ensure() => _session((uid, check) async {
    if (_lastEnsureUid != uid) {
      _backgroundChecks.clear();
      _lastEnsureUid = uid;
    }
    String? raw;
    try {
      raw = await storage.read(uid);
    } catch (_) {
      /* Require server. */
    }
    check();
    final cached = _blocked.contains(uid) ? null : _decode(raw, uid);
    if (cached != null) {
      // No network wait on an already verified account; errors handled below.
      if (_backgroundChecks.add(uid)) {
        unawaited(
          refresh().then<void>((_) {}, onError: (Object _, StackTrace _) {}),
        );
      }
      return cached;
    }
    final result = await refresh();
    check();
    return result;
  });

  @override
  Future<String> refresh() => _session((uid, check) async {
    final existing = _flights[uid];
    if (existing != null) {
      final result = await existing;
      check();
      return result;
    }
    final future = _refresh(uid, check);
    _flights[uid] = future;
    try {
      return await future;
    } finally {
      if (identical(_flights[uid], future)) _flights.remove(uid);
    }
  });

  Future<String> _refresh(String uid, void Function() check) async {
    try {
      final id = await authoritative.ensure();
      check();
      if (!RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(id)) {
        throw StateError('Invalid household');
      }
      // A persistence failure must not invalidate a valid online result.
      try {
        await storage.write(
          uid,
          jsonEncode({'version': 1, 'uid': uid, 'householdId': id}),
        );
      } catch (_) {}
      check();
      _blocked.remove(uid);
      _backgroundChecks.add(uid);
      _events.add((uid: uid, id: id));
      return id;
    } catch (error) {
      check();
      if (error is! HouseholdSessionChanged && !isTransient(error)) {
        _blocked.add(uid);
        try {
          await storage.clear(uid);
        } catch (_) {}
        check();
        _events.add((uid: uid, id: null));
      }
      rethrow;
    }
  }

  @override
  Stream<String> watch() {
    final uid = currentUid();
    late StreamController<String> controller;
    StreamSubscription<String?>? authSub, remoteSub;
    StreamSubscription<({String uid, String? id})>? eventSub;
    var closed = false;
    String? last;
    var eventEpoch = 0;
    void emit(String id) {
      if (!closed &&
          !_blocked.contains(uid) &&
          currentUid() == uid &&
          last != id) {
        last = id;
        controller.add(id);
      }
    }

    void fail(Object error) {
      if (!closed) controller.addError(error);
    }

    controller = StreamController<String>(
      onListen: () {
        if (uid == null) {
          fail(HouseholdSessionChanged());
          return;
        }
        authSub = sessions.listen((u) {
          if (u != uid && !closed) {
            _backgroundChecks.remove(uid);
            fail(HouseholdSessionChanged());
            closed = true;
            unawaited(remoteSub?.cancel());
            unawaited(eventSub?.cancel());
            unawaited(controller.close());
          }
        });
        eventSub = _events.stream.listen((event) {
          if (event.uid != uid || closed) return;
          eventEpoch++;
          if (event.id == null) {
            last = null;
            fail(StateError('Household unavailable'));
          } else {
            emit(event.id!);
          }
        });
        remoteSub = _remoteFor(uid).listen(
          (id) {
            if (!closed) {
              unawaited(
                refresh().then<void>(
                  emit,
                  onError: (Object error, StackTrace _) {
                    if (!isTransient(error)) fail(error);
                  },
                ),
              );
            }
          },
          onError: (Object error) {
            if (!isTransient(error)) {
              unawaited(
                refresh().then<void>(
                  emit,
                  onError: (Object e, StackTrace _) {
                    if (!isTransient(e)) fail(e);
                  },
                ),
              );
            }
          },
        );
        final initialEpoch = eventEpoch;
        unawaited(
          ensure().then<void>((id) {
            if (eventEpoch == initialEpoch) emit(id);
          }, onError: (Object error, StackTrace _) => fail(error)),
        );
      },
      onCancel: () async {
        closed = true;
        await authSub?.cancel();
        await remoteSub?.cancel();
        await eventSub?.cancel();
      },
    );
    return controller.stream;
  }
}
