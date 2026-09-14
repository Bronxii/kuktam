import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/recipes/data/repositories/recipe_repository.dart';
import 'package:kuktam/recipes/domain/models/recipe.dart';
import 'package:kuktam/recipes/domain/models/recipe_import_draft.dart';
import 'package:kuktam/recipes/presentation/widgets/ingredient_row.dart';
import 'package:kuktam/recipes/presentation/widgets/spice_row.dart';
import 'package:kuktam/recipes/presentation/screens/add_recipe_screen.dart';

class _Repository implements RecipeRepository {
  Recipe? saved;
  Recipe? updated;
  int checks = 0;
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
    saved = recipe;
  }

  @override
  Future<void> updateRecipe(Recipe recipe) async {
    updated = recipe;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );
  Future<void> open(
    WidgetTester tester,
    _Repository repo, {
    Recipe? recipe,
    RecipeImportDraft? initialImport,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AddRecipeScreen(
                    recipe: recipe,
                    initialImport: initialImport,
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
  }

  Future<void> save(WidgetTester tester) async {
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
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mentés'));
    await tester.pumpAndSettle();
  }

  RecipeImportIngredientDraft ingredient(
    String name, {
    double? quantity = 1.25,
    String unit = 'kg',
    String? rawQuantityText,
    List<RecipeImportWarning> warnings = const [],
  }) => RecipeImportIngredientDraft(
    sourceOrder: 7,
    rawText: 'raw $name',
    name: name,
    quantity: quantity,
    rawQuantityText: rawQuantityText,
    unit: unit,
    warnings: warnings,
  );
  RecipeImportDraft imported({
    String title = 'Importált recept',
    List<RecipeImportIngredientDraft>? ingredients,
    List<String> unprocessed = const [],
  }) => RecipeImportDraft(
    originalText: 'Eredeti teljes szöveg',
    title: title,
    ingredients: ingredients ?? [ingredient('Liszt')],
    preparationText: '1. Adj hozzá 1/2 dl vizet.\n\n• Keverd össze.',
    unprocessedSegments: unprocessed,
  );
  List<IngredientRow> rows(WidgetTester tester) =>
      tester.widgetList<IngredientRow>(find.byType(IngredientRow)).toList();

  test('recipe and initialImport cannot be combined', () {
    expect(
      () => AddRecipeScreen(
        recipe: const Recipe(
          name: 'Régi',
          ingredients: [],
          spices: [],
          preparation: '',
        ),
        initialImport: imported(),
      ),
      throwsAssertionError,
    );
  });

  testWidgets('import prefills normalized data and never autosaves', (
    tester,
  ) async {
    final repo = _Repository();
    final draft = imported(
      ingredients: [
        ingredient('Liszt'),
        ingredient('Tojás', quantity: 2.5, unit: 'db'),
        ingredient('Olaj', quantity: 1.234, unit: 'tk'),
      ],
    );
    await open(tester, repo, initialImport: draft);
    expect(
      tester.widget<TextField>(field('Recept neve')).controller!.text,
      draft.title,
    );
    expect(rows(tester).map((r) => r.data.nameController.text), [
      'Liszt',
      'Tojás',
      'Olaj',
    ]);
    expect(rows(tester).map((r) => r.data.amountController.text), [
      '1,25',
      '2,5',
      '1,234',
    ]);
    expect(rows(tester).map((r) => r.data.selectedUnit), ['kg', 'db', 'tk']);
    expect(find.byType(SpiceRow), findsNothing);
    expect(find.textContaining('Eredeti:'), findsNothing);
    expect(repo.checks, 0);
    expect(repo.saved, isNull);
    expect(repo.updated, isNull);
    await save(tester);
    expect(repo.saved!.id, isNull);
    expect(repo.saved!.name, draft.title);
    expect(repo.saved!.ingredients.map((i) => i.quantity), [1.25, 2.5, 1.234]);
    expect(repo.saved!.ingredients.map((i) => i.unit), ['kg', 'db', 'tk']);
    expect(repo.saved!.spices, isEmpty);
    expect(repo.saved!.preparation, draft.preparationText);
    expect(
      repo.saved!.toMap().keys,
      unorderedEquals(['name', 'ingredients', 'spices', 'preparation']),
    );
    expect(
      repo.saved!.ingredients.first.toMap().keys,
      unorderedEquals(['name', 'quantity', 'unit']),
    );
    expect(repo.updated, isNull);
    expect(find.byType(AddRecipeScreen), findsNothing);
    expect(find.text('Kilépés mentés nélkül?'), findsNothing);
  });

  for (final warning in RecipeImportWarning.values) {
    testWidgets('row-specific $warning remains informational after editing', (
      tester,
    ) async {
      final repo = _Repository();
      await open(
        tester,
        repo,
        initialImport: imported(
          ingredients: [
            ingredient('Liszt', warnings: [warning]),
            ingredient('Tej'),
          ],
        ),
      );
      final data = rows(tester).first.data;
      final warningFinder = find.textContaining('Eredeti: raw Liszt');
      expect(warningFinder, findsOneWidget);
      expect(find.textContaining('Eredeti: raw Tej'), findsNothing);
      final keyedRow = find.byKey(ObjectKey(data));
      expect(
        find.descendant(of: keyedRow, matching: warningFinder),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(warningFinder).dy,
        greaterThan(tester.getTopLeft(find.byType(IngredientRow).first).dy),
      );
      await tester.enterText(field('Hozzávaló').first, 'Javított');
      await tester.pump();
      expect(warningFinder, findsOneWidget);
      await save(tester);
      expect(repo.saved!.ingredients.first.name, 'Javított');
      expect(repo.updated, isNull);
    });
  }

  for (final raw in <String?>['0', '1/0', null, '125']) {
    testWidgets('null quantity $raw cannot become valid during prefill', (
      tester,
    ) async {
      final repo = _Repository();
      await open(
        tester,
        repo,
        initialImport: imported(
          ingredients: [
            ingredient(
              'Liszt',
              quantity: null,
              rawQuantityText: raw,
              warnings: [RecipeImportWarning.invalidQuantity],
            ),
          ],
        ),
      );
      expect(
        rows(tester).single.data.amountController.text,
        raw == '125' ? '' : raw ?? '',
      );
      await save(tester);
      expect(repo.checks, 0);
      expect(repo.saved, isNull);
      await tester.ensureVisible(field('Mennyiség'));
      await tester.enterText(field('Mennyiség'), '1,5');
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await save(tester);
      expect(repo.saved!.ingredients.single.quantity, 1.5);
    });
  }

  testWidgets(
    'middle deletion retains controllers edited names units and warnings',
    (tester) async {
      final repo = _Repository();
      await open(
        tester,
        repo,
        initialImport: imported(
          ingredients: [
            ingredient('Első', warnings: [RecipeImportWarning.unknownUnit]),
            ingredient(
              'Második',
              warnings: [RecipeImportWarning.missingQuantity],
            ),
            ingredient('Harmadik', warnings: [RecipeImportWarning.unknownUnit]),
          ],
        ),
      );
      final before = rows(tester).map((r) => r.data).toList();
      await tester.enterText(field('Hozzávaló').at(2), 'Harmadik szerkesztve');
      await tester.enterText(field('Mennyiség').at(2), '3,75');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Hozzávaló törlése').at(1));
      await tester.pumpAndSettle();
      expect(rows(tester).map((r) => r.data), [before[0], before[2]]);
      expect(before[2].nameController.text, 'Harmadik szerkesztve');
      expect(before[2].amountController.text, '3,75');
      expect(find.textContaining('Eredeti: raw Második'), findsNothing);
      expect(find.textContaining('Eredeti: raw Harmadik'), findsOneWidget);
      // Force a normal parent rebuild without replacing the surviving row state.
      await tester.ensureVisible(find.text('Hozzávaló hozzáadása'));
      await tester.tap(find.text('Hozzávaló hozzáadása'));
      await tester.pumpAndSettle();
      expect(rows(tester).last.data.importDraft, isNull);
      final survivingRow = find.byKey(ObjectKey(before[2]));
      await tester.ensureVisible(survivingRow);
      expect(
        tester
            .widget<IngredientRow>(
              find.descendant(
                of: survivingRow,
                matching: find.byType(IngredientRow),
              ),
            )
            .data,
        same(before[2]),
      );
      await tester.enterText(
        find.descendant(of: survivingRow, matching: field('Hozzávaló')),
        'Végleges',
      );
      expect(before[2].nameController.text, 'Végleges');
      expect(before[0].nameController.text, 'Első');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('last import row deletion leaves clean default row', (
    tester,
  ) async {
    await open(
      tester,
      _Repository(),
      initialImport: imported(
        ingredients: [
          ingredient('Liszt', warnings: [RecipeImportWarning.unknownUnit]),
        ],
      ),
    );
    final old = rows(tester).single.data;
    await tester.tap(find.byTooltip('Hozzávaló törlése'));
    await tester.pumpAndSettle();
    final data = rows(tester).single.data;
    expect(data, isNot(same(old)));
    expect(data.nameController.text, '');
    expect(data.amountController.text, '');
    expect(data.selectedUnit, 'g');
    expect(data.importDraft, isNull);
    expect(find.textContaining('Eredeti:'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'empty import title and unprocessed-only draft remain editable and dirty',
    (tester) async {
      await open(
        tester,
        _Repository(),
        initialImport: imported(
          title: '',
          ingredients: [],
          unprocessed: ['Első eredeti sor', '  Második eredeti sor  '],
        ),
      );
      expect(
        tester.widget<TextField>(field('Recept neve')).controller!.text,
        '',
      );
      expect(rows(tester).single.data.nameController.text, '');
      expect(find.byType(SpiceRow), findsNothing);
      expect(
        find.text('Első eredeti sor\n  Második eredeti sor  '),
        findsNothing,
      );
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      expect(
        find.text('Első eredeti sor\n  Második eredeti sor  '),
        findsOneWidget,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Kilépés mentés nélkül?'), findsOneWidget);
      await tester.tap(find.text('Mégsem'));
      await tester.pumpAndSettle();
      expect(find.byType(AddRecipeScreen), findsOneWidget);
    },
  );

  testWidgets('import immediate system back prompts existing discard dialog', (
    tester,
  ) async {
    await open(tester, _Repository(), initialImport: imported());
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Kilépés mentés nélkül?'), findsOneWidget);
    await tester.tap(find.text('Kilépés'));
    await tester.pumpAndSettle();
    expect(find.byType(AddRecipeScreen), findsNothing);
  });

  testWidgets('ordinary new defaults and pristine back unchanged', (
    tester,
  ) async {
    await open(tester, _Repository());
    expect(rows(tester).single.data.amountController.text, '');
    expect(rows(tester).single.data.selectedUnit, 'g');
    expect(find.byType(SpiceRow), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Kilépés mentés nélkül?'), findsNothing);
    expect(find.byType(AddRecipeScreen), findsNothing);
  });

  testWidgets('existing edit prefills spices and pristine back unchanged', (
    tester,
  ) async {
    await open(
      tester,
      _Repository(),
      recipe: const Recipe(
        id: 'old',
        name: 'Régi',
        ingredients: [RecipeIngredient(name: 'Tej', quantity: 2, unit: 'l')],
        spices: [RecipeSpice(name: 'bors')],
        preparation: 'Eredeti szöveg',
      ),
    );
    expect(rows(tester).single.data.amountController.text, '2');
    expect(
      tester.widget<SpiceRow>(find.byType(SpiceRow)).data.nameController.text,
      'bors',
    );
    expect(find.textContaining('Eredeti:'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Kilépés mentés nélkül?'), findsNothing);
    expect(find.byType(AddRecipeScreen), findsNothing);
  });

  testWidgets('import allows ordinary manual spice addition', (tester) async {
    await open(tester, _Repository(), initialImport: imported());
    await tester.ensureVisible(find.text('Fűszer hozzáadása'));
    await tester.tap(find.text('Fűszer hozzáadása'));
    await tester.pumpAndSettle();
    expect(find.byType(SpiceRow), findsOneWidget);
  });

  testWidgets(
    'import unit editing keeps warning and saves chosen canonical unit',
    (tester) async {
      final repo = _Repository();
      await open(
        tester,
        repo,
        initialImport: imported(
          ingredients: [
            ingredient(
              'Liszt',
              quantity: 2,
              unit: 'db',
              warnings: [RecipeImportWarning.unknownUnit],
            ),
          ],
        ),
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('kg').last);
      await tester.pumpAndSettle();
      expect(rows(tester).single.data.selectedUnit, 'kg');
      expect(find.textContaining('Eredeti: raw Liszt'), findsOneWidget);
      await save(tester);
      expect(repo.saved!.ingredients.single.unit, 'kg');
      expect(repo.saved!.ingredients.single.quantity, 2);
    },
  );

  for (final editing in [false, true]) {
    testWidgets('ordinary mode editing=$editing still protects changes', (
      tester,
    ) async {
      await open(
        tester,
        _Repository(),
        recipe: editing
            ? const Recipe(
                id: 'old',
                name: 'Régi',
                ingredients: [
                  RecipeIngredient(name: 'Tej', quantity: 2, unit: 'l'),
                ],
                spices: [],
                preparation: '',
              )
            : null,
      );
      await tester.enterText(field('Recept neve'), 'Módosított');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Kilépés mentés nélkül?'), findsOneWidget);
      await tester.tap(find.text('Mégsem'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(field('Recept neve')).controller!.text,
        'Módosított',
      );
    });
  }

  testWidgets(
    'narrow viewport keeps import fields in one row with warning below',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await open(
        tester,
        _Repository(),
        initialImport: imported(
          ingredients: [
            ingredient(
              'Nagyon hosszú hozzávalónév szerkeszthető szöveggel',
              warnings: [RecipeImportWarning.unknownUnit],
            ),
          ],
        ),
      );
      expect(
        tester.getTopLeft(field('Hozzávaló')).dy,
        tester.getTopLeft(field('Mennyiség')).dy,
      );
      expect(tester.widget<TextField>(field('Hozzávaló')).maxLines, 1);
      expect(find.textContaining('Eredeti: raw Nagyon hosszú'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final entry in {'1,5': 1.5, '1.5': 1.5, '1/2': 0.5, '½': 0.5}.entries) {
    testWidgets('new recipe saves ${entry.key} as numeric quantity', (
      tester,
    ) async {
      final repo = _Repository();
      await open(tester, repo);
      await tester.enterText(field('Recept neve'), 'Teszt');
      await tester.enterText(field('Hozzávaló'), 'liszt');
      await tester.enterText(field('Mennyiség'), entry.key);
      await save(tester);
      expect(repo.saved!.ingredients.single.quantity, entry.value);
      expect(repo.updated, isNull);
      expect(find.byType(AddRecipeScreen), findsNothing);
    });
  }
  for (final value in ['abc', '0', '-2', '', 'NaN', 'Infinity', '1/0']) {
    testWidgets('invalid quantity "$value" blocks all repository calls', (
      tester,
    ) async {
      final repo = _Repository();
      await open(tester, repo);
      await tester.enterText(field('Recept neve'), 'Teszt');
      await tester.enterText(field('Hozzávaló'), 'liszt');
      await tester.enterText(field('Mennyiség'), value);
      await save(tester);
      expect(repo.saved, isNull);
      expect(repo.updated, isNull);
      expect(repo.checks, 0);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.byType(AddRecipeScreen), findsOneWidget);
    });
  }
  testWidgets('second invalid ingredient prevents any save', (tester) async {
    final repo = _Repository();
    await open(
      tester,
      repo,
      recipe: const Recipe(
        id: 'two',
        name: 'Teszt',
        ingredients: [
          RecipeIngredient(name: 'liszt', quantity: 2, unit: 'g'),
          RecipeIngredient(name: 'tej', quantity: 0, unit: 'ml'),
        ],
        spices: [],
        preparation: '',
      ),
    );
    await save(tester);
    expect(repo.updated, isNull);
    expect(repo.saved, isNull);
    expect(repo.checks, 0);
    expect(find.byType(SnackBar), findsOneWidget);
  });
  testWidgets('existing recipe keeps update path and legacy kk compatibility', (
    tester,
  ) async {
    final repo = _Repository();
    await open(
      tester,
      repo,
      recipe: const Recipe(
        id: 'existing',
        name: 'Teszt',
        ingredients: [RecipeIngredient(name: 'cukor', quantity: 1, unit: 'kk')],
        spices: [],
        preparation: 'Eredeti',
      ),
    );
    await tester.enterText(field('Mennyiség'), '1,5');
    await save(tester);
    expect(repo.saved, isNull);
    expect(repo.updated!.id, 'existing');
    expect(repo.updated!.ingredients.single.quantity, 1.5);
    expect(repo.updated!.ingredients.single.unit, 'tk');
    expect(repo.updated!.preparation, 'Eredeti');
  });
}
