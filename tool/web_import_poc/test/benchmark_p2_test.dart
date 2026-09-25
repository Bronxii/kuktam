import 'package:test/test.dart';
import '../bin/benchmark_p2.dart' as p2;

void main() {
  test('comparison ignores case and Unicode whitespace only', () {
    expect(p2.normalize('  2\u00a0db\u202fTOJÁS\n'), '2 db tojás');
    expect(p2.normalize('só'), isNot(p2.normalize('so')));
    expect(p2.normalize('0.5 dl tej'), isNot(p2.normalize('0 dl tej')));
    expect(p2.normalize('10 dkg liszt'), isNot(p2.normalize('100 g liszt')));
  });
  test('duplicate reference cannot reuse one extracted line', () {
    expect(p2.matchLines(['Só', 'só'], ['só']), [0, -1]);
    expect(p2.matchLines(['Só', 'só'], ['só', 'Só']), [0, 1]);
  });
  test('matching exposes reordered lines without changing inputs', () {
    expect(p2.matchLines(['só', 'bors'], ['Bors', 'Só']), [1, 0]);
  });
  test('GT reader retains raw ingredients and numbered paraphrase', () {
    final gt = p2.readGroundTruth(
      '\ufeffCÍM:\r\nPróba\r\n\r\nHOZZÁVALÓK:\r\n0.5 dl tej\r\n\r\nELKÉSZÍTÉS:\r\n1. Keverd össze.\r\n',
    );
    expect(gt['title'], 'Próba');
    expect(gt['ingredients'], ['0.5 dl tej']);
    expect(gt['instructions'], ['1. Keverd össze.']);
  });
  test('malformed GT fails instead of silent partial measurement', () {
    expect(() => p2.readGroundTruth('CÍM:\nPróba'), throwsFormatException);
  });
  test('snapshot audit reads JSON-LD only, no page DOM fallback', () {
    final recipes = p2.sourceRecipes(
      '<div>Other recipe</div><script type="application/ld+json">{"@graph":[{"@type":["Recipe"],"recipeIngredient":["0 dl tej"]}]}</script>',
    );
    expect(recipes.single['recipeIngredient'], ['0 dl tej']);
    expect(p2.sourceRecipes('<div>Recipe</div>'), isEmpty);
  });
}
