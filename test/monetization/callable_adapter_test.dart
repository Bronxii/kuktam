import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/monetization/callable_gateways.dart';
import 'package:kuktam/billing/billing_contracts.dart';

class Result<T> implements HttpsCallableResult<T> {
  Result(this.data);
  @override
  final T data;
}

class CallableFake implements HttpsCallable {
  Object? error;
  Completer<Object?>? barrier;
  Map<String, Object?>? sent;
  @override
  Future<HttpsCallableResult<T>> call<T>([dynamic parameters]) async {
    sent = Map<String, Object?>.from(parameters as Map);
    if (error != null) throw error!;
    return Result<T>(
      (barrier == null
              ? {'schemaVersion': 1, 'outcome': 'verified'}
              : await barrier!.future)
          as T,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected call');
}

class FunctionsFake implements FirebaseFunctions {
  final callable = CallableFake();
  int count = 0;
  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) {
    count++;
    return callable;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected call');
}

void main() {
  test('Functions adapter carries no UID or package input', () async {
    final functions = FunctionsFake();
    final gateway = CallablePurchaseGateway(
      FirebaseCallableTransport(functions: functions, isCurrent: () => true),
    );
    expect(
      await gateway.verify(const PurchaseEvidence('fake')),
      VerificationOutcome.verified,
    );
    expect(functions.callable.sent, {
      'productId': ProProduct.id,
      'purchaseToken': 'fake',
    });
  });
  test('Functions adapter refuses invalidated auth before dispatch', () async {
    final functions = FunctionsFake();
    final transport = FirebaseCallableTransport(
      functions: functions,
      isCurrent: () => false,
    );
    await expectLater(
      transport.call('getEntitlementProof', {}),
      throwsA(isA<TransportFailure>()),
    );
    expect(functions.count, 0);
  });
  test('Functions adapter ignores reply after auth switch', () async {
    final functions = FunctionsFake();
    var current = true;
    functions.callable.barrier = Completer<Object?>();
    final transport = FirebaseCallableTransport(
      functions: functions,
      isCurrent: () => current,
    );
    final result = transport.call('getEntitlementProof', {});
    current = false;
    functions.callable.barrier!.complete({});
    await expectLater(result, throwsA(isA<TransportFailure>()));
  });
  for (final entry in {
    'unauthenticated': 'unauthenticated',
    'permission-denied': 'permissionDenied',
    'invalid-argument': 'invalidArgument',
    'not-found': 'configuration',
    'unavailable': 'retryableUnavailable',
    'deadline-exceeded': 'retryableUnavailable',
  }.entries) {
    test('Functions ${entry.key} mapped without raw details', () async {
      final functions = FunctionsFake();
      functions.callable.error = FirebaseFunctionsException(
        code: entry.key,
        message: 'secret',
      );
      final transport = FirebaseCallableTransport(
        functions: functions,
        isCurrent: () => true,
      );
      await expectLater(
        transport.call('getEntitlementProof', {}),
        throwsA(
          isA<TransportFailure>()
              .having((e) => e.code, 'code', entry.value)
              .having(
                (e) => e.toString(),
                'redaction',
                isNot(contains('secret')),
              ),
        ),
      );
    });
  }
  test('unexpected callable name cannot be dispatched', () async {
    final functions = FunctionsFake();
    await expectLater(
      FirebaseCallableTransport(
        functions: functions,
        isCurrent: () => true,
      ).call('other', {}),
      throwsA(isA<TransportFailure>()),
    );
    expect(functions.count, 0);
  });
}
