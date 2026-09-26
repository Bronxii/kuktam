import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/home/presentation/screens/main_screen.dart';
import 'package:kuktam/recipes/data/repositories/recipe_repository.dart';
import 'package:kuktam/recipes/domain/models/recipe.dart';
import 'package:kuktam/recipes/domain/models/recipe_import_draft.dart';
import 'package:kuktam/recipes/domain/services/recipe_text_parser.dart';
import 'package:kuktam/recipes/presentation/screens/add_recipe_screen.dart';
import 'package:kuktam/recipes/presentation/widgets/ingredient_row.dart';
import 'package:kuktam/recipes/presentation/widgets/spice_row.dart';
import 'package:kuktam/recipes/presentation/widgets/recipe_import_dialog.dart';
import 'package:kuktam/shopping/data/repositories/shopping_repository.dart';

class _Recipes implements RecipeRepository {
  int saves = 0, updates = 0, checks = 0;
  Recipe? saved;
  @override
  Future<bool> recipeNameExists({
    required String name,
    String? excludedRecipeId,
  }) async {
    checks++;
    return false;
  }

  @override
  Future<void> saveRecipe(Recipe recipe) async {
    saves++;
    saved = recipe;
  }

  @override
  Future<void> updateRecipe(Recipe recipe) async {
    updates++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Shopping implements ShoppingRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final input = find.byKey(const ValueKey('recipe-import-text'));
  final process = find.widgetWithText(FilledButton, 'Feldolgozás');
  Future<void> enter(WidgetTester tester, String text) async {
    await tester.enterText(input, text);
    await tester.pump();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.ensureVisible(process);
    await tester.tap(process);
    await tester.pumpAndSettle();
  }

  Future<void> dialog(
    WidgetTester tester, {
    RecipeImportDraft Function(String)? parse,
    ValueChanged<RecipeImportDraft?>? onResult,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final result = await showDialog<RecipeImportDraft>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => RecipeImportDialog(parse: parse),
                );
                onResult?.call(result);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> mainScreen(WidgetTester tester, _Recipes repo) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MainScreen(
          recipeRepository: repo,
          shoppingRepository: _Shopping(),
          tabBodies: const [
            Text('Recipe tab'),
            Text('Shopping tab'),
            Text('Cook tab'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('single URL is processed only as recipe text', (tester) async {
    const url = 'https://example.com/recept';
    String? parsedInput;
    RecipeImportDraft? result;
    await dialog(
      tester,
      parse: (text) {
        parsedInput = text;
        return const RecipeTextParser().parse(text);
      },
      onResult: (draft) => result = draft,
    );
    await enter(tester, url);
    await submit(tester);
    expect(parsedInput, url);
    expect(result!.originalText, url);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('empty whitespace and multiline enabled state', (tester) async {
    await dialog(tester);
    expect(tester.widget<FilledButton>(process).onPressed, isNull);
    await enter(tester, ' \n ');
    expect(tester.widget<FilledButton>(process).onPressed, isNull);
    await enter(tester, 'Hozzávalók:\n2 tojás');
    expect(tester.widget<FilledButton>(process).onPressed, isNotNull);
    expect(
      tester.widget<TextField>(input).controller!.text,
      'Hozzávalók:\n2 tojás',
    );
  });

  for (final count in [20000, 20001]) {
    testWidgets('character limit $count without truncation', (tester) async {
      int calls = 0;
      RecipeImportDraft? received;
      await dialog(
        tester,
        parse: (text) {
          calls++;
          return const RecipeTextParser().parse(text);
        },
        onResult: (draft) => received = draft,
      );
      final text = 'a' * count;
      await enter(tester, text);
      await submit(tester);
      if (count == 20000) {
        expect(calls, 1);
        expect(received!.originalText, text);
        expect(find.byType(RecipeImportDialog), findsNothing);
      } else {
        expect(calls, 0);
        expect(received, isNull);
        expect(find.textContaining('Legfeljebb 20 000'), findsOneWidget);
        expect(tester.widget<TextField>(input).controller!.text, text);
      }
    });
  }

  testWidgets(
    'exception preserves text and allows retry with unchanged draft',
    (tester) async {
      bool fail = true;
      final expected = const RecipeTextParser().parse('Ismeretlen szöveg');
      RecipeImportDraft? received;
      await dialog(
        tester,
        parse: (_) {
          if (fail) throw StateError('technical secret');
          return expected;
        },
        onResult: (d) => received = d,
      );
      await enter(tester, 'Ismeretlen szöveg');
      await submit(tester);
      expect(find.textContaining('Nem sikerült feldolgozni'), findsOneWidget);
      expect(find.textContaining('technical secret'), findsNothing);
      expect(
        tester.widget<TextField>(input).controller!.text,
        'Ismeretlen szöveg',
      );
      fail = false;
      await submit(tester);
      expect(received, same(expected));
    },
  );

  for (final back in [false, true]) {
    testWidgets('empty closes immediately back=$back', (tester) async {
      await dialog(tester);
      if (back) {
        await tester.binding.handlePopRoute();
      } else {
        await tester.tap(find.byTooltip('Bezárás'));
      }
      await tester.pumpAndSettle();
      expect(find.byType(RecipeImportDialog), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
    });
  }

  testWidgets(
    'dirty barrier cancel and discard preserve separate close state',
    (tester) async {
      await dialog(tester);
      await enter(tester, 'Beillesztett recept');
      await tester.tapAt(const Offset(1, 1));
      await tester.pumpAndSettle();
      expect(find.byType(RecipeImportDialog), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('A beillesztett recept elveszik.'), findsOneWidget);
      await tester.tap(find.text('Mégsem'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(input).controller!.text,
        'Beillesztett recept',
      );
      await tester.tap(find.byTooltip('Bezárás'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kilépés'));
      await tester.pumpAndSettle();
      expect(find.byType(RecipeImportDialog), findsNothing);
    },
  );

  testWidgets('small viewport and keyboard remain scrollable', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await dialog(tester);
    await enter(tester, 'Hosszú sor\n' * 100);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.ensureVisible(process);
    expect(tester.takeException(), isNull);
  });

  for (final config in [
    (const Size(320, 640), 300.0, 1.0),
    (const Size(740, 360), 170.0, 1.0),
    (const Size(360, 740), 300.0, 1.6),
  ]) {
    testWidgets('paste field drag scrolls dialog with keyboard $config', (
      tester,
    ) async {
      tester.view.physicalSize = config.$1;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      RecipeImportDraft? result;
      await dialog(tester, textScale: config.$3, onResult: (d) => result = d);
      final text = 'Hosszú hozzávalósor\n' * 80;
      await enter(tester, text);
      final controller = tester.widget<TextField>(input).controller!;
      controller.selection = const TextSelection.collapsed(offset: 0);
      tester.view.viewInsets = FakeViewPadding(bottom: config.$2);
      await tester.pumpAndSettle();

      final outer = find.descendant(
        of: find.byType(RecipeImportDialog),
        matching: find.byType(Scrollable),
      ).first;
      final position = tester.state<ScrollableState>(outer).position;
      final viewport = tester.getRect(find.byType(SingleChildScrollView).first);
      final visibleField = tester.getRect(input).intersect(viewport);
      expect(visibleField.height, greaterThan(30));
      final before = position.pixels;
      await tester.dragFrom(visibleField.center, const Offset(0, -60));
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(before));

      // A real drag can reach the footer without dismissing the keyboard.
      await tester.drag(outer, Offset(0, -position.maxScrollExtent));
      await tester.pumpAndSettle();
      expect(process.hitTestable(), findsOneWidget);
      expect(tester.getRect(process).bottom,
          lessThanOrEqualTo(config.$1.height - config.$2));
      expect(controller.text, text);
      expect(tester.takeException(), isNull);
      await tester.tap(process);
      await tester.pumpAndSettle();
      expect(result!.originalText, text);
    });
  }

  testWidgets('recipe action tab scope and ordinary FAB', (tester) async {
    final repo = _Recipes();
    await mainScreen(tester, repo);
    expect(find.byTooltip('Recept importálása'), findsOneWidget);
    await tester.tap(find.text('Lista'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Recept importálása'), findsNothing);
    expect(find.byTooltip('Importálás'), findsOneWidget);
    await tester.tap(find.byType(NavigationDestination).at(2));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Recept importálása'), findsNothing);
    await tester.tap(find.byType(NavigationDestination).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Új recept'));
    await tester.pumpAndSettle();
    final editor = tester.widget<AddRecipeScreen>(find.byType(AddRecipeScreen));
    expect(editor.initialImport, isNull);
    expect(editor.recipe, isNull);
    expect(find.byType(ExpansionTile), findsNothing);
    expect(
      tester
          .widget<IngredientRow>(find.byType(IngredientRow))
          .data
          .nameController
          .text,
      '',
    );
    expect(repo.saves, 0);
  });

  testWidgets(
    'Recipes import through parser and editor saves only on explicit save',
    (tester) async {
      final repo = _Recipes();
      await mainScreen(tester, repo);
      await tester.tap(find.byTooltip('Recept importálása'));
      await tester.pumpAndSettle();
      const text =
          'Teszt recept\nAdag: 4 fő\nHozzávalók:\n2 bögre liszt\n25 dkg vaj\n15 dl tej\nFűszerek:\n1 tk majoranna\nbors\nElkészítés:\nAdj hozzá 1/2 dl vizet.';
      await enter(tester, text);
      await submit(tester);
      expect(find.byType(RecipeImportDialog), findsNothing);
      final draft = tester
          .widget<AddRecipeScreen>(find.byType(AddRecipeScreen))
          .initialImport!;
      expect(draft.originalText, text);
      expect(draft.title, 'Teszt recept');
      expect(draft.ingredients.map((i) => (i.quantity, i.unit)), [
        (2.0, 'db'),
        (250.0, 'g'),
        (1.5, 'l'),
        (1.0, 'tk'),
        (1.0, 'db'),
      ]);
      expect(find.textContaining('Eredeti: 2 bögre liszt'), findsOneWidget);
      expect(find.byType(SpiceRow), findsNothing);
      expect(repo.checks, 0);
      expect(repo.saves, 0);
      expect(repo.updates, 0);
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      expect(find.text('Adag: 4 fő'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Kilépés mentés nélkül?'), findsOneWidget);
      await tester.tap(find.text('Mégsem'));
      await tester.pumpAndSettle();
      final name = find
          .byWidgetPredicate(
            (w) => w is TextField && w.decoration?.labelText == 'Hozzávaló',
          )
          .first;
      await tester.ensureVisible(name);
      await tester.enterText(name, 'Javított liszt');
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
      expect(repo.saves, 1);
      expect(repo.updates, 0);
      expect(repo.saved!.ingredients.first.name, 'Javított liszt');
      expect(repo.saved!.spices, isEmpty);
      expect(repo.saved!.preparation, 'Adj hozzá 1/2 dl vizet.');
      expect(find.byType(AddRecipeScreen), findsNothing);
    },
  );

  testWidgets(
    'weak parse still opens protected editor with unprocessed content',
    (tester) async {
      await mainScreen(tester, _Recipes());
      await tester.tap(find.byTooltip('Recept importálása'));
      await tester.pumpAndSettle();
      await enter(tester, 'Ismeretlen receptszöveg');
      await submit(tester);
      expect(find.byType(AddRecipeScreen), findsOneWidget);
      expect(find.byType(ExpansionTile), findsOneWidget);
      expect(
        tester
            .widget<IngredientRow>(find.byType(IngredientRow))
            .data
            .nameController
            .text,
        '',
      );
    },
  );
}
