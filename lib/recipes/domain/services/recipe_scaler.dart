import '../models/recipe.dart';

/// Pure operations for temporary recipe scaling. No persistence or UI state.
class RecipeScaler {
  const RecipeScaler();

  // Four double machine epsilons, relative to the quantity (no absolute floor).
  // Only for display decisions, never to round calculated quantities.
  static const double _displayTolerance = 4 * 2.220446049250313e-16;

  /// Always pass the original snapshot, not the result of an earlier call.
  /// targetQuantity is expressed in the original basis ingredient's unit.
  /// Convert edited display quantities back to that unit before calling scale.
  /// Invalid indices throw RangeError; invalid quantities, overflow and
  /// underflow to zero throw ArgumentError. All quantities must be positive.
  List<RecipeIngredient> scale({
    required List<RecipeIngredient> originalIngredients,
    required int basisIndex,
    required double targetQuantity,
  }) {
    RangeError.checkValidIndex(basisIndex, originalIngredients, 'basisIndex');
    _requireQuantity(targetQuantity, 'targetQuantity');
    for (var i = 0; i < originalIngredients.length; i++) {
      _requireQuantity(originalIngredients[i].quantity, 'originalQuantity[$i]');
    }
    final factor = targetQuantity / originalIngredients[basisIndex].quantity;
    _requireQuantity(factor, 'scaleFactor');
    return List<RecipeIngredient>.unmodifiable([
      for (var i = 0; i < originalIngredients.length; i++)
        RecipeIngredient(
          name: originalIngredients[i].name,
          quantity: _requireQuantity(
            i == basisIndex
                ? targetQuantity
                : originalIngredients[i].quantity * factor,
            'scaledQuantity[$i]',
          ),
          unit: originalIngredients[i].unit,
        ),
    ]);
  }

  /// Explicit conversion, without display normalization or rounding.
  /// Identical units preserve the quantity; only g/kg and ml/l are convertible.
  /// Invalid quantities, incompatible units, overflow and underflow to zero
  /// throw ArgumentError, just like scale.
  double convertQuantity({
    required double quantity,
    required String fromUnit,
    required String toUnit,
  }) {
    _requireQuantity(quantity, 'quantity');
    if (fromUnit == toUnit) return quantity;
    final double converted;
    if ((fromUnit == 'kg' && toUnit == 'g') ||
        (fromUnit == 'l' && toUnit == 'ml')) {
      converted = quantity * 1000;
    } else if ((fromUnit == 'g' && toUnit == 'kg') ||
        (fromUnit == 'ml' && toUnit == 'l')) {
      converted = quantity / 1000;
    } else {
      throw ArgumentError('Cannot convert $fromUnit to $toUnit.');
    }
    return _requireQuantity(converted, 'convertedQuantity');
  }

  /// Null means invalid/incomplete input. Accepts plain decimal notation with
  /// either separator, without grouping; never substitutes zero.
  double? parseQuantity(String input) {
    final text = input.trim();
    if (!RegExp(r'^\d+(?:[.,]\d+)?$').hasMatch(text)) return null;
    final value = double.tryParse(text.replaceAll(',', '.'));
    return value != null && value.isFinite && value > 0 ? value : null;
  }

  /// Selects display units without rounding the returned numeric quantity.
  /// Other units are preserved verbatim. Keep the returned unit together with
  /// its quantity when interpreting later user input.
  ({double quantity, String unit}) normalizeForDisplay({
    required double quantity,
    required String unit,
  }) {
    _requireQuantity(quantity, 'quantity');
    if (unit == 'kg' || unit == 'l') {
      if (!_fitsTwoDecimals(quantity)) {
        return (
          quantity: _requireQuantity(quantity * 1000, 'convertedQuantity'),
          unit: unit == 'kg' ? 'g' : 'ml',
        );
      }
    } else if ((unit == 'g' || unit == 'ml') && quantity >= 1000) {
      final largerQuantity = quantity / 1000;
      if (_fitsTwoDecimals(largerQuantity)) {
        return (quantity: largerQuantity, unit: unit == 'g' ? 'kg' : 'l');
      }
    }
    return (quantity: quantity, unit: unit);
  }

  /// Hungarian decimal text, with only machine-scale display noise removed.
  /// Does not change the numeric input or impose a two-decimal rounding rule.
  String formatQuantity(double quantity) {
    _requireQuantity(quantity, 'quantity');
    var text = quantity.toString();
    for (var digits = 1; digits <= 17; digits++) {
      final candidateText = quantity.toStringAsPrecision(digits);
      final candidate = double.tryParse(candidateText);
      if (candidate != null &&
          candidate.isFinite &&
          candidate > 0 &&
          _closeForDisplay(quantity, candidate)) {
        text = candidateText;
        break;
      }
    }
    return _plainDecimal(text).replaceAll('.', ',');
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

  static String _plainDecimal(String text) {
    final parts = text.toLowerCase().split('e');
    var plain = parts.first;
    if (parts.length == 2) {
      final exponent = int.parse(parts[1]);
      final dot = plain.indexOf('.');
      final decimalPosition = (dot < 0 ? plain.length : dot) + exponent;
      final digits = plain.replaceAll('.', '');
      if (decimalPosition <= 0) {
        plain = '0.${'0' * -decimalPosition}$digits';
      } else if (decimalPosition >= digits.length) {
        plain = '$digits${'0' * (decimalPosition - digits.length)}';
      } else {
        plain =
            '${digits.substring(0, decimalPosition)}.'
            '${digits.substring(decimalPosition)}';
      }
    }
    if (plain.contains('.')) {
      plain = plain.replaceFirst(RegExp(r'0+$'), '');
      plain = plain.replaceFirst(RegExp(r'\.$'), '');
    }
    return plain;
  }
}
