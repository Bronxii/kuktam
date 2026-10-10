import '../domain/models/entitlement_snapshot.dart';
import '../domain/repositories/entitlement_repository.dart';
import 'effective_entitlement_dto.dart';

/// Trusted dependency: authenticates UID, request freshness and proof integrity.
/// Firestore document/cache reads and Play callbacks do not satisfy this contract.
/// N5.1 has fakes only, no deployed transport or cryptographic verification.
abstract interface class TrustedEntitlementBackend {
  Future<TrustedEntitlementProof> fetchProof(String uid);
}

final class EntitlementBackendException implements Exception {
  const EntitlementBackendException(this.failure);
  final EntitlementFailure failure;
  @override
  String toString() => 'EntitlementBackendException(${failure.name})';
}

final class TrustedEntitlementProof {
  TrustedEntitlementProof({
    required this.uid,
    required this.entitlement,
    required this.trustedProofAt,
  }) {
    validateUid(uid);
    if (!trustedProofAt.isUtc ||
        entitlement.updatedAt.isAfter(trustedProofAt) ||
        entitlement.verifiedAt.isAfter(trustedProofAt)) {
      badData();
    }
  }
  final String uid;
  final EffectiveEntitlementDto entitlement;
  final DateTime trustedProofAt;
  DateTime get offlineValidUntil =>
      trustedProofAt.add(EntitlementSnapshot.offlineGracePeriod);
  DateTime get effectiveLimit =>
      entitlement.validUntil != null &&
          entitlement.validUntil!.isBefore(offlineValidUntil)
      ? entitlement.validUntil!
      : offlineValidUntil;
}

void validateUid(String uid) {
  if (uid.isEmpty ||
      uid.length > 128 ||
      uid.trim() != uid ||
      uid.contains('/')) {
    badData();
  }
}

/// Single atomic slot, serialized by the repository. A later device adapter must
/// supply persistence/integrity; this interface does not imply secure storage.
abstract interface class EntitlementCacheStorage {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

abstract interface class EntitlementClock {
  DateTime wallNow();
  Duration monotonicNow();
}

final class SystemEntitlementClock implements EntitlementClock {
  final Stopwatch _watch = Stopwatch()..start();
  @override
  DateTime wallNow() => DateTime.now().toUtc();
  @override
  Duration monotonicNow() => _watch.elapsed;
}
