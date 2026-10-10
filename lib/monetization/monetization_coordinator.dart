import '../billing/billing_contracts.dart';
import '../billing/purchase_orchestrator.dart';
import '../entitlements/data/entitlement_contracts.dart';
import '../entitlements/data/local_entitlement_repository.dart';
import '../entitlements/domain/repositories/entitlement_repository.dart';
import 'callable_gateways.dart';

/// App composition with explicitly gated online transport (disabled by default).
/// Auth host calls changeSession immediately on auth changes (including logout).
/// Local/emulator Functions routing belongs to the injected transport factory.
final class MonetizationCoordinator {
  MonetizationCoordinator({
    required BillingAdapter billing,
    required EntitlementCacheStorage storage,
    required EntitlementClock clock,
    required this.transportFactory,
    required this.onlineEnabled,
  }) {
    entitlements = LocalEntitlementRepository(
      backend: _backend,
      storage: storage,
      clock: clock,
    );
    purchases = PurchaseOrchestrator(
      billing: billing,
      entitlements: entitlements,
    );
  }
  final CallableTransport Function(String uid, bool Function() isCurrent)
  transportFactory;
  final bool onlineEnabled;
  final _SwitchingProofBackend _backend = _SwitchingProofBackend();
  late final LocalEntitlementRepository entitlements;
  late final PurchaseOrchestrator purchases;
  int _generation = 0;
  bool _disposed = false, _initialized = false;
  String? _uid;

  Future<void> changeSession(String? uid) async {
    if (_disposed) return;
    final generation = ++_generation;
    purchases.bindSession(null);
    _backend.current = null;
    _uid = uid;
    final clear = _initialized || uid == null;
    _initialized = true;
    if (clear) await entitlements.clearForLogout();
    if (_disposed || generation != _generation || uid == null) return;
    bool current() => !_disposed && generation == _generation && _uid == uid;
    CallablePurchaseGateway? gateway;
    if (onlineEnabled) {
      final transport = transportFactory(uid, current);
      gateway = CallablePurchaseGateway(
        transport,
        onAccountClosed: (failure) async {
          if (current()) await entitlements.invalidateAccount(failure);
        },
      );
      _backend.current = CallableEntitlementBackend(
        transport: transport,
        uid: uid,
        isCurrent: current,
      );
    }
    await entitlements.initializeForUser(uid, refreshOnline: onlineEnabled);
    if (!current() || gateway == null) return;
    purchases.bindSession(
      PurchaseSession(
        uid: uid,
        gateway: gateway,
        contextGateway: gateway,
        isCurrent: current,
      ),
    );
  }

  Future<void> resume() async {
    if (_disposed || _uid == null) return;
    await entitlements.reevaluate();
    if (!_disposed && onlineEnabled) await entitlements.refresh();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _backend.current = null;
    await purchases.dispose();
    await entitlements.reevaluate(); // persist the current clock checkpoint
    await entitlements.dispose();
  }
}

final class _SwitchingProofBackend implements TrustedEntitlementBackend {
  TrustedEntitlementBackend? current;
  @override
  Future<TrustedEntitlementProof> fetchProof(String uid) {
    final selected = current;
    if (selected == null) {
      throw const EntitlementBackendException(
        EntitlementFailure.serverUnavailable,
      );
    }
    return selected.fetchProof(uid);
  }
}
