import 'package:flutter/material.dart';

import '../../domain/models/shopping_item.dart';

class ShoppingItemTile extends StatelessWidget {
  const ShoppingItemTile({
    required this.item,
    required this.onItemTap,
    required this.onItemLongPress,
    required this.onCheckedChanged,
    super.key,
  });

  final ShoppingItem item;
  final VoidCallback onItemTap;
  final VoidCallback onItemLongPress;
  final VoidCallback onCheckedChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 80,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onItemTap,
              onLongPress: onItemLongPress,
              child: Padding(
                padding: const EdgeInsets.only(left: 20, right: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.name,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          decoration: item.isChecked
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _formatQuantityAndUnit(
                        quantity: item.quantity,
                        unit: item.unit,
                      ),
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        decoration: item.isChecked
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: onCheckedChanged,
              child: Center(
                child: IgnorePointer(
                  child: Transform.scale(
                    scale: 1.6,
                    child: Checkbox(
                      value: item.isChecked,
                      onChanged: (_) {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  String _formatQuantityAndUnit({
    required double quantity,
    required String unit,
  }) {
    if (unit == 'g' && quantity >= 1000) {
      return '${_formatQuantity(quantity / 1000)} kg';
    }

    if (unit == 'ml' && quantity >= 1000) {
      return '${_formatQuantity(quantity / 1000)} l';
    }

    return '${_formatQuantity(quantity)} $unit';
  }

  String _formatQuantity(double quantity) {
    if (quantity == quantity.roundToDouble()) {
      return quantity.toInt().toString();
    }

    return quantity
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'[.,]$'), '')
        .replaceAll('.', ',');
  }
}