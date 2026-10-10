import 'dart:async';
import '../entitlements/domain/repositories/entitlement_repository.dart';
import 'billing_contracts.dart';

/// App/service scoped; the future auth host must call bindSession(null) BEFORE
/// logout/account switch, then initialize the entitlement repository and bind
/// the new authenticated session. No UI, credentials, persistent tokens or ACK.
final class PurchaseOrchestrator {
  PurchaseOrchestrator({
    required this.billing,
    required this.entitlements,
    this.verificationTimeout = const Duration(seconds: 30),
  }) {
    _subscription = billing.events.listen(
      _onEvent,
      onError: (Object _) {
        if (_valid(_generation) && _inFlight.isEmpty) {
          _set(
            PurchaseFlowStatus.retryableError,
            failure: BillingFailure.unknown,
          );
        }
      },
    );
  }
  final BillingAdapter billing;
  final EntitlementRepository entitlements;
  final Duration verificationTimeout;
  final _states = StreamController<PurchaseFlowState>.broadcast();
  late final StreamSubscription<PurchaseEvent> _subscription;
  PurchaseFlowState _current = const PurchaseFlowState(PurchaseFlowStatus.idle);
  PurchaseFlowState get current => _current;
  Stream<PurchaseFlowState> get changes => _states.stream;
  PurchaseSession? _session;
  int _generation = 0;
  bool _disposed = false;
  bool _action = false;
  bool _closedAccount = false;
  bool _awaitingPurchase = false;
  ProductOffer? _offer;
  String? _purchaseBinding;
  Future<void> _tail = Future.value();
  final Map<String, Future<void>> _inFlight = {};

  void bindSession(PurchaseSession? session) {
    if (_disposed) return;
    _generation++;
    _session = session;
    _action = false;
    _closedAccount = false;
    _awaitingPurchase = false;
    _offer = null;
    _purchaseBinding = null;
    _inFlight.clear();
    _tail = Future.value();
    _set(PurchaseFlowStatus.idle);
  }

  bool _valid(int generation) {
    final session = _session;
    return !_disposed &&
        generation == _generation &&
        session != null &&
        session.isCurrent() &&
        entitlements.current.uid == session.uid &&
        !_closedAccount &&
        entitlements.current.failure != EntitlementFailure.accountDeleting &&
        entitlements.current.failure != EntitlementFailure.accountDeleted;
  }

  void _set(
    PurchaseFlowStatus status, {
    BillingFailure? failure,
    VerificationOutcome? outcome,
  }) {
    if (_disposed) return;
    _current = PurchaseFlowState(
      status,
      offer: _offer,
      billingFailure: failure,
      verificationOutcome: outcome,
    );
    _states.add(_current);
  }

  void _reportAccountClosure(int generation) {
    if (_disposed ||
        generation != _generation ||
        _session?.isCurrent() != true) {
      return;
    }
    final failure = entitlements.current.failure;
    if (failure == EntitlementFailure.accountDeleting ||
        failure == EntitlementFailure.accountDeleted) {
      _closedAccount = true;
      _set(
        PurchaseFlowStatus.blocked,
        outcome: failure == EntitlementFailure.accountDeleting
            ? VerificationOutcome.accountDeleting
            : VerificationOutcome.accountDeleted,
      );
    }
  }

  Future<void> loadOffer() async {
    final generation = _generation;
    if (!_valid(generation) || _action || _inFlight.isNotEmpty) return;
    _action = true;
    _set(PurchaseFlowStatus.loadingStore);
    try {
      final available = await billing.isAvailable();
      if (!_valid(generation)) return;
      if (!available) {
        _offer = null;
        _set(
          PurchaseFlowStatus.unavailable,
          failure: BillingFailure.billingUnavailable,
        );
        return;
      }
      final offer = await billing.loadOffer();
      if (!_valid(generation)) return;
      _offer = offer;
      _set(
        offer == null
            ? PurchaseFlowStatus.unavailable
            : PurchaseFlowStatus.ready,
        failure: offer == null ? BillingFailure.itemUnavailable : null,
      );
    } catch (error) {
      if (_valid(generation)) _billingError(error);
    } finally {
      if (generation == _generation) _action = false;
    }
  }

