import 'dart:async';
import 'dart:convert';
import '../../domain/models/shopping_item.dart';
import '../../domain/shopping_mutation.dart';
import 'shopping_intent_queue.dart';
import 'shopping_mutation_dispatcher.dart';
import 'shopping_outbox.dart';
import 'shopping_projection.dart';

abstract interface class ShoppingCoordinatorBackend {
  Stream<String> households(String uid);
  Stream<ShoppingMutationContext> contexts(String uid, String householdId);
  Future<ShoppingMutationContext> ensureContext(String uid);
  Stream<List<ShoppingItem>> items(String uid, String householdId);
}

abstract interface class ShoppingAbsenceVerifier {
  Future<Set<String>> absentItems(
    String uid,
    String householdId,
    List<String> ids,
  );
}

/// One session owner, independent of all shopping screens and repositories.
class ShoppingCoordinator {
  ShoppingCoordinator({
    required this.outbox,
    required this.dispatcher,
    required this.backend,
    required this.currentUid,
  }) {
    _receiptChanges = dispatcher.changes.listen((_) => _scheduleProjection());
  }
  final ShoppingOutbox outbox;
  final ShoppingMutationDispatcher dispatcher;
  final ShoppingCoordinatorBackend backend;
  final String? Function() currentUid;
  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;
  List<ShoppingItem> get items => List.unmodifiable(_visible);
  ShoppingMutationContext? get context => _context;
  String? get notice => _notice;
  StreamSubscription<void>? _receiptChanges;
  StreamSubscription<String>? _households;
  StreamSubscription<ShoppingMutationContext>? _contexts;
  StreamSubscription<List<ShoppingItem>>? _items;
  String? _uid, _householdId, _notice;
  ShoppingMutationContext? _context;
  List<ShoppingItem> _canonical = [], _visible = [];
  List<String> _noticeIds = [];
  int _generation = 0, _householdGeneration = 0;
  int _authorityVersion = 0;
  bool _closed = false;
  Future<void> _projection = Future.value();
  final _absenceChecked = <String>{};
  Future<void> get settled => _projection;
  bool _current(String uid, int generation) =>
      !_closed &&
      _uid == uid &&
      currentUid() == uid &&
      _generation == generation;

  Future<void> bind(String? uid) async {
    final generation = ++_generation;
    _uid = uid;
    _householdGeneration++;
    _householdId = null;
    _context = null;
    _canonical = [];
    _visible = [];
    _notice = null;
    _noticeIds = [];
    _absenceChecked.clear();
    _changes.add(null);
    final oldHouseholds = _households,
        oldContexts = _contexts,
        oldItems = _items;
    _households = null;
    _contexts = null;
    _items = null;
    await Future.wait([
      if (oldHouseholds != null) oldHouseholds.cancel(),
      if (oldContexts != null) oldContexts.cancel(),
      if (oldItems != null) oldItems.cancel(),
    ]);
    if (_closed || generation != _generation) return;
    await dispatcher.bind(uid);
    if (uid == null || !_current(uid, generation)) return;
    _households = backend
        .households(uid)
        .distinct()
        .listen(
          (id) {
            if (_current(uid, generation)) {
              unawaited(_bindHousehold(uid, generation, id));
            }
          },
          onError: (Object _) {
            _scheduleProjection();
          },
        );
  }

  Future<void> _bindHousehold(String uid, int generation, String id) async {
    final h = ++_householdGeneration;
    bool valid() => _current(uid, generation) && h == _householdGeneration;
    _householdId = id;
    _context = null;
    _canonical = [];
    _visible = [];
    _notice = null;
    _noticeIds = [];
    _changes.add(null);
    final oldItems = _items, oldContexts = _contexts;
    _items = null;
    _contexts = null;
    await Future.wait([
      if (oldItems != null) oldItems.cancel(),
      if (oldContexts != null) oldContexts.cancel(),
    ]);
    if (!valid()) return;
    final cached = await outbox.readContext(uid);
    if (!valid()) return;
    if (cached?.householdId == id) _context = cached;
    _items = backend
        .items(uid, id)
        .listen(
          (items) {
            if (!valid()) return;
            _canonical = items;
            _scheduleProjection();
          },
          onError: (Object _) {
            if (valid()) _scheduleProjection();
          },
        );
    _contexts = backend.contexts(uid, id).listen((context) {
      if (valid()) unawaited(_confirmContext(uid, generation, h, context));
    }, onError: (Object _) {});
    _scheduleProjection();
    final authorityBeforeEnsure = _authorityVersion;
    try {
      final fresh = await backend.ensureContext(uid);
      if (valid() &&
          fresh.householdId == id &&
          authorityBeforeEnsure == _authorityVersion) {
        await _confirmContext(uid, generation, h, fresh);
      }
    } catch (_) {
      // No legacy writer fallback. Previously verified context remains scoped
      // to its UID/household/epoch and server rules decide reconnection safety.
    }
  }

