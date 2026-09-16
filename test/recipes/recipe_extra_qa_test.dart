import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/recipes/domain/models/recipe.dart';
import 'package:kuktam/recipes/presentation/screens/recipe_details_screen.dart';
import 'package:kuktam/recipes/presentation/widgets/recipe_scaling_dialog.dart';
import 'package:kuktam/recipes/domain/services/recipe_text_parser.dart';
import 'package:kuktam/recipes/domain/models/recipe_import_draft.dart';
import 'package:kuktam/recipes/presentation/screens/add_recipe_screen.dart';
import 'package:kuktam/recipes/presentation/widgets/ingredient_row.dart';
import 'recipe_core_test.dart' show CoreRepository, coreField, saveCallback;

const original = Recipe(
  name: 'Eredeti',
  ingredients: [
    RecipeIngredient(name: 'Liszt', quantity: 500, unit: 'g'),
    RecipeIngredient(name: 'Tej', quantity: 750, unit: 'ml'),
  ],
  spices: [RecipeSpice(name: 'Bors')],
  preparation: 'Adj hozzá 1/2 dl vizet.\n\nŐrizd meg.',
);

Future<void> openMultiplier(
  WidgetTester tester,
  AddScalingShoppingItem add, {
  Recipe recipe = original,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => RecipeDetailsScreen(
                  recipe: recipe,
                  addMultiplierShoppingItem: add,
                ),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.widgetWithText(FilledButton, 'Bevásárlólistához adás'),
    300,
  );
  await tester.tap(find.widgetWithText(FilledButton, 'Bevásárlólistához adás'));
  await tester.pumpAndSettle();
}

