import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:kuktam/billing/billing_contracts.dart';
import 'package:kuktam/monetization/monetization_coordinator.dart';
import 'package:kuktam/pro/monetization_host.dart';
import 'package:kuktam/pro/pro_controller.dart';
import 'package:kuktam/pro/pro_screen.dart';
import 'package:kuktam/pro/profile_pro_card.dart';
import 'package:kuktam/settings/settings_screen.dart';
import 'package:kuktam/features/auth/presentation/widgets/account_deletion_dialog.dart';
import '../billing/fakes.dart';
import '../monetization/integration_test.dart' show LocalTransport, MovingClock;
import '../auth/account_deletion_test.dart' as deletion;
import '../auth/auth_qa_test.dart' show UiRepo;

class UiTransport extends LocalTransport {
  @override
  Future<Object?> call(String name, Map<String, Object?> data) async {
    // No Flutter expect() from an asynchronous platform callback while pump()
    // holds its test guard. Assertions belong in the test body.
    calls.add(name);
    if (pause == name) return barrier!.future;
    if (error != null) return {'schemaVersion': 1, 'error': error};
    if (name == 'prepareProPurchase') {
      return {
        'schemaVersion': 1,
        'productId': ProProduct.id,
        'opaqueAccountId': bindingA,
      };
    }
    if (name == 'verifyProPurchase') {
      return {'schemaVersion': 1, 'outcome': outcome};
    }
    return this.proof();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeBilling billing;
  late LocalTransport backend;
  late MonetizationCoordinator coordinator;
  late ProController c;
  late MovingClock clock;
  Future<void> initialize() async {
    billing = FakeBilling();
    backend = UiTransport();
    clock = MovingClock();
    coordinator = MonetizationCoordinator(
      billing: billing,
      storage: MemoryStorage(),
      clock: clock,
      onlineEnabled: true,
      transportFactory: (_, _) => backend,
    );
    await coordinator.changeSession('user');
    c = ProController(
      entitlements: coordinator.entitlements,
      purchases: coordinator.purchases,
      paymentsEnabled: true,
    );
  }

  void scenario(String name, WidgetTesterCallback body) {
    testWidgets(name, (tester) async {
      await initialize();
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox());
        c.dispose();
        var disposed = false;
        unawaited(
          coordinator.dispose().then((_) {
            disposed = true;
          }),
        );
        for (var i = 0; i < 8; i++) {
          await tester.runAsync(() => Future<void>.delayed(Duration.zero));
          await tester.pump();
        }
        expect(billing.controller.isClosed, true);
        expect(disposed, true);
      }
    });
  }

  Future<void> pump(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
  }

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: ProScreen(controller: c)));
    await pump(tester);
  }

  Future<void> tap(
    WidgetTester tester,
    String key, {
    bool twice = false,
  }) async {
    final finder = find.byKey(Key(key));
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    if (twice) await tester.tap(finder);
    await pump(tester);
  }

  void activate() {
    backend.active = true;
    backend.revision = 1;
  }

  scenario(
    'buy twice → one prepare/launch; trusted proof alone enables success',
    (tester) async {
      await open(tester);
      await tap(tester, 'pro-buy', twice: true);
      expect(billing.buys, 1);
      expect(backend.calls.where((e) => e == 'prepareProPurchase').length, 1);
      backend.pause = 'verifyProPurchase';
      backend.barrier = Completer<Object?>();
      billing.controller.add(event());
      await pump(tester);
      expect(find.text('Vásárlás ellenőrzése…'), findsOneWidget);
      expect(c.isPro, false);
      backend.pause = null;
      activate();
      backend.barrier!.complete({'schemaVersion': 1, 'outcome': 'verified'});
      await pump(tester);
      expect(find.text('A Kuktám Pro aktív.'), findsOneWidget);
      expect(find.byKey(const Key('pro-buy')), findsNothing);
      await tester.pump();
      expect(find.text('A Kuktám Pro aktív.'), findsOneWidget);
    },
  );
  scenario('verified result with trusted Free cannot display success', (
    tester,
  ) async {
    await open(tester);
    await tap(tester, 'pro-buy');
    billing.controller.add(event());
    await pump(tester);
    expect(c.flow.status, PurchaseFlowStatus.completed);
    expect(c.isPro, false);
    expect(find.text('A Kuktám Pro aktív.'), findsNothing);
  });
  scenario('pending stays pending and cannot repurchase', (tester) async {
    await open(tester);
    await tap(tester, 'pro-buy');
    billing.controller.add(event(PurchaseEventKind.pending));
    await pump(tester);
    expect(find.text('A vásárlás még feldolgozás alatt van.'), findsOneWidget);
    await c.buy();
    expect(billing.buys, 1);
    expect(c.isPro, false);
  });
  scenario('cancel allows explicit new buy', (tester) async {
    billing.buyError = const BillingException(BillingFailure.userCanceled);
    await open(tester);
    await tap(tester, 'pro-buy');
    expect(find.text('A vásárlás megszakadt.'), findsOneWidget);
    billing.buyError = null;
    await tap(tester, 'pro-buy');
    expect(billing.buys, 2);
  });
  scenario('restore duplicate → one query, verified trusted success', (
    tester,
  ) async {
    billing.restoreBarrier = Completer<List<PurchaseEvent>>();
    await open(tester);
    await tap(tester, 'pro-restore', twice: true);
    expect(billing.restores, 1);
    expect(find.text('Korábbi vásárlás ellenőrzése…'), findsOneWidget);
    activate();
    billing.restoreBarrier!.complete([event(PurchaseEventKind.restored)]);
    await pump(tester);
    expect(find.text('A Kuktám Pro helyreállítva.'), findsOneWidget);
    expect(backend.calls.contains('prepareProPurchase'), false);
  });
  scenario('restore no purchase is neutral', (tester) async {
    await open(tester);
    await tap(tester, 'pro-restore');
    expect(
      find.text('Nem találtunk visszaállítható Kuktám Pro vásárlást.'),
      findsOneWidget,
    );
    expect(c.isPro, false);
    expect(billing.buys, 0);
  });
  scenario('explicit empty restore survives proof and offer refresh', (
    tester,
  ) async {
    await open(tester);
    await tap(tester, 'pro-restore');
    const message = 'Nem találtunk visszaállítható Kuktám Pro vásárlást.';
    expect(c.restoreResult, message);
    await c.refresh();
    await c.load();
    await pump(tester);
    expect(find.text(message), findsOneWidget);
    expect(c.canBuy, true);
    expect(c.canRestore, true);
    expect(billing.buys, 0);
    expect(backend.calls.contains('verifyProPurchase'), false);
  });
  scenario(
    'second restore clears prior result and preserves rejection across refresh',
    (tester) async {
      await open(tester);
      await tap(tester, 'pro-restore');
      billing.restoreBarrier = Completer<List<PurchaseEvent>>();
      await tap(tester, 'pro-restore');
      expect(c.restoreResult, isNull);
      expect(find.text('Korábbi vásárlás ellenőrzése…'), findsOneWidget);
      expect(c.canBuy, false);
      expect(c.canRestore, false);
      backend.outcome = 'rejected';
      billing.restoreBarrier!.complete([event(PurchaseEventKind.restored)]);
      await pump(tester);
      const message =
          'A vásárlást nem sikerült igazolni. Ellenőrizd a korábbi vásárlásaidat.';
      expect(find.text(message), findsOneWidget);
      await c.refresh();
      await pump(tester);
      expect(find.text(message), findsOneWidget);
      expect(c.canBuy, false);
      expect(c.canRestore, true);
      expect(c.isPro, false);
    },
  );
  scenario('fast empty restore result is visible on small scrolled screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await open(tester);
    await tap(tester, 'pro-restore');
    final result = find.text(
      'Nem találtunk visszaállítható Kuktám Pro vásárlást.',
    );
    expect(result, findsOneWidget);
    expect(result.hitTestable(), findsOneWidget);
    final rect = tester.getRect(result);
    expect(rect.top, greaterThanOrEqualTo(kToolbarHeight));
    expect(rect.bottom, lessThanOrEqualTo(480));
    await c.refresh();
    await pump(tester);
    expect(result.hitTestable(), findsOneWidget);
  });
  scenario('already-owned automatically shows recovery, no early Pro', (
    tester,
  ) async {
    billing.buyError = const BillingException(BillingFailure.alreadyOwned);
    billing.restoreBarrier = Completer<List<PurchaseEvent>>();
    await open(tester);
    await tap(tester, 'pro-buy');
    expect(find.text('Korábbi vásárlás ellenőrzése…'), findsOneWidget);
    expect(c.isPro, false);
    activate();
    billing.restoreBarrier!.complete([event()]);
    await pump(tester);
    expect(c.isPro, true);
    expect(billing.restores, 1);
  });
  for (final error in ['supportRequired', 'tokenBindingConflict']) {
    scenario('restore $error shows support, no transfer', (tester) async {
      billing.owned = [event()];
      backend.error = error;
      await open(tester);
      await tap(tester, 'pro-restore');
      expect(find.textContaining('nem tudtuk automatikusan'), findsOneWidget);
      expect(find.text('kuktam.support@gmail.com'), findsOneWidget);
      expect(c.isPro, false);
    });
  }
  scenario('temporary failure → explicit double retry only one query', (
    tester,
  ) async {
    await open(tester);
    await tap(tester, 'pro-buy');
    backend.error = 'retryableUnavailable';
    billing.controller.add(event());
    await pump(tester);
    expect(c.canRetry, true);
    backend.error = null;
    billing.restoreBarrier = Completer<List<PurchaseEvent>>();
    await tap(tester, 'pro-retry', twice: true);
    expect(billing.restores, 1);
    activate();
    billing.restoreBarrier!.complete([event()]);
    await pump(tester);
    expect(c.isPro, true);
    expect(billing.buys, 1);
  });
  for (final error in ['accountDeleting', 'accountDeleted']) {
    scenario('prepare $error immediately blocks UI and clears Pro evidence', (
      tester,
    ) async {
      await open(tester);
      backend.error = error;
      await tap(tester, 'pro-buy');
      expect(c.closed, true);
      expect(c.canBuy, false);
      expect(c.canRestore, false);
      expect(billing.buys, 0);
    });
  }
  scenario('valid offline grace persists through restore/backend failure', (
    tester,
  ) async {
    activate();
    await coordinator.entitlements.refresh();
    backend.error = 'retryableUnavailable';
    await coordinator.entitlements.refresh();
    await open(tester);
    expect(find.text('Kuktám Pro – offline módban'), findsOneWidget);
    billing.owned = [event()];
    await coordinator.purchases.restore();
    await pump(tester);
    expect(c.isPro, true);
    expect(find.text('Kuktám Free'), findsNothing);
  });
  scenario(
    'expired grace requires online check without expired purchase claim',
    (tester) async {
      activate();
      await coordinator.entitlements.refresh();
      backend.error = 'retryableUnavailable';
      clock.current = now.add(const Duration(days: 31));
      await coordinator.entitlements.reevaluate();
      await open(tester);
      expect(
        find.textContaining('internetkapcsolat szükséges'),
        findsOneWidget,
      );
      expect(c.canBuy, false);
    },
  );
  scenario('route back during purchase preserves app service operation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ProfileProCard(controller: c)),
      ),
    );
    await tester.tap(find.text('Pro megtekintése'));
    await tester.pumpAndSettle();
    await tap(tester, 'pro-buy');
    await tester.pageBack();
    await tester.pumpAndSettle();
    activate();
    billing.controller.add(event());
    await pump(tester);
    expect(find.text('Kuktám Pro – Aktív'), findsOneWidget);
    expect(billing.buys, 1);
  });
  scenario('account switch while verify pending cannot show previous success', (
    tester,
  ) async {
    await open(tester);
    await tap(tester, 'pro-buy');
    backend.pause = 'verifyProPurchase';
    backend.barrier = Completer<Object?>();
    billing.controller.add(event());
    await pump(tester);
    await coordinator.changeSession('other');
    backend.pause = null;
    backend.barrier!.complete({'schemaVersion': 1, 'outcome': 'verified'});
    await pump(tester);
    expect(c.entitlement.uid, 'other');
    expect(c.isPro, false);
    expect(find.text('A Kuktám Pro aktív.'), findsNothing);
  });
  scenario('host disabled: profile opens with no backend or Play purchase', (
    tester,
  ) async {
    final ids = StreamController<String?>();
    final offlineBilling = FakeBilling();
    var calls = 0;
    final offline = MonetizationCoordinator(
      billing: offlineBilling,
      storage: MemoryStorage(),
      clock: FakeClock(),
      onlineEnabled: false,
      transportFactory: (_, _) {
        calls++;
        return backend;
      },
    );
    await tester.pumpWidget(
      MonetizationHost(
        coordinator: offline,
        userIds: ids.stream,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ProfileProCard(controller: ProScope.maybeOf(context)),
            ),
          ),
        ),
      ),
    );
    ids.add('owner');
    await pump(tester);
    await tester.tap(find.text('Pro megtekintése'));
    await tester.pumpAndSettle();
    expect(
      find.text('A vásárlás és a visszaállítás jelenleg nem érhető el.'),
      findsOneWidget,
    );
    expect(calls, 0);
    expect(offlineBilling.buys, 0);
    expect(offlineBilling.restores, 0);
    await tester.pumpWidget(const SizedBox());
    await pump(tester);
    await tester.runAsync(ids.close);
  });
  scenario(
    'old restore completion does not carry no-purchase result to new UID',
    (tester) async {
      await open(tester);
      billing.restoreBarrier = Completer<List<PurchaseEvent>>();
      await tap(tester, 'pro-restore');
      await coordinator.changeSession('other');
      await pump(tester);
      expect(c.noPurchaseFound, false);
      expect(c.canBuy, true);
      billing.restoreBarrier!.complete([]);
      await pump(tester);
      expect(c.noPurchaseFound, false);
      expect(c.canBuy, true);
    },
  );
  scenario('cached Free stays Free during temporary offline failure', (
    tester,
  ) async {
    backend.error = 'retryableUnavailable';
    await coordinator.entitlements.refresh();
    await open(tester);
    expect(find.text('Kuktám Free'), findsOneWidget);
    expect(c.isPro, false);
  });
  scenario('opening before session initialization eventually loads offer', (
    tester,
  ) async {
    await coordinator.changeSession(null);
    await open(tester);
    expect(find.byKey(const Key('pro-price')), findsNothing);
    await coordinator.changeSession('new');
    await pump(tester);
    expect(c.canBuy, true);
    expect(find.text(billing.offer!.localizedPrice), findsOneWidget);
  });
  for (final pro in [false, true]) {
    scenario('delete confirmation pro=$pro keeps existing two stages', (
      tester,
    ) async {
      final f = deletion.Fixture();
      await tester.pumpWidget(
        MaterialApp(
          home: AccountDeletionDialog(repository: f.repo, hasPro: pro),
        ),
      );
      expect(
        find.text(proDeletionWarning),
        pro ? findsOneWidget : findsNothing,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Fiók törlése'));
      await pump(tester);
      expect(find.byType(TextField), findsOneWidget);
      expect(f.user.deletes, 0);
      expect(
        find.text(proDeletionWarning),
        pro ? findsOneWidget : findsNothing,
      );
    });
  }
  scenario('real Settings scope passes Pro to deletion confirmation', (
    tester,
  ) async {
    PackageInfo.setMockInitialValues(
      appName: 'Kuktam',
      packageName: 'test',
      version: '1',
      buildNumber: '1',
      buildSignature: '',
    );
    activate();
    await coordinator.entitlements.refresh();
    final f = deletion.Fixture();
    await tester.pumpWidget(
      ProScope(
        controller: c,
        child: MaterialApp(
          home: SettingsScreen(
            authRepository: UiRepo(),
            deletionRepository: f.repo,
          ),
        ),
      ),
    );
    await pump(tester);
    await tester.scrollUntilVisible(find.text('Fiók törlése'), 400);
    await tester.tap(find.text('Fiók törlése'));
    await tester.pumpAndSettle();
    expect(find.text(proDeletionWarning), findsOneWidget);
    expect(
      find.textContaining('automatikus Google Play-visszatérítést'),
      findsOneWidget,
    );
  });
}
