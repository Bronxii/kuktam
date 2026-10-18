import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/shopping/domain/shopping_mutation.dart';

ShoppingMutationContext testContext([
  String uid = 'a',
  String household = 'home',
]) => ShoppingMutationContext(
  uid: uid,
  householdId: household,
  epoch: '1999999999999-${'a' * 32}',
);

void main() {
  test(
    'request hash matches Node/S1A JSON hashing, including Hungarian text',
    () {
      final context = testContext();
      final request = ShoppingMutationRequest.restore({
        'schemaVersion': 1,
        'mutationId': '${context.epoch}_${'b' * 64}',
        'actorUid': 'a',
        'householdId': 'home',
        'epoch': context.epoch,
        'kind': 'ADD',
        'payloadJson':
            '{"type":"ADD","name":"őrölt paprika","quantity":1.5,"unit":"g"}',
      });
      expect(
        request.requestHash,
        '6f1c2d964bad59a8b2fddc3c3b1eb6532479e5b53a8ef7629688c1ccc1da2bd6',
      );
    },
  );
  test('normalizes current name/unit semantics and uses semantic delta', () {
    final child = ShoppingMutationChild.add(
      name: '  Liszt  ',
      quantity: 0.5,
      unit: 'kg',
    );
    expect(child.toJson(), {
      'type': 'ADD',
      'name': 'liszt',
      'quantity': 500.0,
      'unit': 'g',
    });
    expect(
      ShoppingMutationChild.add(name: 'A  B', quantity: 2, unit: 'l').toJson(),
      {'type': 'ADD', 'name': 'a  b', 'quantity': 2000.0, 'unit': 'ml'},
    );
  });
  test(
    'ID format and restoration preserve exact payload bytes and identity',
    () {
      final r = ShoppingMutationRequest.create(
        context: testContext(),
        children: [
          ShoppingMutationChild.add(name: 'tea', quantity: 2, unit: 'db'),
        ],
      );
      expect(
        r.mutationId,
        matches(RegExp(r'^[0-9]{13}-[a-f0-9]{32}_[a-f0-9]{64}$')),
      );
      final restored = ShoppingMutationRequest.restore(r.toJson());
      expect(restored.mutationId, r.mutationId);
      expect(restored.payloadJson, r.payloadJson);
      expect(restored.toJson(), r.toJson());
      expect(restored.toJson().containsKey('status'), false);
    },
  );
  test('distinct logical actions get distinct cryptographic identities', () {
    final ids = List.generate(
      100,
      (_) => ShoppingMutationRequest.create(
        context: testContext(),
        children: [
          ShoppingMutationChild.add(name: 'tea', quantity: 1, unit: 'db'),
        ],
      ).mutationId,
    );
    expect(ids.toSet(), hasLength(100));
  });
  for (final size in [1, 10, 50, 200]) {
    test(
      'bulk $size children preserves order and stable parent/cursor identity',
      () {
        final r = ShoppingMutationRequest.create(
          context: testContext(),
          bulk: true,
          children: List.generate(
            size,
            (i) => ShoppingMutationChild.add(
              name: 'item $i',
              quantity: i + 0.5,
              unit: 'g',
            ),
          ),
        );
        expect(r.type, ShoppingMutationType.bulk);
        expect((jsonDecode(r.payloadJson)['items'] as List).length, size);
        expect(
          ShoppingMutationRequest.restore(r.toJson()).payloadJson,
          r.payloadJson,
        );
      },
    );
  }
  test(
    'revision-bound operations retain observed revision and desired checked state',
    () {
      expect(
        ShoppingMutationChild.delete(
          itemId: 'one',
          expectedRevision: 0,
        ).toJson(),
        {'type': 'DELETE', 'itemId': 'one', 'expectedRevision': 0},
      );
      expect(
        ShoppingMutationChild.setChecked(
          itemId: 'one',
          expectedRevision: 4,
          isChecked: false,
        ).toJson(),
        {
          'type': 'SET_CHECKED',
          'itemId': 'one',
          'expectedRevision': 4,
          'isChecked': false,
        },
      );
      expect(
        ShoppingMutationChild.edit(
          itemId: 'one',
          expectedRevision: 7,
          name: ' x ',
          quantity: 1,
          unit: 'db',
        ).expectedRevision,
        7,
      );
    },
  );
  test('invalid input fails before a command exists', () {
    for (final q in [0.0, -1.0, double.infinity, double.nan, 1e20]) {
      expect(
        () => ShoppingMutationChild.add(name: 'x', quantity: q, unit: 'db'),
        throwsFormatException,
      );
    }
    expect(
      () => ShoppingMutationChild.add(name: '', quantity: 1, unit: 'db'),
      throwsFormatException,
    );
    expect(
      () => ShoppingMutationChild.add(name: 'x', quantity: 1, unit: 'bucket'),
      throwsFormatException,
    );
    expect(
      () => ShoppingMutationChild.delete(itemId: 'x', expectedRevision: -1),
      throwsFormatException,
    );
    expect(
      () =>
          ShoppingMutationRequest.create(context: testContext(), children: []),
      throwsFormatException,
    );
    expect(
      () => ShoppingMutationRequest.create(
        context: testContext(),
        children: List.generate(
          201,
          (_) => ShoppingMutationChild.delete(itemId: 'x', expectedRevision: 0),
        ),
      ),
      throwsFormatException,
    );
  });
  test('status parser fails closed on unknown server states', () {
    expect(
      ShoppingMutationStatusContract.parse(null),
      ShoppingMutationStatus.pending,
    );
    for (final status in ShoppingMutationStatus.values) {
      expect(ShoppingMutationStatusContract.parse(status.wire), status);
    }
    expect(
      () => ShoppingMutationStatusContract.parse('SURPRISE'),
      throwsFormatException,
    );
  });
  test('context cannot silently rebind across UID/household/epoch', () {
    expect(testContext().sameAs(testContext('b')), false);
    expect(testContext().sameAs(testContext('a', 'other')), false);
    expect(testContext().sameAs(testContext()), true);
    expect(
      () => ShoppingMutationContext(
        uid: 'a/b',
        householdId: 'home',
        epoch: testContext().epoch,
      ),
      throwsFormatException,
    );
  });
}
