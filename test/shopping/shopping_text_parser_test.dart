import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/shopping/domain/models/shopping_import_draft.dart';
import 'package:kuktam/shopping/domain/services/shopping_text_parser.dart';
import 'package:kuktam/shopping/domain/shopping_units.dart';

void main() {
  const parser = ShoppingTextParser();
  for (final c in <(String, String, double, String)>[
    ('25 dkg vaj', 'vaj', 250, 'g'),
    ('vaj 25 dkg', 'vaj', 250, 'g'),
    ('25dkg vaj', 'vaj', 250, 'g'),
    ('vaj 25dkg', 'vaj', 250, 'g'),
    ('2 dl tej', 'tej', 200, 'ml'),
    ('tej 2 dl', 'tej', 200, 'ml'),
    ('2dl tej', 'tej', 200, 'ml'),
    ('tej 2dl', 'tej', 200, 'ml'),
    ('1,5 dl tejszín', 'tejszín', 150, 'ml'),
    ('0,25 dl rum', 'rum', 25, 'ml'),
    ('5 dkg sajt', 'sajt', 50, 'g'),
    ('1,5 dkg élesztő', 'élesztő', 15, 'g'),
    ('0,33 dkg vaj', 'vaj', 3, 'g'),
    ('1 kk cukor', 'cukor', 1, 'tk'),
    ('1/2 kg hús', 'hús', 0.5, 'kg'),
    ('½kg hús', 'hús', 0.5, 'kg'),
    ('dkg vaj', 'vaj', 10, 'g'),
    ('1000 g liszt', 'liszt', 1, 'kg'),
    ('1250 g liszt', 'liszt', 1.25, 'kg'),
    ('1500 ml tej', 'tej', 1.5, 'l'),
    ('125 dkg vaj', 'vaj', 1.25, 'kg'),
    ('tej 15dl', 'tej', 1.5, 'l'),
    ('12,34 dl tej', 'tej', 1.23, 'l'),
  ]) {
    test('canonical import quantity and editable text: ${c.$1}', () {
      final item = parser.parse(c.$1).single;
      expect(item.name, c.$2);
      expect(item.quantity, closeTo(c.$3, 1e-12));
      expect(item.unit, c.$4);
      expect(item.issue, isNull);
      expect(item.rawSegment, c.$1);
      expect(
        double.parse(item.quantityText.replaceAll(',', '.')),
        closeTo(c.$3, 1e-12),
      );
    });
  }
  test('invalid converted quantities preserve raw draft without fallback', () {
    for (final text in [
      '0 dkg vaj',
      '-1 dl tej',
      '1/0 dl tej',
      '${'9' * 309} dkg vaj',
    ]) {
      final item = parser.parse(text).single;
      expect(item.quantity, isNull);
      expect(item.issue, ShoppingImportIssue.invalidQuantity);
      expect(item.rawSegment, text);
    }
  });
  for (final c in <(String, String, double, String)>[
    ('3 db alma', 'alma', 3, 'db'),
    ('500g csirkemell', 'csirkemell', 500, 'g'),
    ('1,5 kg burgonya', 'burgonya', 1.5, 'kg'),
    ('1.5 kg burgonya', 'burgonya', 1.5, 'kg'),
    ('alma 3 db', 'alma', 3, 'db'),
    ('tej 2 l', 'tej', 2, 'l'),
    ('tej 1', 'tej', 1, 'db'),
    ('burgonya 2', 'burgonya', 2, 'db'),
    ('3 alma', 'alma', 3, 'db'),
    ('kenyér', 'kenyér', 1, 'db'),
    ('kg alma', 'alma', 1, 'kg'),
    ('alma kg', 'alma', 1, 'kg'),
    ('1 csomag pelenka', 'pelenka', 1, 'csomag'),
    ('2 üveg paradicsomszósz', 'paradicsomszósz', 2, 'üveg'),
    ('1 karton tej', 'karton tej', 1, 'db'),
    ('B12 vitamin', 'B12 vitamin', 1, 'db'),
    ('literes tej', 'literes tej', 1, 'db'),
    ('csomag pelenka', 'pelenka', 1, 'csomag'),
    ('3 db Piros Alma', 'Piros Alma', 3, 'db'),
  ]) {
    test('recognizes ${c.$1}', () {
      final item = parser.parse(c.$1).single;
      expect((item.name, item.quantity, item.unit), (c.$2, c.$3, c.$4));
      expect(item.hasError, false);
      expect(item.rawSegment, c.$1);
    });
  }
  test('mixed separators preserve decimal commas and order', () {
    final items = parser.parse(
      '3 db alma, 1 csomag pelenka;1,5 kg alma, 2 l tej\nkenyér\r\nburgonya 2',
    );
    expect(items.map((d) => d.name), [
      'alma',
      'pelenka',
      'alma',
      'tej',
      'kenyér',
      'burgonya',
    ]);
    expect(items.map((d) => d.quantity), [3, 1, 1.5, 2, 1, 2]);
    expect(items.map((d) => d.sourceIndex), [0, 1, 2, 3, 4, 5]);
  });
  test('bullets and numbering allow default', () {
    for (final prefix in [
      '• ',
      '- ',
      '* ',
      '– ',
      '1. ',
      '24. ',
      '26. ',
      '1) ',
    ]) {
      final item = parser.parse('${prefix}kenyér').single;
      expect((item.name, item.quantity, item.unit), ('kenyér', 1, 'db'));
      expect(item.quantityWasMissing, true);
    }
  });
  test('empty punctuation and bare numbering have no drafts', () {
    expect(parser.parse(' \n,; -\n•\n*\n–\n1.\n1)\n...'), isEmpty);
  });
  test('explicit invalid quantity never becomes fallback', () {
    for (final text in [
      '-1 alma',
      '0 kg alma',
      '1,2.3 kg alma',
      'alma 0 kg',
      'NaN kg alma',
      'Infinity alma',
    ]) {
      final item = parser.parse(text).single;
      expect(item.quantity, isNull);
      expect(item.quantityWasMissing, false);
      expect(item.issue, ShoppingImportIssue.invalidQuantity);
      expect(item.rawSegment, text);
      expect(item.quantityText, isNotEmpty);
      expect(item.name, 'alma');
    }
  });
  test('ambiguous input does not choose a quantity', () {
    for (final text in [
      'tej 1 2',
      '2 db alma 3 kg',
      'alma 2 piros',
      'kg alma l',
    ]) {
      final item = parser.parse(text).single;
      expect(item.issue, ShoppingImportIssue.ambiguous);
      expect(item.quantity, isNull);
      expect(item.rawSegment, text);
      expect(item.name, text);
    }
  });
  test('approved aliases case and one trailing dot', () {
    const aliases = {
      'darab': 'db',
      'gr': 'g',
      'kiló': 'kg',
      'kilo': 'kg',
      'liter': 'l',
      'teáskanál': 'tk',
      'evőkanál': 'ek',
      'csom': 'csomag',
    };
    for (final unit in shoppingUnits) {
      expect(parser.recognizeUnit('${unit.toUpperCase()}.'), unit);
    }
    for (final entry in aliases.entries) {
      final item = parser.parse('2 ${entry.key.toUpperCase()}. Termék').single;
      expect((item.quantity, item.unit, item.name), (2, entry.value, 'Termék'));
    }
  });
  test('unit prefixes and unapproved spellings stay in name', () {
    for (final token in ['literes', 'dobozos', 'uveg', 'kg..', 'karton']) {
      expect(parser.recognizeUnit(token), isNull);
      final item = parser.parse('1 $token tej').single;
      expect((item.name, item.unit), ('$token tej', 'db'));
    }
  });
  test('raw whitespace preserved and name casing unchanged', () {
    const raw = '  3 DB. Piros   Alma  ';
    final item = parser.parse(raw).single;
    expect(item.rawSegment, raw);
    expect(item.name, 'Piros Alma');
  });
  test('mass/volume rounded while other explicit quantities stay exact', () {
    for (final c in [
      ('1,234 l tej', 1.23),
      ('2,5 db tojás', 2.5),
      ('0,04 csomag tea', 0.04),
    ]) {
      expect(parser.parse(c.$1).single.quantity, c.$2);
    }
  });
  test('plain decimal validation and finite check', () {
    for (final text in ['1', '2', '500', '1,5', '1.5', '0,5', '0.5', ' 1,5 ']) {
      expect(parser.parseQuantity(text), isNotNull);
    }
    for (final text in [
      '',
      '0',
      '-1',
      'NaN',
      'Infinity',
      '1,2.3',
      '1e3',
      '1${'0' * 400}',
      '0.${'0' * 400}1',
    ]) {
      expect(parser.parseQuantity(text), isNull);
    }
  });
  test('missing name is repairable', () {
    final item = parser.parse('3 db').single;
    expect(item.issue, ShoppingImportIssue.missingName);
    expect(item.quantity, 3);
  });
  test('canonical unit order immutable', () {
    expect(shoppingUnits, [
      'g',
      'kg',
      'ml',
      'l',
      'db',
      'ek',
      'tk',
      'csomag',
      'üveg',
      'doboz',
      'konzerv',
    ]);
    expect(() => shoppingUnits.add('karton'), throwsUnsupportedError);
  });
  test('character boundary and overflow', () {
    expect(parser.parse('a' * 20000), hasLength(1));
    expect(
      () => parser.parse('a' * 20001),
      throwsA(
        isA<ShoppingTextLimitException>().having(
          (e) => e.limit,
          'limit',
          ShoppingTextLimit.characters,
        ),
      ),
    );
  });
  test('item boundary rejects instead of truncating', () {
    expect(parser.parse(List.filled(200, 'alma').join('\n')), hasLength(200));
    expect(
      () => parser.parse(List.filled(201, 'alma').join('\n')),
      throwsA(
        isA<ShoppingTextLimitException>().having(
          (e) => e.limit,
          'limit',
          ShoppingTextLimit.items,
        ),
      ),
    );
  });
  test('source positions and immutable output', () {
    final items = parser.parse('\nalma;;tej');
    expect(items.map((i) => i.sourceIndex), [1, 3]);
    expect(() => items.clear(), throwsUnsupportedError);
  });
}