void main() {
  for (final example in <(String, List<(double, String)>)>[
    ('0.5', [(250, 'g'), (375, 'ml')]),
    ('1', [(500, 'g'), (750, 'ml')]),
    ('1,5', [(750, 'g'), (1.13, 'l')]),
    ('2', [(1, 'kg'), (1.5, 'l')]),
    ('0.333333', [(167, 'g'), (250, 'ml')]),
    ('0.000001', [(1, 'g'), (1, 'ml')]),
    ('1.25', [(625, 'g'), (938, 'ml')]),
  ]) {
    testWidgets(
      'multiplier ${example.$1} passes scaled normalized amounts without changing recipe',
      (tester) async {
        final before = original.toMap();
        final calls = <(double, String)>[];
        final names = <String>[];
        await openMultiplier(tester, ({
          required name,
          required quantity,
          required unit,
        }) async {
          names.add(name);
          calls.add((quantity, unit));
        });
        await tester.enterText(find.byType(TextField), example.$1);
        await tester.tap(find.text('Hozzáadás'));
        await tester.pumpAndSettle();
        expect(calls, example.$2);
        expect(names, ['Liszt', 'Tej']);
        expect(original.toMap(), before);
        expect(find.byType(RecipeDetailsScreen), findsNothing);
        if (example.$1 == '1.25') {
          expect(find.textContaining('1,25×'), findsOneWidget);
        }
      },
    );
  }

  for (final input in [
    '',
    '0',
    '-1',
    'abc',
    '1..2',
    '1/2',
    'NaN',
    'Infinity',
  ]) {
    testWidgets('invalid multiplier draft "$input" cannot write', (
      tester,
    ) async {
      var calls = 0;
      await openMultiplier(tester, ({
        required name,
        required quantity,
        required unit,
      }) async {
        calls++;
      });
      // Exercise validation independently of the keyboard's restrictive formatter.
      tester.widget<TextField>(find.byType(TextField)).controller!.text = input;
      await tester.tap(find.text('Hozzáadás'));
      await tester.pumpAndSettle();
      expect(find.text('Adj meg pozitív értéket!'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(calls, 0);
    });
  }

  testWidgets('overflow in a later ingredient is rejected before any write', (
    tester,
  ) async {
    var calls = 0;
    await openMultiplier(
      tester,
      ({required name, required quantity, required unit}) async {
        calls++;
      },
      recipe: const Recipe(
        name: 'Nagy',
        ingredients: [
          RecipeIngredient(name: 'Első', quantity: 1, unit: 'g'),
          RecipeIngredient(name: 'Második', quantity: 1e308, unit: 'g'),
        ],
        spices: [],
        preparation: '',
      ),
    );
    await tester.enterText(find.byType(TextField), '2');
    await tester.tap(find.text('Hozzáadás'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(
      find.text('A megadott mennyiséggel a recept nem számítható át.'),
      findsOneWidget,
    );
    expect(find.byType(RecipeDetailsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed first write resets action so user can retry', (
    tester,
  ) async {
    var failWrite = true;
    final calls = <String>[];
    await openMultiplier(tester, ({
      required name,
      required quantity,
      required unit,
    }) async {
      if (failWrite) throw StateError('network');
      calls.add(name);
    });
    await tester.tap(find.text('Hozzáadás'));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    failWrite = false;
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Bevásárlólistához adás'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hozzáadás'));
    await tester.pumpAndSettle();
    expect(calls, ['Liszt', 'Tej']);
    expect(find.text('Open'), findsOneWidget);
  });

  test(
    'mixed fraction remains ambiguous; arbitrary adjective is preserved',
    () {
      const parser = RecipeTextParser();
      final mixed = parser
          .parse('Hozzávalók:\n1 1/2 kg liszt')
          .ingredients
          .single;
      expect(mixed.quantity, isNull);
      expect(mixed.warnings, [RecipeImportWarning.ambiguousIngredient]);
      expect(mixed.rawText, '1 1/2 kg liszt');
      for (final name in ['nagy alma', 'érett körte', 'friss tojás']) {
        final ingredient = parser
            .parse('Hozzávalók:\n2 $name')
            .ingredients
            .single;
        expect(ingredient.name, name);
        expect(ingredient.quantity, 2);
        expect(ingredient.unit, 'db');
        expect(ingredient.warnings, isEmpty);
      }
    },
  );

  testWidgets(
    'edited import explicitly saved and reloaded scales without import metadata',
    (tester) async {
      final repo = CoreRepository();
      final draft = const RecipeTextParser().parse(
        'Teszt\nHozzávalók:\n2 bögre liszt\n15 dl tej\nElkészítés:\nAdj hozzá 1/2 dl vizet.',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<Recipe>(
                    builder: (_) => AddRecipeScreen(
                      initialImport: draft,
                      recipeRepository: repo,
                    ),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(repo.saves, 0);
      expect(repo.updates, 0);
      expect(find.textContaining('Eredeti: 2 bögre liszt'), findsOneWidget);
      await tester.enterText(coreField('Hozzávaló').first, 'Liszt');
      await tester.enterText(coreField('Mennyiség').first, '500');
      final row = tester.widget<IngredientRow>(
        find.byType(IngredientRow).first,
      );
      row.data.selectedUnit = 'g';
      (await saveCallback(tester))();
      await tester.pumpAndSettle();
      expect(repo.saves, 1);
      expect(repo.updates, 0);
      final map = repo.recipes.single.toMap();
      expect(map.keys, ['name', 'ingredients', 'spices', 'preparation']);
      for (final ingredient in map['ingredients'] as List) {
        expect((ingredient as Map).keys, ['name', 'quantity', 'unit']);
      }
      final saved = Recipe.fromMap(map, id: 'saved');
      expect(saved.spices, isEmpty);
      expect(saved.preparation, 'Adj hozzá 1/2 dl vizet.');
      final calls = <(String, double, String)>[];
      await tester.pumpWidget(
        MaterialApp(
          home: RecipeDetailsScreen(
            recipe: saved,
            addScalingShoppingItem:
                ({required name, required quantity, required unit}) async {
                  calls.add((name, quantity, unit));
                },
          ),
        ),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Átszámítás'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('scaling-quantity-0')),
        '750',
      );
      final add = find.descendant(
        of: find.byType(RecipeScalingDialog),
        matching: find.widgetWithText(FilledButton, 'Bevásárlólistához adás'),
      );
      await tester.ensureVisible(add);
      await tester.pumpAndSettle();
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(calls, [('Liszt', 750, 'g'), ('tej', 2.25, 'l')]);
      expect(saved.toMap(), map);
      expect(repo.saves, 1);
      expect(repo.updates, 0);
    },
  );

  testWidgets(
    'multiplier repository failure stays on detail and hides raw exception',
    (tester) async {
      var calls = 0;
      await openMultiplier(tester, ({
        required name,
        required quantity,
        required unit,
      }) async {
        calls++;
        if (calls == 2) throw StateError('private backend detail');
      });
      await tester.tap(find.text('Hozzáadás'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(calls, 2);
      expect(find.byType(RecipeDetailsScreen), findsOneWidget);
      expect(
        find.textContaining('Nem sikerült minden tételt hozzáadni'),
        findsOneWidget,
      );
      expect(find.textContaining('private backend'), findsNothing);
    },
  );

  testWidgets('multiplier rejects overflow text before any write', (
    tester,
  ) async {
    var calls = 0;
    await openMultiplier(tester, ({
      required name,
      required quantity,
      required unit,
    }) async {
      calls++;
    });
    await tester.enterText(find.byType(TextField), '9' * 400);
    await tester.tap(find.text('Hozzáadás'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets(
    'multiplier double submit cannot pop the detail during pending writes',
    (tester) async {
      final pending = Completer<void>();
      var calls = 0;
      await openMultiplier(tester, ({
        required name,
        required quantity,
        required unit,
      }) async {
        calls++;
        await pending.future;
      });
      final submit = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Hozzáadás'))
          .onPressed!;
      submit();
      submit();
      await tester.pump();
      expect(calls, 1);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(
        find.byType(RecipeDetailsScreen, skipOffstage: false),
        findsOneWidget,
      );
      pending.complete();
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('Open'), findsOneWidget);
    },
  );
}