  Future<void> buyPro() async {
    final generation = _generation;
    if (!_valid(generation)) {
      _set(PurchaseFlowStatus.blocked);
      return;
    }
    if (_action || _awaitingPurchase || _inFlight.isNotEmpty) return;
    if (_offer == null) {
      _set(
        PurchaseFlowStatus.unavailable,
        failure: BillingFailure.itemUnavailable,
      );
      return;
    }
    _action = true;
    _set(PurchaseFlowStatus.launchingPurchase);
    try {
      if (!await billing.isAvailable()) {
        throw const BillingException(BillingFailure.billingUnavailable);
      }
      if (!_valid(generation)) return;
      final session = _session!;
      final binding = session.contextGateway == null
          ? session.accountBinding!
          : await session.contextGateway!.preparePurchase();
      if (!_valid(generation)) return;
      _purchaseBinding = binding;
      _awaitingPurchase = true;
      await billing.buyNonConsumable(
        binding,
        isCurrent: () => _valid(generation),
      );
    } catch (error) {
      _reportAccountClosure(generation);
      if (!_valid(generation)) return;
      _awaitingPurchase = false;
      _purchaseBinding = null;
      if (error is PurchasePreparationException) {
        final outcome = error.outcome;
        _closedAccount =
            outcome == VerificationOutcome.accountDeleting ||
            outcome == VerificationOutcome.accountDeleted;
        _set(
          _closedAccount
              ? PurchaseFlowStatus.blocked
              : outcome == VerificationOutcome.temporaryFailure
              ? PurchaseFlowStatus.retryableError
              : PurchaseFlowStatus.supportRequired,
          outcome: outcome,
        );
        return;
      }
      if (error is BillingException &&
          error.failure == BillingFailure.alreadyOwned) {
        await _restore(generation);
      } else if (_inFlight.isEmpty) {
        _billingError(error);
      }
    } finally {
      if (generation == _generation) _action = false;
    }
  }

  /// Also the explicit retry entry point. Re-query ownership rather than keep a
  /// token history after a failed verification. No automatic retry engine.
  Future<void> restore() async {
    final generation = _generation;
    if (!_valid(generation)) {
      _set(PurchaseFlowStatus.blocked);
      return;
    }
    if (_action || _inFlight.isNotEmpty) return;
    _action = true;
    try {
      await _restore(generation);
    } finally {
      if (generation == _generation) _action = false;
    }
  }

  Future<void> _restore(int generation) async {
    _set(PurchaseFlowStatus.restoring);
    try {
      final events = await billing.restore();
      if (!_valid(generation)) return;
      _awaitingPurchase = false;
      if (events.isEmpty) _set(PurchaseFlowStatus.idle);
      for (final event in events) {
        if (!_valid(generation)) return;
        await _accept(event, generation, explicitRestore: true);
      }
    } catch (error) {
      if (_valid(generation)) _billingError(error);
    }
  }

  void _onEvent(PurchaseEvent event) {
    unawaited(_accept(event, _generation));
  }

