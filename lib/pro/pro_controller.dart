import 'dart:async';
import 'package:flutter/foundation.dart';
import '../billing/billing_contracts.dart';
import '../billing/purchase_orchestrator.dart';
import '../entitlements/domain/repositories/entitlement_repository.dart';

/// Presentation only: entitlement and purchase flow remain separate truths.
/// Owned by the app host, never by a route. Does not dispose N5 services.
class ProController extends ChangeNotifier {
  ProController({
    required this.entitlements,
    required this.purchases,
    required this.paymentsEnabled,
  }) {
    _sessionUid = entitlements.current.uid;
    _entitlementSubscription = entitlements.changes.listen((state) {
      if (state.uid != _sessionUid) {
        _sessionUid = state.uid;
        _commandGeneration++;
        _commandBusy = false;
        _lastAction = null;
        _previousFlow = null;
        noPurchaseFound = false;
      }
      _notify();
    });
    _purchaseSubscription = purchases.changes.listen((state) {
      if (state.status == PurchaseFlowStatus.restoring) {
        _lastAction = _Action.restore;
      }
      if (_lastAction == _Action.restore &&
          _previousFlow == PurchaseFlowStatus.restoring &&
          state.status == PurchaseFlowStatus.idle) {
        noPurchaseFound = true;
      }
      // Session reset must not retain an old account's presentation result.
      if (state.status == PurchaseFlowStatus.idle &&
          _previousFlow != PurchaseFlowStatus.restoring) {
        noPurchaseFound = false;
        _lastAction = null;
      }
      _previousFlow = state.status;
      _notify();
      if (_storeRequested &&
          state.status == PurchaseFlowStatus.idle &&
          !noPurchaseFound) {
        unawaited(load());
      }
    });
  }
  final EntitlementRepository entitlements;
  final PurchaseOrchestrator purchases;
  final bool paymentsEnabled;
  late final StreamSubscription<ClientEntitlementState>
  _entitlementSubscription;
  late final StreamSubscription<PurchaseFlowState> _purchaseSubscription;
  PurchaseFlowStatus? _previousFlow;
  _Action? _lastAction;
  bool _commandBusy = false, _disposed = false;
  bool _storeRequested = false;
  String? _sessionUid;
  int _commandGeneration = 0;
  bool noPurchaseFound = false;
  ClientEntitlementState get entitlement => entitlements.current;
  PurchaseFlowState get flow => purchases.current;
  bool get isPro =>
      entitlement.status == ClientEntitlementStatus.proOnline ||
      entitlement.status == ClientEntitlementStatus.proOfflineGrace;
  bool get checking =>
      entitlement.status == ClientEntitlementStatus.unknown ||
      entitlement.status == ClientEntitlementStatus.checking;
  bool get closed =>
      entitlement.failure == EntitlementFailure.accountDeleting ||
      entitlement.failure == EntitlementFailure.accountDeleted ||
      flow.verificationOutcome == VerificationOutcome.accountDeleting ||
      flow.verificationOutcome == VerificationOutcome.accountDeleted;
  bool get processing =>
      _commandBusy ||
      const {
        PurchaseFlowStatus.loadingStore,
        PurchaseFlowStatus.launchingPurchase,
        PurchaseFlowStatus.restoring,
        PurchaseFlowStatus.verifying,
        PurchaseFlowStatus.refreshingEntitlement,
      }.contains(flow.status);
  bool get canBuy =>
      paymentsEnabled &&
      !closed &&
      !processing &&
      entitlement.status == ClientEntitlementStatus.free &&
      flow.offer != null &&
      const {
        PurchaseFlowStatus.ready,
        PurchaseFlowStatus.canceled,
        PurchaseFlowStatus.idle,
      }.contains(flow.status);
  bool get canRestore =>
      paymentsEnabled &&
      !closed &&
      !processing &&
      !checking &&
      entitlement.uid != null &&
      flow.status != PurchaseFlowStatus.supportRequired;
  bool get canRetry =>
      paymentsEnabled &&
      !closed &&
      !processing &&
      !checking &&
      const {
        PurchaseFlowStatus.retryableError,
        PurchaseFlowStatus.unavailable,
        PurchaseFlowStatus.rejected,
      }.contains(flow.status);
  bool get restored => _lastAction == _Action.restore;
  String get statusLabel {
    if (closed) {
      return 'Ez a Kuktám-fiók törlés alatt áll vagy már törölve lett.';
    }
    return switch (entitlement.status) {
      ClientEntitlementStatus.unknown ||
      ClientEntitlementStatus.checking => 'Pro állapot ellenőrzése…',
      ClientEntitlementStatus.free => 'Kuktám Free',
      ClientEntitlementStatus.proOnline => 'Kuktám Pro – Aktív',
      ClientEntitlementStatus.proOfflineGrace => 'Kuktám Pro – offline módban',
      ClientEntitlementStatus.unavailable =>
        'A Pro jogosultság ellenőrzéséhez internetkapcsolat szükséges.',
    };
  }

