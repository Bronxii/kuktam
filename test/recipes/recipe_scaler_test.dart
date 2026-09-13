import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/recipes/domain/models/recipe.dart';
import 'package:kuktam/recipes/domain/services/recipe_scaler.dart';

void main() {
  const scaler = RecipeScaler();
  const original = [
    RecipeIngredient(name: 'Vaj', quantity: 200, unit: 'g'),
    RecipeIngredient(name: 'Liszt', quantity: 500, unit: 'g'),
    RecipeIngredient(name: 'Tej', quantity: 300, unit: 'ml'),
    RecipeIngredient(name: 'Tojás', quantity: 2, unit: 'db'),
  ];

  group('Scaling from original ingredients', () {
    test('200 to 250 scales every ingredient without rounding eggs', () {
      final result = scaler.scale(
        originalIngredients: original,
        basisIndex: 0,
        targetQuantity: 250,
      );
      expect(result.map((item) => item.quantity), [250, 625, 375, 2.5]);
      expect(
        result.map((item) => item.name),
        original.map((item) => item.name),
      );
      expect(result.map((item) => item.unit), ['g', 'g', 'ml', 'db']);
    });

    test('second call uses original 300 ml, not previously scaled 375 ml', () {
      final first = scaler.scale(
        originalIngredients: original,
        basisIndex: 0,
        targetQuantity: 250,
      );
      final second = scaler.scale(
        originalIngredients: original,
        basisIndex: 2,
        targetQuantity: 450,
      );
      expect(second.map((item) => item.quantity), [300, 750, 450, 3]);
      expect(first.map((item) => item.quantity), [250, 625, 375, 2.5]);
      expect(original.map((item) => item.quantity), [200, 500, 300, 2]);
    });

    test('fractional piece target is preserved exactly', () {
      final result = scaler.scale(
        originalIngredients: original,
        basisIndex: 3,
        targetQuantity: 2.5,
      );
      expect(result.map((item) => item.quantity), [250, 625, 375, 2.5]);
    });

    test('does not mutate a mutable input list or its objects', () {
      final input = [...original];
      final before = input.map((item) => item.toMap()).toList();
      final result = scaler.scale(
        originalIngredients: input,
        basisIndex: 0,
        targetQuantity: 250,
      );
      expect(input.map((item) => item.toMap()).toList(), before);
      for (var i = 0; i < input.length; i++) {
        expect(identical(input[i], original[i]), isTrue);
        expect(identical(result[i], input[i]), isFalse);
      }
      expect(() => result.clear(), throwsUnsupportedError);
    });

    test('duplicate names are distinguished by index', () {
      const items = [
        RecipeIngredient(name: 'Liszt', quantity: 100, unit: 'g'),
        RecipeIngredient(name: 'Liszt', quantity: 300, unit: 'g'),
      ];
      final result = scaler.scale(
        originalIngredients: items,
        basisIndex: 1,
        targetQuantity: 450,
      );
      expect(result.map((item) => item.quantity), [150, 450]);
    });

    test('retains actual extra precision in the calculation', () {
      const target = 2.5000000001;
      final result = scaler.scale(
        originalIngredients: original,
        basisIndex: 3,
        targetQuantity: target,
      );
      expect(result[3].quantity, target);
      expect(result[0].quantity, 200 * (target / 2));
    });
  });

  group('Validation', () {
    for (final invalid in [
      0.0,
      -1.0,
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      test('rejects target $invalid', () {
        expect(
          () => scaler.scale(
            originalIngredients: original,
            basisIndex: 0,
            targetQuantity: invalid,
          ),
          throwsArgumentError,
        );
      });
      test('rejects original basis $invalid', () {
        expect(
          () => scaler.scale(
            originalIngredients: [
              RecipeIngredient(name: 'Vaj', quantity: invalid, unit: 'g'),
            ],
            basisIndex: 0,
            targetQuantity: 1,
          ),
          throwsArgumentError,
        );
      });
      test('rejects invalid non-basis quantity $invalid', () {
        expect(
          () => scaler.scale(
            originalIngredients: [
              original[0],
              RecipeIngredient(name: 'X', quantity: invalid, unit: 'g'),
            ],
            basisIndex: 0,
            targetQuantity: 250,
          ),
          throwsArgumentError,
        );
      });
      test('display helpers reject $invalid', () {
        expect(() => scaler.formatQuantity(invalid), throwsArgumentError);
        expect(
          () => scaler.normalizeForDisplay(quantity: invalid, unit: 'g'),
          throwsArgumentError,
        );
      });
    }
    for (final index in [-1, 4]) {
      test('rejects out-of-range index $index', () {
        expect(
          () => scaler.scale(
            originalIngredients: original,
            basisIndex: index,
            targetQuantity: 1,
          ),
          throwsRangeError,
        );
      });
    }
    test('rejects empty original list', () {
      expect(
        () => scaler.scale(
          originalIngredients: [],
          basisIndex: 0,
          targetQuantity: 1,
        ),
        throwsRangeError,
      );
    });
    test('rejects infinite factor', () {
      expect(
        () => scaler.scale(
          originalIngredients: [
            RecipeIngredient(
              name: 'X',
              quantity: double.minPositive,
              unit: 'g',
            ),
          ],
          basisIndex: 0,
          targetQuantity: double.maxFinite,
        ),
        throwsArgumentError,
      );
    });
    test('rejects infinite result', () {
      expect(
        () => scaler.scale(
          originalIngredients: [
            original[3],
            RecipeIngredient(name: 'X', quantity: double.maxFinite, unit: 'g'),
          ],
          basisIndex: 0,
          targetQuantity: 4,
        ),
        throwsArgumentError,
      );
    });
    test('rejects result underflow to zero', () {
      expect(
        () => scaler.scale(
          originalIngredients: [
            original[3],
            RecipeIngredient(
              name: 'X',
              quantity: double.minPositive,
              unit: 'g',
            ),
          ],
          basisIndex: 0,
          targetQuantity: 0.5,
        ),
        throwsArgumentError,
      );
    });
  });

  group('Explicit unit conversion', () {
    for (final c in <(double, String, String, double)>[
      (1.5, 'kg', 'g', 1500),
      (1250, 'g', 'kg', 1.25),
      (150, 'g', 'kg', 0.15),
      (0.125, 'kg', 'g', 125),
      (1.25, 'l', 'ml', 1250),
      (750, 'ml', 'l', 0.75),
    ]) {
      test('${c.$1} ${c.$2} to ${c.$3}', () {
        expect(
          scaler.convertQuantity(quantity: c.$1, fromUnit: c.$2, toUnit: c.$3),
          c.$4,
        );
      });
    }
    for (final unit in [
      'g',
      'kg',
      'ml',
      'l',
      'db',
      'tk',
      'ek',
      'csomag',
      'üveg',
      'doboz',
      'konzerv',
    ]) {
      test('identical $unit preserves quantity exactly', () {
        const quantity = 2.5000000001;
        expect(
          scaler.convertQuantity(
            quantity: quantity,
            fromUnit: unit,
            toUnit: unit,
          ),
          quantity,
        );
      });
    }
    for (final pair in [
      ('g', 'ml'),
      ('kg', 'db'),
      ('l', 'csomag'),
      ('db', 'g'),
      ('KG', 'g'),
    ]) {
      test('rejects incompatible ${pair.$1} to ${pair.$2}', () {
        expect(
          () => scaler.convertQuantity(
            quantity: 1,
            fromUnit: pair.$1,
            toUnit: pair.$2,
          ),
          throwsArgumentError,
        );
      });
    }
    for (final invalid in [
      0.0,
      -1.0,
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      test('rejects invalid conversion input $invalid', () {
        for (final target in ['g', 'kg']) {
          expect(
            () => scaler.convertQuantity(
              quantity: invalid,
              fromUnit: 'kg',
              toUnit: target,
            ),
            throwsArgumentError,
          );
        }
      });
    }
    test('rejects conversion overflow and underflow to zero', () {
      expect(
        () => scaler.convertQuantity(
          quantity: double.maxFinite,
          fromUnit: 'kg',
          toUnit: 'g',
        ),
        throwsArgumentError,
      );
      expect(
        () => scaler.convertQuantity(
          quantity: double.minPositive,
          fromUnit: 'ml',
          toUnit: 'l',
        ),
        throwsArgumentError,
      );
    });
    test(
      'machine noise stays within floating-point precision in both directions',
      () {
        final quantity = 0.1 + 0.2;
        for (final pair in [('kg', 'g'), ('l', 'ml')]) {
          final smaller = scaler.convertQuantity(
            quantity: quantity,
            fromUnit: pair.$1,
            toUnit: pair.$2,
          );
          expect(smaller, closeTo(300, 300 * 1e-15));
          final restored = scaler.convertQuantity(
            quantity: smaller,
            fromUnit: pair.$2,
            toUnit: pair.$1,
          );
          expect(restored, closeTo(quantity, quantity * 1e-15));
          expect(scaler.formatQuantity(smaller), '300');
        }
      },
    );
    test('does not introduce business rounding', () {
      const quantity = 2.5000000001;
      expect(
        scaler.convertQuantity(quantity: quantity, fromUnit: 'kg', toUnit: 'g'),
        quantity * 1000,
      );
      expect(
        scaler.convertQuantity(quantity: 1325, fromUnit: 'g', toUnit: 'kg'),
        1.325,
      );
    });
    test('display edit converts back to original grams before scaling', () {
      const input = [
        RecipeIngredient(name: 'Liszt', quantity: 1250, unit: 'g'),
        RecipeIngredient(name: 'Vaj', quantity: 200, unit: 'g'),
      ];
      final display = scaler.normalizeForDisplay(
        quantity: input[0].quantity,
        unit: input[0].unit,
      );
      final target = scaler.convertQuantity(
        quantity: 1.5,
        fromUnit: display.unit,
        toUnit: input[0].unit,
      );
      final result = scaler.scale(
        originalIngredients: input,
        basisIndex: 0,
        targetQuantity: target,
      );
      expect(result.map((item) => item.quantity), [1500, 240]);
    });
    test('display edit converts back to original kilograms before scaling', () {
      const input = [
        RecipeIngredient(name: 'Vaj', quantity: 0.125, unit: 'kg'),
      ];
      final display = scaler.normalizeForDisplay(
        quantity: input[0].quantity,
        unit: input[0].unit,
      );
      final target = scaler.convertQuantity(
        quantity: 150,
        fromUnit: display.unit,
        toUnit: input[0].unit,
      );
      final result = scaler.scale(
        originalIngredients: input,
        basisIndex: 0,
        targetQuantity: target,
      );
      expect(result.single.quantity, 0.15);
      expect(result.single.unit, 'kg');
    });
  });

  group('Parsing', () {
    for (final entry in {
      '2': 2.0,
      '1,5': 1.5,
      '1.5': 1.5,
      ' 1,5 ': 1.5,
      '0,125': 0.125,
      '0.125': 0.125,
    }.entries) {
      test(
        'accepts ${entry.key}',
        () => expect(scaler.parseQuantity(entry.key), entry.value),
      );
    }
    for (final input in [
      '',
      ' ',
      '-1',
      '0',
      '0,0',
      'NaN',
      'infinity',
      'Infinity',
      '1,2.3',
      '1,',
      '.',
      '1 000',
      '2g',
      '1e3',
    ]) {
      test(
        'rejects "$input"',
        () => expect(scaler.parseQuantity(input), isNull),
      );
    }
    test('rejects overflow and underflow text', () {
      expect(scaler.parseQuantity('1${'0' * 400}'), isNull);
      expect(scaler.parseQuantity('0.${'0' * 400}1'), isNull);
    });
  });

  group('Display units', () {
    final cases = <(double, String, double, String, String)>[
      (0.125, 'kg', 125, 'g', '125'),
      (0.333, 'kg', 333, 'g', '333'),
      (0.25, 'kg', 0.25, 'kg', '0,25'),
      (0.125, 'l', 125, 'ml', '125'),
      (0.333, 'l', 333, 'ml', '333'),
      (0.33, 'l', 0.33, 'l', '0,33'),
      (0.5, 'l', 0.5, 'l', '0,5'),
      (1000, 'g', 1, 'kg', '1'),
      (1250, 'g', 1.25, 'kg', '1,25'),
      (1500, 'g', 1.5, 'kg', '1,5'),
      (1010, 'g', 1.01, 'kg', '1,01'),
      (1325, 'g', 1.325, 'kg', '1,33'),
      (2125, 'g', 2.125, 'kg', '2,13'),
      (2500, 'g', 2.5, 'kg', '2,5'),
      (2.125, 'kg', 2.125, 'kg', '2,13'),
      (1000, 'ml', 1, 'l', '1'),
      (1250, 'ml', 1.25, 'l', '1,25'),
      (1325, 'ml', 1.325, 'l', '1,33'),
      (2125, 'ml', 2.125, 'l', '2,13'),
      (2.125, 'l', 2.125, 'l', '2,13'),
      (4.411764705, 'db', 4.411764705, 'db', '4,5'),
      (1.176470588, 'tk', 1.176470588, 'tk', '1,25'),
      (2.5, 'db', 2.5, 'db', '2,5'),
      (3, 'db', 3, 'db', '3'),
      (999, 'g', 999, 'g', '999'),
    ];
    for (final c in cases) {
      test('${c.$1} ${c.$2} becomes ${c.$5} ${c.$4}', () {
        final result = scaler.normalizeForDisplay(quantity: c.$1, unit: c.$2);
        expect(result.quantity, c.$3);
        expect(result.unit, c.$4);
        expect(scaler.formatQuantity(result.quantity, unit: result.unit), c.$5);
      });
    }
    for (final unit in [
      'db',
      'tk',
      'ek',
      'csomag',
      'üveg',
      'doboz',
      'konzerv',
      'unknown',
    ]) {
      test('preserves $unit and quantity', () {
        for (final quantity in [2.5, 0.125, 1250.0]) {
          final result = scaler.normalizeForDisplay(
            quantity: quantity,
            unit: unit,
          );
          expect(result, (quantity: quantity, unit: unit));
        }
      });
    }
    test('machine noise does not trigger unnecessary downward conversion', () {
      final quantity = 0.1 + 0.2;
      final result = scaler.normalizeForDisplay(quantity: quantity, unit: 'kg');
      expect(result, (quantity: quantity, unit: 'kg'));
      expect(scaler.formatQuantity(result.quantity), '0,3');
    });
    test('machine noise does not prevent upward conversion', () {
      final result = scaler.normalizeForDisplay(
        quantity: 1250.0000000000002,
        unit: 'g',
      );
      expect(result.unit, 'kg');
      expect(scaler.formatQuantity(result.quantity), '1,25');
    });
    test('real extra decimal precision is not treated as noise', () {
      final result = scaler.normalizeForDisplay(
        quantity: 0.2500000001,
        unit: 'kg',
      );
      expect(result.unit, 'g');
      expect(result.quantity, 0.2500000001 * 1000);
      expect(
        scaler.normalizeForDisplay(quantity: 1250.0000001, unit: 'g').unit,
        'kg',
      );
    });
    test('very small quantities are not treated as zero hundredths', () {
      final result = scaler.normalizeForDisplay(quantity: 1e-12, unit: 'kg');
      expect(result.unit, 'g');
      expect(result.quantity, 1e-12 * 1000);
    });
    test('large finite quantities remain finite', () {
      expect(
        scaler
            .normalizeForDisplay(quantity: double.maxFinite, unit: 'kg')
            .quantity,
        double.maxFinite,
      );
    });
  });

  group('Formatting', () {
    for (final c in <(double, String, double, String, String)>[
      (356.56, 'g', 357, 'g', '357'),
      (0.4, 'g', 1, 'g', '1'),
      (356.56, 'ml', 357, 'ml', '357'),
      (0.4, 'ml', 1, 'ml', '1'),
      (8.82, 'db', 9, 'db', '9'),
      (4.41, 'db', 4.5, 'db', '4,5'),
      (0.1, 'db', 0.5, 'db', '0,5'),
      (0.88, 'tk', 1, 'tk', '1'),
      (0.08, 'tk', 0.25, 'tk', '0,25'),
      (1.18, 'ek', 1.25, 'ek', '1,25'),
      (0.08, 'ek', 0.25, 'ek', '0,25'),
      (1.67, 'doboz', 1.7, 'doboz', '1,7'),
      for (final unit in ['csomag', 'üveg', 'doboz', 'konzerv'])
        (0.04, unit, 0.1, unit, '0,1'),
      (2125, 'g', 2.13, 'kg', '2,13'),
      (1325, 'ml', 1.33, 'l', '1,33'),
      (0.125, 'kg', 125, 'g', '125'),
      (0.125, 'l', 125, 'ml', '125'),
      (999.6, 'g', 1000, 'g', '1000'),
    ]) {
      test('numeric shopping and display agree for ${c.$1} ${c.$2}', () {
        final shopping = scaler.normalizeForShopping(
          quantity: c.$1,
          unit: c.$2,
        );
        expect(shopping, (quantity: c.$3, unit: c.$4));
        final display = scaler.normalizeForDisplay(quantity: c.$1, unit: c.$2);
        expect(
          scaler.formatQuantity(display.quantity, unit: display.unit),
          c.$5,
        );
      });
    }
    for (final invalid in [0.0, -1.0, double.nan, double.infinity]) {
      test('minimum never makes $invalid valid', () {
        expect(
          () => scaler.normalizeForShopping(quantity: invalid, unit: 'db'),
          throwsArgumentError,
        );
        expect(
          () => scaler.formatQuantity(invalid, unit: 'db'),
          throwsArgumentError,
        );
      });
    }
    for (final c in <(double, String)>[
      (356.56, '357'),
      (176.47, '176'),
      (282.35, '282'),
      (70.59, '71'),
      (235.29, '235'),
      (999.4, '999'),
      (999.6, '1000'),
      (12.5, '13'),
    ]) {
      test('${c.$1} grams rounds only the text to ${c.$2}', () {
        final display = scaler.normalizeForDisplay(quantity: c.$1, unit: 'g');
        expect(display.unit, 'g');
        expect(display.quantity, c.$1);
        expect(
          scaler.formatQuantity(display.quantity, unit: display.unit),
          c.$2,
        );
      });
    }
    for (final unit in ['kg', 'l']) {
      test('$unit retains two-decimal formatting', () {
        expect(scaler.formatQuantity(4.411764, unit: unit), '4,41');
        expect(scaler.formatQuantity(1.176470, unit: unit), '1,18');
        expect(scaler.formatQuantity(2.5, unit: unit), '2,5');
      });
    }
    final kitchenCases = <String, List<(double, String)>>{
      'ml': [
        (176.47, '176'),
        (282.35, '282'),
        (356.56, '357'),
        (70.59, '71'),
        (999.6, '1000'),
      ],
      'db': [
        (8.82, '9'),
        (4.41, '4,5'),
        (4.24, '4'),
        (2.5, '2,5'),
        (2.74, '2,5'),
        (2.76, '3'),
        (2.25, '2,5'),
      ],
      for (final unit in ['tk', 'ek'])
        unit: [
          (0.88, '1'),
          (1.18, '1,25'),
          (1.62, '1,5'),
          (1.87, '1,75'),
          (1.88, '2'),
          (1.125, '1,25'),
        ],
      for (final unit in ['csomag', 'üveg', 'doboz', 'konzerv'])
        unit: [
          (1.67, '1,7'),
          (1.64, '1,6'),
          (2.34, '2,3'),
          (2.36, '2,4'),
          (0.84, '0,8'),
          (0.86, '0,9'),
          (2, '2'),
          (1.65, '1,7'),
        ],
    };
    for (final entry in kitchenCases.entries) {
      for (final c in entry.value) {
        test(
          '${c.$1} ${entry.key} displays ${c.$2} without numeric rounding',
          () {
            final display = scaler.normalizeForDisplay(
              quantity: c.$1,
              unit: entry.key,
            );
            expect(display.unit, entry.key);
            expect(display.quantity, c.$1);
            expect(
              scaler.formatQuantity(display.quantity, unit: display.unit),
              c.$2,
            );
          },
        );
      }
    }
    for (final entry in <double, String>{
      1.0: '1',
      1.5: '1,5',
      1.25: '1,25',
      2.5: '2,5',
      0.125: '0,13',
      1.23456789: '1,23',
      2.5000000001: '2,5',
      1e-9: '0',
      1.176470588: '1,18',
      4.411764705: '4,41',
      176.470588: '176,47',
      282.352941: '282,35',
      1.005: '1,01',
      1e21: '1000000000000000000000',
    }.entries) {
      test('${entry.key} becomes ${entry.value}', () {
        expect(scaler.formatQuantity(entry.key), entry.value);
      });
    }
    test('machine-scale noise does not appear in rounded display', () {
      expect(scaler.formatQuantity(0.1 + 0.2), '0,3');
      expect(scaler.formatQuantity(2.5000000000000004), '2,5');
    });
    test('extreme values obey display precision without changing input', () {
      for (final quantity in [double.minPositive, double.maxFinite]) {
        final text = scaler.formatQuantity(quantity);
        expect(text.contains('e'), isFalse);
        expect(
          text,
          quantity == double.minPositive
              ? '0'
              : scaler.formatQuantity(double.maxFinite),
        );
        if (quantity == double.maxFinite) {
          expect(scaler.parseQuantity(text), quantity);
        }
      }
    });
  });

  test('display rounding preserves full precision scaling results', () {
    final result = scaler.scale(
      originalIngredients: original,
      basisIndex: 0,
      targetQuantity: 200 * (20 / 17),
    );
    final before = result.map((item) => item.quantity).toList();
    for (final item in result) {
      final display = scaler.normalizeForDisplay(
        quantity: item.quantity,
        unit: item.unit,
      );
      scaler.formatQuantity(display.quantity, unit: display.unit);
    }
    expect(scaler.formatQuantity(result.first.quantity, unit: 'g'), '235');
    expect(result.map((item) => item.quantity), before);
    expect(result.first.quantity, 200 * (20 / 17));
    expect(result.first.quantity, isNot(235));
    final next = scaler.scale(
      originalIngredients: original,
      basisIndex: 2,
      targetQuantity: 450,
    );
    expect(next.map((item) => item.quantity), [300, 750, 450, 3]);
  });
}
