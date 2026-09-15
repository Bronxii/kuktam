import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:kuktam/features/auth/data/repositories/auth_repository.dart';
import 'package:kuktam/features/auth/presentation/screens/login_screen.dart';
import 'package:kuktam/settings/settings_screen.dart';
import 'package:kuktam/features/auth/presentation/widgets/auth_gate.dart';
import 'package:kuktam/features/auth/presentation/widgets/account_deletion_dialog.dart';
import 'account_deletion_test.dart' as sdk;

class QaAuth extends sdk.Auth {
  int signouts = 0, exchanges = 0;
  String? sentEmail, sentPassword;
  @override
  Future<void> signOut() async {
    signouts++;
    user = null;
    events.add(null);
  }

  @override
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    sentEmail = email;
    sentPassword = password;
    events.add(user);
    return sdk.Credential(user!);
  }

  @override
  Future<UserCredential> signInWithCredential(AuthCredential credential) async {
    exchanges++;
    return sdk.Credential(user!);
  }
}

class QaUser extends sdk.Account {
  QaUser(super.auth, super.providers);
  bool failMail = false;
  int mails = 0;
  String identity = 'owner';
  bool verified = true;
  Completer<void>? mailHold;
  @override
  String get uid => identity;
  @override
  String get email => '$identity@example.com';
  @override
  bool get emailVerified => verified;
  @override
  Future<void> sendEmailVerification([ActionCodeSettings? settings]) async {
    mails++;
    if (mailHold != null) await mailHold!.future;
    if (failMail) throw FirebaseAuthException(code: 'network-request-failed');
  }
}

class FailingGoogle extends sdk.Google {
  @override
  Future<void> signOut() async {
    throw StateError('cleanup');
  }
}

class UiRepo implements AuthRepository {
  int logins = 0, registrations = 0, googleCalls = 0, changes = 0;
  String? oldPassword, newPassword;
  Object? error;
  Completer<void>? hold;
  bool passwordProvider = true;
  final auth = sdk.Auth();
  @override
  User? get currentUser =>
      sdk.Account(auth, passwordProvider ? ['password'] : ['google.com']);
  @override
  bool get isEmailPasswordUser => passwordProvider;
  Future<UserCredential> perform() async {
    if (hold != null) await hold!.future;
    if (error != null) throw error!;
    return sdk.Credential(currentUser!);
  }

