import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../billing/billing_contracts.dart';
import '../entitlements/data/effective_entitlement_dto.dart';
import '../entitlements/data/entitlement_contracts.dart';
import '../entitlements/domain/repositories/entitlement_repository.dart';

abstract interface class CallableTransport {
  Future<Object?> call(String name, Map<String, Object?> data);
}

final class TransportFailure implements Exception {
  const TransportFailure(this.code);
  final String code;
  @override
  String toString() => 'TransportFailure';
}

/// Explicitly injected Functions instance, region and session predicate.
/// No singleton/default production endpoint, no manually handled Auth tokens.
final class FirebaseCallableTransport implements CallableTransport {
  FirebaseCallableTransport({required this.functions, required this.isCurrent});
  final FirebaseFunctions functions;
  final bool Function() isCurrent;
  @override
  Future<Object?> call(String name, Map<String, Object?> data) async {
    if (!isCurrent()) throw const TransportFailure('unauthenticated');
    if (!{
      'prepareProPurchase',
      'verifyProPurchase',
      'getEntitlementProof',
    }.contains(name)) {
      throw const TransportFailure('invalidArgument');
    }
    try {
      final result = await functions
          .httpsCallable(
            name,
            options: HttpsCallableOptions(timeout: const Duration(seconds: 25)),
          )
          .call<Object?>(data);
      if (!isCurrent()) throw const TransportFailure('unauthenticated');
      return result.data;
    } on FirebaseFunctionsException catch (e) {
      throw TransportFailure(switch (e.code) {
        'unauthenticated' => 'unauthenticated',
        'permission-denied' => 'permissionDenied',
        'invalid-argument' => 'invalidArgument',
        'not-found' || 'unimplemented' => 'configuration',
        _ => 'retryableUnavailable',
      });
    }
  }
}

Map<String, dynamic> responseMap(Object? raw, Set<String> keys) {
  if (raw is! Map || raw.keys.any((k) => k is! String)) {
    throw const TransportFailure('internalMalformed');
  }
  final map = Map<String, dynamic>.from(raw);
  if (map['schemaVersion'] is! int || map['schemaVersion'] != 1) {
    throw const TransportFailure('internalMalformed');
  }
  if (map.length == 2 &&
      map['error'] is String &&
      map.containsKey('schemaVersion')) {
    throw TransportFailure(map['error'] as String);
  }
  if (map.length != keys.length || !keys.every(map.containsKey)) {
    throw const TransportFailure('internalMalformed');
  }
  return map;
}

VerificationOutcome verificationFailure(Object error) =>
    switch (error is TransportFailure ? error.code : '') {
      'accountDeleting' => VerificationOutcome.accountDeleting,
      'accountDeleted' => VerificationOutcome.accountDeleted,
      'tokenBindingConflict' => VerificationOutcome.tokenBindingConflict,
      'permissionDenied' ||
      'supportRequired' => VerificationOutcome.supportRequired,
      'configuration' => VerificationOutcome.permanentConfigurationFailure,
      'internalMalformed' => VerificationOutcome.malformedResponse,
      'invalidArgument' => VerificationOutcome.rejected,
      _ => VerificationOutcome.temporaryFailure,
    };

final class CallablePurchaseGateway
    implements PurchaseVerificationGateway, PurchaseContextGateway {
  CallablePurchaseGateway(this.transport, {this.onAccountClosed});
  final CallableTransport transport;
  final Future<void> Function(EntitlementFailure)? onAccountClosed;
  Future<void> _invalidate(Object e) async {
    if (e is TransportFailure &&
        (e.code == 'accountDeleting' || e.code == 'accountDeleted')) {
      await onAccountClosed?.call(
        e.code == 'accountDeleting'
            ? EntitlementFailure.accountDeleting
            : EntitlementFailure.accountDeleted,
      );
    }
  }

  @override
  Future<String> preparePurchase() async {
    try {
      final map = responseMap(await transport.call('prepareProPurchase', {}), {
        'schemaVersion',
        'productId',
        'opaqueAccountId',
      });
      final binding = map['opaqueAccountId'];
      if (map['productId'] != ProProduct.id ||
          binding is! String ||
          !RegExp(r'^v1_[A-Za-z0-9_-]{43}$').hasMatch(binding)) {
        throw const TransportFailure('internalMalformed');
      }
      return binding;
    } catch (e) {
      await _invalidate(e);
      throw PurchasePreparationException(verificationFailure(e));
    }
  }

  @override
  Future<VerificationOutcome> verify(
    PurchaseEvidence evidence, {
    bool explicitRestore = false,
  }) async {
    if (!evidence.valid ||
        evidence.token.length > 4096 ||
        evidence.token.trim() != evidence.token) {
      return VerificationOutcome.rejected;
    }
    try {
      final map = responseMap(
        await transport.call('verifyProPurchase', {
          'productId': ProProduct.id,
          'purchaseToken': evidence.token,
          if (explicitRestore) 'intent': 'restore',
        }),
        {'schemaVersion', 'outcome'},
      );
      return switch (map['outcome']) {
        'verified' => VerificationOutcome.verified,
        'pending' => VerificationOutcome.pending,
        'rejected' => VerificationOutcome.rejected,
        _ => VerificationOutcome.malformedResponse,
      };
    } catch (e) {
      await _invalidate(e);
      return verificationFailure(e);
    }
  }
}

final class CallableEntitlementBackend implements TrustedEntitlementBackend {
  CallableEntitlementBackend({
    required this.transport,
    required this.uid,
    required this.isCurrent,
  });
  final CallableTransport transport;
  final String uid;
  final bool Function() isCurrent;
  @override
  Future<TrustedEntitlementProof> fetchProof(String requestedUid) async {
    try {
      if (requestedUid != uid || !isCurrent()) {
        throw const TransportFailure('unauthenticated');
      }
      final map = responseMap(await transport.call('getEntitlementProof', {}), {
        'schemaVersion',
        'active',
        'sources',
        'validUntil',
        'revision',
        'verifiedAt',
        'updatedAt',
        'proofIssuedAt',
      });
      if (!isCurrent()) throw const TransportFailure('unauthenticated');
      DateTime time(Object? value) {
        if (value is! int || value < 0 || value > 8640000000000000) {
          throw const TransportFailure('internalMalformed');
        }
        return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
      }

      final dto = EffectiveEntitlementDto.parse({
        'schemaVersion': 2,
        'active': map['active'],
        'sources': map['sources'],
        'validUntil': map['validUntil'] == null
            ? null
            : Timestamp.fromDate(time(map['validUntil'])),
        'revision': map['revision'],
        'verifiedAt': Timestamp.fromDate(time(map['verifiedAt'])),
        'updatedAt': Timestamp.fromDate(time(map['updatedAt'])),
      });
      return TrustedEntitlementProof(
        uid: uid,
        entitlement: dto,
        trustedProofAt: time(map['proofIssuedAt']),
      );
    } catch (e) {
      throw EntitlementBackendException(switch (e is TransportFailure
          ? e.code
          : 'internalMalformed') {
        'unauthenticated' => EntitlementFailure.unauthenticated,
        'permissionDenied' => EntitlementFailure.permissionDenied,
        'accountDeleting' => EntitlementFailure.accountDeleting,
        'accountDeleted' => EntitlementFailure.accountDeleted,
        'retryableUnavailable' ||
        'configuration' => EntitlementFailure.serverUnavailable,
        _ => EntitlementFailure.malformedEntitlement,
      });
    }
  }
}
