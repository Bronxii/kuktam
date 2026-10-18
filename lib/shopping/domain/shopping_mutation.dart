import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

import 'shopping_units.dart';

enum ShoppingMutationType { add, edit, delete, setChecked, bulk }

enum ShoppingMutationStatus {
  pending,
  processing,
  applied,
  partial,
  rejectedStale,
  rejectedContextChanged,
  rejectedNotFound,
  rejectedUnauthorized,
  failedRetryable,
  failedTerminal,
  resultExpired,
}

extension ShoppingMutationStatusContract on ShoppingMutationStatus {
  String get wire => const {
    ShoppingMutationStatus.pending: 'PENDING',
    ShoppingMutationStatus.processing: 'PROCESSING',
    ShoppingMutationStatus.applied: 'APPLIED',
    ShoppingMutationStatus.partial: 'PARTIAL',
    ShoppingMutationStatus.rejectedStale: 'REJECTED_STALE',
    ShoppingMutationStatus.rejectedContextChanged: 'REJECTED_CONTEXT_CHANGED',
    ShoppingMutationStatus.rejectedNotFound: 'REJECTED_NOT_FOUND',
    ShoppingMutationStatus.rejectedUnauthorized: 'REJECTED_UNAUTHORIZED',
    ShoppingMutationStatus.failedRetryable: 'FAILED_RETRYABLE',
    ShoppingMutationStatus.failedTerminal: 'FAILED_TERMINAL',
    ShoppingMutationStatus.resultExpired: 'RESULT_EXPIRED',
  }[this]!;

  bool get terminal => ![
    ShoppingMutationStatus.pending,
    ShoppingMutationStatus.processing,
    ShoppingMutationStatus.failedRetryable,
  ].contains(this);

  static ShoppingMutationStatus parse(String? value) =>
      ShoppingMutationStatus.values.firstWhere(
        (s) => s.wire == (value ?? 'PENDING'),
        orElse: () => throw const FormatException('Unknown mutation status'),
      );
}

extension ShoppingMutationTypeContract on ShoppingMutationType {
  String get wire =>
      const ['ADD', 'EDIT', 'DELETE', 'SET_CHECKED', 'BULK'][index];
}

/// An observed context is immutable, including across authentication changes.
class ShoppingMutationContext {
  ShoppingMutationContext({
    required this.uid,
    required this.householdId,
    required this.epoch,
  }) {
    if (uid.isEmpty ||
        uid.length > 128 ||
        uid.trim() != uid ||
        uid.contains('/') ||
        !_id.hasMatch(householdId) ||
        !_epoch.hasMatch(epoch)) {
      throw const FormatException('Invalid shopping context');
    }
  }
  static final _id = RegExp(r'^[a-zA-Z0-9_-]{1,128}$');
  static final _epoch = RegExp(r'^[0-9]{13}-[a-f0-9]{32}$');
  final String uid;
  final String householdId;
  final String epoch;
  DateTime get expiresAt => DateTime.fromMillisecondsSinceEpoch(
    int.parse(epoch.substring(0, 13)),
    isUtc: true,
  );
  bool sameAs(ShoppingMutationContext other) =>
      uid == other.uid &&
      householdId == other.householdId &&
      epoch == other.epoch;
}

/// Typed child intent. It never contains an arbitrary Firestore patch.
class ShoppingMutationChild {
  ShoppingMutationChild._(
    this.type, {
    this.itemId,
    this.expectedRevision,
    this.name,
    this.quantity,
    this.unit,
    this.isChecked,
  });

  factory ShoppingMutationChild.add({
    required String name,
    required double quantity,
    required String unit,
  }) => ShoppingMutationChild._value(
    ShoppingMutationType.add,
    name,
    quantity,
    unit,
  );

  factory ShoppingMutationChild.edit({
    required String itemId,
    required int expectedRevision,
    required String name,
    required double quantity,
    required String unit,
  }) {
    _target(itemId, expectedRevision);
    return ShoppingMutationChild._value(
      ShoppingMutationType.edit,
      name,
      quantity,
      unit,
      itemId: itemId,
      revision: expectedRevision,
    );
  }

