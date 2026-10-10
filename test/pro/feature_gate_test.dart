import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/pro/feature_gate.dart';
import 'package:kuktam/pro/pro_screen.dart';
import 'package:kuktam/pro/pro_controller.dart';
import 'package:kuktam/pro/monetization_host.dart';
import 'package:kuktam/billing/purchase_orchestrator.dart';
import 'package:kuktam/home/presentation/screens/main_screen.dart';
import 'package:kuktam/entitlements/domain/models/feature_access_decision.dart';
import 'package:kuktam/recipes/domain/models/recipe.dart';
import 'package:kuktam/recipes/domain/services/recipe_text_parser.dart';
import 'package:kuktam/recipes/presentation/widgets/recipe_import_dialog.dart';
import 'package:kuktam/recipes/presentation/widgets/recipe_scaling_dialog.dart';
import 'package:kuktam/recipes/presentation/screens/recipe_details_screen.dart';
import 'package:kuktam/shopping/presentation/widgets/shopping_import_dialog.dart';
import 'package:kuktam/what_to_cook/presentation/screens/what_to_cook_screen.dart';
import '../support/feature_access.dart';
import '../recipes/recipe_core_test.dart' show CoreRepository;
import '../shopping/shopping_core_qa_test.dart' show ShoppingFake;
import '../billing/fakes.dart' show FakeBilling;

class CookSpy extends CoreRepository {
  int subscriptions = 0;
  @override
  Stream<List<Recipe>> watchRecipes() {
    subscriptions++;
    return Stream.value([]);
  }
}

const ingredients = [RecipeIngredient(name: 'Liszt', quantity: 100, unit: 'g')];
const recipe = Recipe(
  name: 'Teszt',
  ingredients: ingredients,
  spices: [],
  preparation: 'Keverd össze.',
);
const released = [
  ProFeature.recipeScaling,
  ProFeature.scaledRecipeToShopping,
  ProFeature.whatToCook,
];

