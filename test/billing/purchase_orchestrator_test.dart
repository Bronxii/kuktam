import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/billing/billing_contracts.dart';
import 'package:kuktam/billing/purchase_orchestrator.dart';
import 'package:kuktam/entitlements/data/local_entitlement_repository.dart';
import 'package:kuktam/entitlements/data/entitlement_contracts.dart';
import 'package:kuktam/entitlements/domain/repositories/entitlement_repository.dart';
import 'fakes.dart';

void main() {
  late FakeBilling billing;
  late FakeGateway gateway;
  late FakeProofBackend backend;
  late LocalEntitlementRepository repo;
  late PurchaseOrchestrator service;
  String? uid;
  PurchaseSession session(String user) => PurchaseSession(
    uid: user,
    accountBinding: user == 'a' ? bindingA : bindingB,
    gateway: gateway,
    isCurrent: () => uid == user,
  );
  setUp(() async {
    uid = 'a';
    billing = FakeBilling();
    gateway = FakeGateway();
    backend = FakeProofBackend();
    repo = LocalEntitlementRepository(
      backend: backend,
      storage: MemoryStorage(),
      clock: FakeClock(),
    );
    await repo.initializeForUser('a');
    service = PurchaseOrchestrator(billing: billing, entitlements: repo)
      ..bindSession(session('a'));
  });
  tearDown(() async {
    await service.dispose();
    await repo.dispose();
  });
  Future<void> send(PurchaseEvent e) async {
    billing.controller.add(e);
    await flush();
  }

  Future<void> switchUser() async {
    uid = null;
    service.bindSession(null);
    await repo.clearForLogout();
    uid = 'b';
    await repo.initializeForUser('b');
    service.bindSession(session('b'));
  }

  test('only explicit restore opts into deleted-purchase recovery', () async {
    await send(event());
    expect(gateway.restoreIntents, [false]);
    billing.owned = [event(PurchaseEventKind.restored)];
    await service.restore();
    expect(gateway.restoreIntents, [false, true]);
  });

  test(
    'offer preserves localized price/product and launch uses opaque binding',
    () async {
      await service.loadOffer();
      expect(service.current.offer!.localizedPrice, '€7.99');
      expect(service.current.offer!.productId, ProProduct.id);
      await service.buyPro();
      await service.buyPro();
      expect(billing.buys, 1);
      expect(billing.boughtBinding, bindingA);
    },
  );
  test('unavailable store prevents buy, leaves entitlement', () async {
    billing.available = false;
    await service.loadOffer();
    await service.buyPro();
    expect(billing.buys, 0);
    expect(repo.current.status, ClientEntitlementStatus.free);
  });
  test('missing product distinguished', () async {
    billing.offer = null;
    await service.loadOffer();
    expect(service.current.billingFailure, BillingFailure.itemUnavailable);
  });
  test('query error controlled', () async {
    billing.queryError = const BillingException(BillingFailure.network);
    await service.loadOffer();
    expect(service.current.status, PurchaseFlowStatus.retryableError);
  });
  test(
    'pending no verification, later purchased refreshes trusted proof',
    () async {
      await send(event(PurchaseEventKind.pending));
      expect(gateway.calls, 0);
      expect(service.current.status, PurchaseFlowStatus.pendingPurchase);
      backend.active = true;
      await send(event());
      expect(repo.current.status, ClientEntitlementStatus.proOnline);
    },
  );
  test('callback does not grant while verification delayed', () async {
    final c = Completer<VerificationOutcome>();
    gateway.reply = (_) => c.future;
    await send(event());
    expect(repo.current.status, ClientEntitlementStatus.free);
    expect(service.current.status, PurchaseFlowStatus.verifying);
    c.complete(VerificationOutcome.verified);
    await flush();
    expect(repo.current.status, ClientEntitlementStatus.free);
    expect(service.current.status, PurchaseFlowStatus.completed);
  });
  for (final result in VerificationOutcome.values) {
    test('verification outcome $result never directly grants', () async {
      gateway.reply = (_) async => result;
      await send(event());
      expect(repo.current.status, ClientEntitlementStatus.free);
      expect(backend.calls, result == VerificationOutcome.verified ? 2 : 1);
      expect(service.current.verificationOutcome, result);
    });
  }
  for (final active in [true, false]) {
    test('restore uses actual entitlement active=$active', () async {
      billing.owned = [event(PurchaseEventKind.restored)];
      backend.active = active;
      await service.restore();
      expect(gateway.calls, 1);
      expect(
        repo.current.status,
        active
            ? ClientEntitlementStatus.proOnline
            : ClientEntitlementStatus.free,
      );
    });
  }
  test(
    'restore old account evidence goes to backend conflict, never transfer',
    () async {
      billing.owned = [
        event(PurchaseEventKind.restored, 'old-token', bindingB),
      ];
      gateway.reply = (_) async => VerificationOutcome.tokenBindingConflict;
      await service.restore();
      expect(service.current.status, PurchaseFlowStatus.supportRequired);
      expect(repo.current.status, ClientEntitlementStatus.free);
    },
  );
  test('already owned launch automatically queries ownership', () async {
    billing.buyError = const BillingException(BillingFailure.alreadyOwned);
    billing.owned = [event(PurchaseEventKind.restored)];
    backend.active = true;
    await service.loadOffer();
    await service.buyPro();
    expect(billing.restores, 1);
    expect(gateway.calls, 1);
    expect(repo.current.status, ClientEntitlementStatus.proOnline);
  });
  for (final failure in BillingFailure.values.where(
    (f) => f != BillingFailure.alreadyOwned,
  )) {
    test('purchase failure $failure preserves existing Pro', () async {
      backend.active = true;
      await repo.refresh();
      billing.buyError = BillingException(failure);
      await service.loadOffer();
      await service.buyPro();
      expect(repo.current.status, ClientEntitlementStatus.proOnline);
      expect(service.current.billingFailure, failure);
    });
  }
  test('verification temporary failure preserves offline grace', () async {
    backend.active = true;
    await repo.refresh();
    await repo.initializeForUser('a', refreshOnline: false);
    gateway.reply = (_) async => VerificationOutcome.temporaryFailure;
    await send(event());
    expect(repo.current.status, ClientEntitlementStatus.proOfflineGrace);
  });
  test(
    'explicit retry requeries ownership, no retained token required',
    () async {
      gateway.reply = (_) async => VerificationOutcome.temporaryFailure;
      await send(event());
      gateway.reply = (_) async => VerificationOutcome.verified;
      backend.active = true;
      billing.owned = [event(PurchaseEventKind.restored)];
      await service.restore();
      expect(gateway.calls, 2);
      expect(repo.current.status, ClientEntitlementStatus.proOnline);
    },
  );
  for (final duplicate in [
    PurchaseEventKind.purchased,
    PurchaseEventKind.restored,
  ]) {
    test('in-flight dedupe purchased + $duplicate', () async {
      final c = Completer<VerificationOutcome>();
      gateway.reply = (_) => c.future;
      await send(event());
      await send(event(duplicate));
      expect(gateway.calls, 1);
      c.complete(VerificationOutcome.verified);
      await flush();
      expect(backend.calls, 2);
    });
  }
  test(
    'different tokens serialized, no reordered verification responses',
    () async {
      final c = Completer<VerificationOutcome>();
      gateway.reply = (e) => e.token == 'one'
          ? c.future
          : Future.value(VerificationOutcome.verified);
      await send(event(PurchaseEventKind.purchased, 'one'));
      await send(event(PurchaseEventKind.purchased, 'two'));
      expect(gateway.calls, 1);
      c.complete(VerificationOutcome.rejected);
      await flush();
      expect(gateway.calls, 2);
      expect(service.current.status, PurchaseFlowStatus.completed);
    },
  );
  test('old retry cannot overwrite newer session success', () async {
    final c = Completer<VerificationOutcome>();
    gateway.reply = (_) => c.future;
    await send(event());
    await switchUser();
    gateway.reply = (_) async => VerificationOutcome.verified;
    backend.active = true;
    await send(event(PurchaseEventKind.purchased, 'new', bindingB));
    c.complete(VerificationOutcome.rejected);
    await flush();
    expect(repo.current.uid, 'b');
    expect(repo.current.status, ClientEntitlementStatus.proOnline);
    expect(service.current.status, PurchaseFlowStatus.completed);
  });
  test('logout during verification ignores old completion', () async {
    final c = Completer<VerificationOutcome>();
    gateway.reply = (_) => c.future;
    await send(event());
    await switchUser();
    final before = backend.calls;
    c.complete(VerificationOutcome.verified);
    await flush();
    expect(backend.calls, before);
    expect(repo.current.uid, 'b');
    expect(service.current.status, PurchaseFlowStatus.idle);
  });
  test('restore delayed across UID switch does not verify', () async {
    final c = Completer<List<PurchaseEvent>>();
    billing.restoreBarrier = c;
    final task = service.restore();
    await switchUser();
    c.complete([event(PurchaseEventKind.restored)]);
    await task;
    expect(gateway.calls, 0);
  });
  test(
    'late A event in B session ignored even without pending operation',
    () async {
      await switchUser();
      await send(event());
      expect(gateway.calls, 0);
    },
  );
  test('event after logout ignored', () async {
    uid = null;
    service.bindSession(null);
    await send(event());
    expect(gateway.calls, 0);
  });
  test('external auth invalidation alone prevents dispatch', () async {
    uid = null;
    await send(event());
    expect(gateway.calls, 0);
  });
  test('delayed entitlement refresh is also session fenced by N5.1', () async {
    final c = Completer<TrustedEntitlementProof>();
    backend.barrier = c;
    await send(event());
    expect(service.current.status, PurchaseFlowStatus.refreshingEntitlement);
    backend.barrier = null;
    await switchUser();
    c.complete(proof('a', true, 10));
    await flush();
    expect(repo.current.uid, 'b');
    expect(repo.current.status, ClientEntitlementStatus.free);
  });
  for (final outcome in [
    VerificationOutcome.accountDeleting,
    VerificationOutcome.accountDeleted,
  ]) {
    test('$outcome blocks new purchase, restore and callback', () async {
      gateway.reply = (_) async => outcome;
      await send(event());
      await service.loadOffer();
      await service.buyPro();
      await service.restore();
      await send(event());
      expect(billing.buys, 0);
      expect(billing.restores, 0);
      expect(gateway.calls, 1);
    });
  }
  test(
    'single listener on rebind; dispose cancels and delayed result ignored',
    () async {
      final c = Completer<VerificationOutcome>();
      gateway.reply = (_) => c.future;
      service.bindSession(session('a'));
      service.bindSession(session('a'));
      await send(event());
      expect(gateway.calls, 1);
      await service.dispose();
      expect(billing.controller.hasListener, false);
      c.complete(VerificationOutcome.verified);
      await flush();
      expect(backend.calls, 1);
    },
  );
  test('stream error sanitized and existing entitlement untouched', () async {
    billing.controller.addError(Exception('secret-token'));
    await flush();
    expect(service.current.billingFailure, BillingFailure.unknown);
    expect(repo.current.status, ClientEntitlementStatus.free);
  });
  test('restart then restore does not require in-memory history', () async {
    await service.dispose();
    billing = FakeBilling()..owned = [event(PurchaseEventKind.restored)];
    service = PurchaseOrchestrator(billing: billing, entitlements: repo)
      ..bindSession(session('a'));
    backend.active = true;
    await service.restore();
    expect(repo.current.status, ClientEntitlementStatus.proOnline);
  });
  test('evidence diagnostics redact token', () {
    expect(
      const PurchaseEvidence('secret').toString(),
      isNot(contains('secret')),
    );
  });
  test(
    'verification timeout retryable, late success never refreshes',
    () async {
      await service.dispose();
      billing = FakeBilling();
      service = PurchaseOrchestrator(
        billing: billing,
        entitlements: repo,
        verificationTimeout: const Duration(milliseconds: 1),
      )..bindSession(session('a'));
      final c = Completer<VerificationOutcome>();
      gateway.reply = (_) => c.future;
      await send(event());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(service.current.status, PurchaseFlowStatus.retryableError);
      c.complete(VerificationOutcome.verified);
      await flush();
      expect(backend.calls, 1);
    },
  );
  test(
    'stream canceled after successful purchase cannot overwrite completion',
    () async {
      await send(event());
      await send(const PurchaseEvent(PurchaseEventKind.canceled));
      expect(service.current.status, PurchaseFlowStatus.completed);
    },
  );
  test(
    'unbound purchased callback ignored; explicit restore can verify it',
    () async {
      const e = PurchaseEvent(
        PurchaseEventKind.purchased,
        evidence: PurchaseEvidence('token'),
      );
      await send(e);
      expect(gateway.calls, 0);
      billing.owned = [e];
      await service.restore();
      expect(gateway.calls, 1);
    },
  );
  for (final evidence in [
    PurchaseEvidence('', accountBinding: bindingA),
    PurchaseEvidence('token', productId: 'wrong', accountBinding: bindingA),
    PurchaseEvidence('token', packageName: 'wrong', accountBinding: bindingA),
  ]) {
    test(
      'malformed evidence ${evidence.productId}/${evidence.packageName}/${evidence.token.isEmpty}',
      () async {
        await send(
          PurchaseEvent(PurchaseEventKind.purchased, evidence: evidence),
        );
        expect(gateway.calls, 0);
        expect(service.current.status, PurchaseFlowStatus.rejected);
      },
    );
  }
  test(
    'verification backlog bounded and duplicate storm does not create requests',
    () async {
      final c = Completer<VerificationOutcome>();
      gateway.reply = (_) => c.future;
      for (var i = 0; i < 12; i++) {
        billing.controller.add(event(PurchaseEventKind.purchased, 'token-$i'));
      }
      await flush();
      expect(gateway.calls, 1);
      c.complete(VerificationOutcome.verified);
      await flush();
      expect(gateway.calls, 4);
    },
  );
}
