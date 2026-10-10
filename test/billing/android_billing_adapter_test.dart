import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:kuktam/billing/android_billing_adapter.dart';
import 'package:kuktam/billing/billing_contracts.dart';
import 'fakes.dart';

const ok = BillingResultWrapper(responseCode: BillingResponse.ok);
PurchaseWrapper purchase({
  PurchaseStateWrapper state = PurchaseStateWrapper.purchased,
  bool acknowledged = false,
}) => PurchaseWrapper(
  orderId: 'fake-order',
  packageName: ProProduct.packageName,
  purchaseTime: 1,
  purchaseToken: 'secret',
  signature: '',
  products: const [ProProduct.id],
  isAutoRenewing: false,
  originalJson: '{}',
  isAcknowledged: acknowledged,
  purchaseState: state,
  obfuscatedAccountId: bindingA,
);
PurchasesResultWrapper purchases(
  List<PurchaseWrapper> list, {
  BillingResponse code = BillingResponse.ok,
}) => PurchasesResultWrapper(
  billingResult: BillingResultWrapper(responseCode: code),
  responseCode: BillingResponse.ok,
  purchasesList: list,
);

class NativeFake implements BillingClient {
  Completer<BillingResultWrapper>? connectionBarrier;
  int starts = 0, ends = 0, launches = 0, acks = 0, consumes = 0;
  BillingResponse launchCode = BillingResponse.ok;
  PurchasesResultWrapper owned = purchases([]);
  late PurchasesUpdatedListener listener;
  String? account;
  List<ProductWrapper>? queried;
  bool found = true;
  @override
  Future<BillingResultWrapper> startConnection({
    required OnBillingServiceDisconnected onBillingServiceDisconnected,
    BillingChoiceMode billingChoiceMode = BillingChoiceMode.playBillingOnly,
    dynamic pendingPurchasesParams,
  }) async {
    starts++;
    return connectionBarrier == null ? ok : await connectionBarrier!.future;
  }

  @override
  Future<void> endConnection() async {
    ends++;
  }

  @override
  Future<ProductDetailsResponseWrapper> queryProductDetails({
    required List<ProductWrapper> productList,
  }) async {
    queried = productList;
    return ProductDetailsResponseWrapper(
      billingResult: ok,
      productDetailsList: found
          ? [
              const ProductDetailsWrapper(
                description: 'Pro',
                name: 'Pro',
                productId: ProProduct.id,
                productType: ProductType.inapp,
                title: 'Pro lifetime',
                oneTimePurchaseOfferDetails: OneTimePurchaseOfferDetailsWrapper(
                  formattedPrice: '£4.99',
                  priceAmountMicros: 4990000,
                  priceCurrencyCode: 'GBP',
                ),
              ),
            ]
          : [],
    );
  }

  @override
  Future<BillingResultWrapper> launchBillingFlow({
    required String product,
    String? offerToken,
    String? accountId,
    String? obfuscatedProfileId,
    String? oldProduct,
    String? purchaseToken,
    ReplacementMode? replacementMode,
  }) async {
    launches++;
    account = accountId;
    expect(product, ProProduct.id);
    expect(oldProduct, isNull);
    expect(purchaseToken, isNull);
    expect(replacementMode, isNull);
    return BillingResultWrapper(responseCode: launchCode);
  }

  @override
  Future<PurchasesResultWrapper> queryPurchases(ProductType productType) async {
    expect(productType, ProductType.inapp);
    return owned;
  }

  @override
  Future<BillingResultWrapper> acknowledgePurchase(
    String purchaseToken, {
    String? developerPayload,
  }) async {
    acks++;
    throw StateError('Client ACK forbidden');
  }

