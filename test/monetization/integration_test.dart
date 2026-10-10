import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/billing/billing_contracts.dart';
import 'package:kuktam/monetization/callable_gateways.dart';
import 'package:kuktam/monetization/monetization_coordinator.dart';
import 'package:kuktam/monetization/secure_entitlement_storage.dart';
import 'package:kuktam/entitlements/domain/repositories/entitlement_repository.dart';
import '../billing/fakes.dart';

class LocalTransport implements CallableTransport {
  final calls = <String>[];
  bool active = false;
  int revision = 0;
  int issued = now.millisecondsSinceEpoch;
  String? error;
  String outcome = 'verified';
  String? pause;
  Completer<Object?>? barrier;
  Map<String, Object?> proof() => {
    'schemaVersion': 1,
    'active': active,
    'sources': active ? ['PLAY_PURCHASE'] : <String>[],
    'validUntil': null,
    'revision': revision,
    'verifiedAt': now.millisecondsSinceEpoch,
    'updatedAt': now.millisecondsSinceEpoch,
    'proofIssuedAt': issued,
  };
  @override
  Future<Object?> call(String name, Map<String, Object?> data) async {
    calls.add(name);
    expect(data.containsKey('uid'), false);
    expect(data.containsKey('packageName'), false);
    if (pause == name) return barrier!.future;
    if (error != null) return {'schemaVersion': 1, 'error': error};
    if (name == 'prepareProPurchase') {
      return {
        'schemaVersion': 1,
        'productId': ProProduct.id,
        'opaqueAccountId': bindingA,
      };
    }
    if (name == 'verifyProPurchase') {
      return {'schemaVersion': 1, 'outcome': outcome};
    }
    return proof();
  }
}

