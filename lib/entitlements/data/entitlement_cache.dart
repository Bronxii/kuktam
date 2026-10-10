import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'effective_entitlement_dto.dart';
import 'entitlement_contracts.dart';

/// Best-effort offline evidence, not a signed proof. No client secret.
final class EntitlementCache {
  EntitlementCache(
    this.proof,
    this.lastWall,
    this.estimatedAt, {
    this.suspiciousClock = false,
  }) {
    if (!lastWall.isUtc ||
        !estimatedAt.isUtc ||
        estimatedAt.isBefore(proof.trustedProofAt)) {
      badData();
    }
  }
  final TrustedEntitlementProof proof;
  final DateTime lastWall;
  final DateTime estimatedAt;
  final bool suspiciousClock;
  String encode() {
    final doc = proof.entitlement.toDocument();
    for (final k in ['validUntil', 'verifiedAt', 'updatedAt']) {
      final t = doc[k];
      doc[k] = t == null
          ? null
          : (t as Timestamp).toDate().microsecondsSinceEpoch;
    }
    return jsonEncode({
      'schemaVersion': 1,
      'suspiciousClock': suspiciousClock,
      'uid': proof.uid,
      'effective': doc,
      'trustedProofAt': proof.trustedProofAt.microsecondsSinceEpoch,
      'offlineValidUntil': proof.offlineValidUntil.microsecondsSinceEpoch,
      'lastWall': lastWall.microsecondsSinceEpoch,
      'estimatedAt': estimatedAt.microsecondsSinceEpoch,
    });
  }

  static EntitlementCache decode(String value, String uid) {
    if (value.length > 16384) badData();
    final m = strictMap(jsonDecode(value), const {
      'schemaVersion',
      'suspiciousClock',
      'uid',
      'effective',
      'trustedProofAt',
      'offlineValidUntil',
      'lastWall',
      'estimatedAt',
    });
    if (m['schemaVersion'] is! int ||
        m['schemaVersion'] != 1 ||
        m['uid'] != uid ||
        m['suspiciousClock'] is! bool) {
      badData();
    }
    final doc = Map<String, dynamic>.from(
      strictMap(m['effective'], const {
        'schemaVersion',
        'active',
        'validUntil',
        'sources',
        'revision',
        'verifiedAt',
        'updatedAt',
      }),
    );
    for (final k in ['validUntil', 'verifiedAt', 'updatedAt']) {
      if (doc[k] != null) doc[k] = Timestamp.fromDate(_time(doc[k]));
    }
    final p = TrustedEntitlementProof(
      uid: uid,
      entitlement: EffectiveEntitlementDto.parse(doc),
      trustedProofAt: _time(m['trustedProofAt']),
    );
    if (p.offlineValidUntil != _time(m['offlineValidUntil'])) badData();
    return EntitlementCache(
      p,
      _time(m['lastWall']),
      _time(m['estimatedAt']),
      suspiciousClock: m['suspiciousClock'] as bool,
    );
  }

  static DateTime _time(Object? v) {
    if (v is! int || v < -62135596800000000 || v > 253402300799999999) {
      badData();
    }
    return DateTime.fromMicrosecondsSinceEpoch(v, isUtc: true);
  }
}