Future<void> mount(
  WidgetTester tester,
  AccessRepository repo,
  Widget child, {
  double scale = 1,
}) async {
  await tester.pumpWidget(const SizedBox());
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
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final status in ClientEntitlementStatus.values) {
    testWidgets('text imports execute independently of entitlement: $status', (
      tester,
    ) async {
      final repo = AccessRepository(status);
      var parsed = 0, saved = 0;
      await mount(
        tester,
        repo,
        RecipeImportDialog(
          parse: (text) {
            parsed++;
            return const RecipeTextParser().parse(text);
          },
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('recipe-import-text')),
        'Leves\nHozzávalók:\n1 kg liszt\nElkészítés:\nKeverd össze.',
      );
      await tester.pump();
      await tester.tap(find.text('Feldolgozás'));
      await tester.pumpAndSettle();
      expect(parsed, 1);
      await mount(
        tester,
        repo,
        ShoppingImportDialog(
          addItems: (items) async {
            saved += items.length;
          },
        ),
      );
      await tester.enterText(find.byType(TextField).first, '1 kg liszt');
      await tester.pump();
      await tester.tap(find.text('Feldolgozás'));
      await tester.pumpAndSettle();
      final shoppingSave = find.widgetWithText(
        FilledButton,
        'Hozzáadás a bevásárlólistához',
      );
      await tester.ensureVisible(shoppingSave);
      await tester.tap(shoppingSave);
      await tester.pumpAndSettle();
      expect(saved, 1);
      expect(find.text('Kuktám Pro funkció'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final label in ['Átszámítás', 'Bevásárlólistához adás']) {
    testWidgets(
      'account switch during entry await cannot open old recipe: $label',
      (tester) async {
        final repo = AccessRepository();
        await mount(tester, repo, const RecipeDetailsScreen(recipe: recipe));
        final button = find.widgetWithText(FilledButton, label);
        await tester.ensureVisible(button);
        final action = tester.widget<FilledButton>(button).onPressed!;
        action();
        repo.set(ClientEntitlementStatus.proOnline, uid: 'B');
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(RecipeScalingDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'actual main entries remain visible and Free can launch imports but not cook',
    (tester) async {
      final repo = AccessRepository(ClientEntitlementStatus.free);
      await mount(
        tester,
        repo,
        MainScreen(
          recipeRepository: CoreRepository(),
          shoppingRepository: ShoppingFake(),
          tabBodies: const [Text('Recipes'), Text('Shopping'), Text('Cook')],
        ),
      );
      await tester.tap(find.byTooltip('Recept importálása'));
      await tester.pumpAndSettle();
      expect(find.text('Kuktám Pro funkció'), findsNothing);
      expect(find.byType(RecipeImportDialog), findsOneWidget);
      await tester.tap(find.byTooltip('Bezárás'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lista'));
      await tester.pumpAndSettle();
      expect(find.byType(FloatingActionButton), findsOneWidget);
      await tester.tap(find.byTooltip('Importálás'));
      await tester.pumpAndSettle();
      expect(find.text('Kuktám Pro funkció'), findsNothing);
      expect(find.byType(ShoppingImportDialog), findsOneWidget);
      await tester.tap(find.byTooltip('Bezárás'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mit főzzek?'));
      await tester.pumpAndSettle();
      expect(find.textContaining('A Mit főzzek?'), findsOneWidget);
      expect(find.text('Cook'), findsNothing);
    },
  );
  testWidgets(
    'actual detail scaling entry remains visible, Free gets contextual prompt',
    (tester) async {
      await mount(
        tester,
        AccessRepository(ClientEntitlementStatus.free),
        const RecipeDetailsScreen(recipe: recipe),
      );
      await tester.tap(find.text('Átszámítás'));
      await tester.pumpAndSettle();
      expect(
        find.text('A receptátszámítás a Kuktám Pro része.'),
        findsOneWidget,
      );
      expect(find.byType(RecipeScalingDialog), findsNothing);
    },
  );
  testWidgets(
    'upsell borrows app Pro controller; duplicate CTA cannot pop twice or purchase',
    (tester) async {
      final repo = AccessRepository(ClientEntitlementStatus.free);
      final billing = FakeBilling();
      final engine = PurchaseOrchestrator(billing: billing, entitlements: repo);
      final controller = ProController(
        entitlements: repo,
        purchases: engine,
        paymentsEnabled: false,
      );
      await tester.pumpWidget(
        ProScope(
          controller: controller,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () =>
                      FeatureGate.request(context, ProFeature.recipeScaling),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final action = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Kuktám Pro megtekintése'),
          )
          .onPressed!;
      action();
      action();
      await tester.pumpAndSettle();
      expect(find.byType(ProScreen), findsOneWidget);
      expect(
        tester.widget<ProScreen>(find.byType(ProScreen)).controller,
        same(controller),
      );
      expect(billing.buys, 0);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Open'), findsOneWidget);
      expect(billing.controller.isClosed, false);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      unawaited(engine.dispose());
      await tester.pump();
    },
  );
  testWidgets('multiplier open before revoke cannot commit shopping write', (
    tester,
  ) async {
    final repo = AccessRepository();
    var writes = 0;
    await mount(
      tester,
      repo,
      RecipeDetailsScreen(
        recipe: recipe,
        addMultiplierShoppingItems: (_) async {
          writes++;
        },
      ),
    );
    final open = find.widgetWithText(FilledButton, 'Bevásárlólistához adás');
    await tester.ensureVisible(open);
    await tester.tap(open);
    await tester.pumpAndSettle();
    final action = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Hozzáadás'))
        .onPressed!;
    repo.set(ClientEntitlementStatus.free);
    action();
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(find.textContaining('Az átszámított recept'), findsOneWidget);
  });
  testWidgets('checking prompt reacts to Free and Pro without paywall flash', (
    tester,
  ) async {
    final repo = AccessRepository(ClientEntitlementStatus.checking);
    await mount(
      tester,
      repo,
      const RecipeScalingDialog(ingredients: ingredients),
    );
    expect(find.text('Kuktám Pro megtekintése'), findsNothing);
    repo.set(ClientEntitlementStatus.free);
    await tester.pumpAndSettle();
    expect(find.text('Kuktám Pro megtekintése'), findsOneWidget);
    repo.set(ClientEntitlementStatus.proOnline);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Kuktám Pro megtekintése'), findsNothing);
  });
  for (final feature in ProFeature.values) {
    for (final status in ClientEntitlementStatus.values) {
      test('central adapter $feature $status', () {
        final expected = feature == ProFeature.imageImport
            ? FeatureAccessDecision.featureUnavailable
            : switch (status) {
                ClientEntitlementStatus.free =>
                  FeatureAccessDecision.requiresPro,
                ClientEntitlementStatus.proOnline ||
                ClientEntitlementStatus.proOfflineGrace =>
                  FeatureAccessDecision.allowed,
                ClientEntitlementStatus.unavailable =>
                  FeatureAccessDecision.requiresConnection,
                _ => FeatureAccessDecision.checking,
              };
        expect(accessState(status).access(feature), expected);
      });
    }
  }
  for (final feature in released) {
    testWidgets(
      'Free contextual prompt, cancel and existing ProScreen: $feature',
      (tester) async {
        final repo = AccessRepository(ClientEntitlementStatus.free);
        var executions = 0;
        await mount(
          tester,
          repo,
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                if (await FeatureGate.request(context, feature)) executions++;
              },
              child: const Text('Open'),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(
          find.text('${FeatureGate.title(feature)} a Kuktám Pro része.'),
          findsOneWidget,
        );
        expect(find.textContaining('előfizetés nélkül'), findsOneWidget);
        expect(executions, 0);
        await tester.tap(find.text('Mégse'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Kuktám Pro megtekintése'));
        await tester.pumpAndSettle();
        expect(find.byType(ProScreen), findsOneWidget);
        expect(executions, 0);
        await tester.pageBack();
        await tester.pumpAndSettle();
        repo.set(ClientEntitlementStatus.proOnline);
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(executions, 1);
        expect(find.byType(AlertDialog), findsNothing);
      },
    );
    for (final status in [
      ClientEntitlementStatus.unknown,
      ClientEntitlementStatus.checking,
      ClientEntitlementStatus.unavailable,
    ]) {
      testWidgets('$feature $status does not upsell or execute', (
        tester,
      ) async {
        final repo = AccessRepository(status);
        await mount(
          tester,
          repo,
          Builder(
            builder: (context) => TextButton(
              onPressed: () => FeatureGate.execute(context, feature),
              child: const Text('Open'),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.text('Kuktám Pro megtekintése'), findsNothing);
        expect(
          find.textContaining(
            status == ClientEntitlementStatus.unavailable
                ? 'internetkapcsolat szükséges'
                : 'ellenőrzése folyamatban',
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Mégse'));
        await tester.pumpAndSettle();
      });
    }
  }
  for (final status in [
    ClientEntitlementStatus.free,
    ClientEntitlementStatus.unknown,
    ClientEntitlementStatus.unavailable,
  ]) {
    testWidgets('direct constructors block scaling and matcher: $status', (
      tester,
    ) async {
      final repo = AccessRepository(status);
      final cook = CookSpy();
      var calls = 0;
      for (final child in <Widget>[
        RecipeScalingDialog(
          ingredients: ingredients,
          addShoppingItems: (_) async {
            calls++;
          },
        ),
        WhatToCookScreen(recipeRepository: cook),
      ]) {
        await mount(tester, repo, child);
        expect(find.byType(TextField), findsNothing);
        expect(calls, 0);
        expect(cook.subscriptions, 0);
      }
    });
  }
  for (final status in [
    ClientEntitlementStatus.proOnline,
    ClientEntitlementStatus.proOfflineGrace,
  ]) {
    testWidgets('real import/scaling/scaled shopping/matcher run: $status', (
      tester,
    ) async {
      final repo = AccessRepository(status);
      var parsed = 0, saved = 0;
      await mount(
        tester,
        repo,
        RecipeImportDialog(
          parse: (text) {
            parsed++;
            return const RecipeTextParser().parse(text);
          },
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('recipe-import-text')),
        'Leves\nHozzávalók:\n1 kg liszt\nElkészítés:\nKeverd össze.',
      );
      await tester.pump();
      await tester.tap(find.text('Feldolgozás'));
      await tester.pumpAndSettle();
      expect(parsed, 1);
      await mount(
        tester,
        repo,
        ShoppingImportDialog(
          addItems: (items) async {
            saved += items.length;
          },
        ),
      );
      await tester.enterText(find.byType(TextField).first, '1 kg liszt');
      await tester.pump();
      await tester.tap(find.text('Feldolgozás'));
      await tester.pumpAndSettle();
      final shoppingSave = find.widgetWithText(
        FilledButton,
        'Hozzáadás a bevásárlólistához',
      );
      await tester.ensureVisible(shoppingSave);
      await tester.tap(shoppingSave);
      await tester.pumpAndSettle();
      expect(saved, 1);
      await mount(
        tester,
        repo,
        RecipeScalingDialog(
          ingredients: ingredients,
          addShoppingItems: (items) async {
            saved += items.length;
            expect(items.single.quantity, 200);
          },
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('scaling-quantity-0')),
        '200',
      );
      await tester.pump(const Duration(milliseconds: 600));
      final add = find.widgetWithText(FilledButton, 'Bevásárlólistához adás');
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(saved, 2);
      final cook = CookSpy();
      await mount(tester, repo, WhatToCookScreen(recipeRepository: cook));
      expect(cook.subscriptions, 1);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Kuktám Pro megtekintése'), findsNothing);
    });
  }
  testWidgets(
    'captured recipe parse action stays available after entitlement loss',
    (tester) async {
      final repo = AccessRepository();
      var calls = 0;
      await mount(
        tester,
        repo,
        RecipeImportDialog(
          parse: (text) {
            calls++;
            return const RecipeTextParser().parse(text);
          },
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('recipe-import-text')),
        'Teszt recept',
      );
      await tester.pump();
      final action = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Feldolgozás'),
          )
          .onPressed!;
      repo.set(ClientEntitlementStatus.free);
      action();
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.textContaining('a Kuktám Pro része.'), findsNothing);
    },
  );
  testWidgets('shopping preview save stays available after revoke', (
    tester,
  ) async {
    final repo = AccessRepository();
    var calls = 0;
    await mount(
      tester,
      repo,
      ShoppingImportDialog(
        addItems: (_) async {
          calls++;
        },
      ),
    );
    await tester.enterText(find.byType(TextField).first, '1 kg liszt');
    await tester.pump();
    await tester.tap(find.text('Feldolgozás'));
    await tester.pumpAndSettle();
    final action = tester
        .widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Hozzáadás a bevásárlólistához'),
        )
        .onPressed!;
    repo.set(ClientEntitlementStatus.free);
    action();
    await tester.pumpAndSettle();
    expect(calls, 1);
  });
  for (final newUid in <String?>['user-b', null]) {
    testWidgets('old-session scaled shopping action cannot write: $newUid', (
      tester,
    ) async {
      final repo = AccessRepository();
      var calls = 0;
      await mount(
        tester,
        repo,
        RecipeScalingDialog(
          ingredients: ingredients,
          addShoppingItems: (_) async {
            calls++;
          },
        ),
      );
      final action = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Bevásárlólistához adás'),
          )
          .onPressed!;
      repo.set(
        newUid == null
            ? ClientEntitlementStatus.unknown
            : ClientEntitlementStatus.proOnline,
        uid: newUid,
      );
      action();
      await tester.pumpAndSettle();
      expect(calls, 0);
    });
  }
  testWidgets('same UID draft retained, new UID discards draft', (
    tester,
  ) async {
    final repo = AccessRepository();
    await mount(
      tester,
      repo,
      const RecipeScalingDialog(ingredients: ingredients),
    );
    await tester.enterText(
      find.byKey(const ValueKey('scaling-quantity-0')),
      '250',
    );
    repo.set(ClientEntitlementStatus.free);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    repo.set(ClientEntitlementStatus.proOnline);
    await tester.pumpAndSettle();
    expect(find.text('250'), findsOneWidget);
    repo.set(ClientEntitlementStatus.proOnline, uid: 'B');
    await tester.pumpAndSettle();
    expect(find.text('250'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '100',
    );
  });
  testWidgets(
    'detail multiplier separate entry blocked Free; manual details remain',
    (tester) async {
      final repo = AccessRepository(ClientEntitlementStatus.free);
      await mount(tester, repo, const RecipeDetailsScreen(recipe: recipe));
      expect(find.text('Teszt'), findsOneWidget);
      expect(find.byTooltip('Szerkesztés'), findsOneWidget);
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Bevásárlólistához adás'),
      );
      await tester.tap(
        find.widgetWithText(FilledButton, 'Bevásárlólistához adás'),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Az átszámított recept'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    },
  );
  testWidgets('double tap, small viewport, large text, accessible badge', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    final repo = AccessRepository(ClientEntitlementStatus.free);
    await mount(
      tester,
      repo,
      Builder(
        builder: (context) => IconButton(
          onPressed: () =>
              FeatureGate.request(context, ProFeature.scaledRecipeToShopping),
          icon: const ProFeatureIcon(
            feature: ProFeature.scaledRecipeToShopping,
            icon: Icons.shopping_cart,
          ),
        ),
      ),
      scale: 2,
    );
    expect(find.bySemanticsLabel(RegExp('Pro funkció')), findsOneWidget);
    final action = tester
        .widget<IconButton>(find.byType(IconButton))
        .onPressed!;
    action();
    action();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
    final cta = find.text('Kuktám Pro megtekintése');
    await tester.ensureVisible(cta);
    await tester.tap(cta);
    await tester.pumpAndSettle();
    expect(find.byType(ProScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
  for (final failure in [
    EntitlementFailure.accountDeleting,
    EntitlementFailure.accountDeleted,
  ]) {
    testWidgets('account $failure cannot upsell', (tester) async {
      final repo = AccessRepository();
      repo.set(ClientEntitlementStatus.unavailable, failure: failure);
      await mount(
        tester,
        repo,
        const RecipeScalingDialog(ingredients: ingredients),
      );
      expect(find.textContaining('törlés alatt'), findsOneWidget);
      expect(find.text('Kuktám Pro megtekintése'), findsNothing);
    });
  }
}