class MovingClock extends FakeClock {
  DateTime current = now;
  @override
  DateTime wallNow() => current;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  late Map<String, String> disk;
  late LocalTransport transport;
  late FakeBilling billing;
  late MonetizationCoordinator coordinator;
  late MovingClock clock;
  bool failRead = false, failWrite = false;
  MonetizationCoordinator create({bool online = true}) =>
      MonetizationCoordinator(
        billing: billing,
        storage: SecureEntitlementStorage(),
        clock: clock,
        onlineEnabled: online,
        transportFactory: (_, _) => transport,
      );
  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('kuktam/entitlement_durability'),
          (_) async => null,
        );
    disk = {};
    failRead = false;
    failWrite = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final args = Map<String, dynamic>.from(call.arguments as Map);
          final key = args['key'] as String;
          if (call.method == 'read') {
            if (failRead) {
              throw PlatformException(
                code: 'decrypt-failed',
                message: 'private',
              );
            }
            return disk[key];
          }
          if (call.method == 'write') {
            if (failWrite) {
              throw PlatformException(code: 'disk-failed', message: 'private');
            }
            disk[key] = args['value'] as String;
          } else if (call.method == 'delete') {
            disk.remove(key);
          }
          return null;
        });
    transport = LocalTransport();
    billing = FakeBilling();
    clock = MovingClock();
    coordinator = create();
    await coordinator.changeSession('a');
  });
  tearDown(() async {
    await coordinator.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  Future<void> buy() async {
    await coordinator.purchases.loadOffer();
    await coordinator.purchases.buyPro();
  }

  Future<void> emit([
    PurchaseEventKind kind = PurchaseEventKind.purchased,
  ]) async {
    billing.controller.add(event(kind));
    await flush();
  }

  Future<void> restart({bool online = false}) async {
    await coordinator.dispose();
    billing = FakeBilling();
    coordinator = create(online: online);
    await coordinator.changeSession('a');
  }

  void activate() {
    transport.active = true;
    transport.revision = 1;
    transport.issued++;
  }

  test(
    'full buy chain prepares binding then verifies then trusted proof; persisted without tokens',
    () async {
      await buy();
      expect(billing.boughtBinding, bindingA);
      expect(
        coordinator.entitlements.current.status,
        ClientEntitlementStatus.free,
      );
      activate();
      await emit();
      expect(
        coordinator.entitlements.current.status,
        ClientEntitlementStatus.proOnline,
      );
      expect(transport.calls, [
        'getEntitlementProof',
        'prepareProPurchase',
        'verifyProPurchase',
        'getEntitlementProof',
      ]);
      final cache = disk.values.single;
      expect(cache, isNot(contains(bindingA)));
      expect(cache, isNot(contains('test-token')));
      expect(jsonDecode(cache)['trustedProofAt'], transport.issued * 1000);
    },
  );
  test('pending no verify/proof; purchased later continues', () async {
    await buy();
    await emit(PurchaseEventKind.pending);
    expect(transport.calls.length, 2);
    activate();
    await emit();
    expect(
      coordinator.entitlements.current.status,
      ClientEntitlementStatus.proOnline,
    );
  });
  test('verified but inactive proof remains Free', () async {
    await buy();
    transport.issued++;
    await emit();
    expect(
      coordinator.entitlements.current.status,
      ClientEntitlementStatus.free,
    );
  });
  test('restore does not prepare new binding', () async {
    billing.owned = [event(PurchaseEventKind.restored)];
    activate();
    await coordinator.purchases.restore();
    expect(transport.calls.contains('prepareProPurchase'), false);
    expect(
      coordinator.entitlements.current.status,
      ClientEntitlementStatus.proOnline,
    );
  });
  test('already owned uses restore verify proof', () async {
    billing.buyError = const BillingException(BillingFailure.alreadyOwned);
    billing.owned = [event(PurchaseEventKind.restored)];
    activate();
    await buy();
    expect(billing.restores, 1);
    expect(
      coordinator.entitlements.current.status,
      ClientEntitlementStatus.proOnline,
    );
  });
  test(
    'deleted-account purchase restore conflict never produces Pro cache for B',
    () async {
      await coordinator.changeSession('b');
      transport.error = 'tokenBindingConflict';
      billing.owned = [event(PurchaseEventKind.restored)];
      await coordinator.purchases.restore();
      expect(
        coordinator.purchases.current.status,
        PurchaseFlowStatus.supportRequired,
      );
      expect(
        coordinator.entitlements.current.status,
        ClientEntitlementStatus.free,
      );
      expect(jsonDecode(disk.values.single)['effective']['active'], false);
    },
  );
  for (final error in [
    'unauthenticated',
    'accountDeleting',
    'accountDeleted',
    'configuration',
    'retryableUnavailable',
  ]) {
    test('prepare $error prevents Play launch', () async {
      transport.error = error;
      await buy();
      expect(billing.buys, 0);
    });
  }
  for (final method in [
    'prepareProPurchase',
    'verifyProPurchase',
    'getEntitlementProof',
  ]) {
    test('session switch during $method discards A completion', () async {
      if (method != 'prepareProPurchase') await buy();
      transport.pause = method;
      transport.barrier = Completer<Object?>();
      final pending = method == 'prepareProPurchase'
          ? coordinator.purchases.buyPro()
          : emit();
      await flush();
      transport.pause = null;
      await coordinator.changeSession('b');
      transport.barrier!.complete(
        method == 'prepareProPurchase'
            ? {
                'schemaVersion': 1,
                'productId': ProProduct.id,
                'opaqueAccountId': bindingA,
              }
            : method == 'verifyProPurchase'
            ? {'schemaVersion': 1, 'outcome': 'verified'}
            : transport.proof(),
      );
      await pending;
      await flush();
      expect(coordinator.entitlements.current.uid, 'b');
      expect(
        coordinator.entitlements.current.status,
        ClientEntitlementStatus.free,
      );
      if (method == 'prepareProPurchase') expect(billing.buys, 0);
    });
  }
  test('duplicate callbacks one verification', () async {
    await buy();
    transport.pause = 'verifyProPurchase';
    transport.barrier = Completer<Object?>();
    await emit();
    await emit();
    expect(transport.calls.where((e) => e == 'verifyProPurchase').length, 1);
    transport.barrier!.complete({'schemaVersion': 1, 'outcome': 'verified'});
    await flush();
  });
  test(
    'secure cache survives process-style restart, offline no transport',
    () async {
      activate();
      await coordinator.entitlements.refresh();
      final count = transport.calls.length;
      await restart();
      expect(
        coordinator.entitlements.current.status,
        ClientEntitlementStatus.proOfflineGrace,
      );
      expect(transport.calls.length, count);
    },
  );
  test('restart online gets new trusted proof', () async {
    activate();
    await coordinator.entitlements.refresh();
    transport.issued++;
    await restart(online: true);
    expect(
      coordinator.entitlements.current.status,
      ClientEntitlementStatus.proOnline,
    );
  });
  test('expired cache never Pro offline', () async {
    activate();
    await coordinator.entitlements.refresh();
    clock.current = now.add(const Duration(days: 31));
    await restart();
    expect(
      coordinator.entitlements.current.status,
      isNot(ClientEntitlementStatus.proOfflineGrace),
    );
  });
  test('clock rollback latch persists over restart', () async {
    activate();
    await coordinator.entitlements.refresh();
    clock.current = now.subtract(const Duration(hours: 1));
    await coordinator.entitlements.reevaluate();
    await restart();
    expect(
      coordinator.entitlements.current.failure,
      EntitlementFailure.suspiciousClock,
    );
  });
  test('inactive proof overwrites old Pro for offline restart', () async {
    activate();
    await coordinator.entitlements.refresh();
    transport.active = false;
    transport.revision++;
    transport.issued++;
    await coordinator.entitlements.refresh();
    await restart();
    expect(
      coordinator.entitlements.current.status,
      ClientEntitlementStatus.free,
    );
  });
  for (final error in ['accountDeleting', 'accountDeleted']) {
    test('$error proof clears persistent Pro', () async {
      activate();
      await coordinator.entitlements.refresh();
      transport.error = error;
      await coordinator.entitlements.refresh();
      expect(disk, isEmpty);
      await restart();
      expect(
        coordinator.entitlements.current.status,
        isNot(ClientEntitlementStatus.proOfflineGrace),
      );
    });
  }
  test('temporary proof failure uses valid grace, never fake Free', () async {
    activate();
    await coordinator.entitlements.refresh();
    transport.error = 'retryableUnavailable';
    await coordinator.entitlements.refresh();
    expect(
      coordinator.entitlements.current.status,
      ClientEntitlementStatus.proOfflineGrace,
    );
  });
  test(
    'secure write failure retains online Pro with explicit warning',
    () async {
      activate();
      failWrite = true;
      await coordinator.entitlements.refresh();
      expect(
        coordinator.entitlements.current.status,
        ClientEntitlementStatus.proOnline,
      );
      expect(
        coordinator.entitlements.current.failure,
        EntitlementFailure.storageFailure,
      );
    },
  );
  test('decrypt failure discarded and online recovery works', () async {
    activate();
    await coordinator.entitlements.refresh();
    await coordinator.dispose();
    failRead = true;
    billing = FakeBilling();
    coordinator = create();
    transport.issued++;
    await coordinator.changeSession('a');
    expect(
      coordinator.entitlements.current.status,
      ClientEntitlementStatus.proOnline,
    );
  });
  for (final corrupt in [
    'not json',
    '{"schemaVersion":999}',
    '{"active":true}',
  ]) {
    test('corrupt cache discarded: $corrupt', () async {
      await coordinator.dispose();
      disk[SecureEntitlementStorage.key] = corrupt;
      billing = FakeBilling();
      coordinator = create(online: false);
      await coordinator.changeSession('a');
      expect(
        coordinator.entitlements.current.status,
        isNot(ClientEntitlementStatus.proOfflineGrace),
      );
      expect(disk, isEmpty);
    });
  }
  test('logout clears cache; no cross UID grace', () async {
    activate();
    await coordinator.entitlements.refresh();
    await coordinator.changeSession(null);
    expect(disk, isEmpty);
    transport.error = 'retryableUnavailable';
    await coordinator.changeSession('b');
    expect(
      coordinator.entitlements.current.status,
      ClientEntitlementStatus.unavailable,
    );
  });
  for (final method in ['prepareProPurchase', 'verifyProPurchase']) {
    test(
      '$method confirmed deletion invalidates already cached Pro immediately',
      () async {
        activate();
        await coordinator.entitlements.refresh();
        if (method == 'verifyProPurchase') await buy();
        transport.error = 'accountDeleted';
        if (method == 'prepareProPurchase') {
          await buy();
        } else {
          await emit();
        }
        expect(disk, isEmpty);
        expect(
          coordinator.entitlements.current.failure,
          EntitlementFailure.accountDeleted,
        );
        expect(
          coordinator.purchases.current.status,
          PurchaseFlowStatus.blocked,
        );
      },
    );
  }
  test('durability barrier failure is exposed as storage warning', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('kuktam/entitlement_durability'),
          (_) async => throw PlatformException(code: 'storage-failure'),
        );
    activate();
    await coordinator.entitlements.refresh();
    expect(
      coordinator.entitlements.current.status,
      ClientEntitlementStatus.proOnline,
    );
    expect(
      coordinator.entitlements.current.failure,
      EntitlementFailure.storageFailure,
    );
  });
  for (final malformed in [
    null,
    {'schemaVersion': 99},
    {'schemaVersion': 1, 'active': true},
  ]) {
    test('malformed proof never renews freshness $malformed', () async {
      activate();
      await coordinator.entitlements.refresh();
      final old = disk.values.single;
      transport.pause = 'getEntitlementProof';
      transport.barrier = Completer<Object?>()..complete(malformed);
      await coordinator.entitlements.refresh();
      expect(disk.values.single, old);
    });
  }
  test(
    'same revision fresh server proof renews grace; replay does not',
    () async {
      activate();
      await coordinator.entitlements.refresh();
      final first = jsonDecode(disk.values.single)['offlineValidUntil'];
      transport.issued += 1000;
      await coordinator.entitlements.refresh();
      final newer = jsonDecode(disk.values.single)['offlineValidUntil'];
      expect(newer, greaterThan(first));
      await coordinator.entitlements.refresh();
      expect(jsonDecode(disk.values.single)['offlineValidUntil'], newer);
    },
  );
}
