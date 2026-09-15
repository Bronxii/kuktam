import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/features/auth/data/repositories/auth_repository.dart';
import 'package:kuktam/features/auth/presentation/widgets/auth_gate.dart';

class TestProvider implements UserInfo {
  TestProvider(this.providerId);
  @override
  final String providerId;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestUser implements User {
  TestUser(this.emailVerified, this.providers);
  @override
  final bool emailVerified;
  final List<String> providers;
  @override
  String get uid => 'test-user';
  @override
  List<UserInfo> get providerData => providers.map(TestProvider.new).toList();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestCredential implements UserCredential {
  TestCredential(this.user);
  @override
  final User user;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestAuth implements FirebaseAuth {
  TestAuth(this.loginUser);
  final User loginUser;
  final changes = StreamController<User?>.broadcast();
  int signOutCalls = 0;
  final releaseLogin = Completer<void>();
  bool pauseLogin = false;
  bool failSignOut = false;
  User? user;
  @override
  User? get currentUser => user;
  @override
  Stream<User?> authStateChanges() => changes.stream;
  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    user = loginUser;
    changes.add(loginUser);
    if (pauseLogin) await releaseLogin.future;
    return TestCredential(loginUser);
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    if (failSignOut) {
      throw FirebaseAuthException(code: 'network-request-failed');
    }
    user = null;
    changes.add(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'restored sign-out failure stays blocked without rebuild retry loop',
    (tester) async {
      final auth = TestAuth(TestUser(false, ['password']))..failSignOut = true;
      auth.user = auth.loginUser;
      final repo = AuthRepository(firebaseAuth: auth);
      Widget app() => MaterialApp(
        home: AuthGate(
          authRepository: repo,
          mainBuilder: (_) => const Text('Main'),
        ),
      );
      await tester.pumpWidget(app());
      auth.changes.add(auth.user);
      await tester.pumpAndSettle();
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      auth.changes.add(auth.user);
      await tester.pumpAndSettle();
      expect(auth.signOutCalls, 1);
      expect(find.text('Main'), findsNothing);
      expect(find.textContaining('Spam mappát'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await auth.changes.close();
    },
  );
  testWidgets(
    'rapid auth changes and later verified login clear stale verification notice',
    (tester) async {
      final auth = TestAuth(TestUser(false, ['password']));
      auth.user = auth.loginUser;
      await tester.pumpWidget(
        MaterialApp(
          home: AuthGate(
            authRepository: AuthRepository(firebaseAuth: auth),
            mainBuilder: (_) => const Text('Main'),
          ),
        ),
      );
      auth.changes.add(auth.user);
      await tester.pumpAndSettle();
      expect(auth.signOutCalls, 1);
      auth.user = TestUser(true, ['password']);
      auth.changes.add(null);
      auth.changes.add(auth.user);
      await tester.pumpAndSettle();
      expect(find.text('Main'), findsOneWidget);
      await auth.signOut();
      await tester.pumpAndSettle();
      expect(find.text('Bejelentkezés e-maillel'), findsOneWidget);
      expect(find.textContaining('Spam mappát'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await auth.changes.close();
    },
  );
  for (final entry in [
    (false, ['password'], false),
    (true, ['password'], true),
    (false, ['google.com'], true),
    (true, ['password', 'google.com'], true),
    (false, ['password', 'google.com'], false),
  ]) {
    testWidgets('restored verified=${entry.$1} providers=${entry.$2}', (
      tester,
    ) async {
      final auth = TestAuth(TestUser(entry.$1, entry.$2));
      final repo = AuthRepository(firebaseAuth: auth);
      var mainBuilds = 0;
      Widget app() => MaterialApp(
        home: AuthGate(
          authRepository: repo,
          mainBuilder: (_) {
            mainBuilds++;
            return const Scaffold(body: Text('Main destination'));
          },
        ),
      );
      await tester.pumpWidget(app());
      auth.user = auth.loginUser;
      auth.changes.add(auth.loginUser);
      await tester.pumpAndSettle();
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(
        find.text('Main destination'),
        entry.$3 ? findsOneWidget : findsNothing,
      );
      if (!entry.$3) expect(mainBuilds, 0);
      expect(auth.signOutCalls, entry.$3 ? 0 : 1);
      await tester.pumpWidget(const SizedBox());
      await auth.changes.close();
    });
  }

  for (final verified in [false, true]) {
    testWidgets('email login verified=$verified', (tester) async {
      final auth = TestAuth(TestUser(verified, ['password']))
        ..pauseLogin = true;
      var mainBuilds = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: AuthGate(
            authRepository: AuthRepository(firebaseAuth: auth),
            mainBuilder: (_) {
              mainBuilds++;
              return const Scaffold(body: Text('Main destination'));
            },
          ),
        ),
      );
      auth.changes.add(null);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bejelentkezés e-maillel'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'user@example.com');
      await tester.enterText(find.byType(TextField).at(1), 'secret123');
      await tester.tap(find.widgetWithText(FilledButton, 'Bejelentkezés'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      if (!verified) expect(mainBuilds, 0);
      auth.releaseLogin.complete();
      await tester.pumpAndSettle();
      if (verified) {
        expect(find.text('Main destination'), findsOneWidget);
        expect(auth.signOutCalls, 0);
      } else {
        expect(mainBuilds, 0);
        expect(auth.signOutCalls, 1);
        expect(
          find.textContaining('A bejelentkezés előtt erősítsd'),
          findsOneWidget,
        );
        expect(find.textContaining('Spam mappát'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Bejelentkezés'),
              )
              .onPressed,
          isNotNull,
        );
        await tester.tap(find.text('Mégse'));
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 350));
      await auth.changes.close();
    });
  }
}
