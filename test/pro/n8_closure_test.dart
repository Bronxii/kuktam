import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/billing/billing_contracts.dart';
import 'package:kuktam/billing/purchase_orchestrator.dart';
import 'package:kuktam/entitlements/data/local_entitlement_repository.dart';
import 'package:kuktam/entitlements/domain/repositories/entitlement_repository.dart';
import 'package:kuktam/pro/feature_gate.dart';
import 'package:kuktam/entitlements/domain/models/entitlement_snapshot.dart';
import 'package:kuktam/pro/profile_pro_card.dart';
import 'package:kuktam/pro/pro_screen.dart';
import 'package:kuktam/recipes/domain/services/recipe_text_parser.dart';
import 'package:kuktam/recipes/presentation/widgets/recipe_import_dialog.dart';
import 'package:kuktam/recipes/presentation/widgets/recipe_scaling_dialog.dart';
import 'package:kuktam/recipes/domain/models/recipe.dart';
import '../billing/fakes.dart' show FakeBilling;
import '../entitlements/data/entitlement_repository_test.dart'
    show Backend, Clock, Storage, proof;
import 'pro_ui_test.dart' show UiRepository, PreviewController;

void main() {
  testWidgets('text import works after real repository offline grace expires', (
    tester,
  ) async {
    final clock = Clock();
    final repo = LocalEntitlementRepository(
      backend: Backend(),
      storage: Storage(),
      clock: clock,
    );
    await repo.initializeForUser('a');
    var parsed = 0;
    await tester.pumpWidget(
      FeatureAccessScope(
        repository: repo,
        child: MaterialApp(
          home: Scaffold(
            body: RecipeImportDialog(
              parse: (text) {
                parsed++;
                return const RecipeTextParser().parse(text);
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('recipe-import-text')),
      'Leves',
    );
    await tester.pump();
    clock.advance(const Duration(days: 30));
    await tester.tap(find.text('Feldolgozás'));
    await tester.pumpAndSettle();
    expect(parsed, 1);
    expect(find.textContaining('internetkapcsolat szükséges'), findsNothing);
    expect(find.text('Kuktám Pro megtekintése'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    unawaited(repo.dispose());
    await tester.pump();
  });

  testWidgets(
    'real repository trusted inactive and account switch reach open gate',
    (tester) async {
      final backend = Backend();
      final repo = LocalEntitlementRepository(
        backend: backend,
        storage: Storage(),
        clock: Clock(),
      );
      await repo.initializeForUser('a');
      await tester.pumpWidget(
        FeatureAccessScope(
          repository: repo,
          child: const MaterialApp(
            home: Scaffold(
              body: RecipeScalingDialog(
                ingredients: [
                  RecipeIngredient(name: 'Liszt', quantity: 100, unit: 'g'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '250');
      backend.reply = (uid) async =>
          proof(uid: uid, active: false, revision: 2);
      await repo.refresh();
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Kuktám Pro megtekintése'), findsOneWidget);
      await repo.clearForLogout();
      await repo.initializeForUser('b');
      await tester.pumpAndSettle();
      expect(repo.current.uid, 'b');
      expect(repo.current.status, ClientEntitlementStatus.free);
      expect(find.text('250', skipOffstage: false), findsNothing);
      await tester.pumpWidget(const SizedBox());
      unawaited(repo.dispose());
      await tester.pump();
    },
  );

  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(800, 1000),
  ]) {
    for (final scale in [1.0, 2.0, 2.5]) {
      testWidgets(
        'Profile/Pro pending/support/price/upsell layout $size scale $scale',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final repo = UiRepository()
            ..current = const ClientEntitlementState(
              ClientEntitlementStatus.free,
              uid: 'user',
              snapshot: EntitlementSnapshot.free(),
            );
          final billing = FakeBilling();
          final engine = PurchaseOrchestrator(
            billing: billing,
            entitlements: repo,
          );
          final controller = PreviewController(repo, engine);
          final semantics = tester.ensureSemantics();
          Future<void> show(Widget child) async {
            await tester.pumpWidget(
              FeatureAccessScope(
                repository: repo,
                child: MaterialApp(
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  ),
                  home: child,
                ),
              ),
            );
            await tester.pump();
          }

          for (final flow in [
            PurchaseFlowStatus.ready,
            PurchaseFlowStatus.pendingPurchase,
            PurchaseFlowStatus.verifying,
            PurchaseFlowStatus.supportRequired,
          ]) {
            controller.show(
              flow,
              offer: const ProductOffer(
                localizedPrice: 'CHF 1’234’567.89 – einmalig',
                currency: 'CHF',
                title: 'Pro',
              ),
            );
            await show(ProScreen(controller: controller));
            await tester.ensureVisible(find.byKey(const Key('pro-price')));
            await tester.pump();
            expect(find.text('CHF 1’234’567.89 – einmalig'), findsOneWidget);
            expect(tester.takeException(), isNull);
            if (flow == PurchaseFlowStatus.supportRequired) {
              await tester.ensureVisible(find.text('kuktam.support@gmail.com'));
              await tester.pump();
              expect(
                find.bySemanticsLabel(RegExp('Kuktám ügyfélszolgálat')),
                findsWidgets,
              );
            }
          }
          await show(
            Scaffold(
              body: SingleChildScrollView(
                child: ProfileProCard(controller: controller),
              ),
            ),
          );
          expect(tester.takeException(), isNull);
          await show(
            Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => FeatureGate.request(
                    context,
                    ProFeature.scaledRecipeToShopping,
                  ),
                  child: const Text('Gate'),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Gate'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('Kuktám Pro megtekintése'), findsOneWidget);
          await tester.pumpWidget(const SizedBox());
          semantics.dispose();
          controller.dispose();
          unawaited(engine.dispose());
          unawaited(repo.dispose());
          await tester.pump();
        },
      );
    }
  }
}