  factory ShoppingMutationChild.delete({
    required String itemId,
    required int expectedRevision,
  }) {
    _target(itemId, expectedRevision);
    return ShoppingMutationChild._(
      ShoppingMutationType.delete,
      itemId: itemId,
      expectedRevision: expectedRevision,
    );
  }

  factory ShoppingMutationChild.setChecked({
    required String itemId,
    required int expectedRevision,
    required bool isChecked,
  }) {
    _target(itemId, expectedRevision);
    return ShoppingMutationChild._(
      ShoppingMutationType.setChecked,
      itemId: itemId,
      expectedRevision: expectedRevision,
      isChecked: isChecked,
    );
  }

  static void _target(String id, int revision) {
    if (!ShoppingMutationContext._id.hasMatch(id) ||
        revision < 0 ||
        revision > 9007199254740991) {
      throw const FormatException('Invalid item reference');
    }
  }

  static ShoppingMutationChild _value(
    ShoppingMutationType type,
    String name,
    double quantity,
    String unit, {
    String? itemId,
    int? revision,
  }) {
    final normalized = name.trim().toLowerCase();
    if (normalized.isEmpty ||
        normalized.runes.length > 200 ||
        !shoppingUnits.contains(unit) ||
        !quantity.isFinite ||
        quantity <= 0) {
      throw const FormatException('Invalid shopping value');
    }
    if (unit == 'kg' || unit == 'l') quantity *= 1000;
    if (!quantity.isFinite || quantity > 9007199254740991) {
      throw const FormatException('Quantity overflow');
    }
    return ShoppingMutationChild._(
      type,
      itemId: itemId,
      expectedRevision: revision,
      name: normalized,
      quantity: quantity,
      unit: unit == 'kg'
          ? 'g'
          : unit == 'l'
          ? 'ml'
          : unit,
    );
  }

  final ShoppingMutationType type;
  final String? itemId;
  final int? expectedRevision;
  final String? name;
  final double? quantity;
  final String? unit;
  final bool? isChecked;

  factory ShoppingMutationChild.fromJson(Map<String, Object?> data) {
    final type = data['type'];
    final allowed = switch (type) {
      'ADD' => {'type', 'name', 'quantity', 'unit'},
      'EDIT' => {
        'type',
        'itemId',
        'expectedRevision',
        'name',
        'quantity',
        'unit',
      },
      'DELETE' => {'type', 'itemId', 'expectedRevision'},
      'SET_CHECKED' => {'type', 'itemId', 'expectedRevision', 'isChecked'},
      _ => throw const FormatException('Unknown child type'),
    };
    if (data.length != allowed.length || !data.keys.every(allowed.contains)) {
      throw const FormatException('Unexpected mutation fields');
    }
    return switch (type) {
      'ADD' => ShoppingMutationChild.add(
        name: data['name'] as String,
        quantity: (data['quantity'] as num).toDouble(),
        unit: data['unit'] as String,
      ),
      'EDIT' => ShoppingMutationChild.edit(
        itemId: data['itemId'] as String,
        expectedRevision: data['expectedRevision'] as int,
        name: data['name'] as String,
        quantity: (data['quantity'] as num).toDouble(),
        unit: data['unit'] as String,
      ),
      'DELETE' => ShoppingMutationChild.delete(
        itemId: data['itemId'] as String,
        expectedRevision: data['expectedRevision'] as int,
      ),
      'SET_CHECKED' => ShoppingMutationChild.setChecked(
        itemId: data['itemId'] as String,
        expectedRevision: data['expectedRevision'] as int,
        isChecked: data['isChecked'] as bool,
      ),
      _ => throw const FormatException('Unknown child type'),
    };
  }

  Map<String, Object?> toJson() => {
    'type': type.wire,
    if (itemId != null) 'itemId': itemId,
    if (expectedRevision != null) 'expectedRevision': expectedRevision,
    if (name != null) 'name': name,
    if (quantity != null) 'quantity': quantity,
    if (unit != null) 'unit': unit,
    if (isChecked != null) 'isChecked': isChecked,
  };
}

