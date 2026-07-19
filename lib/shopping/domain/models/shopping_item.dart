class ShoppingItem {
  const ShoppingItem({
    required this.id,
    required this.name,
    required this.quantity,
    required this.unit,
    required this.isChecked,
  });

  final String id;
  final String name;
  final double quantity;
  final String unit;
  final bool isChecked;
}