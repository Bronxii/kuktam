import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/entitlements/data/effective_entitlement_dto.dart';
import 'package:kuktam/entitlements/data/entitlement_cache.dart';
import 'package:kuktam/entitlements/data/entitlement_contracts.dart';
import 'package:kuktam/entitlements/data/local_entitlement_repository.dart';
import 'package:kuktam/entitlements/domain/models/pro_feature.dart';
import 'package:kuktam/entitlements/domain/models/feature_access_decision.dart';
import 'package:kuktam/entitlements/domain/repositories/entitlement_repository.dart';

final start = DateTime.utc(2026, 10, 8);
Map<String, dynamic> document({
  bool active = true,
  int revision = 1,
  DateTime? expiry,
  List<String>? sources,
}) => {
  'schemaVersion': 2,
  'active': active,
  'validUntil': expiry == null ? null : Timestamp.fromDate(expiry),
  'sources': sources ?? (active ? ['PLAY_PURCHASE'] : <String>[]),
  'revision': revision,
  'verifiedAt': Timestamp.fromDate(start),
  'updatedAt': Timestamp.fromDate(start),
};
TrustedEntitlementProof proof({
  String uid = 'a',
  bool active = true,
  int revision = 1,
  DateTime? at,
  DateTime? expiry,
  List<String>? sources,
}) => TrustedEntitlementProof(
  uid: uid,
  entitlement: EffectiveEntitlementDto.parse(
    document(
      active: active,
      revision: revision,
      expiry: expiry,
      sources: sources,
    ),
  ),
  trustedProofAt: at ?? start,
);

class Clock implements EntitlementClock {
  DateTime wall = start;
  Duration mono = Duration.zero;
  @override
  DateTime wallNow() => wall;
  @override
  Duration monotonicNow() => mono;
  void advance(Duration d) {
    wall = wall.add(d);
    mono += d;
  }
}

class Storage implements EntitlementCacheStorage {
  String? value;
  bool failRead = false, failWrite = false, failClear = false;
  Completer<void>? writeBarrier;
  Completer<void>? readBarrier;
  @override
  Future<String?> read() async {
    if (failRead) throw Exception('private storage details');
    final captured = value;
    await readBarrier?.future;
    return captured;
  }

  @override
  Future<void> write(String v) async {
    await writeBarrier?.future;
    if (failWrite) throw Exception('private storage details');
    value = v;
  }

  @override
  Future<void> clear() async {
    if (failClear) throw Exception('private storage details');
    value = null;
  }
}

class Backend implements TrustedEntitlementBackend {
  Future<TrustedEntitlementProof> Function(String) reply = (uid) async =>
      proof(uid: uid);
  @override
  Future<TrustedEntitlementProof> fetchProof(String uid) => reply(uid);
}

