import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/recipes/domain/models/recipe.dart';
import 'package:kuktam/what_to_cook/domain/services/recipe_matcher.dart';

Recipe recipe(String name, List<String> names) => Recipe(
  name: name,
  ingredients: [
    for (final n in names) RecipeIngredient(name: n, quantity: 500, unit: 'g'),
  ],
  spices: const [RecipeSpice(name: 'só')],
  preparation: 'Keverd.',
);

void main() {
  const matcher = RecipeMatcher();
  final chicken = recipe('Csirkés étel', ['csirkemell', 'krémsajt']);

  final cases =
      <
        ({
          String label,
          List<String> names,
          List<String> selected,
          bool matches,
        })
      >[
        (
          label:
              'one selected ingredient matches a recipe with additional ingredients',
          names: ['csirkemell', 'krémsajt'],
          selected: ['csirkemell'],
          matches: true,
        ),
        (
          label: 'all selected ingredients match',
          names: ['csirkemell', 'krémsajt'],
          selected: ['csirkemell', 'krémsajt'],
          matches: true,
        ),
        (
          label: 'one missing selected ingredient excludes the recipe',
          names: ['csirkemell', 'krémsajt'],
          selected: ['csirkemell', 'burgonya'],
          matches: false,
        ),
        (
          label: 'matching ignores case',
          names: ['Csirkemell'],
          selected: ['csirkemell'],
          matches: true,
        ),
        (
          label: 'matching trims both recipe and selected names',
          names: ['  Csirkemell  '],
          selected: [' csirkemell '],
          matches: true,
        ),
        (
          label: 'multiple additional recipe ingredients are allowed',
          names: ['csirkemell', 'krémsajt', 'tortilla', 'főzőtejszín'],
          selected: ['csirkemell'],
          matches: true,
        ),
        (
          label: 'duplicate selections and recipe ingredients are harmless',
          names: ['csirkemell', 'csirkemell', 'krémsajt'],
          selected: ['csirkemell', ' CSIRKEMELL '],
          matches: true,
        ),
        (
          label: 'accents remain significant',
          names: ['krémsajt'],
          selected: ['kremsajt'],
          matches: false,
        ),
        (
          label: 'an empty recipe cannot satisfy a selection',
          names: [],
          selected: ['csirkemell'],
          matches: false,
        ),
      ];
  for (final c in cases) {
    test(c.label, () {
      final r = recipe('Étel', c.names);
      expect(
        matcher.findMatchingRecipes(
          recipes: [r],
          selectedIngredients: c.selected,
        ),
        c.matches ? [r] : isEmpty,
      );
    });
  }

  test(
    'empty selection keeps sorted all-recipes browsing including empty recipes',
    () {
      final empty = recipe('Üres', []);
      expect(
        matcher.findMatchingRecipes(
          recipes: [empty, chicken],
          selectedIngredients: [],
        ),
        [chicken, empty],
      );
    },
  );

  test('spices do not satisfy a selected ingredient', () {
    expect(
      matcher.findMatchingRecipes(
        recipes: [chicken],
        selectedIngredients: ['csirkemell', 'só'],
      ),
      isEmpty,
    );
  });

  test('quantity and unit do not affect ingredient-name matching', () {
    final otherQuantity = Recipe(
      name: 'Más mennyiség',
      ingredients: const [
        RecipeIngredient(name: 'csirkemell', quantity: 0.125, unit: 'kg'),
      ],
      spices: const [],
      preparation: '',
    );
    expect(
      matcher.findMatchingRecipes(
        recipes: [otherQuantity, chicken],
        selectedIngredients: ['csirkemell'],
      ),
      [chicken, otherQuantity],
    );
  });
}
