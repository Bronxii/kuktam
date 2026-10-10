import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/entitlements/domain/models/entitlement_grant.dart';
import 'package:kuktam/entitlements/domain/models/entitlement_snapshot.dart';
import 'package:kuktam/entitlements/domain/models/feature_access_decision.dart';
import 'package:kuktam/entitlements/domain/models/pro_feature.dart';
import 'package:kuktam/entitlements/domain/services/entitlement_aggregator.dart';
import 'package:kuktam/entitlements/domain/services/feature_access_service.dart';

void main() {
  const service = FeatureAccessService();
  final now = DateTime.utc(2026, 9, 27);
  final playPro = const EntitlementAggregator().aggregate([
    EntitlementGrant(
      source: EntitlementSource.playPurchase,
      status: EntitlementGrantStatus.active,
      startsAt: now,
    ),
  ], now: now);

  for (final feature in ProFeature.values) {
    final unavailable = feature == ProFeature.imageImport;
    test('Free / $feature', () {
      expect(
        service.evaluate(const EntitlementSnapshot.free(), feature),
        unavailable
            ? FeatureAccessDecision.featureUnavailable
            : FeatureAccessDecision.requiresPro,
      );
    });
    test('verified Play grant input / $feature', () {
      expect(
        service.evaluate(playPro, feature),
        unavailable
            ? FeatureAccessDecision.featureUnavailable
            : FeatureAccessDecision.allowed,
      );
    });
    test('checking / $feature', () {
      expect(
        service.evaluate(const EntitlementSnapshot.checking(), feature),
        unavailable
            ? FeatureAccessDecision.featureUnavailable
            : FeatureAccessDecision.checking,
      );
    });
    test('unknown / $feature', () {
      expect(
        service.evaluate(const EntitlementSnapshot.unknown(), feature),
        unavailable
            ? FeatureAccessDecision.featureUnavailable
            : FeatureAccessDecision.checking,
      );
    });
  }

  test('unknown is distinct from known Free', () {
    const unknown = EntitlementSnapshot.unknown();
    const free = EntitlementSnapshot.free();
    expect(unknown.status, isNot(free.status));
    expect(
      service.evaluate(unknown, ProFeature.recipeScaling),
      isNot(service.evaluate(free, ProFeature.recipeScaling)),
    );
  });
}
