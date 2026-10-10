enum EntitlementStatus { unknown, checking, free, pro }

/// Immutable point-in-time decision, not a purchase proof or persisted cache.
/// Revoked/expired/inactive grants yield Free unless another active grant remains.
/// Unknown/checking must not be treated as an authoritative Free result.
final class EntitlementSnapshot {
  const EntitlementSnapshot.unknown()
    : status = EntitlementStatus.unknown,
      validUntil = null,
      verifiedAt = null,
      offlineValidUntil = null;

  const EntitlementSnapshot.checking()
    : status = EntitlementStatus.checking,
      validUntil = null,
      verifiedAt = null,
      offlineValidUntil = null;

  const EntitlementSnapshot.free({this.verifiedAt})
    : status = EntitlementStatus.free,
      validUntil = null,
      offlineValidUntil = null;

  const EntitlementSnapshot.pro({
    this.validUntil,
    this.verifiedAt,
    this.offlineValidUntil,
  }) : status = EntitlementStatus.pro;

  /// Policy for a later verified-cache layer. N1 does not issue or renew leases.
  static const offlineGracePeriod = Duration(days: 30);

  final EntitlementStatus status;

  /// Latest expiry among currently active grants, null for permanent Pro.
  /// The caller must re-evaluate grants when time or their state changes.
  final DateTime? validUntil;

  /// Supplied only by a future trusted verification layer, never by aggregation.
  final DateTime? verifiedAt;

  /// Reserved metadata; does not by itself grant access or verify a signature.
  /// A future cache resolver must check this before producing an access snapshot.
  final DateTime? offlineValidUntil;

  bool get isLifetime => status == EntitlementStatus.pro && validUntil == null;
}