  @override
  Future<BillingResultWrapper> consumeAsync(
    String purchaseToken, {
    String? developerPayload,
  }) async {
    consumes++;
    throw StateError('Client consume forbidden');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected native call');
}

void main() {
  late NativeFake native;
  late AndroidBillingAdapter adapter;
  setUp(() {
    native = NativeFake();
    adapter = AndroidBillingAdapter(
      android: true,
      clientFactory: (listener) {
        native.listener = listener;
        return native;
      },
    );
  });
  tearDown(() async {
    await adapter.dispose();
    expect(native.acks, 0);
    expect(native.consumes, 0);
  });
  test('one native connection, localized price, inapp product only', () async {
    await Future.wait([adapter.isAvailable(), adapter.isAvailable()]);
    final offer = await adapter.loadOffer();
    expect(native.starts, 1);
    expect(offer!.localizedPrice, '£4.99');
    expect(native.queried!.single.productType, ProductType.inapp);
    await adapter.buyNonConsumable(bindingA, isCurrent: () => true);
    expect(native.account, bindingA);
  });
  test('product not found returns null', () async {
    native.found = false;
    expect(await adapter.loadOffer(), isNull);
  });
  test('raw UID cannot be sent as binding', () async {
    await adapter.loadOffer();
    await expectLater(
      adapter.buyNonConsumable('firebase-uid', isCurrent: () => true),
      throwsA(isA<BillingException>()),
    );
    expect(native.launches, 0);
  });
  test(
    'session invalidated before native launch suppresses purchase',
    () async {
      await adapter.loadOffer();
      await adapter.buyNonConsumable(bindingA, isCurrent: () => false);
      expect(native.launches, 0);
    },
  );
  for (final state in PurchaseStateWrapper.values) {
    test('restore preserves native state $state', () async {
      native.owned = purchases([purchase(state: state)]);
      final e = (await adapter.restore()).single;
      expect(e.kind, switch (state) {
        PurchaseStateWrapper.pending => PurchaseEventKind.pending,
        PurchaseStateWrapper.purchased => PurchaseEventKind.restored,
        _ => PurchaseEventKind.error,
      });
      expect(e.evidence!.token, 'secret');
    });
  }
  for (final ack in [false, true]) {
    test(
      'native purchase acknowledged=$ack never acknowledged or consumed by client',
      () async {
        final received = <PurchaseEvent>[];
        final sub = adapter.events.listen(received.add);
        await adapter.loadOffer();
        await adapter.buyNonConsumable(bindingA, isCurrent: () => true);
        native.listener(purchases([purchase(acknowledged: ack)]));
        await flush();
        expect(received.single.kind, PurchaseEventKind.purchased);
        native.owned = purchases([purchase(acknowledged: ack)]);
        await adapter.restore();
        await sub.cancel();
      },
    );
  }
  final codes = {
    BillingResponse.userCanceled: BillingFailure.userCanceled,
    BillingResponse.itemAlreadyOwned: BillingFailure.alreadyOwned,
    BillingResponse.serviceUnavailable: BillingFailure.serviceUnavailable,
    BillingResponse.serviceTimeout: BillingFailure.serviceUnavailable,
    BillingResponse.serviceDisconnected: BillingFailure.serviceUnavailable,
    BillingResponse.networkError: BillingFailure.network,
    BillingResponse.billingUnavailable: BillingFailure.billingUnavailable,
    BillingResponse.itemUnavailable: BillingFailure.itemUnavailable,
    BillingResponse.developerError: BillingFailure.configuration,
    BillingResponse.error: BillingFailure.unknown,
  };
  for (final entry in codes.entries) {
    test('launch exact error ${entry.key} sanitized', () async {
      await adapter.loadOffer();
      native.launchCode = entry.key;
      await expectLater(
        adapter.buyNonConsumable(bindingA, isCurrent: () => true),
        throwsA(
          isA<BillingException>().having(
            (e) => e.failure,
            'failure',
            entry.value,
          ),
        ),
      );
    });
  }
  test(
    'owned query inspects real billing result despite forced wrapper OK',
    () async {
      native.owned = purchases([], code: BillingResponse.networkError);
      await expectLater(adapter.restore(), throwsA(isA<BillingException>()));
    },
  );
  test('callback cancellation and stream mapping', () async {
    final received = <PurchaseEvent>[];
    final sub = adapter.events.listen(received.add);
    await adapter.isAvailable();
    native.listener(purchases([], code: BillingResponse.userCanceled));
    await flush();
    expect(received.single.kind, PurchaseEventKind.canceled);
    await sub.cancel();
  });
  test(
    'dispose stops native connection and late callback is ignored',
    () async {
      await adapter.isAvailable();
      await adapter.dispose();
      native.listener(purchases([purchase()]));
      expect(native.ends, 1);
      expect(await adapter.isAvailable(), false);
    },
  );
  test(
    'late native connection completion after dispose is closed again',
    () async {
      native.connectionBarrier = Completer<BillingResultWrapper>();
      final connecting = adapter.isAvailable();
      await adapter.dispose();
      native.connectionBarrier!.complete(ok);
      expect(await connecting, false);
      expect(native.ends, 2);
    },
  );
  test('non Android never creates a native client', () async {
    final other = AndroidBillingAdapter(
      android: false,
      clientFactory: (_) => throw StateError('wrong platform'),
    );
    expect(await other.isAvailable(), false);
    await other.dispose();
  });
}
