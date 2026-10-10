import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/entitlements/domain/models/entitlement_grant.dart';
import 'package:kuktam/entitlements/domain/models/entitlement_snapshot.dart';
import 'package:kuktam/entitlements/domain/models/feature_access_decision.dart';
import 'package:kuktam/entitlements/domain/models/pro_feature.dart';
import 'package:kuktam/entitlements/domain/services/entitlement_aggregator.dart';
import 'package:kuktam/entitlements/domain/services/feature_access_service.dart';

void main() {
  const aggregator = EntitlementAggregator();
  final start = DateTime.utc(2026, 9, 27);
  final end = start.add(const Duration(days: 1));
  final promo = EntitlementGrant(
    source: EntitlementSource.promo,
    status: EntitlementGrantStatus.active,
    startsAt: start,
    expiresAt: end,
  );

  test('start is inclusive and expiry exclusive to microsecond precision', () {
    for (final (instant, expected) in [
      (start.subtract(const Duration(microseconds: 1)), EntitlementStatus.free),
      (start, EntitlementStatus.pro),
      (end.subtract(const Duration(microseconds: 1)), EntitlementStatus.pro),
      (end, EntitlementStatus.free),
      (end.add(const Duration(microseconds: 1)), EntitlementStatus.free),
    ]) {
      expect(aggregator.aggregate([promo], now: instant).status, expected);
    }
  });

  test('different timezone representations compare as the same instant', () {
    final sameStart = DateTime.parse('2026-09-27T02:00:00+02:00');
    expect(
      aggregator.aggregate([promo], now: sameStart).status,
      EntitlementStatus.pro,
    );
    expect(
      aggregator.aggregate([promo], now: end.toLocal()).status,
      EntitlementStatus.free,
    );
  });

  test(
    're-evaluation closes access at expiry without changing old snapshot',
    () {
      final before = aggregator.aggregate([promo], now: start);
      final after = aggregator.aggregate([promo], now: end);
      const access = FeatureAccessService();
      expect(
        access.evaluate(before, ProFeature.whatToCook),
        FeatureAccessDecision.allowed,
      );
      expect(
        access.evaluate(after, ProFeature.whatToCook),
        FeatureAccessDecision.requiresPro,
      );
      expect(before.status, EntitlementStatus.pro);
    },
  );

  test(
    'snapshots do not retain mutable grant list or another account state',
    () {
      final grants = [promo];
      final accountA = aggregator.aggregate(grants, now: start);
      grants.clear();
      final accountB = aggregator.aggregate(grants, now: start);
      expect(accountA.status, EntitlementStatus.pro);
      expect(accountB.status, EntitlementStatus.free);
      expect(
        const EntitlementSnapshot.unknown().status,
        EntitlementStatus.unknown,
      );
    },
  );

  test('30-day grace metadata is carried, never minted by aggregation', () {
    expect(EntitlementSnapshot.offlineGracePeriod, const Duration(days: 30));
    final deadline = start.add(EntitlementSnapshot.offlineGracePeriod);
    final snapshot = EntitlementSnapshot.pro(
      verifiedAt: start,
      offlineValidUntil: deadline,
    );
    expect(snapshot.verifiedAt, start);
    expect(snapshot.offlineValidUntil, deadline);
    final aggregated = aggregator.aggregate([promo], now: start);
    expect(aggregated.verifiedAt, isNull);
    expect(aggregated.offlineValidUntil, isNull);
  });
}
