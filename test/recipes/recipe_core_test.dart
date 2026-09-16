import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/recipes/data/repositories/recipe_repository.dart';
import 'package:kuktam/recipes/domain/models/recipe.dart';
import 'package:kuktam/recipes/presentation/screens/add_recipe_screen.dart';
import 'package:kuktam/recipes/presentation/screens/recipes_screen.dart';
import 'package:kuktam/recipes/presentation/screens/recipe_details_screen.dart';
import 'package:kuktam/recipes/presentation/widgets/ingredient_row.dart';
import 'package:kuktam/recipes/presentation/widgets/spice_row.dart';
import 'package:kuktam/features/auth/data/repositories/auth_repository.dart';
import 'package:kuktam/features/auth/presentation/widgets/auth_gate.dart';
import 'package:kuktam/core/domain/measurement_units.dart';
import 'recipe_repository_test.dart' show RecipeTestAuth, RecipeTestUser;

class CoreRepository implements RecipeRepository {
  final recipes = <Recipe>[];
  int saves = 0, updates = 0, deletes = 0, checks = 0;
  bool failCheck = false,
      failSave = false,
      failUpdate = false,
      failDelete = false;
  Completer<void>? pending;
  Completer<List<Recipe>>? pendingLoad;
  bool failLoad = false;
  @override
  Future<bool> recipeNameExists({
    required String name,
    String? excludedRecipeId,
  }) async {
    checks++;
    if (failCheck) throw StateError('private backend detail');
    return recipes.any(
      (r) =>
          r.id != excludedRecipeId &&
          r.name.trim().toLowerCase() == name.trim().toLowerCase(),
    );
  }

  @override
  Future<void> saveRecipe(Recipe recipe) async {
    saves++;
    if (pending != null) await pending!.future;
    if (failSave) throw StateError('private backend detail');
    recipes.add(recipe);
  }

  @override
  Future<void> updateRecipe(Recipe recipe) async {
    updates++;
    if (pending != null) await pending!.future;
    if (failUpdate) throw StateError('private backend detail');
    recipes.removeWhere((r) => r.id == recipe.id);
    recipes.add(recipe);
  }

  @override
  Future<void> deleteRecipe(String id) async {
    deletes++;
    if (pending != null) await pending!.future;
    if (failDelete) throw StateError('private backend detail');
    recipes.removeWhere((r) => r.id == id);
  }

