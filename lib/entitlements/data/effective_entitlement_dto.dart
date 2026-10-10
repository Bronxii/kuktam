import 'package:cloud_firestore/cloud_firestore.dart';
import '../domain/models/entitlement_grant.dart';

/// Schema parsing is not proof-origin validation.
final class EffectiveEntitlementDto {
  EffectiveEntitlementDto._(
    this.schemaVersion,
    this.active,
    this.validUntil,
    List<EntitlementSource> sources,
    this.revision,
    this.verifiedAt,
    this.updatedAt,
  ) : sources = List.unmodifiable(sources);
  final int schemaVersion;
  final bool active;
  final DateTime? validUntil;
  final List<EntitlementSource> sources;
  final int revision;
  final DateTime verifiedAt;
  final DateTime updatedAt;
  static const sourceNames = {
    'PLAY_PURCHASE': EntitlementSource.playPurchase,
    'PROMO': EntitlementSource.promo,
    'ADMIN': EntitlementSource.admin,
    'TEST': EntitlementSource.test,
  };
  static EffectiveEntitlementDto parse(Object? input) {
    final m = strictMap(input, const {
      'schemaVersion',
      'active',
      'validUntil',
      'sources',
      'revision',
      'verifiedAt',
      'updatedAt',
    });
    final version = m['schemaVersion'],
        revision = m['revision'],
        active = m['active'];
    if (version is! int ||
        ![1, 2].contains(version) ||
        revision is! int ||
        revision < 0 ||
        (revision == 0 && active != false) ||
        revision > 9007199254740991 ||
        active is! bool) {
      badData();
    }
    final raw = m['sources'];
    if (raw is! List || raw.any((s) => !sourceNames.containsKey(s))) badData();
    final sources = raw.map((s) => sourceNames[s]!).toList();
    if (sources.toSet().length != sources.length ||
        active != sources.isNotEmpty ||
        !active && m['validUntil'] != null) {
      badData();
    }
    return EffectiveEntitlementDto._(
      version,
      active,
      m['validUntil'] == null ? null : readTimestamp(m['validUntil']),
      sources,
      revision,
      readTimestamp(m['verifiedAt']),
      readTimestamp(m['updatedAt']),
    );
  }

  Map<String, Object?> toDocument() => {
    'schemaVersion': schemaVersion,
    'active': active,
    'validUntil': validUntil == null ? null : Timestamp.fromDate(validUntil!),
    'sources': sources
        .map((s) => sourceNames.entries.firstWhere((e) => e.value == s).key)
        .toList(),
    'revision': revision,
    'verifiedAt': Timestamp.fromDate(verifiedAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };
  bool sameEffective(EffectiveEntitlementDto other) =>
      active == other.active &&
      validUntil == other.validUntil &&
      sources.length == other.sources.length &&
      sources.toSet().containsAll(other.sources);
}

Never badData() => throw const FormatException('invalidEntitlementData');
Map<String, dynamic> strictMap(Object? v, Set<String> keys) {
  if (v is! Map<String, dynamic> ||
      v.length != keys.length ||
      !keys.every(v.containsKey)) {
    badData();
  }
  return v;
}

DateTime readTimestamp(Object? value) {
  // Firestore storage has microsecond precision. Reject finer data, never move
  // an exclusive expiry boundary silently.
  if (value is! Timestamp || value.nanoseconds % 1000 != 0) badData();
  return value.toDate().toUtc();
}
