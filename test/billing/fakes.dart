import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:kuktam/billing/billing_contracts.dart';
import 'package:kuktam/entitlements/data/effective_entitlement_dto.dart';
import 'package:kuktam/entitlements/data/entitlement_contracts.dart';

final now = DateTime.utc(2026, 10, 8);
final bindingA = 'v1_${'a' * 43}';
final bindingB = 'v1_${'b' * 43}';
PurchaseEvent event([
  PurchaseEventKind kind = PurchaseEventKind.purchased,
  String token = 'test-token',
  String? binding,
]) => PurchaseEvent(
  kind,
  evidence: PurchaseEvidence(token, accountBinding: binding ?? bindingA),
);

class FakeBilling implements BillingAdapter {
  final controller = StreamController<PurchaseEvent>.broadcast();
  bool available = true;
  ProductOffer? offer = const ProductOffer(
    localizedPrice: '€7.99',
    currency: 'EUR',
    title: 'Pro',
  );
  Object? queryError, buyError;
  int buys = 0, restores = 0;
  String? boughtBinding;
  List<PurchaseEvent> owned = [];
  Completer<List<PurchaseEvent>>? restoreBarrier;
  @override
  Stream<PurchaseEvent> get events => controller.stream;
  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<ProductOffer?> loadOffer() async {
    if (queryError != null) throw queryError!;
    return offer;
  }

  @override
  Future<void> buyNonConsumable(
    String opaqueAccountBinding, {
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) return;
    buys++;
    boughtBinding = opaqueAccountBinding;
    if (buyError != null) throw buyError!;
  }

  @override
  Future<List<PurchaseEvent>> restore() async {
    restores++;
    return restoreBarrier == null ? owned : await restoreBarrier!.future;
  }

  @override
  Future<void> dispose() => controller.close();
}

class FakeGateway implements PurchaseVerificationGateway {
  int calls = 0;
  Future<VerificationOutcome> Function(PurchaseEvidence) reply = (_) async =>
      VerificationOutcome.verified;
  @override
  Future<VerificationOutcome> verify(PurchaseEvidence evidence) {
    calls++;
    return reply(evidence);
  }
}

class FakeProofBackend implements TrustedEntitlementBackend {
  bool active = false;
  int calls = 0;
  Completer<TrustedEntitlementProof>? barrier;
  @override
  Future<TrustedEntitlementProof> fetchProof(String uid) async {
    calls++;
    return barrier == null ? proof(uid, active, calls) : await barrier!.future;
  }
}

TrustedEntitlementProof proof(String uid, bool active, int revision) =>
    TrustedEntitlementProof(
      uid: uid,
      trustedProofAt: now,
      entitlement: EffectiveEntitlementDto.parse({
        'schemaVersion': 2,
        'active': active,
        'validUntil': null,
        'sources': active ? ['PLAY_PURCHASE'] : <String>[],
        'revision': revision,
        'verifiedAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      }),
    );

class MemoryStorage implements EntitlementCacheStorage {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    this.value = value;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

class FakeClock implements EntitlementClock {
  @override
  DateTime wallNow() => now;
  @override
  Duration monotonicNow() => Duration.zero;
}

Future<void> flush() => Future<void>.delayed(Duration.zero);