  @override
  Future<List<Recipe>> getRecipes() async {
    if (failLoad) throw StateError('private backend detail');
    if (pendingLoad != null) return pendingLoad!.future;
    return List.of(recipes);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Recipe coreRecipe({String id = 'one', String name = 'Leves'}) => Recipe(
  id: id,
  name: name,
  ingredients: const [
    RecipeIngredient(name: 'Liszt', quantity: 1.5, unit: 'kg'),
  ],
  spices: const [RecipeSpice(name: 'Bors')],
  preparation: 'Keverd össze.\n\nŐrölt fűszer.',
);

Finder coreField(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);

Future<void> openCoreEditor(
  WidgetTester tester,
  CoreRepository repo, {
  Recipe? recipe,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<Recipe>(
                builder: (_) =>
                    AddRecipeScreen(recipe: recipe, recipeRepository: repo),
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

Future<VoidCallback> saveCallback(WidgetTester tester) async {
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
  return tester
      .widget<FilledButton>(find.widgetWithText(FilledButton, 'Mentés'))
      .onPressed!;
}

void main() {
  testWidgets(
    'AuthGate user switch removes old recipe state and ignores late A response',
    (tester) async {
      final auth = RecipeTestAuth();
      final a = CoreRepository()..pendingLoad = Completer<List<Recipe>>();
      final b = CoreRepository()
        ..recipes.add(coreRecipe(name: 'B saját recept'));
      await tester.pumpWidget(
        MaterialApp(
          home: AuthGate(
            authRepository: AuthRepository(firebaseAuth: auth),
            mainBuilder: (_) => Scaffold(
              body: RecipesScreen(
                recipeRepository: auth.currentUser!.uid == 'A' ? a : b,
              ),
            ),
          ),
        ),
      );
      auth.changes.add(auth.currentUser);
      await tester.pump();
      await tester.pump();
      auth.currentUser = RecipeTestUser('B');
      auth.changes.add(auth.currentUser);
      await tester.pumpAndSettle();
      expect(find.text('B saját recept'), findsOneWidget);
      a.pendingLoad!.complete([coreRecipe(name: 'A titkos recept')]);
      await tester.pumpAndSettle();
      expect(find.text('A titkos recept'), findsNothing);
      expect(find.text('B saját recept'), findsOneWidget);
      a.pendingLoad = null;
      a.recipes.add(coreRecipe(name: 'A saját recept'));
      auth.currentUser = RecipeTestUser('A');
      auth.changes.add(auth.currentUser);
      await tester.pumpAndSettle();
      expect(find.text('A saját recept'), findsOneWidget);
      expect(find.text('B saját recept'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await auth.changes.close();
    },
  );

  testWidgets(
    'new recipe rapid save once; blank spice/preparation supported, exact units',
    (tester) async {
      final repo = CoreRepository()..pending = Completer<void>();
      await openCoreEditor(tester, repo);
      await tester.enterText(coreField('Recept neve'), '  Új recept  ');
      await tester.enterText(coreField('Hozzávaló'), 'Zab');
      await tester.enterText(coreField('Mennyiség'), '1.236');
      final dropdown = tester.widget<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>),
      );
      dropdown.onChanged!('l');
      await tester.pump();
      final button = tester.widget<DropdownButton<String>>(
        find.byType(DropdownButton<String>),
      );
      expect(button.items!.map((item) => item.value), MeasurementUnits.values);
      final save = await saveCallback(tester);
      save();
      save();
      await tester.pump();
      expect(repo.saves, 1);
      expect(repo.checks, 1);
      repo.pending!.complete();
      await tester.pumpAndSettle();
      final saved = repo.recipes.single;
      expect(saved.name, 'Új recept');
      expect(saved.preparation, '');
      expect(saved.spices.every((spice) => spice.name.isEmpty), isTrue);
      // Manual editor quantities remain exact; kitchen rounding belongs to import/scaling.
      expect(saved.ingredients.single.quantity, 1.236);
      expect(saved.ingredients.single.unit, 'l');
    },
  );

  for (final quantity in ['0.00000001', '10000000000000000000000000']) {
    testWidgets(
      'small/large positive quantity survives editor save and reopen: $quantity',
      (tester) async {
        final repo = CoreRepository();
        await openCoreEditor(tester, repo, recipe: coreRecipe());
        await tester.enterText(coreField('Mennyiség'), quantity);
        (await saveCallback(tester))();
        await tester.pumpAndSettle();
        final second = CoreRepository();
        await openCoreEditor(tester, second, recipe: repo.recipes.single);
        (await saveCallback(tester))();
        await tester.pumpAndSettle();
        expect(second.updates, 1);
        expect(
          second.recipes.single.ingredients.single.quantity,
          double.parse(quantity),
        );
      },
    );
  }

  testWidgets(
    'list loading, safe error retry, empty, name-only case/accent search and clear',
    (tester) async {
      final repo = CoreRepository()..pendingLoad = Completer<List<Recipe>>();
      Future<void> open() => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecipesScreen(key: UniqueKey(), recipeRepository: repo),
          ),
        ),
      );
      await open();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      repo.pendingLoad!.completeError(StateError('private backend detail'));
      await tester.pumpAndSettle();
      expect(find.textContaining('private backend'), findsNothing);
      expect(find.text('Nem sikerült betölteni a recepteket.'), findsOneWidget);
      repo.pendingLoad = null;
      await tester.tap(find.text('Újrapróbálás'));
      await tester.pumpAndSettle();
      expect(find.text('Még nincsenek receptjeid'), findsOneWidget);
      repo.recipes.addAll([
        coreRecipe(name: 'Áfonyás süti'),
        coreRecipe(id: 'two', name: 'Leves'),
      ]);
      await open();
      await tester.pumpAndSettle();
      final search = find.descendant(
        of: find.byType(SearchBar),
        matching: find.byType(TextField),
      );
      for (final query in ['Áfonyás süti', 'FONYÁS', ' áfonyás ']) {
        await tester.enterText(search, query);
        await tester.pump();
        expect(find.widgetWithText(ListTile, 'Áfonyás süti'), findsOneWidget);
        expect(find.widgetWithText(ListTile, 'Leves'), findsNothing);
      }
      await tester.enterText(search, 'Liszt');
      await tester.pump();
      expect(find.text('Nincs találat.'), findsOneWidget);
      await tester.enterText(search, '');
      await tester.pump();
      expect(find.byType(ListTile), findsNWidgets(2));
    },
  );

  for (final editing in [false, true]) {
    testWidgets('create/update error retry preserves fields editing=$editing', (
      tester,
    ) async {
      final repo = CoreRepository()
        ..failSave = true
        ..failUpdate = true;
      await openCoreEditor(tester, repo, recipe: editing ? coreRecipe() : null);
      if (!editing) {
        await tester.enterText(coreField('Recept neve'), 'Új étel');
        await tester.enterText(coreField('Hozzávaló'), 'Liszt');
        await tester.enterText(coreField('Mennyiség'), '1,5');
      }
      (await saveCallback(tester))();
      await tester.pumpAndSettle();
      expect(find.byType(AddRecipeScreen), findsOneWidget);
      expect(
        find.text('Nem sikerült elmenteni a receptet. Próbáld újra.'),
        findsOneWidget,
      );
      expect(find.textContaining('private backend'), findsNothing);
      repo.failSave = false;
      repo.failUpdate = false;
      (await saveCallback(tester))();
      await tester.pumpAndSettle();
      expect(repo.recipes.single.ingredients.single.quantity, 1.5);
      expect(repo.saves, editing ? 0 : 2);
      expect(repo.updates, editing ? 2 : 0);
      expect(find.byType(AddRecipeScreen), findsNothing);
    });
  }

  testWidgets(
    'required and duplicate names, own unchanged name and other name',
    (tester) async {
      final repo = CoreRepository()
        ..recipes.addAll([coreRecipe(), coreRecipe(id: 'two', name: 'Másik')]);
      await openCoreEditor(tester, repo, recipe: coreRecipe());
      await tester.enterText(coreField('Recept neve'), '   ');
      (await saveCallback(tester))();
      await tester.pumpAndSettle();
      expect(repo.checks, 0);
      expect(find.text('Add meg a recept nevét!'), findsOneWidget);
      ScaffoldMessenger.of(
        tester.element(find.byType(AddRecipeScreen)),
      ).clearSnackBars();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        coreField('Recept neve'),
        -300,
        scrollable: find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.enterText(coreField('Recept neve'), '  MÁSIK  ');
      (await saveCallback(tester))();
      await tester.pumpAndSettle();
      expect(repo.updates, 0);
      expect(find.text('Már létezik ilyen nevű recept!'), findsOneWidget);
      await tester.scrollUntilVisible(
        coreField('Recept neve'),
        -300,
        scrollable: find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.enterText(coreField('Recept neve'), ' leves ');
      (await saveCallback(tester))();
      await tester.pumpAndSettle();
      expect(repo.updates, 1);
      expect(repo.recipes.last.name, 'leves');
    },
  );

  testWidgets(
    'ingredient/spice add edit delete retains order and unit, preparation roundtrip',
    (tester) async {
      final repo = CoreRepository();
      await openCoreEditor(tester, repo, recipe: coreRecipe());
      await tester.tap(find.text('Hozzávaló hozzáadása'));
      await tester.pump();
      await tester.tap(find.text('Hozzávaló hozzáadása'));
      await tester.pump();
      final rows = tester
          .widgetList<IngredientRow>(find.byType(IngredientRow))
          .toList();
      rows[1].data.nameController.text = 'Törlendő';
      rows[1].data.amountController.text = '2';
      rows[2].data.nameController.text = 'Tej';
      rows[2].data.amountController.text = '0,125';
      rows[2].data.selectedUnit = 'l';
      rows[1].onRemove();
      await tester.pump();
      final remaining = tester
          .widgetList<IngredientRow>(find.byType(IngredientRow))
          .toList();
      expect(identical(remaining.last.data, rows.last.data), isTrue);
      await tester.ensureVisible(find.text('Fűszer hozzáadása'));
      await tester.tap(find.text('Fűszer hozzáadása'));
      await tester.pump();
      final spices = tester
          .widgetList<SpiceRow>(find.byType(SpiceRow))
          .toList();
      spices.last.data.nameController.text = 'Majoranna';
      spices.first.onRemove();
      await tester.pump();
      await tester.ensureVisible(coreField('Elkészítés menete'));
      const preparation = '1. Őröld meg.\n\nMásodik bekezdés 😊';
      await tester.enterText(coreField('Elkészítés menete'), preparation);
      (await saveCallback(tester))();
      await tester.pumpAndSettle();
      final saved = Recipe.fromMap(repo.recipes.single.toMap(), id: 'one');
      expect(saved.ingredients.map((r) => r.name), ['Liszt', 'Tej']);
      expect(saved.ingredients.last.quantity, .125);
      expect(saved.ingredients.last.unit, 'l');
      expect(saved.spices.single.name, 'Majoranna');
      expect(saved.preparation, preparation);
      await openCoreEditor(tester, CoreRepository(), recipe: saved);
      expect(
        tester
            .widgetList<IngredientRow>(find.byType(IngredientRow))
            .last
            .data
            .nameController
            .text,
        'Tej',
      );
    },
  );

  for (final change in [
    'Hozzávaló',
    'Mennyiség',
    'Fűszer',
    'Elkészítés menete',
    'Egység',
  ]) {
    testWidgets('dirty Back preserves $change and cancel remains editable', (
      tester,
    ) async {
      await openCoreEditor(tester, CoreRepository(), recipe: coreRecipe());
      if (change == 'Egység') {
        tester
                .widget<IngredientRow>(find.byType(IngredientRow))
                .data
                .selectedUnit =
            'g';
      } else {
        await tester.ensureVisible(coreField(change));
        await tester.enterText(
          coreField(change),
          change == 'Mennyiség' ? '2' : 'Módosítva',
        );
      }
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Kilépés mentés nélkül?'), findsOneWidget);
      await tester.tap(find.text('Mégsem'));
      await tester.pumpAndSettle();
      expect(find.byType(AddRecipeScreen), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kilépés'));
      await tester.pumpAndSettle();
      expect(find.byType(AddRecipeScreen), findsNothing);
    });
  }

  testWidgets(
    'delete cancel, failure retry, repeated tap, Back and list refresh',
    (tester) async {
      final repo = CoreRepository()..recipes.add(coreRecipe());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: RecipesScreen(recipeRepository: repo)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Leves'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Törlés'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mégse'));
      await tester.pumpAndSettle();
      expect(repo.deletes, 0);
      repo.failDelete = true;
      await tester.tap(find.byTooltip('Törlés'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Törlés'));
      await tester.pumpAndSettle();
      expect(find.byType(RecipeDetailsScreen), findsOneWidget);
      expect(
        find.text('Nem sikerült törölni a receptet. Próbáld újra.'),
        findsOneWidget,
      );
      expect(find.textContaining('private backend'), findsNothing);
      repo.failDelete = false;
      repo.pending = Completer<void>();
      final action = tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == 'Törlés',
            ),
          )
          .onPressed!;
      action();
      action();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Törlés'));
      await tester.pump();
      action();
      await tester.pump();
      expect(repo.deletes, 2); // one failed attempt plus one retry
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(RecipeDetailsScreen), findsOneWidget);
      repo.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(RecipeDetailsScreen), findsNothing);
      expect(find.text('Még nincsenek receptjeid'), findsOneWidget);
    },
  );

  testWidgets(
    'edit success refreshes list and active search, update does not create document',
    (tester) async {
      final repo = CoreRepository()..recipes.add(coreRecipe());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: RecipesScreen(recipeRepository: repo)),
        ),
      );
      await tester.pumpAndSettle();
      final search = find.descendant(
        of: find.byType(SearchBar),
        matching: find.byType(TextField),
      );
      await tester.enterText(search, 'Leves');
      await tester.pump();
      await tester.tap(find.widgetWithText(ListTile, 'Leves'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Szerkesztés'));
      await tester.pumpAndSettle();
      await tester.enterText(coreField('Recept neve'), 'Új név');
      (await saveCallback(tester))();
      await tester.pumpAndSettle();
      expect(find.byType(RecipeDetailsScreen), findsNothing);
      expect(find.text('Nincs találat.'), findsOneWidget);
      await tester.enterText(search, '');
      await tester.pump();
      expect(find.widgetWithText(ListTile, 'Új név'), findsOneWidget);
      expect(repo.updates, 1);
      expect(repo.saves, 0);
      expect(repo.recipes.length, 1);
    },
  );

  testWidgets(
    'rapid save invokes repository once and blocks Back until complete',
    (tester) async {
      final repo = CoreRepository()..pending = Completer<void>();
      await openCoreEditor(tester, repo, recipe: coreRecipe());
      final save = await saveCallback(tester);
      save();
      save();
      await tester.pump();
      expect(repo.updates, 1);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(AddRecipeScreen), findsOneWidget);
      expect(find.text('Kilépés mentés nélkül?'), findsNothing);
      repo.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(AddRecipeScreen), findsNothing);
    },
  );

  testWidgets(
    'name query failure keeps edits, hides backend details and allows retry',
    (tester) async {
      final repo = CoreRepository()..failCheck = true;
      await openCoreEditor(tester, repo, recipe: coreRecipe());
      final save = await saveCallback(tester);
      save();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.text('Nem sikerült elmenteni a receptet. Próbáld újra.'),
        findsOneWidget,
      );
      expect(find.textContaining('private backend'), findsNothing);
      expect(repo.updates, 0);
      repo.failCheck = false;
      (await saveCallback(tester))();
      await tester.pumpAndSettle();
      expect(repo.updates, 1);
    },
  );
}
