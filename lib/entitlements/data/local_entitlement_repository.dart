import 'dart:async';
import '../domain/models/entitlement_snapshot.dart';
import '../domain/repositories/entitlement_repository.dart';
import 'entitlement_cache.dart';
import 'entitlement_contracts.dart';

/// Client core. Auth integration must call initialize/clear immediately
/// on UID change, and reevaluate on resume. No Firebase/Billing calls or UI.
final class LocalEntitlementRepository implements EntitlementRepository {
  LocalEntitlementRepository({
    required this.backend,
    required this.storage,
    required this.clock,
  });
  final TrustedEntitlementBackend backend;
  final EntitlementCacheStorage storage;
  final EntitlementClock clock;
  static const rollbackTolerance = Duration(minutes: 5);
  final _events = StreamController<ClientEntitlementState>.broadcast();
  Future<void> _io = Future.value();
  ClientEntitlementState _state = const ClientEntitlementState(
    ClientEntitlementStatus.unknown,
  );
  String? _uid;
  int _session = 0, _request = 0;
  bool _disposed = false, _suspicious = false, _online = false;
  final Set<String> _closedAccounts = {};
  EntitlementCache? _cache;
  Duration _anchorMono = Duration.zero;
  DateTime? _wallHigh;

  @override
  Stream<ClientEntitlementState> get changes => _events.stream;
  @override
  ClientEntitlementState get current =>
      (_cache == null || _state.status == ClientEntitlementStatus.checking)
      ? _state
      : _resolve(_state.failure);
  bool _valid(int session) => !_disposed && session == _session;
  Future<T> _storage<T>(Future<T> Function() action) {
    final task = _io.then((_) => action());
    _io = task.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return task;
  }

  void _emit(ClientEntitlementState s) {
    if (_disposed) return;
    _state = s;
    _events.add(s);
  }

  void _install(EntitlementCache c) {
    _cache = c;
    _suspicious = _suspicious || c.suspiciousClock;
    _anchorMono = clock.monotonicNow();
    _wallHigh = c.lastWall;
  }

  DateTime _estimated() {
    final c = _cache!,
        wall = clock.wallNow(),
        mono = clock.monotonicNow() - _anchorMono;
    if (wall.isBefore(_wallHigh!.subtract(rollbackTolerance)) ||
        mono.isNegative) {
      _suspicious = true;
    }
    if (wall.isAfter(_wallHigh!)) _wallHigh = wall;
    final delta = wall.difference(c.lastWall);
    final elapsed = delta > mono ? delta : mono;
    return c.estimatedAt.add(elapsed.isNegative ? Duration.zero : elapsed);
  }

  ClientEntitlementState _resolve([EntitlementFailure? failure]) {
    final c = _cache;
    if (c == null) {
      return ClientEntitlementState(
        ClientEntitlementStatus.unavailable,
        uid: _uid,
        failure: failure ?? EntitlementFailure.connectionRequired,
      );
    }
    final p = c.proof;
    if (!p.entitlement.active) {
      return ClientEntitlementState(
        ClientEntitlementStatus.free,
        uid: _uid,
        snapshot: EntitlementSnapshot.free(verifiedAt: p.trustedProofAt),
        failure: failure,
      );
    }
    final now = _estimated();
    if (_suspicious || !now.isBefore(p.effectiveLimit)) {
      return ClientEntitlementState(
        ClientEntitlementStatus.unavailable,
        uid: _uid,
        failure: _suspicious
            ? EntitlementFailure.suspiciousClock
            : EntitlementFailure.connectionRequired,
      );
    }
    return ClientEntitlementState(
      _online
          ? ClientEntitlementStatus.proOnline
          : ClientEntitlementStatus.proOfflineGrace,
      uid: _uid,
      snapshot: EntitlementSnapshot.pro(
        validUntil: p.entitlement.validUntil,
        verifiedAt: p.trustedProofAt,
        offlineValidUntil: p.offlineValidUntil,
      ),
      failure: failure,
    );
  }

  @override
  Future<void> initializeForUser(
    String uid, {
    bool refreshOnline = true,
  }) async {
    validateUid(uid);
    if (_disposed) return;
    final previous = _uid, s = ++_session;
    final initialRequest = ++_request;
    _uid = uid;
    _cache = null;
    _suspicious = false;
    _online = false;
    _emit(ClientEntitlementState(ClientEntitlementStatus.checking, uid: uid));
    try {
      final raw = await _storage(() async {
        if (previous != null && previous != uid) await storage.clear();
        return storage.read();
      });
      if (!(_valid(s) && initialRequest == _request)) return;
      if (_closedAccounts.contains(uid)) {
        _emit(
          ClientEntitlementState(
            ClientEntitlementStatus.unavailable,
            uid: uid,
            failure: EntitlementFailure.accountDeleted,
          ),
        );
        return;
      }
      if (raw != null) {
        try {
          _install(EntitlementCache.decode(raw, uid));
        } catch (_) {
          await _storage(() async {
            if ((_valid(s) && initialRequest == _request)) {
              await storage.clear();
            }
          });
          if (!(_valid(s) && initialRequest == _request)) return;
          _emit(
            ClientEntitlementState(
              ClientEntitlementStatus.unavailable,
              uid: uid,
              failure: EntitlementFailure.malformedCache,
            ),
          );
        }
      }
    } catch (_) {
      if ((_valid(s) && initialRequest == _request)) {
        _emit(
          ClientEntitlementState(
            ClientEntitlementStatus.unavailable,
            uid: uid,
            failure: EntitlementFailure.storageFailure,
          ),
        );
      }
    }
    if (!(_valid(s) && initialRequest == _request)) return;
    if (refreshOnline) {
      await refresh();
    } else {
      await reevaluate();
    }
  }

