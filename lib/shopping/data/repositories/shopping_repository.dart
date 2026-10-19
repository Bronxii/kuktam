import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../households/household_gateway.dart';
import '../../domain/models/shopping_item.dart';
import '../../domain/shopping_mutation.dart';
import '../mutations/shopping_coordinator.dart';
import '../mutations/production_shopping_coordinator.dart';

typedef ShoppingItemInput = ({String name, double quantity, String unit});

/// Presentation facade. Every business write is a durable semantic intent.
/// There is deliberately no canonical Firestore write or fallback in this class.
class ShoppingRepository {
  ShoppingRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? firebaseAuth,
    this.householdGateway,
    Future<ShoppingCoordinator>? coordinator,
  }) : _auth = firebaseAuth ?? FirebaseAuth.instance,
       _providedCoordinator = coordinator;
  final FirebaseAuth _auth;
  final HouseholdGateway? householdGateway;
  final Future<ShoppingCoordinator>? _providedCoordinator;
  Future<ShoppingCoordinator> get _client =>
      _providedCoordinator ?? productionShoppingCoordinator(auth: _auth);

  bool Function() captureSessionCheck() {
    final uid = _auth.currentUser?.uid;
    return () => uid != null && _auth.currentUser?.uid == uid;
  }

  Future<List<ShoppingItem>> getShoppingItems() async => (await _client).items;
  Stream<List<ShoppingItem>> watchShoppingItems() async* {
    final c = await _client;
    yield* Stream<List<ShoppingItem>>.multi((sink) {
      final sub = c.changes.listen((_) {
        sink.add(c.items);
      }, onError: sink.addError);
      sink.add(c.items);
      sink.onCancel = sub.cancel;
    });
  }

  Stream<String?> watchNotices() async* {
    final c = await _client;
    yield* Stream<String?>.multi((sink) {
      final sub = c.changes.listen((_) {
        sink.add(c.notice);
      }, onError: sink.addError);
      sink.add(c.notice);
      sink.onCancel = sub.cancel;
    });
  }

  Future<void> acknowledgeNotice() async => (await _client).acknowledgeNotice();
  Future<void> addOrMergeItem({
    required String name,
    required double quantity,
    required String unit,
    void Function()? onSyncFailure,
  }) => addOrMergeItems([(name: name, quantity: quantity, unit: unit)]);
  Future<void> addOrMergeItems(List<ShoppingItemInput> items) async {
    if (items.isEmpty) return;
    if (items.length > 200) throw ArgumentError('Maximum 200 shopping items');
    final children = _validated(
      () => items
          .map(
            (i) => ShoppingMutationChild.add(
              name: i.name,
              quantity: i.quantity,
              unit: i.unit,
            ),
          )
          .toList(),
    );
    await (await _client).add(children);
  }

  T _validated<T>(T Function() build) {
    try {
      return build();
    } on FormatException {
      throw ArgumentError('Invalid shopping input');
    }
  }

  ShoppingItem _observed(String id, ShoppingItem? observed) {
    if (observed == null || observed.id != id) {
      throw StateError('Observed shopping item required');
    }
    return observed;
  }

  Future<void> updateItem({
    required String id,
    required String name,
    required double quantity,
    required String unit,
    ShoppingItem? observed,
  }) async {
    final item = _observed(id, observed);
    final child = _validated(
      () => ShoppingMutationChild.edit(
        itemId: item.id,
        expectedRevision: item.revision,
        name: name,
        quantity: quantity,
        unit: unit,
      ),
    );
    await (await _client).mutate([(item: item, child: child)]);
  }

  Future<void> setItemChecked({
    required String id,
    required bool isChecked,
    ShoppingItem? observed,
  }) async {
    final item = _observed(id, observed);
    await (await _client).mutate([
      (
        item: item,
        child: ShoppingMutationChild.setChecked(
          itemId: item.id,
          expectedRevision: item.revision,
          isChecked: isChecked,
        ),
      ),
    ]);
  }

  Future<void> deleteItem(String id, {ShoppingItem? observed}) async {
    final item = _observed(id, observed);
    await (await _client).mutate([
      (
        item: item,
        child: ShoppingMutationChild.delete(
          itemId: item.id,
          expectedRevision: item.revision,
        ),
      ),
    ]);
  }

  Future<void> clearShoppingList({List<ShoppingItem>? observed}) async {
    if (observed == null) throw StateError('Observed shopping list required');
    await (await _client).mutate(
      observed
          .map(
            (item) => (
              item: item,
              child: ShoppingMutationChild.delete(
                itemId: item.id,
                expectedRevision: item.revision,
              ),
            ),
          )
          .toList(),
    );
  }
}
