import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/entitlements/domain/models/entitlement_grant.dart';
import 'package:kuktam/entitlements/domain/models/entitlement_snapshot.dart';
import 'package:kuktam/entitlements/domain/services/entitlement_aggregator.dart';

void main() {
  const aggregator = EntitlementAggregator();
  final now = DateTime.utc(2026, 9, 27);
  EntitlementGrant grant({
    EntitlementSource source = EntitlementSource.promo,
    EntitlementGrantStatus status = EntitlementGrantStatus.active,
    DateTime? start,
    DateTime? expiry,
    DateTime? revoked,
  }) => EntitlementGrant(
    source: source,
    status: status,
    startsAt: start ?? now.subtract(const Duration(days: 1)),
    expiresAt: expiry,
    revokedAt: revoked,
  );

  test('empty known list is Free, not unknown', () {
    expect(aggregator.aggregate([], now: now).status, EntitlementStatus.free);
  });

  for (final source in EntitlementSource.values) {
    test(
      'permanent $source grants lifetime Pro without claiming verification',
      () {
        final result = aggregator.aggregate([grant(source: source)], now: now);
        expect(result.status, EntitlementStatus.pro);
        expect(result.isLifetime, isTrue);
        expect(result.verifiedAt, isNull);
        expect(result.offlineValidUntil, isNull);
      },
    );
  }

  test('expired and future promos are Free', () {
    expect(
      aggregator.aggregate([
        grant(expiry: now.subtract(const Duration(hours: 1))),
        grant(start: now.add(const Duration(hours: 1))),
      ], now: now).status,
      EntitlementStatus.free,
    );
  });

  test(
    'revoked Play is Free, independently of which revocation field is set',
    () {
      for (final revoked in [
        grant(
          source: EntitlementSource.playPurchase,
          status: EntitlementGrantStatus.revoked,
        ),
        grant(source: EntitlementSource.playPurchase, revoked: now),
      ]) {
        expect(
          aggregator.aggregate([revoked], now: now).status,
          EntitlementStatus.free,
        );
      }
    },
  );

  test(
    'Play revoke cannot revoke independent active promo in either order',
    () {
      final grants = [
        grant(
          source: EntitlementSource.playPurchase,
          status: EntitlementGrantStatus.revoked,
        ),
        grant(),
      ];
      expect(
        aggregator.aggregate(grants, now: now).status,
        EntitlementStatus.pro,
      );
      expect(
        aggregator.aggregate(grants.reversed, now: now).status,
        EntitlementStatus.pro,
      );
    },
  );

  test('all inactive grants yield Free', () {
    final grants = EntitlementSource.values.map(
      (source) =>
          grant(source: source, status: EntitlementGrantStatus.inactive),
    );
    final result = aggregator.aggregate(grants, now: now);
    expect(result.status, EntitlementStatus.free);
    expect(result.isLifetime, isFalse);
  });

  test('multiple active grants use latest expiry with no source priority', () {
    final end = now.add(const Duration(days: 10));
    final grants = [
      grant(
        source: EntitlementSource.playPurchase,
        expiry: now.add(const Duration(days: 1)),
      ),
      grant(source: EntitlementSource.test, expiry: end),
      grant(
        status: EntitlementGrantStatus.inactive,
        expiry: now.add(const Duration(days: 100)),
      ),
    ];
    for (final order in [grants, grants.reversed]) {
      final result = aggregator.aggregate(order, now: now);
      expect(result.status, EntitlementStatus.pro);
      expect(result.validUntil, end);
      expect(result.isLifetime, isFalse);
    }
  });

  test('active permanent grant wins over limited grant in either order', () {
    final grants = [grant(expiry: now.add(const Duration(days: 1))), grant()];
    for (final order in [grants, grants.reversed]) {
      expect(aggregator.aggregate(order, now: now).isLifetime, isTrue);
    }
  });

  test('invalid empty or reversed grant period is rejected', () {
    for (final expiry in [now, now.subtract(const Duration(seconds: 1))]) {
      expect(() => grant(start: now, expiry: expiry), throwsArgumentError);
    }
  });
}
