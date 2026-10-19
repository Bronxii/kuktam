import 'dart:convert';
import '../../domain/models/shopping_item.dart';
import '../../domain/shopping_mutation.dart';

class ShoppingProjection {
  const ShoppingProjection(this.items, this.retired);
  final List<ShoppingItem> items;
  final List<String> retired;

  static ShoppingProjection compose(
    ShoppingMutationContext context,
    List<ShoppingItem> canonical,
    List<Map<String, Object?>> rows,
  ) {
    final visible = {for (final item in canonical) item.id: item};
    final authoritative = {for (final item in canonical) item.id: item};
    final retired = <String>[];
    for (final row in rows) {
      final request = ShoppingMutationRequest.restore(
        Map<String, Object?>.from(
          jsonDecode((row['request'] ?? row['draft']) as String) as Map,
        ),
      );
      if (!request.context.sameAs(context)) continue;
      final children = request.children;
      final observations = row['observed'] == null
          ? const []
          : jsonDecode(row['observed'] as String) as List;
      final results = row['result'] == null
          ? const []
          : jsonDecode(row['result'] as String) as List;
      final status = ShoppingMutationStatusContract.parse(
        row['status'] as String?,
      );
      var reconciled = status.terminal;
      for (var i = 0; i < children.length; i++) {
        final child = children[i];
        final result = i < results.length && results[i] is Map
            ? results[i] as Map
            : null;
        final applied = result?['code'] == 'APPLIED';
        if ((status.terminal && !applied) || (result != null && !applied)) {
          continue;
        }
        if (applied) {
          final id = result!['itemId'] as String?;
          final revision = result['revision'];
          final current = authoritative[id];
          final absent =
              jsonDecode((row['absenceProof'] as String?) ?? '[]') as List;
          final observed = child.type == ShoppingMutationType.delete
              ? current == null
              : absent.contains(id) ||
                    current != null &&
                        revision is int &&
                        current.revision >= revision;
          if (observed) continue;
          reconciled = false;
        }
        final observation = i < observations.length && observations[i] is Map
            ? observations[i] as Map
            : null;
        if (child.type == ShoppingMutationType.add) {
          final matches = visible.values
              .where(
                (item) => item.name == child.name && item.unit == child.unit,
              )
              .toList();
          if (matches.length > 1) continue;
          if (matches.isEmpty) {
            final id =
                'pending_${request.mutationId.substring(request.mutationId.length - 32)}_$i';
            visible[id] = ShoppingItem(
              id: id,
              name: child.name!,
              quantity: child.quantity!,
              unit: child.unit!,
              isChecked: false,
              context: context,
              pending: true,
              pendingNewItem: true,
              pendingActionId: request.mutationId,
              pendingChildIndex: i,
            );
          } else {
            final target = matches.single;
            // A canonical revision change may already contain this ADD. Until
            // the receipt disambiguates, never add the delta a second time.
            final canProject =
                target.pendingNewItem ||
                (observation?['id'] == target.id &&
                    observation?['revision'] == target.revision);
            if (canProject) {
              visible[target.id] = target.project(
                quantity: target.quantity + child.quantity!,
                actionId: request.mutationId,
                childIndex: i,
              );
            }
          }
          continue;
        }
        final draft = ShoppingMutationRequest.restore(
          Map<String, Object?>.from(jsonDecode(row['draft'] as String) as Map),
        );
        final target =
            visible[child.itemId] ?? visible[draft.children[i].itemId];
        if (target == null) continue;
        final dependencies = jsonDecode(row['dependencies'] as String) as Map;
        final dependency = dependencies['$i'] as Map?;
        final samePending =
            dependency != null &&
            target.pendingActionId == dependency['id'] &&
            target.pendingChildIndex == dependency['child'];
        if (!samePending &&
            (target.pendingNewItem ||
                target.revision != child.expectedRevision)) {
          continue;
        }
        switch (child.type) {
          case ShoppingMutationType.edit:
            visible[target.id] = target.project(
              name: child.name,
              quantity: child.quantity,
              unit: child.unit,
              actionId: request.mutationId,
              childIndex: i,
            );
          case ShoppingMutationType.setChecked:
            visible[target.id] = target.project(
              isChecked: child.isChecked,
              actionId: request.mutationId,
              childIndex: i,
            );
          case ShoppingMutationType.delete:
            visible.remove(target.id);
          default:
            break;
        }
      }
      if (reconciled) retired.add(request.mutationId);
    }
    return ShoppingProjection([
      ...visible.values.where((i) => !i.isChecked),
      ...visible.values.where((i) => i.isChecked),
    ], retired);
  }
}