void main() {
  late Storage storage;
  late Clock clock;
  late Backend backend;
  late LocalEntitlementRepository repo;
  setUp(() {
    storage = Storage();
    clock = Clock();
    backend = Backend();
    repo = LocalEntitlementRepository(
      backend: backend,
      storage: storage,
      clock: clock,
    );
  });
  tearDown(() async {
    await repo.dispose();
  });
  void seed([TrustedEntitlementProof? p]) {
    storage.value = EntitlementCache(p ?? proof(), start, start).encode();
  }

  Future<void> offline() => repo.initializeForUser('a', refreshOnline: false);
  test('unknown and checking are distinct from Free', () async {
    expect(repo.current.status, ClientEntitlementStatus.unknown);
    final c = Completer<TrustedEntitlementProof>();
    backend.reply = (_) => c.future;
    final task = repo.initializeForUser('a');
    await Future<void>.delayed(Duration.zero);
    expect(repo.current.status, ClientEntitlementStatus.checking);
    c.complete(proof());
    await task;
    expect(repo.current.status, ClientEntitlementStatus.proOnline);
  });
  for (final active in [true, false]) {
    test('trusted startup active=$active', () async {
      backend.reply = (_) async => proof(active: active);
      await repo.initializeForUser('a');
      expect(
        repo.current.status,
        active
            ? ClientEntitlementStatus.proOnline
            : ClientEntitlementStatus.free,
      );
    });
  }
  test('offline startup with no cache is unavailable, not Free', () async {
    await offline();
    expect(repo.current.status, ClientEntitlementStatus.unavailable);
  });
  test('valid offline grace', () async {
    seed();
    await offline();
    expect(repo.current.status, ClientEntitlementStatus.proOfflineGrace);
  });
  for (final offset in [-1, 0, 1]) {
    test('exact 30 day boundary offset $offset microseconds', () async {
      seed();
      clock.advance(Duration(days: 30, microseconds: offset));
      await offline();
      expect(
        repo.current.status,
        offset < 0
            ? ClientEntitlementStatus.proOfflineGrace
            : ClientEntitlementStatus.unavailable,
      );
    });
  }
  for (final source in ['PROMO', 'ADMIN', 'TEST']) {
    for (final offset in [-1, 0, 1]) {
      test('$source expiry boundary $offset', () async {
        seed(
          proof(expiry: start.add(const Duration(days: 5)), sources: [source]),
        );
        clock.advance(Duration(days: 5, microseconds: offset));
        await offline();
        expect(
          repo.current.status,
          offset < 0
              ? ClientEntitlementStatus.proOfflineGrace
              : ClientEntitlementStatus.unavailable,
        );
      });
    }
  }
  test('source list and codec round trip', () {
    final p = proof(sources: ['PLAY_PURCHASE', 'PROMO', 'ADMIN', 'TEST']);
    final c = EntitlementCache(p, start, start);
    expect(EntitlementCache.decode(c.encode(), 'a').encode(), c.encode());
  });
  for (final mutation in [
    'json',
    'version',
    'missing',
    'uid',
    'extra',
    'time',
    'limit',
    'source',
  ]) {
    test('malformed cache $mutation discarded', () async {
      seed();
      final m = jsonDecode(storage.value!) as Map<String, dynamic>;
      switch (mutation) {
        case 'version':
          m['schemaVersion'] = 99;
        case 'missing':
          m.remove('lastWall');
        case 'uid':
          m['uid'] = 'b';
        case 'extra':
          m['secret'] = 'bad';
        case 'time':
          m['trustedProofAt'] = 'bad';
        case 'limit':
          m['offlineValidUntil'] = start
              .add(const Duration(days: 60))
              .microsecondsSinceEpoch;
        case 'source':
          m['effective']['sources'] = ['ALIEN'];
      }
      storage.value = mutation == 'json' ? '{broken' : jsonEncode(m);
      await offline();
      expect(repo.current.status, ClientEntitlementStatus.unavailable);
      expect(storage.value, isNull);
    });
  }
  for (final mutation in [
    'version',
    'source',
    'timestamp',
    'nanos',
    'missing',
    'extra',
    'revision',
    'active',
  ]) {
    test('strict effective parser rejects $mutation', () {
      final m = document();
      switch (mutation) {
        case 'version':
          m['schemaVersion'] = 99;
        case 'source':
          m['sources'] = ['ALIEN'];
        case 'timestamp':
          m['updatedAt'] = '2026';
        case 'nanos':
          m['validUntil'] = Timestamp(1700000000, 1);
        case 'missing':
          m.remove('active');
        case 'extra':
          m['profile'] = 'bad';
        case 'revision':
          m['revision'] = 1.5;
        case 'active':
          m['active'] = false;
      }
      expect(() => EffectiveEntitlementDto.parse(m), throwsFormatException);
    });
  }
  test('v1 and v2 backend effective accepted', () {
    for (final version in [1, 2]) {
      expect(
        EffectiveEntitlementDto.parse({
          ...document(),
          'schemaVersion': version,
        }).active,
        true,
      );
    }
  });
  for (final failure in [
    EntitlementFailure.networkUnavailable,
    EntitlementFailure.serverUnavailable,
    EntitlementFailure.malformedEntitlement,
  ]) {
    test('failure $failure retains valid grace', () async {
      seed();
      backend.reply = (_) async => throw EntitlementBackendException(failure);
      await repo.initializeForUser('a');
      expect(repo.current.status, ClientEntitlementStatus.proOfflineGrace);
      expect(repo.current.failure, failure);
    });
  }
  test('network failure expired grace does not become Free', () async {
    seed();
    clock.advance(const Duration(days: 31));
    backend.reply = (_) async => throw const EntitlementBackendException(
      EntitlementFailure.networkUnavailable,
    );
    await repo.initializeForUser('a');
    expect(repo.current.status, ClientEntitlementStatus.unavailable);
  });
  for (final failure in [
    EntitlementFailure.accountDeleting,
    EntitlementFailure.accountDeleted,
    EntitlementFailure.unauthenticated,
    EntitlementFailure.permissionDenied,
  ]) {
    test('$failure invalidates cached access', () async {
      seed();
      backend.reply = (_) async => throw EntitlementBackendException(failure);
      await repo.initializeForUser('a');
      expect(repo.current.status, ClientEntitlementStatus.unavailable);
      expect(storage.value, isNull);
      if (failure == EntitlementFailure.accountDeleting ||
          failure == EntitlementFailure.accountDeleted) {
        backend.reply = (_) async =>
            proof(at: start.add(const Duration(days: 1)), revision: 2);
        await repo.refresh();
        expect(repo.current.status, ClientEntitlementStatus.unavailable);
      }
    });
  }
  test('inactive proof replaces Pro even after network failure', () async {
    seed();
    await offline();
    backend.reply = (_) async => proof(active: false, revision: 2);
    await repo.refresh();
    expect(repo.current.status, ClientEntitlementStatus.free);
    expect(
      EntitlementCache.decode(storage.value!, 'a').proof.entitlement.active,
      false,
    );
    backend.reply = (_) async => throw Exception('secret');
    await repo.refresh();
    expect(repo.current.status, ClientEntitlementStatus.free);
  });
  test('stale revision cannot restore old Pro', () async {
    backend.reply = (_) async => proof(active: false, revision: 2);
    await repo.initializeForUser('a');
    backend.reply = (_) async => proof(at: start.add(const Duration(days: 1)));
    await repo.refresh();
    expect(repo.current.status, ClientEntitlementStatus.free);
  });
  test(
    'same revision fresh proof extends exactly 30 days; replay does not',
    () async {
      await repo.initializeForUser('a');
      clock.advance(const Duration(days: 3));
      await repo.refresh();
      expect(
        repo.current.snapshot!.offlineValidUntil,
        start.add(const Duration(days: 30)),
      );
      backend.reply = (_) async =>
          proof(at: start.add(const Duration(days: 3)));
      await repo.refresh();
      expect(
        repo.current.snapshot!.offlineValidUntil,
        start.add(const Duration(days: 33)),
      );
    },
  );
  test('same revision different effective payload rejected', () async {
    await repo.initializeForUser('a');
    backend.reply = (_) async =>
        proof(active: false, at: start.add(const Duration(days: 1)));
    await repo.refresh();
    expect(repo.current.status, ClientEntitlementStatus.proOfflineGrace);
    expect(repo.current.failure, EntitlementFailure.malformedEntitlement);
  });
  for (final lateError in [false, true]) {
    test('A callback error=$lateError cannot mutate B', () async {
      final c = Completer<TrustedEntitlementProof>();
      backend.reply = (_) => c.future;
      final a = repo.initializeForUser('a');
      await Future<void>.delayed(Duration.zero);
      await repo.clearForLogout();
      await repo.initializeForUser('b', refreshOnline: false);
      if (lateError) {
        c.completeError(Exception('private'));
      } else {
        c.complete(proof());
      }
      await a;
      expect(repo.current.uid, 'b');
      expect(repo.current.status, ClientEntitlementStatus.unavailable);
      expect(storage.value, isNull);
    });
  }
  test('logout during lookup fences success', () async {
    final c = Completer<TrustedEntitlementProof>();
    backend.reply = (_) => c.future;
    final a = repo.initializeForUser('a');
    await Future<void>.delayed(Duration.zero);
    await repo.clearForLogout();
    c.complete(proof());
    await a;
    expect(repo.current.status, ClientEntitlementStatus.unknown);
  });
  test('switch cached A to offline B never carries Pro', () async {
    seed();
    await offline();
    await repo.initializeForUser('b', refreshOnline: false);
    expect(repo.current.status, ClientEntitlementStatus.unavailable);
    expect(storage.value, isNull);
  });
  test('latest refresh wins concurrent callbacks', () async {
    await offline();
    final a = Completer<TrustedEntitlementProof>(),
        b = Completer<TrustedEntitlementProof>();
    var n = 0;
    backend.reply = (_) => n++ == 0 ? a.future : b.future;
    final x = repo.refresh(), y = repo.refresh();
    b.complete(proof(active: false, revision: 2));
    await y;
    a.complete(proof());
    await x;
    expect(repo.current.status, ClientEntitlementStatus.free);
  });
  test(
    'write failure keeps online result; inactive never falls back to Pro in memory',
    () async {
      seed();
      storage.failWrite = true;
      backend.reply = (_) async => proof(active: false, revision: 2);
      await repo.initializeForUser('a');
      expect(repo.current.status, ClientEntitlementStatus.free);
      expect(repo.current.failure, EntitlementFailure.storageFailure);
    },
  );
  test('read failure unavailable, later trusted refresh recovers', () async {
    storage.failRead = true;
    await offline();
    expect(repo.current.status, ClientEntitlementStatus.unavailable);
    await repo.refresh();
    expect(repo.current.status, ClientEntitlementStatus.proOnline);
  });
  test('UID-mismatched server proof rejected', () async {
    backend.reply = (_) async => proof(uid: 'b');
    await repo.initializeForUser('a');
    expect(repo.current.failure, EntitlementFailure.malformedEntitlement);
  });
  test('significant rollback locks grace across repository restart', () async {
    seed();
    await offline();
    clock.advance(const Duration(days: 10));
    await repo.reevaluate();
    clock.wall = clock.wall.subtract(const Duration(days: 2));
    await repo.reevaluate();
    expect(repo.current.failure, EntitlementFailure.suspiciousClock);
    await repo.dispose();
    repo = LocalEntitlementRepository(
      backend: backend,
      storage: storage,
      clock: clock,
    );
    await offline();
    expect(repo.current.failure, EntitlementFailure.suspiciousClock);
  });
  test(
    'reboot resets monotonic but valid cache still works; starts never renew grace',
    () async {
      seed();
      clock.advance(const Duration(days: 10));
      await offline();
      await repo.dispose();
      clock.mono = Duration.zero;
      clock.wall = clock.wall.add(const Duration(days: 1));
      repo = LocalEntitlementRepository(
        backend: backend,
        storage: storage,
        clock: clock,
      );
      await offline();
      expect(repo.current.status, ClientEntitlementStatus.proOfflineGrace);
      expect(
        repo.current.snapshot!.offlineValidUntil,
        start.add(const Duration(days: 30)),
      );
    },
  );
  test('monotonic elapsed expires grace with frozen wall clock', () async {
    seed();
    await offline();
    clock.mono = const Duration(days: 30);
    await repo.reevaluate();
    expect(repo.current.status, ClientEntitlementStatus.unavailable);
  });
  test(
    'fresh trusted proof resolves clock suspicion, cached replay cannot',
    () async {
      await repo.initializeForUser('a');
      clock.advance(const Duration(days: 5));
      await repo.reevaluate();
      clock.wall = start;
      await repo.reevaluate();
      await repo.refresh();
      expect(repo.current.failure, EntitlementFailure.suspiciousClock);
      backend.reply = (_) async =>
          proof(at: start.add(const Duration(days: 6)));
      await repo.refresh();
      expect(repo.current.status, ClientEntitlementStatus.proOnline);
    },
  );
  test(
    'image remains unavailable in every state; expired grace requires connection',
    () async {
      expect(
        repo.current.access(ProFeature.imageImport),
        FeatureAccessDecision.featureUnavailable,
      );
      seed();
      await offline();
      expect(
        repo.current.access(ProFeature.imageImport),
        FeatureAccessDecision.featureUnavailable,
      );
      clock.advance(const Duration(days: 31));
      expect(
        repo.current.access(ProFeature.recipeScaling),
        FeatureAccessDecision.requiresConnection,
      );
    },
  );
  test('dispose fences pending request and emits no late event', () async {
    final c = Completer<TrustedEntitlementProof>();
    backend.reply = (_) => c.future;
    final task = repo.initializeForUser('a');
    await Future<void>.delayed(Duration.zero);
    await repo.dispose();
    c.complete(proof());
    await task;
  });
  test('cache contains no billing or profile fields', () {
    seed();
    final value = storage.value!;
    for (final name in [
      'purchaseToken',
      'accountBinding',
      'password',
      'email',
      'displayName',
      'rawResponse',
    ]) {
      expect(value.contains(name), false);
    }
  });
  test(
    'late startup cache read cannot overwrite newer trusted refresh',
    () async {
      seed();
      storage.readBarrier = Completer<void>();
      final init = offline();
      await Future<void>.delayed(Duration.zero);
      backend.reply = (_) async => proof(active: false, revision: 2);
      final refresh = repo.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(repo.current.status, ClientEntitlementStatus.free);
      storage.readBarrier!.complete();
      await init;
      await refresh;
      expect(repo.current.status, ClientEntitlementStatus.free);
      expect(
        EntitlementCache.decode(storage.value!, 'a').proof.entitlement.revision,
        2,
      );
    },
  );
  test('logout queues invalidation after an in-flight storage write', () async {
    storage.writeBarrier = Completer<void>();
    final init = repo.initializeForUser('a');
    await Future<void>.delayed(Duration.zero);
    final logout = repo.clearForLogout();
    expect(repo.current.status, ClientEntitlementStatus.unknown);
    storage.writeBarrier!.complete();
    await init;
    await logout;
    expect(storage.value, isNull);
    await repo.initializeForUser('b', refreshOnline: false);
    expect(repo.current.status, ClientEntitlementStatus.unavailable);
  });
  test(
    'failed inactive replacement clears old durable Pro when clear still works',
    () async {
      seed();
      storage.failWrite = true;
      backend.reply = (_) async => proof(active: false, revision: 2);
      await repo.initializeForUser('a');
      expect(storage.value, isNull);
      expect(repo.current.status, ClientEntitlementStatus.free);
    },
  );
  test('small rollback does not renew fixed grace', () async {
    seed();
    await offline();
    clock.advance(const Duration(days: 1));
    await repo.reevaluate();
    clock.wall = clock.wall.subtract(const Duration(minutes: 1));
    clock.mono += const Duration(minutes: 1);
    await repo.reevaluate();
    expect(repo.current.status, ClientEntitlementStatus.proOfflineGrace);
    expect(
      repo.current.snapshot!.offlineValidUntil,
      start.add(const Duration(days: 30)),
    );
  });
  test('raw backend exception never escapes state', () async {
    backend.reply = (_) async =>
        throw Exception('token email private response');
    await repo.initializeForUser('a');
    expect(repo.current.failure, EntitlementFailure.serverUnavailable);
  });
  test('disposed active repository no longer exposes Pro access', () async {
    await repo.initializeForUser('a');
    await repo.dispose();
    expect(repo.current.status, ClientEntitlementStatus.unknown);
    expect(
      repo.current.access(ProFeature.recipeScaling),
      FeatureAccessDecision.checking,
    );
  });
}
