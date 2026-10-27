// Test-only SDK doubles; no network.
// ignore_for_file: subtype_of_sealed_class
import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class TestUser implements User {
  TestUser(this.uid);
  @override
  final String uid;
  @override
  String get email => '$uid@example.test';
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