  @override
  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) async {
    logins++;
    return perform();
  }

  @override
  Future<UserCredential> registerWithEmail({
    required String email,
    required String password,
  }) async {
    registrations++;
    return perform();
  }

  @override
  Future<UserCredential> signInWithGoogle() async {
    googleCalls++;
    return perform();
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    changes++;
    oldPassword = currentPassword;
    this.newPassword = newPassword;
    await perform();
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  Future<void> login(
    WidgetTester tester,
    UiRepo repo, {
    bool register = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(home: LoginScreen(authRepository: repo)),
    );
    await tester.tap(
      find.text(register ? 'Regisztráció' : 'Bejelentkezés e-maillel'),
    );
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester, List<String> values) async {
    for (var i = 0; i < values.length; i++) {
      await tester.enterText(find.byType(TextField).at(i), values[i]);
    }
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 400));
  }

  setUp(
    () => PackageInfo.setMockInitialValues(
      appName: 'Kuktám',
      packageName: 'test',
      version: '1',
      buildNumber: '1',
      buildSignature: '',
    ),
  );
  for (final register in [false, true]) {
    testWidgets(
      '${register ? "registration" : "login"} empty/invalid/Firebase error validation',
      (tester) async {
        final repo = UiRepo();
        await login(tester, repo, register: register);
        final button = find.widgetWithText(
          FilledButton,
          register ? 'Regisztráció' : 'Bejelentkezés',
        );
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(repo.logins + repo.registrations, 0);
        await fill(tester, ['   ', 'secret1', if (register) 'secret1']);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(repo.logins + repo.registrations, 0);
        if (register) {
          for (final pair in [('short', 'short'), ('secret1', 'different')]) {
            await fill(tester, ['a@b.hu', pair.$1, pair.$2]);
            await tester.tap(button);
            await tester.pumpAndSettle();
            expect(repo.registrations, 0);
          }
        }
        for (final code
            in register
                ? ['invalid-email', 'weak-password', 'email-already-in-use']
                : [
                    'invalid-email',
                    'wrong-password',
                    'user-not-found',
                    'network-request-failed',
                  ]) {
          repo.error = FirebaseAuthException(
            code: code,
            message: 'PRIVATE-DETAILS',
          );
          await fill(tester, ['invalid', 'secret1', if (register) 'secret1']);
          await tester.tap(button);
          await tester.pumpAndSettle();
          expect(find.textContaining('PRIVATE-DETAILS'), findsNothing);
          expect(
            find.textContaining(
              register
                  ? 'A regisztráció sikertelen'
                  : 'A bejelentkezés sikertelen',
            ),
            findsOneWidget,
          );
          expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
        }
        await tester.tap(find.text('Mégse'));
        await tester.pumpAndSettle();
        await finish(tester);
      },
    );
  }

  for (final kind in ['login', 'registration', 'password', 'deletion']) {
    testWidgets('$kind eye preserves password text and selection', (
      tester,
    ) async {
      final repo = UiRepo();
      if (kind == 'login' || kind == 'registration') {
        await login(tester, repo, register: kind == 'registration');
      } else if (kind == 'password') {
        await tester.pumpWidget(
          MaterialApp(home: SettingsScreen(authRepository: repo)),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Jelszó módosítása'));
        await tester.pumpAndSettle();
      } else {
        final f = sdk.Fixture();
        await tester.pumpWidget(
          MaterialApp(home: AccountDeletionDialog(repository: f.repo)),
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Fiók törlése'));
        await tester.pumpAndSettle();
      }
      final fields = find.byType(TextField);
      for (
        var i = kind == 'login' || kind == 'registration' ? 1 : 0;
        i < fields.evaluate().length;
        i++
      ) {
        final field = fields.at(i);
        await tester.enterText(field, ' secret ');
        final controller = tester.widget<TextField>(field).controller!;
        controller.selection = const TextSelection.collapsed(offset: 3);
        expect(tester.widget<TextField>(field).obscureText, isTrue);
        final eye = find.descendant(
          of: field,
          matching: find.byType(IconButton),
        );
        await tester.tap(eye);
        await tester.pump();
        expect(tester.widget<TextField>(field).obscureText, isFalse);
        expect(controller.text, ' secret ');
        expect(controller.selection.baseOffset, 3);
        await tester.tap(eye);
        await tester.pump();
        expect(tester.widget<TextField>(field).obscureText, isTrue);
        expect(controller.text, ' secret ');
      }
      await finish(tester);
    });
  }

  testWidgets(
    'registration transient user cannot enter main or interrupt verification mail',
    (tester) async {
      final auth = QaAuth();
      final user = QaUser(auth, ['password'])
        ..verified = false
        ..mailHold = Completer<void>();
      final repo = AuthRepository(
        firebaseAuth: auth,
        googleSignIn: sdk.Google(),
      );
      var mainBuilds = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: AuthGate(
            authRepository: repo,
            mainBuilder: (_) {
              mainBuilds++;
              return const Text('Main');
            },
          ),
        ),
      );
      auth.events.add(null);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Regisztráció'));
      await tester.pumpAndSettle();
      await fill(tester, ['a@b.hu', 'secret1', 'secret1']);
      auth.user = user;
      await tester.tap(find.widgetWithText(FilledButton, 'Regisztráció'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(mainBuilds, 0);
      expect(auth.signouts, 0);
      expect(user.mails, 1);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(AlertDialog), findsOneWidget);
      user.mailHold!.complete();
      await tester.pumpAndSettle();
      expect(auth.signouts, 1);
      expect(mainBuilds, 0);
      expect(find.text('Sikeres regisztráció'), findsOneWidget);
      await tester.tap(find.text('Rendben'));
      await tester.pumpAndSettle();
      await finish(tester);
      await auth.events.close();
    },
  );

  testWidgets(
    'Google cancellation resets controls; late completion after dispose is safe',
    (tester) async {
      final repo = UiRepo()
        ..error = const GoogleSignInException(
          code: GoogleSignInExceptionCode.canceled,
        );
      await tester.pumpWidget(
        MaterialApp(home: LoginScreen(authRepository: repo)),
      );
      await tester.tap(find.text('Folytatás Google-lel'));
      await tester.pumpAndSettle();
      expect(
        find.text('A Google-bejelentkezést megszakítottad.'),
        findsOneWidget,
      );
      repo.error = null;
      repo.hold = Completer<void>();
      await tester.tap(find.text('Folytatás Google-lel'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      repo.hold!.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'password validation, reauth failure, duplicate submit and retry',
    (tester) async {
      final repo = UiRepo();
      await tester.pumpWidget(
        MaterialApp(home: SettingsScreen(authRepository: repo)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Jelszó módosítása'));
      await tester.pumpAndSettle();
      for (final values in [
        ['', '', ''],
        ['oldsecret', 'short', 'short'],
        ['oldsecret', 'newsecret', 'different'],
        ['oldsecret', 'oldsecret', 'oldsecret'],
      ]) {
        await fill(tester, values);
        await tester.tap(find.widgetWithText(FilledButton, 'Mentés'));
        await tester.pumpAndSettle();
        expect(repo.changes, 0);
      }
      repo.hold = Completer<void>();
      repo.error = FirebaseAuthException(code: 'wrong-password');
      await fill(tester, ['oldsecret', 'newsecret', 'newsecret']);
      final submit = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Mentés'))
          .onPressed!;
      submit();
      submit();
      await tester.pump();
      expect(repo.changes, 1);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(AlertDialog), findsOneWidget);
      repo.hold!.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('A jelenlegi jelszó hibás'), findsOneWidget);
      repo.hold = null;
      repo.error = null;
      await tester.tap(find.widgetWithText(FilledButton, 'Mentés'));
      await tester.pumpAndSettle();
      expect(find.text('Jelszó módosítva'), findsOneWidget);
      await tester.tap(find.text('Rendben'));
      await tester.pumpAndSettle();
      await finish(tester);
    },
  );

  testWidgets('email change dialog controllers disposed on cancel', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: SettingsScreen(authRepository: UiRepo())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('E-mail-cím módosítása'));
    await tester.pumpAndSettle();
    final controllers = tester
        .widgetList<TextField>(find.byType(TextField))
        .map((f) => f.controller!)
        .toList();
    await tester.tap(find.text('Mégsem'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    for (final controller in controllers) {
      expect(() => controller.addListener(() {}), throwsFlutterError);
    }
    await finish(tester);
  });

  testWidgets(
    'account A logout then Google account B refreshes identity and provider actions',
    (tester) async {
      final auth = QaAuth();
      final google = sdk.Google();
      final repo = AuthRepository(firebaseAuth: auth, googleSignIn: google);
      await tester.pumpWidget(
        MaterialApp(
          home: AuthGate(
            authRepository: repo,
            mainBuilder: (context) => Scaffold(
              body: TextButton(
                child: const Text('Profile'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SettingsScreen(authRepository: repo),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      auth.user = QaUser(auth, ['password'])..identity = 'A';
      auth.events.add(auth.user);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      expect(find.text('A@example.com'), findsOneWidget);
      expect(find.text('Jelszó módosítása'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Kijelentkezés'), 200);
      await tester.tap(find.text('Kijelentkezés'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Kijelentkezés'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsNothing);
      expect(find.text('Bejelentkezés e-maillel'), findsOneWidget);
      auth.user = QaUser(auth, ['google.com'])..identity = 'B';
      auth.events.add(auth.user);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      expect(find.text('B@example.com'), findsOneWidget);
      expect(find.text('A@example.com'), findsNothing);
      expect(find.text('Jelszó módosítása'), findsNothing);
      expect(find.text('Fiók törlése'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Profile'), findsOneWidget);
      await finish(tester);
      await auth.events.close();
    },
  );
  test('mail failure still signs out the newly created account', () async {
    final auth = QaAuth();
    final user = QaUser(auth, ['password'])..failMail = true;
    auth.user = user;
    final repo = AuthRepository(firebaseAuth: auth, googleSignIn: sdk.Google());
    await expectLater(
      repo.registerWithEmail(email: ' a@b.hu ', password: ' secret '),
      throwsA(isA<FirebaseAuthException>()),
    );
    expect(auth.signouts, 1);
    expect(auth.user, isNull);
    await auth.events.close();
  });
  test(
    'registration sends verification then signs out; password preserved',
    () async {
      final auth = QaAuth();
      final user = QaUser(auth, ['password']);
      auth.user = user;
      await AuthRepository(
        firebaseAuth: auth,
        googleSignIn: sdk.Google(),
      ).registerWithEmail(email: ' a@b.hu ', password: ' secret ');
      expect(user.mails, 1);
      expect(auth.signouts, 1);
      expect(auth.sentEmail, 'a@b.hu');
      expect(auth.sentPassword, ' secret ');
      await auth.events.close();
    },
  );
  test('Google cleanup failure cannot prevent Firebase logout', () async {
    final auth = QaAuth();
    auth.user = QaUser(auth, ['password']);
    await AuthRepository(
      firebaseAuth: auth,
      googleSignIn: FailingGoogle(),
    ).signOut();
    expect(auth.signouts, 1);
    expect(auth.user, isNull);
    await auth.events.close();
  });
  test('Google authentication exchanges credential only on success', () async {
    final auth = QaAuth();
    auth.user = QaUser(auth, ['google.com']);
    final google = sdk.Google()..cancel = true;
    final repo = AuthRepository(firebaseAuth: auth, googleSignIn: google);
    await expectLater(
      repo.signInWithGoogle(),
      throwsA(isA<GoogleSignInException>()),
    );
    expect(auth.exchanges, 0);
    google.cancel = false;
    await repo.signInWithGoogle();
    expect(auth.exchanges, 1);
    expect(google.initializes, 1);
    await auth.events.close();
  });
  for (final register in [false, true]) {
    testWidgets(
      '${register ? "register" : "login"} duplicate submit invokes once',
      (tester) async {
        final repo = UiRepo()..hold = Completer<void>();
        await login(tester, repo, register: register);
        await fill(tester, ['a@b.hu', 'secret1', if (register) 'secret1']);
        final button = find.widgetWithText(
          FilledButton,
          register ? 'Regisztráció' : 'Bejelentkezés',
        );
        final submit = tester.widget<FilledButton>(button).onPressed!;
        submit();
        submit();
        await tester.pump();
        expect(register ? repo.registrations : repo.logins, 1);
        repo.hold!.complete();
        await tester.pumpAndSettle();
        if (register) {
          expect(find.textContaining('Spam mappát'), findsOneWidget);
          await tester.tap(find.text('Rendben'));
          await tester.pumpAndSettle();
        }
        await finish(tester);
      },
    );
  }
  testWidgets(
    'Google failure hides technical details and resets loading; duplicate tap blocked',
    (tester) async {
      final repo = UiRepo()
        ..hold = Completer<void>()
        ..error = StateError('PRIVATE-DETAILS');
      await tester.pumpWidget(
        MaterialApp(home: LoginScreen(authRepository: repo)),
      );
      final submit = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Folytatás Google-lel'),
          )
          .onPressed!;
      submit();
      submit();
      await tester.pump();
      expect(repo.googleCalls, 1);
      repo.hold!.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('PRIVATE-DETAILS'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Folytatás Google-lel'),
            )
            .onPressed,
        isNotNull,
      );
      await finish(tester);
    },
  );
  testWidgets('password change preserves whitespace and disposes controllers', (
    tester,
  ) async {
    final repo = UiRepo();
    await tester.pumpWidget(
      MaterialApp(home: SettingsScreen(authRepository: repo)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jelszó módosítása'));
    await tester.pumpAndSettle();
    await fill(tester, [' oldsecret ', ' newsecret ', ' newsecret ']);
    final controller = tester
        .widget<TextField>(find.byType(TextField).first)
        .controller!;
    await tester.tap(find.widgetWithText(FilledButton, 'Mentés'));
    await tester.pumpAndSettle();
    expect(repo.oldPassword, ' oldsecret ');
    expect(repo.newPassword, ' newsecret ');
    await tester.tap(find.text('Rendben'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    expect(() => controller.addListener(() {}), throwsFlutterError);
    await finish(tester);
  });
}
