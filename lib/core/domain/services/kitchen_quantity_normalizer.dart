/// Shared kitchen display rules. Unit selection always precedes rounding.
class KitchenQuantityNormalizer {
  const KitchenQuantityNormalizer();
  static const double _displayTolerance = 4 * 2.220446049250313e-16;

  /// Selects display units without rounding the returned numeric quantity.
  /// Other units are preserved verbatim. Keep the returned unit together with
  /// its quantity when interpreting later user input.
  ({double quantity, String unit}) normalizeForDisplay({
    required double quantity,
    required String unit,
  }) {
    _requireQuantity(quantity, 'quantity');
    if (unit == 'kg' || unit == 'l') {
      if (quantity < 1 && !_fitsTwoDecimals(quantity)) {
        return (
          quantity: _requireQuantity(quantity * 1000, 'convertedQuantity'),
          unit: unit == 'kg' ? 'g' : 'ml',
        );
      }
    } else if ((unit == 'g' || unit == 'ml') && quantity >= 1000) {
      return (quantity: quantity / 1000, unit: unit == 'g' ? 'kg' : 'l');
    }
    return (quantity: quantity, unit: unit);
  }

  static double roundQuantity(double quantity, String? unit) {
    _requireQuantity(quantity, 'quantity');
    // Large doubles already have integral spacing; do not multiply them.
    if (quantity >= 1e21) return quantity;
    final stepsPerUnit = switch (unit) {
      'g' || 'ml' => 1,
      'db' => 2,
      'tk' || 'ek' => 4,
      'csomag' || 'üveg' || 'doboz' || 'konzerv' => 10,
      _ => 100,
    };
    final steps = quantity * stepsPerUnit;
    final midpoint = steps.floorToDouble() + 0.5;
    // Decimal halfway values (e.g. 1.005) may lie just below the midpoint
    // in binary. Correct only machine-scale noise before display rounding.
    final rounded =
        (_closeForDisplay(steps, midpoint) ? midpoint : steps).roundToDouble() /
        stepsPerUnit;
    if (rounded == 0 && stepsPerUnit != 100) return 1 / stepsPerUnit;
    return rounded;
  }

  static double _requireQuantity(double value, String name) {
    if (!value.isFinite || value <= 0) {
      throw ArgumentError.value(value, name, 'Must be positive and finite.');
    }
    return value;
  }

  static bool _closeForDisplay(double value, double candidate) =>
      value == candidate ||
      (value - candidate).abs() <= value.abs() * _displayTolerance;

  static bool _fitsTwoDecimals(double value) {
    // Large doubles already have integral spacing; avoid overflowing value*100.
    if (value == value.truncateToDouble()) return true;
    final hundredths = value * 100;
    if (!hundredths.isFinite) return false;
    final candidate = hundredths.roundToDouble() / 100;
    return candidate > 0 && _closeForDisplay(value, candidate);
  }
}