  Future<void> _confirmContext(
    String uid,
    int generation,
    int h,
    ShoppingMutationContext context,
  ) async {
    if (!_current(uid, generation) ||
        h != _householdGeneration ||
        context.uid != uid ||
        context.householdId != _householdId) {
      return;
    }
    final authorityVersion = ++_authorityVersion;
    await outbox.saveContext(context);
    if (!_current(uid, generation) ||
        h != _householdGeneration ||
        authorityVersion != _authorityVersion) {
      return;
    }
    _context = context;
    _scheduleProjection();
  }

  void _scheduleProjection() {
    _projection = _projection.then((_) => _project()).catchError((Object _) {
      // A failed local read never discards accepted work or rewrites its ID.
    });
  }

  Future<void> _project() async {
    final uid = _uid,
        generation = _generation,
        context = _context,
        h = _householdGeneration;
    if (uid == null || !_current(uid, generation)) return;
    if (context == null) {
      _visible = List.of(_canonical);
      _changes.add(null);
      return;
    }
    final rows = await outbox.projectionRows(uid);
    final notices = await outbox.notices(uid, limit: 100);
    if (!_current(uid, generation) ||
        h != _householdGeneration ||
        _context == null ||
        !_context!.sameAs(context)) {
      return;
    }
    final verifier = backend;
    if (verifier is ShoppingAbsenceVerifier) {
      final missing = <String>{};
      final candidates = <Map<String, Object?>>[];
      for (final row in rows) {
        final id = row['id'] as String;
        if (_absenceChecked.contains(id) || row['result'] == null) continue;
        if (!ShoppingMutationStatusContract.parse(
          row['status'] as String?,
        ).terminal) {
          continue;
        }
        final request = ShoppingMutationRequest.restore(
          Map<String, Object?>.from(
            jsonDecode((row['request'] ?? row['draft']) as String) as Map,
          ),
        );
        if (!request.context.sameAs(context)) continue;
        final results = jsonDecode(row['result'] as String) as List;
        for (var index = 0; index < results.length; index++) {
          if (index >= request.children.length ||
              request.children[index].type == ShoppingMutationType.delete ||
              results[index] is! Map) {
            continue;
          }
          final result = results[index] as Map;
          final target = result['itemId'];
          if (result['code'] == 'APPLIED' &&
              target is String &&
              !_canonical.any((i) => i.id == target)) {
            missing.add(target);
            candidates.add(row);
          }
        }
      }
      if (missing.isNotEmpty) {
        for (final row in candidates) {
          _absenceChecked.add(row['id'] as String);
        }
        unawaited(
          _resolveAbsences(
            verifier as ShoppingAbsenceVerifier,
            uid,
            generation,
            h,
            context,
            missing,
            candidates,
          ),
        );
      }
    }
    if (!_current(uid, generation) ||
        h != _householdGeneration ||
        _context?.sameAs(context) != true) {
      return;
    }
    final canonical = _canonical
        .map(
          (i) => ShoppingItem(
            id: i.id,
            name: i.name,
            quantity: i.quantity,
            unit: i.unit,
            isChecked: i.isChecked,
            revision: i.revision,
            context: context,
          ),
        )
        .toList();
    final projection = ShoppingProjection.compose(context, canonical, rows);
    _visible = projection.items;
    _noticeIds = notices.map((e) => e.request.mutationId).toList();
    _notice = notices.isEmpty
        ? null
        : notices.any(
            (e) => e.status == ShoppingMutationStatus.rejectedContextChanged,
          )
        ? 'Ez a módosítás egy korábbi bevásárlólistához tartozott, ezért nem alkalmaztuk.'
        : 'A bevásárlólista időközben megváltozott. A legfrissebb állapotot mutatjuk. Ellenőrizd a módosításaidat.';
    _changes.add(null);
    for (final id in projection.retired) {
      await outbox.retireProjection(uid, id);
    }
  }