  String? get message {
    if (closed) {
      return 'Ehhez a fiókhoz már nem indítható vásárlás vagy visszaállítás.';
    }
    if (!paymentsEnabled) {
      return 'A vásárlás és a visszaállítás jelenleg nem érhető el.';
    }
    if (noPurchaseFound) {
      return 'Nem találtunk visszaállítható Kuktám Pro vásárlást.';
    }
    if (flow.verificationOutcome ==
            VerificationOutcome.permanentConfigurationFailure ||
        flow.billingFailure == BillingFailure.configuration) {
      return 'A vásárlás jelenleg nem érhető el. Próbáld újra később.';
    }
    return switch (flow.status) {
      PurchaseFlowStatus.idle || PurchaseFlowStatus.ready => null,
      PurchaseFlowStatus.loadingStore => 'Vásárlási adatok betöltése…',
      PurchaseFlowStatus.launchingPurchase =>
        'Google Play vásárlás megnyitása…',
      PurchaseFlowStatus.restoring => 'Korábbi vásárlás ellenőrzése…',
      PurchaseFlowStatus.pendingPurchase =>
        'A vásárlás még feldolgozás alatt van.',
      PurchaseFlowStatus.verifying => 'Vásárlás ellenőrzése…',
      PurchaseFlowStatus.refreshingEntitlement => 'Pro állapot frissítése…',
      PurchaseFlowStatus.completed =>
        isPro
            ? (restored ? 'A Kuktám Pro helyreállítva.' : 'A Kuktám Pro aktív.')
            : 'A Pro állapot ellenőrzése még nem fejeződött be.',
      PurchaseFlowStatus.canceled => 'A vásárlás megszakadt.',
      PurchaseFlowStatus.retryableError =>
        'Az ellenőrzés most nem sikerült. Próbáld újra.',
      PurchaseFlowStatus.supportRequired =>
        'Ezt a korábbi vásárlást nem tudtuk automatikusan ehhez a Kuktám-fiókhoz kapcsolni. Fordulj a Kuktám ügyfélszolgálatához.',
      PurchaseFlowStatus.rejected =>
        'A vásárlást nem sikerült igazolni. Ellenőrizd a korábbi vásárlásaidat.',
      PurchaseFlowStatus.unavailable =>
        flow.billingFailure == BillingFailure.itemUnavailable
            ? 'A Kuktám Pro jelenleg nem vásárolható meg.'
            : 'A Google Play vásárlás jelenleg nem érhető el.',
      PurchaseFlowStatus.blocked =>
        'A vásárláshoz jelentkezz be egy aktív Kuktám-fiókba.',
    };
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_disposed || _commandBusy) return;
    final generation = _commandGeneration;
    _commandBusy = true;
    noPurchaseFound = false;
    _notify();
    try {
      await action();
    } finally {
      if (generation == _commandGeneration) {
        _commandBusy = false;
        _notify();
      }
    }
  }

  Future<void> load() async {
    _storeRequested = true;
    if (!paymentsEnabled ||
        closed ||
        processing ||
        flow.status != PurchaseFlowStatus.idle) {
      return;
    }
    await _run(purchases.loadOffer);
  }

  Future<void> buy() async {
    if (!canBuy) return;
    _lastAction = _Action.buy;
    await _run(purchases.buyPro);
  }

  Future<void> restore() async {
    if (!canRestore) return;
    _lastAction = _Action.restore;
    await _run(purchases.restore);
  }

  Future<void> retry() async {
    if (!canRetry) return;
    if (flow.status == PurchaseFlowStatus.unavailable && _lastAction == null) {
      await _run(purchases.loadOffer);
    } else {
      await restore(); // N5 retry queries ownership; never repurchases blindly.
    }
  }

  Future<void> refresh() async {
    if (!paymentsEnabled || closed || processing) return;
    await _run(entitlements.refresh);
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_entitlementSubscription.cancel());
    unawaited(_purchaseSubscription.cancel());
    super.dispose();
  }
}

enum _Action { buy, restore }
