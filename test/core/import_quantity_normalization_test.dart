import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/core/domain/services/import_unit_normalizer.dart';
import 'package:kuktam/recipes/domain/services/recipe_scaler.dart';

void main() {
  const units = ImportUnitNormalizer();
  const scaler = RecipeScaler();
  for (final c in <(double, String, double, String)>[
    (999, 'g', 999, 'g'),
    (1000, 'g', 1, 'kg'),
    (1250, 'g', 1.25, 'kg'),
    (2500, 'g', 2.5, 'kg'),
    (999, 'ml', 999, 'ml'),
    (1000, 'ml', 1, 'l'),
    (1250, 'ml', 1.25, 'l'),
    (2500, 'ml', 2.5, 'l'),
    (125, 'dkg', 1.25, 'kg'),
    (150, 'dkg', 1.5, 'kg'),
    (10, 'dl', 1, 'l'),
    (15, 'dl', 1.5, 'l'),
    (25, 'dl', 2.5, 'l'),
    (12.34, 'dl', 1.23, 'l'),
    (1.234, 'l', 1.23, 'l'),
    (1.236, 'l', 1.24, 'l'),
    (1.005, 'kg', 1.01, 'kg'),
    (2.125, 'kg', 2.13, 'kg'),
    (999.6, 'g', 1000, 'g'),
    (999.6, 'ml', 1000, 'ml'),
    (0.125, 'kg', 125, 'g'),
    (0.333, 'l', 333, 'ml'),
    (0.25, 'kg', 0.25, 'kg'),
    (0.25, 'l', 0.25, 'l'),
    (0.4, 'g', 1, 'g'),
    (0.4, 'ml', 1, 'ml'),
    (356.56, 'g', 357, 'g'),
    (176.47, 'ml', 176, 'ml'),
  ]) {
    test('import ${c.$1} ${c.$2} shares existing kitchen policy', () {
      final conversion = units.recognize(c.$2)!;
      final result = conversion.normalizeForImport(c.$1)!;
      expect(result, (quantity: c.$3, unit: c.$4));
      expect(
        result,
        scaler.normalizeForShopping(
          quantity: conversion.convert(c.$1)!,
          unit: conversion.unit,
        ),
      );
    });
  }
  test('other import units retain precision without kitchen minimums', () {
    for (final unit in [
      'db',
      'tk',
      'ek',
      'csomag',
      'üveg',
      'doboz',
      'konzerv',
    ]) {
      for (final quantity in [0.004, 1.23456789]) {
        expect(units.recognize(unit)!.normalizeForImport(quantity), (
          quantity: quantity,
          unit: unit,
        ));
      }
    }
  });
  test('invalid and overflowing conversion remains invalid', () {
    for (final quantity in [
      0.0,
      -1.0,
      double.nan,
      double.infinity,
      double.maxFinite,
    ]) {
      expect(units.recognize('dl')!.normalizeForImport(quantity), isNull);
    }
  });
}
