import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'billing_contracts.dart';

BillingFailure mapBillingResponse(BillingResponse response) =>
    switch (response) {
      BillingResponse.userCanceled => BillingFailure.userCanceled,
      BillingResponse.itemAlreadyOwned => BillingFailure.alreadyOwned,
      BillingResponse.serviceTimeout ||
      BillingResponse.serviceDisconnected ||
      BillingResponse.serviceUnavailable => BillingFailure.serviceUnavailable,
      BillingResponse.networkError => BillingFailure.network,
      BillingResponse.billingUnavailable ||
      BillingResponse.featureNotSupported => BillingFailure.billingUnavailable,
      BillingResponse.itemUnavailable => BillingFailure.itemUnavailable,
      BillingResponse.developerError => BillingFailure.configuration,
      _ => BillingFailure.unknown,
    };

/// Uses the plugin's public Android wrappers to preserve launch response codes
/// and pending ownership on restore. Owns one native connection/callback.
/// No completePurchase, acknowledgePurchase or consumePurchase calls.
final class AndroidBillingAdapter implements BillingAdapter {
  AndroidBillingAdapter({
    BillingClient Function(PurchasesUpdatedListener)? clientFactory,
    bool? android,
    this.timeout = const Duration(seconds: 20),
  }) : _factory =
           clientFactory ?? ((listener) => BillingClient(listener, null)),
       _android =
           android ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  final BillingClient Function(PurchasesUpdatedListener) _factory;
  final bool _android;
  final Duration timeout;
  final _events = StreamController<PurchaseEvent>.broadcast();
  BillingClient? _client;
  Future<bool>? _connecting;
  bool _connected = false;
  bool _disposed = false;
  bool _offerLoaded = false;
  @override
  Stream<PurchaseEvent> get events => _events.stream;

  void _check(BillingResponse code) {
    if (code != BillingResponse.ok) {
      throw BillingException(mapBillingResponse(code));
    }
  }

  Future<T> _safe<T>(Future<T> Function() action) async {
    try {
      return await action().timeout(timeout);
    } on BillingException {
      rethrow;
    } on TimeoutException {
      throw const BillingException(BillingFailure.serviceUnavailable);
    } catch (_) {
      throw const BillingException(BillingFailure.unknown);
    }
  }

  @override
  Future<bool> isAvailable() async {
    if (_disposed || !_android) return false;
    if (_connected) return true;
    return _connecting ??= _connect();
  }

  Future<bool> _connect() async {
    try {
      _client ??= _factory(_onUpdate);
      final result = await _safe(() async {
        final result = await _client!.startConnection(
          onBillingServiceDisconnected: () {
            _connected = false;
          },
        );
        // Setup can finish after timeout/dispose. Close a late connection.
        if (_disposed) await _client!.endConnection().timeout(timeout);
        return result;
      });
      if (_disposed) return false;
      _check(result.responseCode);
      _connected = true;
      return true;
    } finally {
      _connecting = null;
    }
  }

  Future<void> _requireStore() async {
    if (!await isAvailable()) {
      throw const BillingException(BillingFailure.billingUnavailable);
    }
    if (_disposed) {
      throw const BillingException(BillingFailure.billingUnavailable);
    }
  }

  @override
  Future<ProductOffer?> loadOffer() => _safe(() async {
    await _requireStore();
    _offerLoaded = false;
    final result = await _client!.queryProductDetails(
      productList: const [
        ProductWrapper(
          productId: ProProduct.id,
          productType: ProductType.inapp,
        ),
      ],
    );
    _check(result.billingResult.responseCode);
    final matches = result.productDetailsList
        .where(
          (p) =>
              p.productId == ProProduct.id &&
              p.productType == ProductType.inapp,
        )
        .toList();
    if (matches.isEmpty) return null;
    if (matches.length != 1 ||
        matches.single.oneTimePurchaseOfferDetails == null) {
      throw const BillingException(BillingFailure.configuration);
    }
    final product = matches.single;
    final price = product.oneTimePurchaseOfferDetails!;
    if (!_disposed) _offerLoaded = true;
    return ProductOffer(
      localizedPrice: price.formattedPrice,
      currency: price.priceCurrencyCode,
      title: product.title,
    );
  });

  @override
  Future<void> buyNonConsumable(
    String opaqueAccountBinding, {
    required bool Function() isCurrent,
  }) => _safe(() async {
    await _requireStore();
    if (!isCurrent()) return;
    if (!_offerLoaded ||
        !RegExp(r'^v1_[A-Za-z0-9_-]{43}$').hasMatch(opaqueAccountBinding)) {
      throw const BillingException(BillingFailure.configuration);
    }
    final result = await _client!.launchBillingFlow(
      product: ProProduct.id,
      accountId: opaqueAccountBinding,
    );
    _check(result.responseCode);
  });

  @override
  Future<List<PurchaseEvent>> restore() => _safe(() async {
    await _requireStore();
    final result = await _client!.queryPurchases(ProductType.inapp);
    // Wrapper responseCode can be forced OK by the plugin. Inspect actual result.
    _check(result.billingResult.responseCode);
    return _mapPurchases(result, restored: true);
  });

  List<PurchaseEvent> _mapPurchases(
    PurchasesResultWrapper result, {
    bool restored = false,
  }) {
    final events = <PurchaseEvent>[];
    for (final p in result.purchasesList) {
      if (!p.products.contains(ProProduct.id)) continue;
      final evidence = PurchaseEvidence(
        p.purchaseToken,
        packageName: p.packageName,
        accountBinding: p.obfuscatedAccountId,
      );
      final kind = switch (p.purchaseState) {
        PurchaseStateWrapper.pending => PurchaseEventKind.pending,
        PurchaseStateWrapper.purchased =>
          restored ? PurchaseEventKind.restored : PurchaseEventKind.purchased,
        _ => PurchaseEventKind.error,
      };
      events.add(
        PurchaseEvent(
          kind,
          evidence: evidence,
          failure: kind == PurchaseEventKind.error
              ? BillingFailure.unknown
              : null,
        ),
      );
    }
    return events;
  }

  void _onUpdate(PurchasesResultWrapper result) {
    if (_disposed) return;
    if (result.billingResult.responseCode != BillingResponse.ok) {
      final failure = mapBillingResponse(result.billingResult.responseCode);
      _events.add(
        PurchaseEvent(
          failure == BillingFailure.userCanceled
              ? PurchaseEventKind.canceled
              : PurchaseEventKind.error,
          failure: failure,
        ),
      );
      return;
    }
    for (final event in _mapPurchases(result)) {
      _events.add(event);
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _connected = false;
    _offerLoaded = false;
    try {
      await _client?.endConnection().timeout(timeout);
    } catch (_) {
      /* No raw plugin errors. */
    }
    await _events.close();
  }
}
