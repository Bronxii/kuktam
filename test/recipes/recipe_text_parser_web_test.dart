import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/recipes/domain/services/recipe_text_parser.dart';
import 'package:kuktam/recipes/domain/models/recipe_import_draft.dart';

void main() {
  const parser = RecipeTextParser();
  for (var level = 1; level <= 6; level++) {
    test('Markdown heading level $level', () {
      final result = parser.parse(
        '${'#' * level} Csirkés tészta\n4 adag\n### Hozzávalók\n100 g liszt',
      );
      expect(result.title, 'Csirkés tészta');
      expect(result.ingredients.single.name, 'liszt');
      expect(result.unprocessedSegments, ['4 adag']);
    });
  }
  test('heading without space and conservative multiple titles', () {
    expect(
      parser.parse('#Csirkés tészta\nHozzávalók:').title,
      'Csirkés tészta',
    );
    expect(parser.parse('#Első cím\nMásodik cím\nHozzávalók:').title, '');
    expect(
      parser.parse('####### Nem heading\nHozzávalók:').title,
      isNot('Nem heading'),
    );
  });
  for (final example in <(String, String, double, String, bool)>[
    (
      '100 g [zabpehely](https://example.com/zab)',
      'zabpehely',
      100,
      'g',
      false,
    ),
    (
      '1 dl [whiskey](https://example.com/whiskey) (skót)',
      'whiskey (skót)',
      100,
      'ml',
      false,
    ),
    (
      '[menta](https://example.com/menta) ízlés szerint',
      'menta ízlés szerint',
      1,
      'db',
      true,
    ),
  ]) {
    test('Markdown link ${example.$2}', () {
      final result = parser.parse('Hozzávalók:\n${example.$1}');
      final row = result.ingredients.single;
      expect(
        (row.name, row.quantity, row.unit),
        (example.$2, example.$3, example.$4),
      );
      expect(row.rawText, example.$1);
      expect(row.sourceOrder, 1);
      expect(
        row.warnings,
        example.$5 ? [RecipeImportWarning.missingQuantity] : isEmpty,
      );
    });
  }
  test('structural noise has no ingredients or title', () {
    final result = parser.parse(
      '****\n**\n###\n-\n-\n•\nHozzávalók:\n****\n#\n-\n•',
    );
    expect(result.ingredients, isEmpty);
    expect(result.title, '');
  });
  for (final reversed in [false, true]) {
    test('nutrition context both orientations $reversed', () {
      final nutrition = reversed
          ? 'Kalória\n504\nFehérje\n5.9g\nCukor\n16.1g'
          : '504\nKalória\n5.9g\nFehérje\n38.4g\nSzénhidrát\n31g\nZsír';
      final result = parser.parse(
        'Hozzávalók:\n100 g liszt\n50 g cukor\n\n$nutrition\nElkészítés:\nKeverd össze.',
      );
      expect(result.ingredients.map((r) => r.name), ['liszt', 'cukor']);
      expect(result.unprocessedSegments, nutrition.split('\n'));
      expect(result.preparationText, 'Keverd össze.');
    });
  }
  test('nutrition names and isolated numbers do not establish a block', () {
    final result = parser.parse(
      'Hozzávalók:\n100 g cukor\n30 g zsír\n200 ml víz\nsó\nvíz\ncukor\n504',
    );
    expect(result.ingredients.map((r) => r.name), [
      'cukor',
      'zsír',
      'víz',
      'só',
      'víz',
      'cukor',
      '504',
    ]);
    expect(result.ingredients.last.quantity, isNull);
    expect(result.ingredients.last.rawText, '504');
  });
  test('web labels and bounded values preserve raw text', () {
    const meta =
        'Idő\n30p\nKöltség\nmegfizethető\nNehézség\nkönnyű\nAdag\n4 adag';
    final result = parser.parse('# Recept\n$meta\nHozzávalók:\n100 g liszt');
    expect(result.title, 'Recept');
    expect(result.ingredients.single.name, 'liszt');
    expect(result.unprocessedSegments, meta.split('\n'));
  });
  for (final ad in [
    'HIRDETÉS',
    'ADVERTISEMENT',
    'AD',
    '[Állítsd be itt, hogy könnyen megtaláld a recepteket!](https://example.org/preferences)',
  ]) {
    test('generic advertisement $ad', () {
      final result = parser.parse(
        'Hozzávalók:\n100 g liszt\n$ad\nElkészítés:\nKeverd össze.',
      );
      expect(result.ingredients.single.name, 'liszt');
      expect(result.unprocessedSegments, [ad]);
      expect(result.preparationText, 'Keverd össze.');
    });
  }
  for (final heading in [
    'Recept infó',
    'Receptinformáció',
    'Recipe info',
    'Információk',
  ]) {
    test('post preparation metadata $heading', () {
      final result = parser.parse(
        'Elkészítés:\n1. Keverd össze.\n2. Süsd meg.\n\n## $heading\n- Előkészítés ideje: 20 p\nSütés ideje: 10 p',
      );
      expect(result.preparationText, '1. Keverd össze.\n2. Süsd meg.');
      expect(result.unprocessedSegments, [
        '## $heading',
        '- Előkészítés ideje: 20 p',
        'Sütés ideje: 10 p',
      ]);
    });
  }
  test('notes tips and heading-like prose remain opaque', () {
    const body =
        '1. Keverd össze.\n\nMegjegyzés:\nMásnap jobb.\n\nTIPP:\nHidegen is jó.\nInformációk\nAdj hozzá 1/2 dl vizet.';
    expect(parser.parse('Elkészítés:\n$body').preparationText, body);
  });
  test('full web paste preserves ingredients steps and meaningful metadata', () {
    final result = parser.parse(webRecipe);
    expect(result.title, 'Cranachan, a skót málnás-zabos pohárkrém');
    expect(result.originalText, webRecipe);
    expect(result.ingredients.map((r) => (r.name, r.quantity, r.unit)), [
      ('zabpehely', 100.0, 'g'),
      ('whiskey (skót)', 100.0, 'ml'),
      ('vaj', 2.0, 'ek'),
      ('méz', 2.0, 'ek'),
      ('málna', 300.0, 'g'),
      ('habtejszín', 300.0, 'ml'),
      ('menta ízlés szerint', 1.0, 'db'),
    ]);
    expect(result.ingredients.take(6).every((r) => r.warnings.isEmpty), isTrue);
    expect(result.ingredients.last.warnings, [
      RecipeImportWarning.missingQuantity,
    ]);
    expect(result.preparationText, steps);
    final lines = webRecipe.split('\n');
    for (var i = 0; i < result.ingredients.length; i++) {
      final row = result.ingredients[i];
      expect(row.rawText, lines[row.sourceOrder]);
      if (i > 0) {
        expect(
          row.sourceOrder,
          greaterThan(result.ingredients[i - 1].sourceOrder),
        );
      }
    }
    // Every meaningful source line is represented, apart from section markers.
    for (final line in lines) {
      if (line.trim().isEmpty ||
          RegExp(r'^[*#\s-]+$').hasMatch(line) ||
          line == '### Hozzávalók' ||
          line == '### Elkészítés' ||
          line.startsWith('# Cranachan')) {
        continue;
      }
      expect(
        result.unprocessedSegments.contains(line) ||
            result.ingredients.any((r) => r.rawText == line) ||
            result.preparationText.contains(line),
        isTrue,
        reason: line,
      );
    }
    expect(
      result.unprocessedSegments,
      containsAll([
        '504',
        'Fehérje',
        'HIRDETÉS',
        '## Recept infó',
        '- Előkészítés ideje: 20 p',
        '- Sütés ideje: 10 p',
      ]),
    );
  });
  test('20k Markdown input retains source and 200 rows', () {
    final prefix =
        '# Recept\n### Hozzávalók\n${List.filled(200, '100 g [liszt](https://example.com/liszt)').join('\n')}\n### Elkészítés\n';
    final text = prefix + 'a' * (20000 - prefix.length);
    final result = parser.parse(text);
    expect(result.originalText.length, 20000);
    expect(result.ingredients.length, 200);
    expect(
      result.ingredients.every((r) => r.name == 'liszt' && r.quantity == 100),
      isTrue,
    );
  });
}

const steps =
    '''1. A zabpelyhet beáztatjuk a whiskey kb. kétharmadába és hagyjuk állni 2-3 órát.
2. Amikor már megszívta magát a zabpehely az alkohollal, serpenyőben átpirítjuk, majd hozzáadunk egy kevés vajat és a méz felét is. Ezzel is a zabot, majd félretesszük kihűlni.
3. A málnát meglocsoljuk a méz másik felével és hozzáöntjük a whiskey maradékát is. Krumplinyomóval alaposan összetörjük az egészet.
4. A tejszínhabot felverjük, majd hozzáforgatjuk a kihűlt zabpehely nagyjából 3/4-ét és habzsákba töltjük.
5. Végül összeállítjuk a pohárkrémeket: alulra egy adag málnapüré kerül, arra egy réteg tejszínhab, arra málna, majd megint krém. A tetejét megszórjuk a maradék zabpehellyel és málnaszemekkel valamint mentalevelekkel díszítjük.''';

const webRecipe =
    '''# Cranachan, a skót málnás-zabos pohárkrém
[Rosanics Petra](https://www.nosalty.hu/receptkonyv/202613?sajat=1)
0,0
**********
0 ÉRTÉKELÉS•[0 HOZZÁSZÓLÁS](https://www.nosalty.hu/recept/cranachan-skot-malna-zab-krem#comments)
**
**
**********
**********
**********
**********
**********
**********
Idő
30p
Költség
megfizethető
Nehézség
könnyű
[**](https://www.nosalty.hu/recept/cranachan-skot-malna-zab-krem?adag=3#ingredients)  adag [**](https://www.nosalty.hu/recept/cranachan-skot-malna-zab-krem?adag=5#ingredients)
### Hozzávalók
-
100 g [zabpehely](https://www.nosalty.hu/alapanyag/zabpehely)

-
1 dl [whiskey](https://www.nosalty.hu/alapanyag/whiskey) (skót)

-
2 ek [vaj](https://www.nosalty.hu/alapanyag/vaj)

-
2 ek [méz](https://www.nosalty.hu/alapanyag/mez)

-
300 g [málna](https://www.nosalty.hu/alapanyag/malna)

-
3 dl [habtejszín](https://www.nosalty.hu/alapanyag/habtejszin)

-
[menta](https://www.nosalty.hu/alapanyag/menta) ízlés szerint

-
-
-
-
-
-
-
504
Kalória
5.9g
Fehérje
38.4g
Szénhidrát
31g
Zsír
133.9g
Víz
98.3g
Koleszterin
7.4g
Élelmi rost
16.1g
Cukor
-
-
-
[Állítsd be itt, hogy a Google keresőben könnyebben megtaláld a Nosalty receptjeit és cikkeit!](https://google.com/preferences/source?q=nosalty.hu)
HIRDETÉS

### Elkészítés
$steps

## Recept infó
- Előkészítés ideje: 20 p
- Sütés ideje: 10 p''';
