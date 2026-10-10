import '../models/entitlement_snapshot.dart';
import '../models/feature_access_decision.dart';
import '../models/pro_feature.dart';

final class FeatureAccessService {
  const FeatureAccessService();

  FeatureAccessDecision evaluate(
    EntitlementSnapshot snapshot,
    ProFeature feature,
  ) {
    // Availability precedes entitlement: not released even for verified Pro.
    if (feature == ProFeature.imageImport) {
      return FeatureAccessDecision.featureUnavailable;
    }
    return switch (snapshot.status) {
      EntitlementStatus.unknown ||
      EntitlementStatus.checking => FeatureAccessDecision.checking,
      EntitlementStatus.free => FeatureAccessDecision.requiresPro,
      EntitlementStatus.pro => FeatureAccessDecision.allowed,
    };
  }
}