  Future<void> _resolveAbsences(
    ShoppingAbsenceVerifier verifier,
    String uid,
    int generation,
    int h,
    ShoppingMutationContext context,
    Set<String> missing,
    List<Map<String, Object?>> rows,
  ) async {
    try {
      final absent = await verifier.absentItems(
        uid,
        context.householdId,
        missing.toList(),
      );
      for (final row in rows) {
        if (!_current(uid, generation) ||
            h != _householdGeneration ||
            _context?.sameAs(context) != true) {
          return;
        }
        final proof =
            (jsonDecode((row['absenceProof'] as String?) ?? '[]') as List)
                .cast<String>()
                .toSet()
              ..addAll(absent);
        await outbox.confirmAbsent(uid, row['id'] as String, proof);
      }
      if (_current(uid, generation) && h == _householdGeneration) {
        _scheduleProjection();
      }
    } catch (_) {
      // A network lookup never holds local UI acceptance hostage. Unknown
      // absence stays unknown, and the next session may obtain fresh proof.
    }
  }

  Future<void> acknowledgeNotice() async {
    final uid = _uid, generation = _generation, ids = List.of(_noticeIds);
    if (uid == null || !_current(uid, generation)) return;
    for (final id in ids) {
      await outbox.acknowledgeNotice(uid, id);
    }
    if (_current(uid, generation)) _scheduleProjection();
  }

  ShoppingMutationContext requireContext() {
    final c = _context;
    if (c == null || c.uid != currentUid() || c.uid != _uid) {
      throw StateError('Shopping context unavailable');
    }
    return c;
  }

  Future<void> add(List<ShoppingMutationChild> children) async {
    final c = requireContext();
    final observations = children.map((child) {
      final targets = _canonical
          .where((i) => i.name == child.name && i.unit == child.unit)
          .toList();
      return targets.length == 1
          ? <String, Object?>{
              'id': targets.single.id,
              'revision': targets.single.revision,
            }
          : null;
    }).toList();
    await dispatcher.enqueueIntent(
      ShoppingMutationRequest.create(
        context: c,
        children: children,
        bulk: children.length > 1,
      ),
      observations: observations,
    );
    _scheduleProjection();
    await settled;
  }

  Future<void> mutate(
    List<({ShoppingItem item, ShoppingMutationChild child})> actions,
  ) async {
    if (actions.isEmpty) return;
    final c = actions.first.item.context;
    if (c == null ||
        !requireContext().sameAs(c) ||
        actions.any(
          (a) => a.item.context == null || !a.item.context!.sameAs(c),
        )) {
      throw StateError('Shopping context changed');
    }
    final generation = _generation;
    final rows = await outbox.projectionRows(c.uid);
    if (!_current(c.uid, generation)) {
      throw StateError('Shopping session changed');
    }
    final dependencies = <int, ShoppingIntentDependency>{};
    for (var i = 0; i < actions.length; i++) {
      final item = actions[i].item, id = item.pendingActionId;
      if (id == null) continue;
      final matches = rows.where((r) => r['id'] == id).toList();
      if (matches.isEmpty) throw StateError('Shopping observation changed');
      final parent = ShoppingMutationRequest.restore(
        Map<String, Object?>.from(
          jsonDecode(matches.single['draft'] as String) as Map,
        ),
      );
      dependencies[i] = ShoppingIntentDependency(
        id,
        childIndex: item.pendingChildIndex,
        createdAdd:
            parent.children[item.pendingChildIndex].type ==
            ShoppingMutationType.add,
      );
    }
    final batches =
        <
          ({
            ShoppingMutationRequest draft,
            Map<int, ShoppingIntentDependency> dependencies,
            List<Map<String, Object?>?> observations,
          })
        >[];
    for (var offset = 0; offset < actions.length; offset += 200) {
      final end = (offset + 200).clamp(0, actions.length);
      final children = actions
          .sublist(offset, end)
          .map((a) => a.child)
          .toList();
      batches.add((
        draft: ShoppingMutationRequest.create(
          context: c,
          children: children,
          bulk: children.length > 1,
        ),
        dependencies: {
          for (final entry in dependencies.entries)
            if (entry.key >= offset && entry.key < end)
              entry.key - offset: entry.value,
        },
        observations: const [],
      ));
    }
    await dispatcher.enqueueIntents(batches);
    _scheduleProjection();
    await settled;
  }

  Future<void> close() async {
    _closed = true;
    _generation++;
    await _households?.cancel();
    await _items?.cancel();
    await _contexts?.cancel();
    await _receiptChanges?.cancel();
    await dispatcher.close();
    await _projection;
    await _changes.close();
  }
}
