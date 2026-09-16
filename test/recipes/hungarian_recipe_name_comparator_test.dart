import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/recipes/domain/services/hungarian_recipe_name_comparator.dart';

void main() {
  test('complete Hungarian alphabet including every multicharacter letter', () {
    const expected = [
      'Alma',
      'Áfonyás',
      'Barack',
      'Citrom',
      'Csirke',
      'Diós',
      'Dz...',
      'Dzs...',
      'Eper',
      'Étel',
      'Fánk',
      'Gulyás',
      'Gyümölcs',
      'Hús',
      'Ital',
      'Ízes...',
      'Joghurt',
      'Kenyér',
      'Lekvár',
      'Ly...',
      'Mák',
      'Nokedli',
      'Ny...',
      'Olíva',
      'Ó...',
      'Öntet',
      'Őszibarack',
      'Paprika',
      'Q...',
      'Rizs',
      'Saláta',
      'Sz...',
      'Torta',
      'Ty...',
      'Uborka',
      'Újhagyma',
      'Üdítő',
      'Űr...',
      'Vaj',
      'W...',
      'X...',
      'Y...',
      'Zöld',
      'Zs...',
    ];
    final actual = expected.reversed.toList()
      ..sort(compareHungarianRecipeNames);
    expect(actual, expected);
  });

  test('primary ordering ignores case and surrounding whitespace', () {
    expect(compareHungarianRecipeNames(' álma ', 'BARACK'), lessThan(0));
    expect(compareHungarianRecipeNames('eper', 'ÉTEL'), lessThan(0));
    expect(compareHungarianRecipeNames('GYÜMÖLCS', 'hús'), lessThan(0));
    expect(compareHungarianRecipeNames('ÁLMA', 'alma'), greaterThan(0));
  });

  test('vowels stay distinct and are compared inside names too', () {
    final expected = [
      'ba',
      'bá',
      'be',
      'bé',
      'bi',
      'bí',
      'bo',
      'bó',
      'bö',
      'bő',
      'bu',
      'bú',
      'bü',
      'bű',
    ];
    expect(
      expected.reversed.toList()..sort(compareHungarianRecipeNames),
      expected,
    );
    expect(compareHungarianRecipeNames('Alma', 'Álma'), isNot(0));
  });

  test('longest matching letters and prefixes', () {
    final expected = ['d', 'da', 'dz', 'dza', 'dzs', 'dzsa', 'e'];
    expect(
      expected.reversed.toList()..sort(compareHungarianRecipeNames),
      expected,
    );
    expect(compareHungarianRecipeNames('Alma', 'Almaleves'), lessThan(0));
    expect(compareHungarianRecipeNames('acukor', 'acsirke'), lessThan(0));
    expect(compareHungarianRecipeNames('asszony', 'asztal'), lessThan(0));
  });

  test('spelling breaks case/whitespace ties independently of input order', () {
    const expected = [' ALMA ', 'ALMA', 'Alma', 'alma'];
    expect(
      expected.reversed.toList()..sort(compareHungarianRecipeNames),
      expected,
    );
    expect(compareHungarianRecipeNames('Alma', 'Alma'), 0);
  });

  test(
    'empty, numeric, punctuation and Unicode fallback form a total order',
    () {
      const names = [
        '',
        ' ',
        '2 étel',
        '10 étel',
        '!Alma',
        'Alma',
        'Álma',
        '😊',
        '🍲',
        'ß',
      ];
      for (final a in names) {
        for (final b in names) {
          expect(
            compareHungarianRecipeNames(a, b).sign,
            -compareHungarianRecipeNames(b, a).sign,
          );
          for (final c in names) {
            if (compareHungarianRecipeNames(a, b) <= 0 &&
                compareHungarianRecipeNames(b, c) <= 0) {
              expect(compareHungarianRecipeNames(a, c), lessThanOrEqualTo(0));
            }
          }
        }
      }
    },
  );
}
