import '../models/entitlement_snapshot.dart';
import '../models/feature_access_decision.dart';
import '../models/pro_feature.dart';
import '../services/feature_access_service.dart';

enum ClientEntitlementStatus {
  unknown,
  checking,
  free,
  proOnline,
  proOfflineGrace,
  unavailable,
}

enum EntitlementFailure {
  malformedEntitlement,
  malformedCache,
  permissionDenied,
  unauthenticated,
  networkUnavailable,
  serverUnavailable,
  accountDeleting,
  accountDeleted,
  connectionRequired,
  suspiciousClock,
  storageFailure,
  staleProof,
}

final class ClientEntitlementState {
  const ClientEntitlementState(
    this.status, {
    this.uid,
    this.snapshot,
    this.failure,
  });
  final ClientEntitlementStatus status;
  final String? uid;
  final EntitlementSnapshot? snapshot;
  final EntitlementFailure? failure;
  FeatureAccessDecision access(ProFeature feature) {
    if (feature == ProFeature.imageImport) {
      return FeatureAccessDecision.featureUnavailable;
    }
    if (status == ClientEntitlementStatus.unavailable) {
      return FeatureAccessDecision.requiresConnection;
    }
    return const FeatureAccessService().evaluate(
      snapshot ??
          (status == ClientEntitlementStatus.checking
              ? const EntitlementSnapshot.checking()
              : const EntitlementSnapshot.unknown()),
      feature,
    );
  }
}

abstract interface class EntitlementRepository {
  ClientEntitlementState get current;
  Stream<ClientEntitlementState> get changes;
  Future<void> initializeForUser(String uid, {bool refreshOnline = true});
  Future<void> refresh();
  Future<void> reevaluate();
  Future<void> clearForLogout();
  Future<void> dispose();
}
