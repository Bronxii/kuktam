import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/sharing/text_share_controller.dart';
import 'package:kuktam/pro/feature_gate.dart';
import 'package:kuktam/home/presentation/screens/main_screen.dart';
import 'package:kuktam/recipes/presentation/widgets/recipe_import_dialog.dart';
import 'package:kuktam/recipes/presentation/screens/add_recipe_screen.dart';
import 'package:kuktam/features/auth/presentation/widgets/auth_gate.dart';
import 'package:kuktam/features/auth/data/repositories/auth_repository.dart';
import '../support/feature_access.dart';
import '../recipes/recipe_core_test.dart' show CoreRepository;
import '../shopping/shopping_core_qa_test.dart' show ShoppingFake;
import '../auth/email_verification_test.dart' show TestAuth, TestUser;

const sample =
    'Áfonyás süti\nHozzávalók:\n2 db tojás\nElkészítés:\nKeverd össze.';
final input = find.byKey(const ValueKey('recipe-import-text'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'queue preserves Unicode, duplicate IDs consumed once, equal text distinct events',
    () {
      final shares = TextShareController();
      shares.accept({'id': 'a', 'text': sample});
      shares.accept({'id': 'a', 'text': sample});
      shares.accept({'id': 'b', 'text': sample});
      expect(shares.take(), sample);
      expect(shares.take(), sample);
      expect(shares.take(), isNull);
      shares.accept({'id': 'a', 'text': sample});
      expect(shares.hasPending, isFalse);
      shares.dispose();
    },
  );
  test('empty/malformed rejected; bounded payload and queue give a notice', () {
    final shares = TextShareController();
    for (final event in [
      null,
      {},
      {'id': 'a', 'text': ' \n '},
      {'id': '', 'text': sample},
    ]) {
      shares.accept(event);
    }
    expect(shares.hasPending, isFalse);
    shares.accept({'id': 'long', 'text': 'é' * 20001});
    expect(shares.take(), isNull);
    expect(shares.takeNotice(), contains('20 000'));
    for (var i = 0; i < 11; i++) {
      shares.accept({'id': '$i', 'text': sample});
    }
    expect(shares.takeNotice(), contains('várakozó'));
    for (var i = 0; i < 10; i++) {
      expect(shares.take(), sample);
    }
    expect(shares.take(), isNull);
  });
  test('URL-only policy never interprets recipe text containing a link', () {
    expect(
      TextShareController.isUrlOnly(' https://example.com/recept '),
      isTrue,
    );
    expect(TextShareController.isUrlOnly('www.example.com'), isTrue);
    expect(
      TextShareController.isUrlOnly('Leves\nhttps://example.com'),
      isFalse,
    );
    expect(TextShareController.isUrlOnly(sample), isFalse);
  });
  testWidgets('bridge drains initial and new event exactly once', (
    tester,
  ) async {
    const channel = MethodChannel('kuktam/text_share');
    final queue = Queue<Object>.of([
      {'id': 'cold', 'text': sample},
    ]);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      expect(call.method, 'take');
      expect(call.arguments, isNull);
      return queue.isEmpty ? null : queue.removeFirst();
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final shares = TextShareController(channel: channel);
    await shares.start();
    expect(shares.take(), sample);
    await shares.start();
    expect(shares.take(), isNull);
    queue.add({'id': 'warm', 'text': 'Új szöveg'});
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'kuktam/text_share',
      const StandardMethodCodec().encodeMethodCall(const MethodCall('pending')),
      (_) {},
    );
    await tester.pump();
    expect(shares.take(), 'Új szöveg');
    expect(shares.take(), isNull);
  });

  Future<void> mount(
    WidgetTester tester,
    TextShareController shares,
    TextShareNavigationObserver observer, {
    ClientEntitlementStatus status = ClientEntitlementStatus.free,
    CoreRepository? recipes,
  }) async {
    await tester.pumpWidget(
      FeatureAccessScope(
        repository: AccessRepository(status),
        child: MaterialApp(
          navigatorObservers: [observer],
          home: MainScreen(
            textShares: shares,
            shareNavigation: observer,
            recipeRepository: recipes ?? CoreRepository(),
            shoppingRepository: ShoppingFake(),
            tabBodies: const [Text('Recipes'), Text('Shopping'), Text('Cook')],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> cancel(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Bezárás'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kilépés'));
    await tester.pumpAndSettle();
  }

  for (final status in [
    ClientEntitlementStatus.free,
    ClientEntitlementStatus.unknown,
  ]) {
    testWidgets(
      'cold pending prefill is editable and uses existing parser/editor: $status',
      (tester) async {
        final shares = TextShareController()
          ..accept({'id': 'cold', 'text': sample});
        await mount(
          tester,
          shares,
          TextShareNavigationObserver(),
          status: status,
        );
        expect(find.byType(RecipeImportDialog), findsOneWidget);
        expect(tester.widget<TextField>(input).controller!.text, sample);
        expect(find.byType(AddRecipeScreen), findsNothing);
        expect(find.text('Kuktám Pro funkció'), findsNothing);
        await tester.enterText(input, sample.replaceFirst('Áfonyás', 'Diós'));
        await tester.pump();
        await tester.tap(find.text('Feldolgozás'));
        await tester.pumpAndSettle();
        final editor = tester.widget<AddRecipeScreen>(
          find.byType(AddRecipeScreen),
        );
        expect(editor.initialImport!.title, 'Diós süti');
        expect(editor.initialImport!.originalText, contains('Diós'));
        expect(shares.hasPending, isFalse);
      },
    );
  }
  testWidgets('shared text uses editable existing editor and explicit save', (
    tester,
  ) async {
    final shares = TextShareController()
      ..accept({'id': 'save', 'text': sample});
    final recipes = CoreRepository();
    await mount(
      tester,
      shares,
      TextShareNavigationObserver(),
      recipes: recipes,
    );
    expect(recipes.saves, 0);
    await tester.tap(find.text('Feldolgozás'));
    await tester.pumpAndSettle();
    expect(recipes.saves, 0);
    final name = find
        .byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == 'Hozzávaló',
        )
        .first;
    await tester.ensureVisible(name);
    await tester.enterText(name, 'Friss tojás');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Mentés'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Mentés'));
    await tester.pumpAndSettle();
    expect(recipes.saves, 1);
    expect(recipes.recipes.single.ingredients.single.name, 'Friss tojás');
    expect(find.byType(AddRecipeScreen), findsNothing);
    expect(find.byType(RecipeImportDialog), findsNothing);
  });
  testWidgets('background share waits for resumed foreground', (tester) async {
    final shares = TextShareController();
    await mount(tester, shares, TextShareNavigationObserver());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    shares.accept({'id': 'background', 'text': sample});
    await tester.pump();
    expect(find.byType(RecipeImportDialog), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byType(RecipeImportDialog), findsOneWidget);
  });
  testWidgets(
    'warm, duplicate, rapid shares, cancel and rebuild do not replay',
    (tester) async {
      final shares = TextShareController();
      final observer = TextShareNavigationObserver();
      await mount(tester, shares, observer);
      await tester.tap(find.text('Lista'));
      await tester.pumpAndSettle();
      shares.accept({'id': 'a', 'text': sample});
      await tester.pumpAndSettle();
      shares.accept({'id': 'a', 'text': sample});
      shares.accept({'id': 'b', 'text': 'Második recept'});
      await tester.pumpAndSettle();
      expect(find.byType(RecipeImportDialog), findsOneWidget);
      expect(tester.widget<TextField>(input).controller!.text, sample);
      await cancel(tester);
      expect(
        tester.widget<TextField>(input).controller!.text,
        'Második recept',
      );
      await cancel(tester);
      expect(find.byType(RecipeImportDialog), findsNothing);
      expect(find.text('Shopping'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(shares.hasPending, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('another modal defers share until dismissed', (tester) async {
    final shares = TextShareController();
    await mount(tester, shares, TextShareNavigationObserver());
    final context = tester.element(find.byType(MainScreen));
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Other modal'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    shares.accept({'id': 'a', 'text': sample});
    await tester.pumpAndSettle();
    expect(find.byType(RecipeImportDialog), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(RecipeImportDialog), findsOneWidget);
  });
  testWidgets('URL-only shows explanation, does not open import or fetch', (
    tester,
  ) async {
    final shares = TextShareController()
      ..accept({'id': 'url', 'text': 'https://example.com'});
    await mount(tester, shares, TextShareNavigationObserver());
    expect(find.textContaining('hivatkozás helyett'), findsOneWidget);
    expect(find.byType(RecipeImportDialog), findsNothing);
    expect(shares.hasPending, isFalse);
  });
  testWidgets(
    'pending survives logged-out AuthGate and opens after verified login',
    (tester) async {
      final shares = TextShareController()
        ..accept({'id': 'login', 'text': sample});
      final observer = TextShareNavigationObserver();
      final auth = TestAuth(TestUser(true, ['password']));
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [observer],
          home: AuthGate(
            authRepository: AuthRepository(firebaseAuth: auth),
            mainBuilder: (_) => MainScreen(
              textShares: shares,
              shareNavigation: observer,
              recipeRepository: CoreRepository(),
              shoppingRepository: ShoppingFake(),
              tabBodies: const [
                Text('Recipes'),
                Text('Shopping'),
                Text('Cook'),
              ],
            ),
          ),
        ),
      );
      auth.changes.add(null);
      await tester.pumpAndSettle();
      expect(find.byType(RecipeImportDialog), findsNothing);
      expect(shares.hasPending, isTrue);
      auth.changes.add(auth.loginUser);
      await tester.pumpAndSettle();
      expect(find.byType(RecipeImportDialog), findsOneWidget);
      expect(tester.widget<TextField>(input).controller!.text, sample);
      await tester.pumpWidget(const SizedBox());
      await auth.changes.close();
    },
  );
}
