import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/sharing/shared_recipe_text_normalizer.dart';
import 'package:kuktam/recipes/domain/services/recipe_text_parser.dart';

void main() {
  const normalizer = SharedRecipeTextNormalizer();
  for (final (quantity, unit, name) in [
    ('1', 'db', 'tojás'),
    ('20', 'dkg', 'porcukor'),
    ('2.5', 'dl', 'tejszín'),
    ('0.5', 'db', 'citrom'),
    ('7.5', 'dkg', 'vaj'),
    ('2,5', 'dl', 'tejszín'),
    ('1/2', 'kg', 'liszt'),
    ('½', 'l', 'tej'),
    ('1', 'db', 'vaníliás cukor'),
    for (final unit in [
      'g',
      'kg',
      'ml',
      'l',
      'tk',
      'kk',
      'ek',
      'darab',
      'gr',
      'teáskanál',
    ])
      ('1', unit, 'cukor'),
  ]) {
    test('reconstructs $quantity / $unit / $name without conversion', () {
      final output = normalizer.normalize('$quantity\n$unit\n$name');
      expect(output, '$quantity $unit $name');
      expect(normalizer.normalize(output), output);
    });
  }
  for (final input in [
    '1\ntojás',
    'db\ntojás',
    '20\nporcukor',
    '1\nmokkáskanál\nvaníliaaroma',
    '1\nmokkáskanál vaníliaaroma',
    '1 mokkáskanál vaníliaaroma',
    '1\ndb\nA tésztához:',
    '1\ndb\nHozzávalók',
    '1\ndb\n2 db tojás',
    '1\ndb\nml',
    '1\ndb',
    'Elkészítés\nMelegítsd elő a sütőt\n180 fokra',
    'Elkészítés:\n1\ndb\ntojás',
    '1 db tojás\n20 dkg porcukor\n2.5 dl tejszín',
    'https://example.com/recept',
    '',
    '   ',
    '0\ndb\ntojás',
    '-1\ndb\ntojás',
  ]) {
    test('preserves ambiguous or already-normal text: $input', () {
      expect(normalizer.normalize(input), input);
    });
  }
  test('mixed sections, consecutive triples, blank lines and accents', () {
    const input =
        'A tésztához:\n\n1\n\ndb\n\ntojás\n20 dkg porcukor\n50\ndkg\ntúró\n\nA vaníliás krémhez:\n';
    const expected =
        'A tésztához:\n\n1 db tojás\n20 dkg porcukor\n50 dkg túró\n\nA vaníliás krémhez:\n';
    expect(normalizer.normalize(input), expected);
    expect(normalizer.normalize(expected), expected);
  });
  test('CRLF preserved and 20k input remains bounded', () {
    expect(normalizer.normalize('1\r\ndb\r\ntojás'), '1 db tojás');
    final input = ('1\ndb\ntojás\n' * 1800);
    final result = normalizer.normalize(input);
    expect(result, '1 db tojás\n' * 1800);
    expect(normalizer.normalize(result), result);
  });
  test('real browser fixture → normalizer → existing recipe parser', () {
    // User-provided phone regression sample; no fetched/site-specific input.
    final raw = File(
      'test/sharing/fixtures/browser_split_ingredients.txt',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final normalized = normalizer.normalize(raw);
    for (final heading in [
      'A tésztához:',
      'A vaníliás krémhez:',
      'A tepsi kikenéséhez:',
    ]) {
      expect(normalized.split('\n'), contains(heading));
    }
    expect(normalized, contains('1\nmokkáskanál vaníliaaroma'));
    expect(normalizer.normalize(normalized), normalized);
    final parsed = const RecipeTextParser().parse(normalized);
    final actual = parsed.ingredients
        .map((i) => (i.name, i.quantity, i.unit))
        .toList();
    for (final expected in [
      ('tojás', 1.0, 'db'),
      ('tojássárgája', 1.0, 'db'),
      ('porcukor', 200.0, 'g'),
      ('túró', 500.0, 'g'),
      ('tejszín', 250.0, 'ml'),
      ('tejföl', 50.0, 'g'),
      ('citrom', 0.5, 'db'),
      ('liszt', 1.0, 'ek'),
      ('tojás', 4.0, 'db'),
      ('vaj', 1.0, 'ek'),
      ('kekszmorzsa', 3.0, 'ek'),
    ]) {
      expect(actual, contains(expected));
    }
  });
}
