import '../models/entitlement_grant.dart';
import '../models/entitlement_snapshot.dart';

/// Evaluates a complete grant list for one account at an explicit instant.
/// Do not pass an unloaded list as empty: use unknown/checking until it is loaded.
final class EntitlementAggregator {
  const EntitlementAggregator();

  EntitlementSnapshot aggregate(
    Iterable<EntitlementGrant> grants, {
    required DateTime now,
  }) {
    var hasActiveGrant = false;
    DateTime? latestExpiry;
    for (final grant in grants) {
      if (!grant.isActiveAt(now)) continue;
      hasActiveGrant = true;
      final expiry = grant.expiresAt;
      if (expiry == null) return const EntitlementSnapshot.pro();
      if (latestExpiry == null || expiry.isAfter(latestExpiry)) {
        latestExpiry = expiry;
      }
    }
    return hasActiveGrant
        ? EntitlementSnapshot.pro(validUntil: latestExpiry)
        : const EntitlementSnapshot.free();
  }
}
