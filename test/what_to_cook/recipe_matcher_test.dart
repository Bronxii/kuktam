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
  final a = recipe('A', ['tojás', 'liszt']);
  final b = recipe('B', ['tojás', 'liszt', 'tej']);
  test('pantry must contain every recipe ingredient, not the reverse', () {
    expect(
      matcher.findMatchingRecipes(
        recipes: [a, b],
        selectedIngredients: ['tojás', 'liszt'],
      ),
      [a],
    );
    expect(
      matcher.findMatchingRecipes(
        recipes: [a, b],
        selectedIngredients: ['tojás', 'liszt', 'tej', 'alma'],
      ),
      [a, b],
    );
  });
  test(
    'case trim accents duplicates; quantities units and spices do not affect matching',
    () {
      final r = recipe('Étel', [' Tojás ', 'LISZT', 'tojás']);
      expect(
        matcher.findMatchingRecipes(
          recipes: [r],
          selectedIngredients: [' TOJÁS ', 'liszt', 'víz'],
        ),
        [r],
      );
      expect(
        matcher.findMatchingRecipes(
          recipes: [r],
          selectedIngredients: ['tojas', 'liszt'],
        ),
        isEmpty,
      );
    },
  );
  test(
    'empty selection retains all-recipes browsing; empty recipe excluded from matches',
    () {
      final empty = recipe('Üres', []);
      expect(
        matcher.findMatchingRecipes(
          recipes: [a, empty],
          selectedIngredients: [],
        ),
        [a, empty],
      );
      expect(
        matcher.findMatchingRecipes(
          recipes: [empty],
          selectedIngredients: ['tojás'],
        ),
        isEmpty,
      );
    },
  );
}
