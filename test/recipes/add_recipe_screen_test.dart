import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/recipes/data/repositories/recipe_repository.dart';
import 'package:kuktam/recipes/domain/models/recipe.dart';
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
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
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
