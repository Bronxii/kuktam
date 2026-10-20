import 'shopping_coordinator.dart';

/// Session owners, never presentation rebuilds, own coordinator instances.
class ShoppingCoordinatorRegistry {
  final _instances = Expando<Future<ShoppingCoordinator>>();
  Future<ShoppingCoordinator> get(
    Object owner,
    Future<ShoppingCoordinator> Function() open,
  ) => _instances[owner] ??= open();
}
