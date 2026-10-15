import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/billing/billing_contracts.dart';
import 'package:kuktam/billing/purchase_orchestrator.dart';
import 'package:kuktam/entitlements/domain/repositories/entitlement_repository.dart';
import 'package:kuktam/pro/pro_controller.dart';
import 'package:kuktam/pro/pro_screen.dart';
import 'package:kuktam/pro/profile_pro_card.dart';
import '../billing/fakes.dart';

class UiRepository implements EntitlementRepository {
  UiRepository([ClientEntitlementStatus status = ClientEntitlementStatus.free])
    : current = ClientEntitlementState(status, uid: 'user');
  @override
  ClientEntitlementState current;
  final stream = StreamController<ClientEntitlementState>.broadcast(sync: true);
  void set(ClientEntitlementStatus status, {EntitlementFailure? failure}) {
    current = ClientEntitlementState(status, uid: 'user', failure: failure);
    stream.add(current);
  }

  @override
  Stream<ClientEntitlementState> get changes => stream.stream;
  @override
  Future<void> initializeForUser(
    String uid, {
    bool refreshOnline = true,
  }) async {}
  @override
  Future<void> refresh() async {}
  @override
  Future<void> reevaluate() async {}
  @override
  Future<void> clearForLogout() async {}
  @override
  Future<void> dispose() => stream.close();
}

/// Widget state matrix fake. Service integration below uses the real N5 state.
class PreviewController extends ProController {
  PreviewController(this.repo, this.engine, {bool enabled = true})
    : super(entitlements: repo, purchases: engine, paymentsEnabled: enabled);
  final UiRepository repo;
  final PurchaseOrchestrator engine;
  PurchaseFlowState view = const PurchaseFlowState(
    PurchaseFlowStatus.ready,
    offer: ProductOffer(
      localizedPrice: 'CHF 7.95',
      currency: 'CHF',
      title: 'Pro',
    ),
  );
  @override
  PurchaseFlowState get flow => view;
  @override
  Future<void> load() async {}
  void show(
    PurchaseFlowStatus status, {
    BillingFailure? failure,
    VerificationOutcome? outcome,
    ProductOffer? offer,
  }) {
    view = PurchaseFlowState(
      status,
      offer: offer ?? view.offer,
      billingFailure: failure,
      verificationOutcome: outcome,
    );
    notifyListeners();
  }
}

