import '../measurement_units.dart';
import 'kitchen_quantity_normalizer.dart';

/// Keeps exact unit conversion separate from user-friendly import output.
class ImportUnitConversion {
  const ImportUnitConversion(this.unit, this.factor);
  final String unit;
  final double factor;

  double? convert(double quantity) {
    if (!quantity.isFinite || quantity <= 0) return null;
    final result = quantity * factor;
    return result.isFinite && result > 0 ? result : null;
  }

  /// Exact alias conversion first; kitchen rules only for mass and volume.
  /// Other import units retain their explicit numeric precision.
  ({double quantity, String unit})? normalizeForImport(double quantity) {
    final converted = convert(quantity);
    if (converted == null) return null;
    if (const ['g', 'kg', 'ml', 'l'].contains(unit)) {
      final display = const KitchenQuantityNormalizer().normalizeForDisplay(
        quantity: converted,
        unit: unit,
      );
      return (
        quantity: KitchenQuantityNormalizer.roundQuantity(
          display.quantity,
          display.unit,
        ),
        unit: display.unit,
      );
    }
    return (quantity: converted, unit: unit);
  }
}

class ImportUnitNormalizer {
  const ImportUnitNormalizer();
  static const _aliases = {
    'darab': MeasurementUnits.db,
    'gr': MeasurementUnits.g,
    'kiló': MeasurementUnits.kg,
    'kilo': MeasurementUnits.kg,
    'liter': MeasurementUnits.l,
    'teáskanál': MeasurementUnits.tk,
    'evőkanál': MeasurementUnits.ek,
    'csom': MeasurementUnits.csomag,
    'kk': MeasurementUnits.tk,
  };

  ImportUnitConversion? recognize(String input) {
    var token = input.trim().toLowerCase();
    if (token.endsWith('.')) token = token.substring(0, token.length - 1);
    if (token == 'dkg') {
      return const ImportUnitConversion(MeasurementUnits.g, 10);
    }
    if (token == 'dl') {
      return const ImportUnitConversion(MeasurementUnits.ml, 100);
    }
    final unit = MeasurementUnits.values.contains(token)
        ? token
        : _aliases[token];
    return unit == null ? null : ImportUnitConversion(unit, 1);
  }
}
