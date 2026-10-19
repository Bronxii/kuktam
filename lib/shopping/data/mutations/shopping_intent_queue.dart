import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../../domain/shopping_mutation.dart';
import 'shopping_outbox.dart';

/// A local dependency points backwards to one immutable action/child, never to
/// an anticipated revision. It cannot cross UID, household or epoch boundaries.
class ShoppingIntentDependency {
  const ShoppingIntentDependency(
    this.mutationId, {
    this.childIndex = 0,
    this.createdAdd = false,
  });
  final String mutationId;
  final int childIndex;
  final bool createdAdd;
  Map<String, Object?> toJson() => {
    'id': mutationId,
    'child': childIndex,
    if (createdAdd) 'createdAdd': true,
  };
}

/// Durable user intent is distinct from a transport request. A held draft is
/// never sent. Materialization and insertion into the immutable outbox happen
/// in the SAME SQLite transaction, with the original allocated action ID.
class ShoppingIntentQueue {
  ShoppingIntentQueue(this.outbox);
  final ShoppingOutbox outbox;

  Future<void> enqueue(
    ShoppingMutationRequest draft, {
    Map<int, ShoppingIntentDependency> dependencies = const {},
    List<Map<String, Object?>?> observations = const [],
  }) => enqueueMany([
    (draft: draft, dependencies: dependencies, observations: observations),
  ]);

  /// One user confirmation may span several bounded server commands. All local
  /// children are committed together, or none are accepted by the UI.
  Future<void> enqueueMany(
    List<
      ({
        ShoppingMutationRequest draft,
        Map<int, ShoppingIntentDependency> dependencies,
        List<Map<String, Object?>?> observations,
      })
    >
    actions,
  ) => outbox.database.transaction((tx) async {
    for (final action in actions) {
      await _insert(tx, action.draft, action.dependencies, action.observations);
    }
  });

  Future<void> _insert(
    Transaction tx,
    ShoppingMutationRequest draft,
    Map<int, ShoppingIntentDependency> dependencies,
    List<Map<String, Object?>?> observations,
  ) async {
    final uid = draft.context.uid;
    final encoded = jsonEncode(draft.toJson());
    if (observations.isNotEmpty &&
        observations.length != draft.children.length) {
      throw StateError('Invalid projection observations');
    }
    final observed = jsonEncode(observations);
    final keys = dependencies.keys.toList()..sort();
    final encodedDependencies = jsonEncode({
      for (final k in keys) '$k': dependencies[k]!.toJson(),
    });
    final prior = await tx.query(
      'shoppingIntents',
      where: 'uid = ? AND id = ?',
      whereArgs: [uid, draft.mutationId],
    );
    if (prior.isNotEmpty) {
      if (prior.single['draft'] != encoded ||
          prior.single['dependencies'] != encodedDependencies) {
        throw StateError('Intent identity conflict');
      }
      final saved = await tx.query(
        'shoppingObservations',
        where: 'uid=? AND id=?',
        whereArgs: [uid, draft.mutationId],
      );
      if (saved.isNotEmpty && saved.single['observed'] != observed) {
        throw StateError('Intent observation conflict');
      }
      return;
    }
    final existing = await tx.query(
      'mutations',
      where: 'uid = ? AND id = ?',
      whereArgs: [uid, draft.mutationId],
    );
    if (existing.isNotEmpty) throw StateError('Intent identity already used');
    final count = Sqflite.firstIntValue(
      await tx.rawQuery(
        '''
      SELECT (SELECT COUNT(*) FROM mutations WHERE uid = ? AND terminal = 0)
      + (SELECT COUNT(*) FROM shoppingIntents WHERE uid = ? AND materialized = 0)
      ''',
        [uid, uid],
      ),
    )!;
    if (count >= ShoppingOutbox.maxPending) {
      throw StateError('Shopping queue full');
    }
    for (final index in keys) {
      final d = dependencies[index]!;
      if (index < 0 ||
          index >= draft.children.length ||
          d.childIndex < 0 ||
          draft.children[index].type == ShoppingMutationType.add) {
        throw StateError('Invalid intent dependency');
      }
      // Only already durable predecessors are allowed. This makes cycles and
      // forward references impossible, including across concurrent enqueues.
      var rows = await tx.query(
        'shoppingIntents',
        columns: ['draft'],
        where: 'uid = ? AND id = ?',
        whereArgs: [uid, d.mutationId],
      );
      String? source = rows.isEmpty ? null : rows.single['draft'] as String;
      if (source == null) {
        rows = await tx.query(
          'mutations',
          columns: ['request'],
          where: 'uid = ? AND id = ?',
          whereArgs: [uid, d.mutationId],
        );
        source = rows.isEmpty ? null : rows.single['request'] as String;
      }
      if (source == null) throw StateError('Missing intent predecessor');
      final parent = _request(source);
      if (!parent.context.sameAs(draft.context) ||
          d.childIndex >= parent.children.length ||
          parent.children[d.childIndex].type == ShoppingMutationType.delete) {
        throw StateError('Invalid intent predecessor');
      }
      // Never silently retarget an edit/delete/check to a merge destination.
      // ADD without a canonical identity needs explicit reconciliation first.
      if (d.createdAdd
          ? parent.children[d.childIndex].type != ShoppingMutationType.add
          : parent.children[d.childIndex].itemId !=
                draft.children[index].itemId) {
        throw StateError('Intent target requires reconciliation');
      }
    }
    await tx.insert('shoppingIntents', {
      'uid': uid,
      'id': draft.mutationId,
      'draft': encoded,
      'dependencies': encodedDependencies,
    });
    await tx.insert('shoppingObservations', {
      'uid': uid,
      'id': draft.mutationId,
      'observed': observed,
    });
    await _materialize(tx, uid);
  }

