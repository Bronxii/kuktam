import '../../core/domain/services/kitchen_quantity_normalizer.dart';

/// Display only: stored base-unit quantities retain their precision for merges.
String formatShoppingAmount(double quantity, String unit) {
  final display = const KitchenQuantityNormalizer().normalizeForDisplay(
    quantity: quantity,
    unit: unit,
  );
  final rounded = KitchenQuantityNormalizer.roundQuantity(
    display.quantity,
    display.unit,
  );
  final text = rounded >= 1e21
      ? rounded.toString()
      : rounded
            .toStringAsFixed(2)
            .replaceFirst(RegExp(r'\.?0+$'), '')
            .replaceAll('.', ',');
  return '$text ${display.unit}';
}