void main() {
  late UiRepository repo;
  late FakeBilling billing;
  late PurchaseOrchestrator engine;
  late PreviewController c;
  setUp(() {
    repo = UiRepository();
    billing = FakeBilling();
    engine = PurchaseOrchestrator(billing: billing, entitlements: repo);
    c = PreviewController(repo, engine);
  });
  tearDown(() async {
    c.dispose();
    await engine.dispose();
    await repo.dispose();
  });
  Future<void> screen(WidgetTester tester, {bool card = false}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: card
            ? Scaffold(
                body: SingleChildScrollView(
                  child: ProfileProCard(controller: c),
                ),
              )
            : ProScreen(controller: c),
      ),
    );
    await tester.pump();
  }

  Future<void> reveal(WidgetTester tester, Key key) async {
    await tester.ensureVisible(find.byKey(key));
    await tester.pump();
  }

  for (final status in [
    ClientEntitlementStatus.unknown,
    ClientEntitlementStatus.checking,
  ]) {
    testWidgets('$status: loading, no Free flash or buy CTA', (tester) async {
      repo.set(status);
      await screen(tester);
      expect(find.text('Pro állapot ellenőrzése…'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byKey(const Key('pro-buy')), findsNothing);
      expect(find.text('Kuktám Free'), findsNothing);
    });
    testWidgets('Profile $status is loading', (tester) async {
      repo.set(status);
      await screen(tester, card: true);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Kuktám Free'), findsNothing);
    });
  }
  testWidgets('Free profile → details → back, duplicate route guarded', (
    tester,
  ) async {
    await screen(tester, card: true);
    expect(find.text('Kuktám Free'), findsOneWidget);
    final openDetails = tester
        .widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, 'Pro megtekintése'),
        )
        .onPressed!;
    openDetails();
    openDetails();
    await tester.pumpAndSettle();
    expect(find.byType(ProScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ProScreen), findsNothing);
    expect(find.byType(ProfileProCard), findsOneWidget);
    // Borrowed services remain usable after route disposal.
    repo.set(ClientEntitlementStatus.proOnline);
    await tester.pump();
    expect(find.text('Kuktám Pro – Aktív'), findsOneWidget);
  });
  for (final status in [
    ClientEntitlementStatus.proOnline,
    ClientEntitlementStatus.proOfflineGrace,
  ]) {
    testWidgets('$status has Pro without buy/price/primary restore', (
      tester,
    ) async {
      repo.set(status);
      await screen(tester);
      expect(find.byKey(const Key('pro-buy')), findsNothing);
      expect(find.byKey(const Key('pro-price')), findsNothing);
      expect(find.byKey(const Key('pro-restore')), findsNothing);
      expect(find.textContaining('Kuktám Pro –'), findsOneWidget);
    });
    testWidgets('Profile $status active and details CTA', (tester) async {
      repo.set(status);
      await screen(tester, card: true);
      expect(find.text('Pro részletek'), findsOneWidget);
    });
    testWidgets('$status survives store error', (tester) async {
      repo.set(status);
      c.show(
        PurchaseFlowStatus.unavailable,
        failure: BillingFailure.billingUnavailable,
      );
      await screen(tester);
      expect(find.textContaining('Kuktám Pro –'), findsOneWidget);
      expect(find.text('Kuktám Free'), findsNothing);
    });
  }
  testWidgets(
    'Free details offer, Pro benefits exclude separate AI credits',
    (tester) async {
      await screen(tester);
      expect(find.text('CHF 7.95'), findsOneWidget);
      for (final title in [
        'Receptátszámítás',
        'Mit főzzek?',
      ]) {
        expect(find.text(title), findsOneWidget);
      }
      expect(find.text('Recept szöveges import'), findsNothing);
      expect(find.text('Bevásárlólista szöveges import'), findsNothing);
      expect(find.textContaining('Nincs előfizetés'), findsOneWidget);
      expect(find.text('Képes receptimport – hamarosan'), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('pro-buy'))).onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('pro-restore')))
            .onPressed,
        isNotNull,
      );
    },
  );
  for (final failure in [
    BillingFailure.billingUnavailable,
    BillingFailure.itemUnavailable,
    BillingFailure.configuration,
  ]) {
    testWidgets('$failure controlled unavailable with no fake price', (
      tester,
    ) async {
      c.view = PurchaseFlowState(
        PurchaseFlowStatus.unavailable,
        billingFailure: failure,
      );
      await screen(tester);
      expect(find.byKey(const Key('pro-price')), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('pro-buy'))).onPressed,
        isNull,
      );
      expect(find.textContaining('jelenleg'), findsWidgets);
    });
  }
  for (final status in [
    PurchaseFlowStatus.loadingStore,
    PurchaseFlowStatus.launchingPurchase,
    PurchaseFlowStatus.restoring,
    PurchaseFlowStatus.pendingPurchase,
    PurchaseFlowStatus.verifying,
    PurchaseFlowStatus.refreshingEntitlement,
  ]) {
    testWidgets('$status is visible and prevents duplicate purchase', (
      tester,
    ) async {
      c.show(status);
      await screen(tester);
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('pro-buy'))).onPressed,
        isNull,
      );
      expect(find.text(c.message!), findsOneWidget);
      expect(find.text('A Kuktám Pro aktív.'), findsNothing);
      if (status != PurchaseFlowStatus.pendingPurchase) {
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
      }
    });
  }
  testWidgets('completed without trusted Pro never shows success', (
    tester,
  ) async {
    c.show(PurchaseFlowStatus.completed);
    repo.set(ClientEntitlementStatus.checking);
    await screen(tester);
    expect(find.text('A Kuktám Pro aktív.'), findsNothing);
    repo.set(ClientEntitlementStatus.proOnline);
    await tester.pump();
    expect(find.text('A Kuktám Pro aktív.'), findsOneWidget);
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);
  });
  testWidgets('canceled neutral and purchase can restart', (tester) async {
    c.show(PurchaseFlowStatus.canceled);
    await screen(tester);
    expect(find.text('A vásárlás megszakadt.'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('pro-buy'))).onPressed,
      isNotNull,
    );
  });
  testWidgets('retryable error provides explicit retry', (tester) async {
    c.show(PurchaseFlowStatus.retryableError);
    await screen(tester);
    await reveal(tester, const Key('pro-retry'));
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('pro-retry')))
          .onPressed,
      isNotNull,
    );
  });
  for (final outcome in [
    VerificationOutcome.supportRequired,
    VerificationOutcome.tokenBindingConflict,
  ]) {
    testWidgets('$outcome has human support copy and selectable contact', (
      tester,
    ) async {
      c.show(PurchaseFlowStatus.supportRequired, outcome: outcome);
      await screen(tester);
      expect(find.byType(SelectableText), findsOneWidget);
      expect(find.textContaining('nem tudtuk automatikusan'), findsOneWidget);
      expect(find.textContaining('tokenBinding'), findsNothing);
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('pro-restore')))
            .onPressed,
        isNull,
      );
    });
  }
  for (final failure in [
    EntitlementFailure.accountDeleting,
    EntitlementFailure.accountDeleted,
  ]) {
    testWidgets('$failure prevents both actions', (tester) async {
      repo.set(ClientEntitlementStatus.unavailable, failure: failure);
      await screen(tester);
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('pro-buy'))).onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('pro-restore')))
            .onPressed,
        isNull,
      );
      expect(find.textContaining('törlés alatt'), findsOneWidget);
    });
  }
  testWidgets(
    'expired grace requests connection, never says lifetime expired',
    (tester) async {
      repo.set(
        ClientEntitlementStatus.unavailable,
        failure: EntitlementFailure.connectionRequired,
      );
      await screen(tester);
      expect(
        find.textContaining('internetkapcsolat szükséges'),
        findsOneWidget,
      );
      expect(find.textContaining('lejárt'), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('pro-buy'))).onPressed,
        isNull,
      );
    },
  );
  for (final status in [
    PurchaseFlowStatus.ready,
    PurchaseFlowStatus.supportRequired,
  ]) {
    testWidgets('small screen, large text, long price $status no overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      c.show(
        status,
        offer: const ProductOffer(
          localizedPrice: '1.234.567,89 hosszú lokalizált ár',
          currency: 'X',
          title: 'Pro',
        ),
      );
      await screen(tester);
      await reveal(tester, const Key('pro-restore'));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('loading semantics and button labels', (tester) async {
    final handle = tester.ensureSemantics();
    c.show(PurchaseFlowStatus.verifying);
    await screen(tester);
    expect(find.bySemanticsLabel('Pro adatok feldolgozása'), findsOneWidget);
    await reveal(tester, const Key('pro-buy'));
    expect(find.bySemanticsLabel('Kuktám Pro megvásárlása'), findsOneWidget);
    handle.dispose();
  });
  testWidgets('profile card large text and narrow viewport scrolls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await screen(tester, card: true);
    await tester.ensureVisible(find.text('Pro megtekintése'));
    expect(tester.takeException(), isNull);
  });
  for (final failure in [
    BillingFailure.network,
    BillingFailure.unknown,
    BillingFailure.serviceUnavailable,
  ]) {
    testWidgets('$failure gives human retry copy', (tester) async {
      c.show(PurchaseFlowStatus.retryableError, failure: failure);
      await screen(tester);
      expect(
        find.text('Az ellenőrzés most nem sikerült. Próbáld újra.'),
        findsOneWidget,
      );
      expect(find.textContaining(failure.name), findsNothing);
      expect(find.byKey(const Key('pro-retry')), findsOneWidget);
    });
  }
}