  /// Called after receipt commits and on session restoration, not on a timer.
  Future<void> materialize(String uid) =>
      outbox.database.transaction((tx) => _materialize(tx, uid));

  Future<void> _materialize(Transaction tx, String uid) async {
    final waiting = await tx.query(
      'shoppingIntents',
      where: 'uid = ? AND materialized = 0',
      whereArgs: [uid],
      orderBy: 'sequence',
      limit: ShoppingOutbox.maxPending,
    );
    for (final row in waiting) {
      final draft = _request(row['draft'] as String);
      final dependencies = jsonDecode(row['dependencies'] as String) as Map;
      final children = draft.children.map((c) => c.toJson()).toList();
      var ready = true;
      ShoppingMutationStatus? rejection;
      for (final entry in dependencies.entries) {
        final i = int.parse(entry.key as String);
        final dependency = entry.value as Map;
        final parent = await tx.query(
          'mutations',
          where: 'uid = ? AND id = ?',
          whereArgs: [uid, dependency['id']],
        );
        if (parent.isEmpty || parent.single['terminal'] != 1) {
          ready = false;
          continue;
        }
        final data = parent.single;
        final status = ShoppingMutationStatusContract.parse(
          data['status'] as String,
        );
        final results = _results(data['result']);
        final index = dependency['child'] as int;
        final result = index < results.length ? results[index] : null;
        if ((status != ShoppingMutationStatus.applied &&
                status != ShoppingMutationStatus.partial) ||
            result is! Map ||
            result['code'] != 'APPLIED') {
          rejection = status == ShoppingMutationStatus.rejectedContextChanged
              ? status
              : ShoppingMutationStatus.rejectedStale;
          continue;
        }
        final revision = result['revision'];
        final parentRequest = _request(data['request'] as String);
        final predecessor = parentRequest.children[index];
        final createdAdd = dependency['createdAdd'] == true;
        final validTarget = createdAdd
            ? predecessor.type == ShoppingMutationType.add &&
                  result['created'] == true
            : predecessor.itemId == result['itemId'];
        if (!validTarget ||
            result['itemId'] is! String ||
            revision is! int ||
            revision < 0 ||
            revision > 9007199254740991) {
          rejection = ShoppingMutationStatus.rejectedStale;
          continue;
        }
        children[i]['itemId'] = result['itemId'];
        children[i]['expectedRevision'] = revision;
      }
      if (!ready && rejection == null) continue;
      final wire = draft.toJson();
      wire['payloadJson'] = jsonEncode(
        draft.type == ShoppingMutationType.bulk
            ? {'items': children}
            : children.single,
      );
      final request = rejection == null
          ? ShoppingMutationRequest.restore(wire)
          : draft;
      await tx.insert('mutations', {
        'uid': uid,
        'id': draft.mutationId,
        'request': jsonEncode(request.toJson()),
        'status': rejection?.wire ?? 'PENDING',
        'terminal': rejection == null ? 0 : 1,
        'noticeAcknowledged': 0,
      });
      await tx.update(
        'shoppingIntents',
        {'materialized': 1},
        where: 'uid = ? AND id = ?',
        whereArgs: [uid, draft.mutationId],
      );
    }
  }

  static ShoppingMutationRequest _request(String value) =>
      ShoppingMutationRequest.restore(
        Map<String, Object?>.from(jsonDecode(value) as Map),
      );

  static List<dynamic> _results(Object? value) {
    if (value is! String) return const [];
    try {
      final decoded = jsonDecode(value);
      return decoded is List ? decoded : const [];
    } on FormatException {
      return const [];
    }
  }
}