  Future<void> _accept(
    PurchaseEvent event,
    int generation, {
    bool explicitRestore = false,
  }) async {
    if (!_valid(generation)) return;
    final evidence = event.evidence;
    // Global Play events carry no Firebase session. Require matching opaque
    // binding. A user-requested ownership query may reach the backend to produce
    // a no-transfer/support result for an old account's purchase.
    if (evidence != null &&
        !explicitRestore &&
        (evidence.accountBinding == null ||
            evidence.accountBinding !=
                (_purchaseBinding ?? _session!.accountBinding))) {
      return;
    }
    if (event.kind == PurchaseEventKind.error ||
        event.kind == PurchaseEventKind.canceled) {
      // Unbound callbacks cannot prove which account launched an old Play UI.
      if (!_awaitingPurchase || _inFlight.isNotEmpty) return;
      _awaitingPurchase = false;
      if (event.failure == BillingFailure.alreadyOwned) {
        await _restore(generation);
      } else {
        _billingError(
          BillingException(
            event.kind == PurchaseEventKind.canceled
                ? BillingFailure.userCanceled
                : event.failure ?? BillingFailure.unknown,
          ),
        );
      }
      return;
    }
    if (evidence == null || !evidence.valid) {
      _set(
        PurchaseFlowStatus.rejected,
        outcome: VerificationOutcome.malformedResponse,
      );
      return;
    }
    if (event.kind == PurchaseEventKind.pending) {
      if (_inFlight.isEmpty) _set(PurchaseFlowStatus.pendingPurchase);
      return;
    }
    _awaitingPurchase = false;
    _purchaseBinding = null;
    final key =
        evidence.token; // In-flight only; removed on all completion paths.
    final existing = _inFlight[key];
    if (existing != null) return existing;
    // Bounded serial processing prevents response reordering and verify storms.
    if (_inFlight.length >= 4) {
      _set(PurchaseFlowStatus.retryableError);
      return;
    }
    final operation = _tail.then((_) => _verify(evidence, generation));
    _inFlight[key] = operation;
    _tail = operation;
    try {
      await operation;
    } finally {
      if (identical(_inFlight[key], operation)) _inFlight.remove(key);
    }
  }

  Future<void> _verify(PurchaseEvidence evidence, int generation) async {
    if (!_valid(generation)) return;
    _set(PurchaseFlowStatus.verifying);
    try {
      final result = await _session!.gateway
          .verify(evidence)
          .timeout(verificationTimeout);
      _reportAccountClosure(generation);
      if (!_valid(generation)) return;
      switch (result) {
        case VerificationOutcome.verified:
          _set(PurchaseFlowStatus.refreshingEntitlement);
          await entitlements.refresh();
          if (!_valid(generation)) return;
          // Completed describes the flow only: the repository can still be Free.
          _set(
            entitlements.current.failure == null
                ? PurchaseFlowStatus.completed
                : PurchaseFlowStatus.retryableError,
            outcome: result,
          );
        case VerificationOutcome.pending:
          _set(PurchaseFlowStatus.pendingPurchase, outcome: result);
        case VerificationOutcome.accountDeleting:
        case VerificationOutcome.accountDeleted:
          _closedAccount = true;
          _set(PurchaseFlowStatus.blocked, outcome: result);
        case VerificationOutcome.tokenBindingConflict:
        case VerificationOutcome.supportRequired:
        case VerificationOutcome.permanentConfigurationFailure:
          _set(PurchaseFlowStatus.supportRequired, outcome: result);
        case VerificationOutcome.temporaryFailure:
          _set(PurchaseFlowStatus.retryableError, outcome: result);
        case VerificationOutcome.rejected:
        case VerificationOutcome.malformedResponse:
          _set(PurchaseFlowStatus.rejected, outcome: result);
      }
    } catch (_) {
      if (_valid(generation)) {
        _set(
          PurchaseFlowStatus.retryableError,
          outcome: VerificationOutcome.temporaryFailure,
        );
      }
    }
  }

  void _billingError(Object error) {
    final failure = error is BillingException
        ? error.failure
        : BillingFailure.unknown;
    _set(switch (failure) {
      BillingFailure.userCanceled => PurchaseFlowStatus.canceled,
      BillingFailure.configuration => PurchaseFlowStatus.supportRequired,
      BillingFailure.billingUnavailable ||
      BillingFailure.itemUnavailable => PurchaseFlowStatus.unavailable,
      _ => PurchaseFlowStatus.retryableError,
    }, failure: failure);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _session = null;
    _inFlight.clear();
    await _subscription.cancel();
    await billing.dispose();
    await _states.close();
  }
}
