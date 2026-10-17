// Test-only SDK doubles; no network.
// ignore_for_file: subtype_of_sealed_class
import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/households/callable_household_gateway.dart';

class TestUser implements User {
  TestUser(this.uid);
  @override
  final String uid;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('Unexpected');
}

class TestAuth implements FirebaseAuth {
  @override
  User? currentUser = TestUser('a');
  final events = StreamController<User?>.broadcast(sync: true);
  @override
  Stream<User?> authStateChanges() => events.stream;
  void switchTo(String? uid) {
    currentUser = uid == null ? null : TestUser(uid);
    events.add(currentUser);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('Unexpected');
}

class Result<T> implements HttpsCallableResult<T> {
  Result(this.data);
  @override
  final T data;
}

class Functions implements FirebaseFunctions {
  final names = <String>[];
  final callable = Callable();
  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) {
    names.add(name);
    return callable;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('Unexpected');
}

class Callable implements HttpsCallable {
  final sent = <Object?>[];
  Future<Object?> Function() reply = () async => {
    'schemaVersion': 1,
    'ready': true,
    'householdId': 'home',
  };
  @override
  Future<HttpsCallableResult<T>> call<T>([dynamic parameters]) async {
    sent.add(parameters);
    return Result<T>((await reply()) as T);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('Unexpected');
}

void main() {
  test(
    'only empty authenticated household callable; no billing or arbitrary UID',
    () async {
      final auth = TestAuth(), f = Functions();
      addTearDown(auth.events.close);
      expect(
        await CallableHouseholdGateway(auth: auth, functions: f).ensure(),
        'home',
      );
      expect(f.names, ['ensurePrivateHousehold']);
      expect(f.callable.sent, [{}]);
      expect(auth.events.hasListener, false);
    },
  );
  test('anonymous initialization sends nothing', () async {
    final auth = TestAuth()..currentUser = null, f = Functions();
    addTearDown(auth.events.close);
    await expectLater(
      CallableHouseholdGateway(auth: auth, functions: f).ensure(),
      throwsStateError,
    );
    expect(f.names, isEmpty);
  });
  test('pending migration resumes within bounded calls', () async {
    final auth = TestAuth(), f = Functions();
    addTearDown(auth.events.close);
    var n = 0;
    f.callable.reply = () async => ++n < 3
        ? {'schemaVersion': 1, 'ready': false}
        : {'schemaVersion': 1, 'ready': true, 'householdId': 'home'};
    expect(
      await CallableHouseholdGateway(auth: auth, functions: f).ensure(),
      'home',
    );
    expect(n, 3);
  });
  test(
    'perpetually pending migration stops and permits later explicit retry',
    () async {
      final auth = TestAuth(), f = Functions();
      addTearDown(auth.events.close);
      f.callable.reply = () async => {'schemaVersion': 1, 'ready': false};
      final gateway = CallableHouseholdGateway(auth: auth, functions: f);
      await expectLater(gateway.ensure(), throwsStateError);
      expect(f.names.length, 20);
      expect(auth.events.hasListener, false);
      f.callable.reply = () async => {
        'schemaVersion': 1,
        'ready': true,
        'householdId': 'home',
      };
      expect(await gateway.ensure(), 'home');
    },
  );
  for (final switchBack in [false, true]) {
    test(
      'in-flight account switch cannot leak household, ABA=$switchBack',
      () async {
        final auth = TestAuth(), f = Functions();
        addTearDown(auth.events.close);
        final pending = Completer<Object?>();
        f.callable.reply = () => pending.future;
        final result = CallableHouseholdGateway(
          auth: auth,
          functions: f,
        ).ensure();
        auth.switchTo('b');
        if (switchBack) auth.switchTo('a');
        pending.complete({
          'schemaVersion': 1,
          'ready': true,
          'householdId': 'a-home',
        });
        await expectLater(result, throwsStateError);
        expect(auth.events.hasListener, false);
      },
    );
  }
  for (final value in [
    null,
    {},
    {'schemaVersion': 2, 'ready': true, 'householdId': 'h'},
    {'schemaVersion': 1, 'ready': true, 'householdId': 'a/b'},
  ]) {
    test('reject malformed household response $value', () async {
      final auth = TestAuth(), f = Functions();
      addTearDown(auth.events.close);
      f.callable.reply = () async => value;
      await expectLater(
        CallableHouseholdGateway(auth: auth, functions: f).ensure(),
        throwsStateError,
      );
    });
  }
}
