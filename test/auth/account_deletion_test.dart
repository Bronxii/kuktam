// Test-only SDK doubles. No Firebase/network access.
// ignore_for_file: subtype_of_sealed_class
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:kuktam/settings/settings_screen.dart';
import 'package:kuktam/features/auth/data/repositories/account_deletion_repository.dart';
import 'package:kuktam/features/auth/data/repositories/auth_repository.dart';
import 'package:kuktam/features/auth/presentation/widgets/account_deletion_dialog.dart';
import 'package:kuktam/features/auth/presentation/widgets/auth_gate.dart';

class Provider implements UserInfo {
  Provider(this.providerId);
  @override
  final String providerId;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class Account implements User {
  Account(this.auth, this.providers);
  final Auth auth;
  final List<String> providers;
  bool failReauth = false, failDelete = false;
  int reauths = 0, deletes = 0;
  AuthCredential? credential;
  Completer<void>? hold;
  @override
  String get uid => 'owner';
  @override
  String get email => 'owner@example.com';
  @override
  bool get emailVerified => true;
  @override
  List<UserInfo> get providerData => providers.map(Provider.new).toList();
  @override
  Future<UserCredential> reauthenticateWithCredential(
    AuthCredential value,
  ) async {
    reauths++;
    credential = value;
    if (hold != null) await hold!.future;
    if (failReauth) throw FirebaseAuthException(code: 'wrong-password');
    return Credential(this);
  }

  @override
  Future<void> delete() async {
    deletes++;
    if (failDelete) throw FirebaseAuthException(code: 'requires-recent-login');
    auth.user = null;
    auth.events.add(null);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class Credential implements UserCredential {
  Credential(this.user);
  @override
  final User user;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class Auth implements FirebaseAuth {
  Account? user;
  final events = StreamController<User?>.broadcast();
  @override
  User? get currentUser => user;
  @override
  Stream<User?> authStateChanges() => events.stream;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class GoogleAccount implements GoogleSignInAccount {
  @override
  GoogleSignInAuthentication get authentication =>
      const GoogleSignInAuthentication(idToken: 'token');
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class Google implements GoogleSignIn {
  int initializes = 0, signouts = 0, authentications = 0;
  bool cancel = false, failCleanup = false;
  @override
  Future<void> initialize({
    String? clientId,
    String? serverClientId,
    String? nonce,
    String? hostedDomain,
  }) async {
    initializes++;
  }

  @override
  Future<void> signOut() async {
    signouts++;
    if (failCleanup && signouts > 1) throw StateError('cleanup');
  }

  @override
  Future<GoogleSignInAccount> authenticate({
    List<String> scopeHint = const [],
  }) async {
    authentications++;
    if (cancel) {
      throw const GoogleSignInException(
        code: GoogleSignInExceptionCode.canceled,
      );
    }
    return GoogleAccount();
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class Db implements FirebaseFirestore {
  final paths = <String>{};
  final deleted = <String>[];
  final sizes = <int>[];
  String? failCollection;
  bool failCommit = false;
  bool failRootDelete = false;
  int reads = 0;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      Collection(this, path);
  @override
  WriteBatch batch() => Batch(this);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class Doc implements DocumentReference<Map<String, dynamic>> {
  Doc(this.db, this.path);
  final Db db;
  @override
  final String path;
  @override
  CollectionReference<Map<String, dynamic>> collection(String name) =>
      Collection(db, '$path/$name');
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async {
    expect(options?.source, Source.server);
    return RootSnapshot(db.paths.contains(path));
  }

  @override
  Future<void> delete() async {
    if (path == 'users/owner' && db.failRootDelete) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
    }
    db.paths.remove(path);
    db.deleted.add(path);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class RootSnapshot implements DocumentSnapshot<Map<String, dynamic>> {
  RootSnapshot(this.exists);
  @override
  final bool exists;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class Collection implements CollectionReference<Map<String, dynamic>> {
  Collection(this.db, this.path, [this.cap = 200]);
  final Db db;
  @override
  final String path;
  final int cap;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? id]) =>
      Doc(db, '$path/$id');
  @override
  Query<Map<String, dynamic>> limit(int value) => Collection(db, path, value);
  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    expect(options?.source, Source.server);
    db.reads++;
    if (db.failCollection == path) {
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    }
    return Snapshot(
      db.paths
          .where(
            (p) =>
                p.startsWith('$path/') &&
                !p.substring(path.length + 1).contains('/'),
          )
          .take(cap)
          .map((p) => SnapshotDoc(Doc(db, p)))
          .toList(),
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class Snapshot implements QuerySnapshot<Map<String, dynamic>> {
  Snapshot(this.docs);
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class SnapshotDoc implements QueryDocumentSnapshot<Map<String, dynamic>> {
  SnapshotDoc(this.reference);
  @override
  final DocumentReference<Map<String, dynamic>> reference;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class Batch implements WriteBatch {
  Batch(this.db);
  final Db db;
  final pending = <DocumentReference>[];
  @override
  void delete(DocumentReference reference) {
    pending.add(reference);
  }

  @override
  Future<void> commit() async {
    if (db.failCommit) throw StateError('commit failed');
    db.sizes.add(pending.length);
    for (final doc in pending) {
      await doc.delete();
    }
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class Fixture {
  Fixture([List<String> providers = const ['password']]) {
    user = Account(auth, providers);
    auth.user = user;
    db.paths.addAll([
      'users/owner',
      'users/owner/recipes/r',
      'users/owner/shopping/s',
      'users/other/recipes/r',
      'ingredients/salt',
    ]);
    repo = AccountDeletionRepository(
      firebaseAuth: auth,
      firestore: db,
      googleSignIn: google,
    );
    addTearDown(auth.events.close);
  }
  final auth = Auth();
  final db = Db();
  final google = Google();
  late final Account user;
  late final AccountDeletionRepository repo;
}

void main() {
  for (final rootFailure in [false, true]) {
    test(
      'failed ${rootFailure ? "root deletion" : "batch commit"} blocks Auth deletion',
      () async {
        final f = Fixture();
        f.db.failCommit = !rootFailure;
        f.db.failRootDelete = rootFailure;
        await expectLater(
          f.repo.deleteCurrentAccount(password: 'secret'),
          throwsA(anything),
        );
        expect(f.user.deletes, 0);
        f.db.failCommit = false;
        f.db.failRootDelete = false;
        await f.repo.deleteCurrentAccount(password: 'secret');
        expect(f.user.deletes, 1);
      },
    );
  }

  testWidgets(
    'Settings account action removes stale profile route on success',
    (tester) async {
      PackageInfo.setMockInitialValues(
        appName: 'Kuktám',
        packageName: 'com.bronxii.kuktam',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
      );
      final f = Fixture();
      final authRepo = AuthRepository(
        firebaseAuth: f.auth,
        googleSignIn: f.google,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AuthGate(
            authRepository: authRepo,
            mainBuilder: (context) => Scaffold(
              body: TextButton(
                child: const Text('Profile'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SettingsScreen(
                      authRepository: authRepo,
                      deletionRepository: f.repo,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      f.auth.events.add(f.user);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Fiók törlése'));
      await tester.tap(find.text('Fiók törlése'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Fiók törlése'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'secret');
      await tester.tap(find.widgetWithText(FilledButton, 'Fiók törlése'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsNothing);
      expect(find.text('Bejelentkezés e-maillel'), findsOneWidget);
      expect(f.user.deletes, 1);
    },
  );

  test('password reauth failure deletes nothing', () async {
    final f = Fixture();
    f.user.failReauth = true;
    await expectLater(
      f.repo.deleteCurrentAccount(password: 'wrong'),
      throwsA(isA<FirebaseAuthException>()),
    );
    expect(f.db.reads, 0);
    expect(f.user.deletes, 0);
  });
  test(
    'all owned data, root, and auth deleted; password not trimmed; other owners safe',
    () async {
      final f = Fixture();
      await f.repo.deleteCurrentAccount(password: ' secret ');
      expect((f.user.credential as EmailAuthCredential).password, ' secret ');
      expect(f.db.paths, {'users/other/recipes/r', 'ingredients/salt'});
      expect(f.db.deleted.last, 'users/owner');
      expect(f.user.deletes, 1);
      expect(f.auth.currentUser, isNull);
    },
  );
  test('pagination supports more than one batch with no skips', () async {
    final f = Fixture();
    f.db.paths.addAll(List.generate(605, (i) => 'users/owner/recipes/$i'));
    await f.repo.deleteCurrentAccount(password: 'secret');
    expect(f.db.sizes, [200, 200, 200, 6, 1]);
    expect(f.db.paths.any((p) => p.startsWith('users/owner')), isFalse);
  });
  test('Google cancellation leaves Firebase session/data intact', () async {
    final f = Fixture(['google.com']);
    f.google.cancel = true;
    await expectLater(
      f.repo.deleteCurrentAccount(),
      throwsA(isA<GoogleSignInException>()),
    );
    expect(f.db.reads, 0);
    expect(f.user.deletes, 0);
    expect(f.auth.currentUser, f.user);
  });
  test('Google reauth and best-effort cleanup; no Firebase sign-in', () async {
    final f = Fixture(['google.com']);
    f.google.failCleanup = true;
    await f.repo.deleteCurrentAccount();
    expect(f.user.credential?.providerId, 'google.com');
    expect(f.user.deletes, 1);
    expect(f.google.initializes, 1);
    expect(f.google.signouts, 2);
    expect(f.auth.currentUser, isNull);
  });
  test('multiple providers choose password deterministically', () async {
    final f = Fixture(['google.com', 'password']);
    await f.repo.deleteCurrentAccount(password: 'secret');
    expect(f.user.credential?.providerId, 'password');
    expect(f.google.authentications, 0);
  });
  test('partial failure prevents Auth delete and permits retry', () async {
    final f = Fixture();
    f.db.failCollection = 'users/owner/shopping';
    await expectLater(
      f.repo.deleteCurrentAccount(password: 'secret'),
      throwsA(isA<FirebaseException>()),
    );
    expect(f.db.paths.contains('users/owner/recipes/r'), isFalse);
    expect(f.db.paths.contains('users/owner/shopping/s'), isTrue);
    expect(f.user.deletes, 0);
    f.db.failCollection = null;
    await f.repo.deleteCurrentAccount(password: 'secret');
    expect(f.user.deletes, 1);
  });
  test(
    'Auth delete failure is not success; retry on empty data works',
    () async {
      final f = Fixture();
      f.user.failDelete = true;
      await expectLater(
        f.repo.deleteCurrentAccount(password: 'secret'),
        throwsA(isA<FirebaseAuthException>()),
      );
      expect(f.auth.currentUser, f.user);
      expect(f.db.paths.contains('users/owner'), isFalse);
      f.user.failDelete = false;
      await f.repo.deleteCurrentAccount(password: 'secret');
      expect(f.auth.currentUser, isNull);
    },
  );
  test('duplicate deletion and changed auth identity are rejected', () async {
    final f = Fixture();
    f.user.hold = Completer<void>();
    final first = f.repo.deleteCurrentAccount(password: 'secret');
    await expectLater(
      f.repo.deleteCurrentAccount(password: 'secret'),
      throwsStateError,
    );
    f.auth.user = null;
    f.user.hold!.complete();
    await expectLater(first, throwsStateError);
    expect(f.db.reads, 0);
  });

  Future<void> open(WidgetTester tester, Fixture f) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AuthGate(
          authRepository: AuthRepository(
            firebaseAuth: f.auth,
            googleSignIn: f.google,
          ),
          mainBuilder: (context) => Scaffold(
            body: TextButton(
              child: const Text('Open account'),
              onPressed: () async {
                await showDialog<bool>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => AccountDeletionDialog(repository: f.repo),
                );
              },
            ),
          ),
        ),
      ),
    );
    f.auth.events.add(f.user);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open account'));
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Fiók törlése'));
    await tester.pumpAndSettle();
  }

  testWidgets('cancel first confirmation causes no reauth or deletion', (
    tester,
  ) async {
    final f = Fixture();
    await open(tester, f);
    await tester.tap(find.text('Mégse'));
    await tester.pumpAndSettle();
    expect(f.user.reauths, 0);
    expect(f.db.reads, 0);
  });
  testWidgets(
    'password error retains dialog and retry; successful delete shows AuthGate login',
    (tester) async {
      final f = Fixture();
      f.user.failReauth = true;
      await open(tester, f);
      await confirm(tester);
      await tester.enterText(find.byType(TextField), ' secret ');
      await confirm(tester);
      expect(
        find.textContaining('Az újrahitelesítés nem sikerült'),
        findsOneWidget,
      );
      expect(f.db.reads, 0);
      expect(find.byType(AccountDeletionDialog), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        ' secret ',
      );
      f.user.failReauth = false;
      await confirm(tester);
      expect(find.byType(AccountDeletionDialog), findsNothing);
      expect(find.text('Bejelentkezés e-maillel'), findsOneWidget);
      expect(f.user.deletes, 1);
    },
  );
  testWidgets('busy blocks repeated submit, barrier and system back', (
    tester,
  ) async {
    final f = Fixture();
    f.user.hold = Completer<void>();
    await open(tester, f);
    await confirm(tester);
    await tester.enterText(find.byType(TextField), 'secret');
    await tester.tap(find.widgetWithText(FilledButton, 'Fiók törlése'));
    await tester.tap(find.widgetWithText(FilledButton, 'Fiók törlése'));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.tapAt(const Offset(2, 2));
    await tester.pump();
    expect(f.user.reauths, 1);
    expect(find.byType(AccountDeletionDialog), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    f.user.hold!.complete();
    await tester.pumpAndSettle();
    expect(f.user.deletes, 1);
  });
  testWidgets(
    'Auth failure is visible; Google cancellation message and no deletion',
    (tester) async {
      final f = Fixture(['google.com']);
      f.google.cancel = true;
      await open(tester, f);
      await confirm(tester);
      await confirm(tester);
      expect(
        find.textContaining('A Google-hitelesítést megszakítottad'),
        findsOneWidget,
      );
      expect(f.db.reads, 0);
      f.google.cancel = false;
      f.user.failDelete = true;
      await confirm(tester);
      expect(
        find.textContaining('A fióktörlés nem fejeződött be'),
        findsOneWidget,
      );
      expect(find.byType(AccountDeletionDialog), findsOneWidget);
      f.user.failDelete = false;
      await confirm(tester);
      expect(find.text('Bejelentkezés e-maillel'), findsOneWidget);
    },
  );
}
