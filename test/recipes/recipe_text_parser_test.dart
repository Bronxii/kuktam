import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/core/domain/measurement_units.dart';
import 'package:kuktam/recipes/domain/models/recipe_import_draft.dart';
import 'package:kuktam/recipes/domain/services/recipe_text_parser.dart';

void main() {
  const parser = RecipeTextParser();
  const unknown = RecipeImportWarning.unknownUnit;
  const missing = RecipeImportWarning.missingQuantity;
  const invalid = RecipeImportWarning.invalidQuantity;
  const ambiguous = RecipeImportWarning.ambiguousIngredient;
  for (final c in <(String, String, List<String>)>[
    ('Csirkés tészta\nHozzávalók:', 'Csirkés tészta', []),
    ('Csirkés tészta\n4 adag\nHozzávalók:', 'Csirkés tészta', ['4 adag']),
    (
      'Csirkés tészta\nkb. 4-5 adag\nIdő: 45 perc\nKalória: 650 kcal\nHozzávalók:',
      'Csirkés tészta',
      ['kb. 4-5 adag', 'Idő: 45 perc', 'Kalória: 650 kcal'],
    ),
    (
      'Csirkés tészta\nElkészítési idő: 45 perc\nSütési idő: 20 perc\nHozzávalók:',
      'Csirkés tészta',
      ['Elkészítési idő: 45 perc', 'Sütési idő: 20 perc'],
    ),
    (
      'Nagymama kedvence\nA család vasárnapi receptje\nHozzávalók:',
      '',
      ['Nagymama kedvence', 'A család vasárnapi receptje'],
    ),
    ('Hozzávalók:', '', []),
    (
      '4 adag\nElkészítési idő: 30 perc\nHozzávalók:',
      '',
      ['4 adag', 'Elkészítési idő: 30 perc'],
    ),
    (
      'BRUTÁL KRÉMES CSIRKÉS-SAJTOS TÉSZTA / sütőben\n\nkb. 5 adag\nIdő: 1 óra körül\nKalória: fogalmam sincs 😄\n\nHOZZÁVALÓK:',
      'BRUTÁL KRÉMES CSIRKÉS-SAJTOS TÉSZTA / sütőben',
      ['kb. 5 adag', 'Idő: 1 óra körül', 'Kalória: fogalmam sincs 😄'],
    ),
  ]) {
    test('title metadata regression: ${c.$1}', () {
      final result = parser.parse('${c.$1}\n500 g liszt');
      expect(result.title, c.$2);
      expect(result.unprocessedSegments, c.$3);
      expect(result.ingredients.single.name, 'liszt');
      expect(result.ingredients.single.quantity, 500);
      expect(result.originalText, '${c.$1}\n500 g liszt');
    });
  }
  test('metadata forms preserve raw text and never become ingredients', () {
    for (final meta in [
      'Adag: 4 fő',
      '4 fő',
      'kb. 4 fő',
      'KB. 4–5 ADAG',
      'FŐZÉSI IDŐ: 10 perc',
      'Pihentetési idő: 20 perc',
      '650 kcal',
      'kb. 650 KCAL',
      'kcal: 650',
    ]) {
      final raw = '  $meta  ';
      final result = parser.parse('Recept\n$raw\nHozzávalók:\n$raw\n2 tojás');
      expect(result.title, 'Recept', reason: meta);
      expect(result.unprocessedSegments, [raw, raw]);
      expect(result.ingredients.single.name, 'tojás');
    }
  });
  test(
    'metadata words inside names or prose do not remove title candidates',
    () {
      for (final text in [
        'A fő kedvencünk',
        'Adag szeretet',
        'Kalória nélkül finoman',
        'Idő nekünk főzni',
      ]) {
        final result = parser.parse(
          'Nagymama kedvence\n$text\nHozzávalók:\n4 adag liszt',
        );
        expect(result.title, '');
        expect(result.unprocessedSegments, ['Nagymama kedvence', text]);
        expect(result.ingredients.single.name, 'adag liszt');
      }
    },
  );
  test('metadata in preparation remains opaque', () {
    const body = '4 adag\nIdő: 45 perc\nAdj hozzá 1/2 dl vizet.';
    expect(parser.parse('Elkészítés:\n$body').preparationText, body);
  });
  for (final c
      in <(String, String, double?, String, List<RecipeImportWarning>)>[
        ('500 g liszt', 'liszt', 500, 'g', []),
        ('liszt 500 g', 'liszt', 500, 'g', []),
        ('2 tojás', 'tojás', 2, 'db', []),
        ('25 dkg vaj', 'vaj', 250, 'g', []),
        ('vaj 25 dkg', 'vaj', 250, 'g', []),
        ('vaj 25dkg', 'vaj', 250, 'g', []),
        ('2 dl tej', 'tej', 200, 'ml', []),
        ('tej 2 dl', 'tej', 200, 'ml', []),
        ('1,5 dl tejszín', 'tejszín', 150, 'ml', []),
        ('125 dkg vaj', 'vaj', 1.25, 'kg', []),
        ('15 dl tej', 'tej', 1.5, 'l', []),
        ('2 bögre liszt', 'liszt', 2, 'db', [unknown]),
        ('1 pohár tej', 'tej', 1, 'db', [unknown]),
        ('1 csipet só', 'só', 1, 'db', [unknown]),
        ('3 marék sajt', 'sajt', 3, 'db', [unknown]),
        ('liszt 2 BÖGRE.', 'liszt', 2, 'db', [unknown]),
        ('só ízlés szerint', 'só ízlés szerint', 1, 'db', [missing]),
        ('bors', 'bors', 1, 'db', [missing]),
        ('kevés olívaolaj', 'kevés olívaolaj', 1, 'db', [missing]),
        ('1/2 kg hús', 'hús', 0.5, 'kg', []),
        ('½ kg hús', 'hús', 0.5, 'kg', []),
        ('¼kg hús', 'hús', 0.25, 'kg', []),
        ('3/4 kg hús', 'hús', 0.75, 'kg', []),
        ('¾ kg hús', 'hús', 0.75, 'kg', []),
        ('1/4 kg hús', 'hús', 0.25, 'kg', []),
        ('1 ek olaj', 'olaj', 1, 'ek', []),
        ('olaj 1 ek', 'olaj', 1, 'ek', []),
        ('1 kk majoranna', 'majoranna', 1, 'tk', []),
        ('0 g liszt', 'liszt', null, 'g', [invalid]),
        ('1/0 kg hús', 'hús', null, 'kg', [invalid]),
        ('-1 alma', 'alma', null, 'db', [invalid]),
        ('1,2.3 kg alma', 'alma', null, 'kg', [invalid]),
        ('NaN g liszt', 'liszt', null, 'g', [invalid]),
        ('Infinity g liszt', 'liszt', null, 'g', [invalid]),
        ('0 bögre liszt', 'liszt', null, 'db', [unknown, invalid]),
        ('2 db alma 3 kg', '2 db alma 3 kg', null, 'db', [ambiguous]),
        ('tej 1 2', 'tej 1 2', null, 'db', [ambiguous]),
        ('1 1/2 kg hús', '1 1/2 kg hús', null, 'db', [ambiguous]),
        ('2 nagy alma', 'nagy alma', 2, 'db', []),
        ('1 karton tej', 'karton tej', 1, 'db', []),
        ('B12 vitamin', 'B12 vitamin', 1, 'db', [missing]),
        ('1.5 kg Piros Alma', 'Piros Alma', 1.5, 'kg', []),
        ('1,234 l tej', 'tej', 1.23, 'l', []),
        ('1,236 l tej', 'tej', 1.24, 'l', []),
        ('1,234 db alma', 'alma', 1.234, 'db', []),
        ('1,234 tk cukor', 'cukor', 1.234, 'tk', []),
        ('• Liszt – 500 g', 'Liszt', 500, 'g', []),
        ('1. 500 g liszt', 'liszt', 500, 'g', []),
      ]) {
    test('ingredient ${c.$1}', () {
      final result = parser.parse('Hozzávalók:\n${c.$1}').ingredients.single;
      expect(result.name, c.$2);
      expect(result.quantity, c.$3);
      expect(result.unit, c.$4);
      expect(result.warnings, c.$5);
      expect(result.rawText, c.$1);
      expect(result.sourceOrder, 1);
      expect(MeasurementUnits.values, contains(result.unit));
    });
  }

  test('title ingredients preparation and original CRLF retained', () {
    const input =
        'Krémes fokhagymás csirke\r\n\r\nHozzávalók:\r\n500 g liszt\r\n2 tojás\r\nElkészítés:\r\n  1. Keverd össze.\r\n\r\n• Adj hozzá 1/2 dl vizet.  ';
    final result = parser.parse(input);
    expect(result.originalText, input);
    expect(result.title, 'Krémes fokhagymás csirke');
    expect(result.ingredients.map((i) => i.name), ['liszt', 'tojás']);
    expect(result.ingredients.map((i) => i.sourceOrder), [3, 4]);
    expect(
      result.preparationText,
      '1. Keverd össze.\n\n• Adj hozzá 1/2 dl vizet.',
    );
    expect(result.unprocessedSegments, isEmpty);
  });

  test('no title and case-insensitive section headings', () {
    final result = parser.parse(
      '  HOZZÁVALÓK :\n2 tojás\n elkészítés MENETE:\nSüsd meg.',
    );
    expect(result.title, '');
    expect(result.ingredients.single.name, 'tojás');
    expect(result.preparationText, 'Süsd meg.');
  });

  test('spices are ingredients in source order without classification', () {
    final result = parser.parse(
      'Recept\nHozzávalók\n2 tojás\nFŰSZEREK:\n1 tk majoranna\nsó\nbors\nElkészítés\nKeverd.',
    );
    expect(result.title, 'Recept');
    expect(result.ingredients.map((i) => i.name), [
      'tojás',
      'majoranna',
      'só',
      'bors',
    ]);
    expect(result.ingredients.map((i) => i.sourceOrder), [2, 4, 5, 6]);
  });

  test('title before spices-only section', () {
    final result = parser.parse(
      'Fűszerkeverék\nFűszerek:\nbors\nElkészítés:\nKeverd.',
    );
    expect(result.title, 'Fűszerkeverék');
    expect(result.ingredients.single.warnings, [missing]);
  });

  test('multiple title candidates retained unprocessed', () {
    final result = parser.parse('Első cím\nMásodik cím\nHozzávalók:\n2 tojás');
    expect(result.title, '');
    expect(result.unprocessedSegments, ['Első cím', 'Második cím']);
  });

  test(
    'headerless ingredients recognized but prose never becomes preparation',
    () {
      final result = parser.parse(
        '500 g liszt\n2 tojás\n\nKeverd össze a hozzávalókat, majd süsd 180 fokon.\nIsmeretlen szöveg',
      );
      expect(result.title, '');
      expect(result.ingredients.map((i) => i.name), ['liszt', 'tojás']);
      expect(result.preparationText, '');
      expect(result.unprocessedSegments, [
        'Keverd össze a hozzávalókat, majd süsd 180 fokon.',
        'Ismeretlen szöveg',
      ]);
    },
  );

  test('headerless ambiguous structures and numbering are not guessed', () {
    final result = parser.parse('2 db alma 3 kg\n1. Keverd össze.\nbors');
    expect(result.ingredients, isEmpty);
    expect(result.unprocessedSegments, [
      '2 db alma 3 kg',
      '1. Keverd össze.',
      'bors',
    ]);
  });

  test('metadata is retained but is neither title nor ingredient', () {
    final result = parser.parse(
      'Elkészítési idő: 45 perc\nHozzávalók:\nSütési idő: 30 perc\nAdag: 4 fő\nKalória: 500 kcal\n2 tojás',
    );
    expect(result.title, '');
    expect(result.ingredients.single.name, 'tojás');
    expect(result.unprocessedSegments, [
      'Elkészítési idő: 45 perc',
      'Sütési idő: 30 perc',
      'Adag: 4 fő',
      'Kalória: 500 kcal',
    ]);
  });

  test('Kuktám share format including separator and footer', () {
    const input =
        'Teszt recept\n\nHozzávalók:\n• Vaj – 125 dkg\n• Tej – 15 dl\n\nFűszerek:\n• bors\n\nElkészítés:\n1. Adj hozzá 1/2 dl vizet.\n\n──────────────\nKészült a Kuktám alkalmazással';
    final result = parser.parse(input);
    expect(result.title, 'Teszt recept');
    expect(result.ingredients.map((i) => (i.name, i.quantity, i.unit)), [
      ('Vaj', 1.25, 'kg'),
      ('Tej', 1.5, 'l'),
      ('bors', 1.0, 'db'),
    ]);
    expect(result.preparationText, '1. Adj hozzá 1/2 dl vizet.');
    expect(result.unprocessedSegments, [
      '──────────────',
      'Készült a Kuktám alkalmazással',
    ]);
  });

  test('export without preparation does not turn footer into ingredients', () {
    final result = parser.parse(
      'Hozzávalók:\n2 tojás\n\n──────────────\nKészült a Kuktám alkalmazással',
    );
    expect(result.ingredients.length, 1);
    expect(result.preparationText, '');
    expect(result.unprocessedSegments.last, 'Készült a Kuktám alkalmazással');
  });

  test('preparation is opaque even with heading-like content and fractions', () {
    const body =
        '1. Adj hozzá ½ kg húst.\n\nHozzávalók:\n- Adj hozzá 1/4 dl vizet.\nAdag: 4 fő';
    final result = parser.parse('Elkészítés:\n$body');
    expect(result.preparationText, body);
    expect(result.ingredients, isEmpty);
  });

  test('blank input and punctuation do not manufacture ingredients', () {
    expect(parser.parse(' \r\n\n').ingredients, isEmpty);
    final result = parser.parse('Hozzávalók:\n•\n-\n*\n1.');
    expect(result.ingredients, isEmpty);
    expect(result.unprocessedSegments, ['•', '-', '*', '1.']);
  });

  test('bullets keep raw whitespace casing and line identity', () {
    const raw = '  •  500 g Piros Liszt  ';
    final result = parser.parse('Hozzávalók:\n\n$raw\n* 2 tojás\n– 1 ek olaj');
    expect(result.ingredients.map((i) => i.name), [
      'Piros Liszt',
      'tojás',
      'olaj',
    ]);
    expect(result.ingredients.first.rawText, raw);
    expect(result.ingredients.map((i) => i.sourceOrder), [2, 3, 4]);
  });

  test('unclassified content preserved verbatim instead of discarded', () {
    const raw = '  Ez nem sorolható biztonságosan sehova.  ';
    final result = parser.parse('$raw\nHozzávalók:\n2 db alma 3 kg');
    expect(result.title, '');
    expect(result.unprocessedSegments, [raw]);
    expect(result.ingredients.single.rawText, '2 db alma 3 kg');
    expect(result.ingredients.single.warnings, [ambiguous]);
  });

  test('original quantity token is distinct from normalized quantity', () {
    final result = parser.parse('Hozzávalók:\n125 dkg vaj').ingredients.single;
    expect(result.rawQuantityText, '125');
    expect(result.quantity, 1.25);
    expect(result.unit, 'kg');
  });

  test('overflow is repairable without substituting a quantity', () {
    final result = parser
        .parse('Hozzávalók:\n${'9' * 308} dl tej')
        .ingredients
        .single;
    expect(result.quantity, isNull);
    expect(result.warnings, [invalid]);
  });

  test('draft collections defensively copied and unmodifiable', () {
    final warnings = [missing];
    final ingredient = RecipeImportIngredientDraft(
      sourceOrder: 0,
      rawText: 'bors',
      name: 'bors',
      quantity: 1,
      rawQuantityText: null,
      unit: 'db',
      warnings: warnings,
    );
    final ingredients = [ingredient];
    final unprocessed = ['meta'];
    final draft = RecipeImportDraft(
      originalText: '',
      title: '',
      ingredients: ingredients,
      preparationText: '',
      unprocessedSegments: unprocessed,
    );
    warnings.clear();
    ingredients.clear();
    unprocessed.clear();
    expect(draft.ingredients.single.warnings, [missing]);
    expect(draft.unprocessedSegments, ['meta']);
    expect(() => draft.ingredients.clear(), throwsUnsupportedError);
    expect(() => ingredient.warnings.clear(), throwsUnsupportedError);
    expect(() => draft.unprocessedSegments.clear(), throwsUnsupportedError);
  });
}
