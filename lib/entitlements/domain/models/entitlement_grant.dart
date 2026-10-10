enum EntitlementSource { playPurchase, promo, admin, test }

enum EntitlementGrantStatus { active, inactive, revoked }

/// A grant for one account. Account binding and deletion are backend concerns:
/// deleting an account must end its entitlement, never transfer it to a new UID.
/// Coupon redemption can later produce a promo grant without changing this model.
final class EntitlementGrant {
  EntitlementGrant({
    required this.source,
    required this.status,
    required this.startsAt,
    this.expiresAt,
    this.revokedAt,
  }) {
    if (expiresAt != null && !expiresAt!.isAfter(startsAt)) {
      throw ArgumentError('expiresAt must be after startsAt');
    }
  }

  final EntitlementSource source;
  final EntitlementGrantStatus status;
  final DateTime startsAt;
  final DateTime? expiresAt;

  /// A recorded revocation disqualifies the grant even if status is stale.
  /// This is an event timestamp, not a scheduled revocation.
  final DateTime? revokedAt;

  /// Start inclusive, expiry exclusive; a null expiry is permanent.
  bool isActiveAt(DateTime now) =>
      status == EntitlementGrantStatus.active &&
      revokedAt == null &&
      !now.isBefore(startsAt) &&
      (expiresAt == null || now.isBefore(expiresAt!));
}
