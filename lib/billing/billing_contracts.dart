/// The only product supported by this Android client. No consumable semantics.
abstract final class ProProduct {
  static const id = 'kuktam_pro_lifetime';
  static const packageName = 'com.bronxii.kuktam';
}

enum BillingFailure {
  userCanceled,
  alreadyOwned,
  serviceUnavailable,
  network,
  billingUnavailable,
  itemUnavailable,
  configuration,
  unknown,
}

final class BillingException implements Exception {
  const BillingException(this.failure);
  final BillingFailure failure;
  @override
  String toString() => 'BillingException(${failure.name})';
}

final class ProductOffer {
  const ProductOffer({
    required this.localizedPrice,
    required this.currency,
    required this.title,
  });
  String get productId => ProProduct.id;
  final String localizedPrice;
  final String currency;
  final String title;
}

enum PurchaseEventKind { pending, purchased, restored, canceled, error }

/// Transient evidence only. Never persist or log this object or its token.
final class PurchaseEvidence {
  const PurchaseEvidence(
    this.token, {
    this.productId = ProProduct.id,
    this.packageName = ProProduct.packageName,
    this.accountBinding,
  });
  final String token;
  final String productId;
  final String packageName;
  final String? accountBinding;
  String get platform => 'android';
  bool get valid =>
      token.isNotEmpty &&
      token.length <= 16384 &&
      productId == ProProduct.id &&
      packageName == ProProduct.packageName;
  @override
  String toString() => 'PurchaseEvidence(redacted)';
}

final class PurchaseEvent {
  const PurchaseEvent(this.kind, {this.evidence, this.failure});
  final PurchaseEventKind kind;
  final PurchaseEvidence? evidence;
  final BillingFailure? failure;
}

abstract interface class BillingAdapter {
  Stream<PurchaseEvent> get events;
  Future<bool> isAvailable();

  /// Null means available store, but product not found.
  Future<ProductOffer?> loadOffer();
  Future<void> buyNonConsumable(
    String opaqueAccountBinding, {
    required bool Function() isCurrent,
  });

  /// Explicit query, not a global stream: its result is fenced to the caller.
  Future<List<PurchaseEvent>> restore();
  Future<void> dispose();
}

enum VerificationOutcome {
  verified,
  pending,
  rejected,
  accountDeleting,
  accountDeleted,
  tokenBindingConflict,
  supportRequired,
  temporaryFailure,
  permanentConfigurationFailure,
  malformedResponse,
}

/// Future transport MUST capture authenticated credentials for this session;
/// never send a caller-selected UID as authoritative request data.
/// Revoked sessions must refuse dispatch, including delayed token acquisition.
abstract interface class PurchaseVerificationGateway {
  Future<VerificationOutcome> verify(
    PurchaseEvidence evidence, {
    bool explicitRestore = false,
  });
}

abstract interface class PurchaseContextGateway {
  Future<String> preparePurchase();
}

final class PurchasePreparationException implements Exception {
  const PurchasePreparationException(this.outcome);
  final VerificationOutcome outcome;
  @override
  String toString() => 'PurchasePreparationException(${outcome.name})';
}

/// Supplied by the future authenticated session factory. Binding comes from the
/// server's HMAC endpoint, never from a client secret/raw UID. This is a local
/// fence, not a replacement for server authentication and token ownership.
final class PurchaseSession {
  PurchaseSession({
    required this.uid,
    this.accountBinding,
    this.contextGateway,
    required this.gateway,
    required this.isCurrent,
  }) {
    if (uid.isEmpty ||
        (accountBinding != null &&
            !RegExp(r'^v1_[A-Za-z0-9_-]{43}$').hasMatch(accountBinding!)) ||
        (accountBinding == null && contextGateway == null)) {
      throw ArgumentError('Invalid purchase session');
    }
  }
  final String uid;
  final String? accountBinding;
  final PurchaseContextGateway? contextGateway;
  final PurchaseVerificationGateway gateway;
  final bool Function() isCurrent;
}

enum PurchaseFlowStatus {
  idle,
  loadingStore,
  ready,
  launchingPurchase,
  restoring,
  pendingPurchase,
  verifying,
  refreshingEntitlement,
  completed,
  canceled,
  retryableError,
  supportRequired,
  rejected,
  unavailable,
  blocked,
}

final class PurchaseFlowState {
  const PurchaseFlowState(
    this.status, {
    this.offer,
    this.billingFailure,
    this.verificationOutcome,
  });
  final PurchaseFlowStatus status;
  final ProductOffer? offer;
  final BillingFailure? billingFailure;
  final VerificationOutcome? verificationOutcome;
}
