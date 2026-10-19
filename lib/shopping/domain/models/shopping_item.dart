import '../shopping_mutation.dart';

class ShoppingItem {
  const ShoppingItem({
    required this.id,
    required this.name,
    required this.quantity,
    required this.unit,
    required this.isChecked,
    this.context,
    this.revision = 0,
    this.pendingActionId,
    this.pendingChildIndex = 0,
    this.pendingNewItem = false,
    this.pending = false,
  });

  final String id;
  final String name;
  final double quantity;
  final String unit;
  final bool isChecked;
  final ShoppingMutationContext? context;
  final int revision;
  final String? pendingActionId;
  final int pendingChildIndex;
  final bool pendingNewItem;
  final bool pending;

  ShoppingItem project({
    String? name,
    double? quantity,
    String? unit,
    bool? isChecked,
    String? actionId,
    int childIndex = 0,
  }) => ShoppingItem(
    id: id,
    name: name ?? this.name,
    quantity: quantity ?? this.quantity,
    unit: unit ?? this.unit,
    isChecked: isChecked ?? this.isChecked,
    context: context,
    revision: revision,
    pendingActionId: actionId,
    pendingChildIndex: childIndex,
    pendingNewItem: pendingNewItem,
    pending: true,
  );
}