class ShoppingMutationRequest {
  ShoppingMutationRequest._(
    this.context,
    this.mutationId,
    this.type,
    this.payloadJson,
  );

  factory ShoppingMutationRequest.create({
    required ShoppingMutationContext context,
    required List<ShoppingMutationChild> children,
    bool bulk = false,
  }) {
    if (children.isEmpty || children.length > 200) {
      throw const FormatException('Expected 1–200 children');
    }
    final type = bulk || children.length > 1
        ? ShoppingMutationType.bulk
        : children.single.type;
    final payload = jsonEncode(
      type == ShoppingMutationType.bulk
          ? {'items': children.map((c) => c.toJson()).toList()}
          : children.single.toJson(),
    );
    if (utf8.encode(payload).length > 262144) {
      throw const FormatException('Mutation too large');
    }
    final random = Random.secure();
    final suffix = List.generate(
      32,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return ShoppingMutationRequest._(
      context,
      '${context.epoch}_$suffix',
      type,
      payload,
    );
  }

  /// Restoring persisted bytes must never reserialize the payload or change ID.
  factory ShoppingMutationRequest.restore(Map<String, Object?> data) {
    const allowed = {
      'schemaVersion',
      'actorUid',
      'householdId',
      'epoch',
      'mutationId',
      'kind',
      'payloadJson',
    };
    if (data.length != allowed.length || !data.keys.every(allowed.contains)) {
      throw const FormatException('Unexpected envelope fields');
    }
    final context = ShoppingMutationContext(
      uid: data['actorUid'] as String,
      householdId: data['householdId'] as String,
      epoch: data['epoch'] as String,
    );
    final id = data['mutationId'] as String;
    if (data['schemaVersion'] != 1 ||
        !id.startsWith('${context.epoch}_') ||
        !RegExp(r'^[0-9]{13}-[a-f0-9]{32}_[a-f0-9]{64}$').hasMatch(id)) {
      throw const FormatException('Invalid persisted mutation');
    }
    final type = ShoppingMutationType.values.firstWhere(
      (t) => t.wire == data['kind'],
    );
    final payload = data['payloadJson'] as String;
    if (utf8.encode(payload).length > 262144) {
      throw const FormatException('Mutation too large');
    }
    final restored = ShoppingMutationRequest._(context, id, type, payload);
    restored.children; // Validate persisted bytes without rewriting them.
    return restored;
  }

  final ShoppingMutationContext context;
  final String mutationId;
  final ShoppingMutationType type;
  final String payloadJson;
  String get requestHash => sha256
      .convert(
        utf8.encode(
          jsonEncode([
            1,
            mutationId,
            context.uid,
            context.householdId,
            context.epoch,
            type.wire,
            payloadJson,
          ]),
        ),
      )
      .toString();
  List<ShoppingMutationChild> get children {
    final decoded = jsonDecode(payloadJson) as Map<String, dynamic>;
    if (type == ShoppingMutationType.bulk) {
      if (decoded.length != 1 || decoded['items'] is! List) {
        throw const FormatException('Invalid bulk');
      }
      final items = decoded['items'] as List;
      if (items.isEmpty || items.length > 200) {
        throw const FormatException('Invalid bulk size');
      }
      return List.unmodifiable(
        items.map(
          (e) => ShoppingMutationChild.fromJson(
            Map<String, Object?>.from(e as Map),
          ),
        ),
      );
    }
    final child = ShoppingMutationChild.fromJson(decoded);
    if (child.type != type) {
      throw const FormatException('Mutation kind mismatch');
    }
    return [child];
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'mutationId': mutationId,
    'actorUid': context.uid,
    'householdId': context.householdId,
    'epoch': context.epoch,
    'kind': type.wire,
    'payloadJson': payloadJson,
  };
}

class ShoppingMutationResult {
  const ShoppingMutationResult({
    required this.status,
    this.itemId,
    this.revision,
  });
  final ShoppingMutationStatus status;
  final String? itemId;
  final int? revision;
}
