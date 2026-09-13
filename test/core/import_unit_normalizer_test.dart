import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/core/domain/measurement_units.dart';
import 'package:kuktam/core/domain/services/import_unit_normalizer.dart';
import 'package:kuktam/shopping/domain/shopping_units.dart';

void main() {
  const normalizer = ImportUnitNormalizer();
  test('canonical membership and dropdown orders stay unchanged', () {
    expect(MeasurementUnits.values, [
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
    ]);
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
    expect(shoppingUnits.toSet(), MeasurementUnits.values.toSet());
    expect(MeasurementUnits.values, isNot(contains('kk')));
    expect(() => MeasurementUnits.values.add('dkg'), throwsUnsupportedError);
  });
  test(
    'recognizes complete canonical tokens with case whitespace and one dot',
    () {
      for (final unit in MeasurementUnits.values) {
        final result = normalizer.recognize(' ${unit.toUpperCase()}. ')!;
        expect(
          (result.unit, result.factor, result.convert(1.234)),
          (unit, 1.0, 1.234),
        );
      }
    },
  );
  test('conversion factors and compatibility aliases', () {
    for (final entry in {
      'dkg': ('g', 10.0),
      'dl': ('ml', 100.0),
      'kk': ('tk', 1.0),
    }.entries) {
      final result = normalizer.recognize(entry.key)!;
      expect((result.unit, result.factor), entry.value);
    }
    expect(normalizer.recognize('dkg')!.convert(0.33), closeTo(3.3, 1e-14));
    expect(normalizer.recognize('dl')!.convert(1.5), 150);
    expect(normalizer.recognize('g')!.convert(1000), 1000);
    expect(normalizer.recognize('ml')!.convert(1000), 1000);
  });
  test('unknown tokens and invalid or overflowing amounts fail explicitly', () {
    for (final token in [
      'bögre',
      'pohár',
      'csipet',
      'marék',
      'literes',
      'kg..',
      'g kg',
      '',
    ]) {
      expect(normalizer.recognize(token), isNull);
    }
    for (final value in [
      0.0,
      -1.0,
      double.nan,
      double.infinity,
      double.maxFinite,
    ]) {
      expect(normalizer.recognize('dl')!.convert(value), isNull);
    }
  });
}