  @override
  Future<void> refresh() async {
    if (_disposed || _uid == null || _closedAccounts.contains(_uid)) return;
    final uid = _uid!, s = _session, r = ++_request;
    _emit(ClientEntitlementState(ClientEntitlementStatus.checking, uid: uid));
    try {
      final proof = await backend.fetchProof(uid);
      if (!_valid(s) || r != _request) return;
      if (proof.uid != uid) {
        throw const EntitlementBackendException(
          EntitlementFailure.malformedEntitlement,
        );
      }
      final old = _cache?.proof;
      if (old != null &&
          (proof.entitlement.revision < old.entitlement.revision ||
              proof.trustedProofAt.isBefore(old.trustedProofAt))) {
        _online = false;
        _emit(_resolve(EntitlementFailure.staleProof));
        return;
      }
      if (old != null &&
          proof.entitlement.revision == old.entitlement.revision &&
          !proof.entitlement.sameEffective(old.entitlement)) {
        throw const EntitlementBackendException(
          EntitlementFailure.malformedEntitlement,
        );
      }
      // Same proof replay cannot reset the wall/monotonic anchors or clock hold.
      if (old != null &&
          proof.trustedProofAt == old.trustedProofAt &&
          proof.entitlement.revision == old.entitlement.revision) {
        _online = false;
        _emit(_resolve());
        return;
      }
      _suspicious = false;
      _online = true;
      _install(EntitlementCache(proof, clock.wallNow(), proof.trustedProofAt));
      _emit(
        _resolve(),
      ); // Inactive takes effect before potentially failing storage.
      try {
        await _storage(() async {
          if (_valid(s) && r == _request) await storage.write(_cache!.encode());
        });
      } catch (_) {
        if (_valid(s) && r == _request) {
          if (!proof.entitlement.active) {
            try {
              await _storage(() async {
                if (_valid(s) && r == _request) await storage.clear();
              });
            } catch (_) {
              /* Broken durable storage requires transport/operator recovery. */
            }
          }
          if (_valid(s) && r == _request) {
            _emit(_resolve(EntitlementFailure.storageFailure));
          }
        }
      }
    } catch (e) {
      if (!_valid(s) || r != _request) return;
      final failure = e is EntitlementBackendException
          ? e.failure
          : e is FormatException
          ? EntitlementFailure.malformedEntitlement
          : EntitlementFailure.serverUnavailable;
      _online = false;
      if (failure == EntitlementFailure.accountDeleting ||
          failure == EntitlementFailure.accountDeleted) {
        await invalidateAccount(failure);
        return;
      }
      if ([
        EntitlementFailure.accountDeleting,
        EntitlementFailure.accountDeleted,
        EntitlementFailure.unauthenticated,
        EntitlementFailure.permissionDenied,
      ].contains(failure)) {
        if (failure == EntitlementFailure.accountDeleting ||
            failure == EntitlementFailure.accountDeleted) {
          _closedAccounts.add(uid);
        }
        _cache = null;
        _emit(
          ClientEntitlementState(
            ClientEntitlementStatus.unavailable,
            uid: uid,
            failure: failure,
          ),
        );
        try {
          await _storage(() async {
            if (_valid(s)) await storage.clear();
          });
        } catch (_) {
          /* State stays fail-closed; no raw exception escapes. */
        }
      } else {
        _emit(_resolve(failure));
      }
    }
  }

  @override
  Future<void> reevaluate() async {
    if (_disposed || _uid == null) return;
    final s = _session, c = _cache;
    if (c != null) {
      final estimated = _estimated();
      {
        _install(
          EntitlementCache(
            c.proof,
            _wallHigh!,
            estimated,
            suspiciousClock: _suspicious,
          ),
        );
        try {
          await _storage(() async {
            if (_valid(s)) await storage.write(_cache!.encode());
          });
        } catch (_) {
          if (_valid(s)) _emit(_resolve(EntitlementFailure.storageFailure));
        }
      }
    }
    if (_valid(s)) _emit(_resolve(_state.failure));
  }

  /// A current authenticated backend operation confirmed terminal account state.
  /// Invalidates even an in-flight older proof; no new network call is needed.
  Future<void> invalidateAccount(EntitlementFailure failure) async {
    if (_disposed || _uid == null) return;
    if (failure != EntitlementFailure.accountDeleting &&
        failure != EntitlementFailure.accountDeleted) {
      throw ArgumentError('Expected account lifecycle failure');
    }
    final session = _session;
    _request++;
    _closedAccounts.add(_uid!);
    _cache = null;
    _online = false;
    _emit(
      ClientEntitlementState(
        ClientEntitlementStatus.unavailable,
        uid: _uid,
        failure: failure,
      ),
    );
    try {
      await _storage(() async {
        if (_valid(session)) await storage.clear();
      });
    } catch (_) {
      /* Remain fail-closed. Storage failure cannot grant this session. */
    }
  }

  @override
  Future<void> clearForLogout() async {
    if (_disposed) return;
    _session++;
    _request++;
    _uid = null;
    _cache = null;
    _online = false;
    _suspicious = false;
    _emit(const ClientEntitlementState(ClientEntitlementStatus.unknown));
    try {
      await _storage(storage.clear);
    } catch (_) {
      /* Nothing cached may grant this session. */
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _state = const ClientEntitlementState(ClientEntitlementStatus.unknown);
    _session++;
    _request++;
    _cache = null;
    _uid = null;
    await _io;
    await _events.close();
  }
}
