import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:kuktam/family/family_invite_link.dart';
import 'package:kuktam/family/family_link_host.dart';
import 'package:kuktam/family/pending_family_invite.dart';
import 'package:kuktam/family/family_join.dart';
import 'package:kuktam/features/auth/data/repositories/auth_repository.dart';
import 'package:kuktam/features/auth/presentation/widgets/auth_gate.dart';
import 'package:kuktam/sharing/text_share_controller.dart';
import 'family_join_test.dart' show JoinRepo, code;
import '../auth/email_verification_test.dart' show TestUser;
import 'pending_invite_fake.dart';

String link(String token) =>
    'https://kuktam-67768.web.app/family/invite?token=$token';

class SecureMemory implements FlutterSecureStorage {
  String? value;
  String? savedKey;
  @override
  Future<String?> read({
    required String key,
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic webOptions,
    dynamic mOptions,
    dynamic wOptions,
  }) async => value;
  @override
  Future<void> write({
    required String key,
    required String? value,
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic webOptions,
    dynamic mOptions,
    dynamic wOptions,
  }) async {
    this.value = value;
    savedKey = key;
  }

  @override
  Future<void> delete({
    required String key,
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic webOptions,
    dynamic mOptions,
    dynamic wOptions,
  }) async {
    value = null;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class AuthEvents implements AuthRepository {
  final events = StreamController<User?>.broadcast(sync: true);
  @override
  User? currentUser;
  void emit(User? u) {
    currentUser = u;
    events.add(u);
  }

  @override
  Stream<User?> authStateChanges() => events.stream;
  @override
  Future<void> signOutUnverifiedSession() async {
    emit(null);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    '8C encrypted adapter stores only version and exact token then flushes',
    () async {
      final memory = SecureMemory();
      var flushes = 0;
      final store = SecurePendingFamilyInviteStore(
        storage: memory,
        flush: () async {
          flushes++;
        },
      );
      await store.write(code);
      expect(memory.savedKey, 'pending_invite_v1');
      expect(jsonDecode(memory.value!), {'version': 1, 'token': code});
      expect(await store.read(), code);
      await store.clear();
      expect(memory.value, isNull);
      expect(flushes, 2);
    },
  );
  test(
    '8C corrupt stored payload cleared without exposing credential',
    () async {
      final memory = SecureMemory()..value = '{bad';
      final store = SecurePendingFamilyInviteStore(
        storage: memory,
        flush: () async {},
      );
      await expectLater(store.read(), throwsFormatException);
      expect(memory.value, isNull);
    },
  );
  test(
    '8C duplicate A then B is single latest pending intent; no pre-auth open',
    () async {
      final store = MemoryPendingInviteStore();
      var opens = 0;
      final r = FamilyLinkRouter(
        currentUid: () => null,
        canNavigate: () => true,
        open: (_) async {
          opens++;
        },
        notice: (_) {},
        pendingStore: store,
      );
      await r.restore();
      await r.receive(link(code));
      await r.receive(link(code));
      expect(store.writes, 1);
      final b = '${'B' * 42}A';
      await r.receive(link(b));
      expect(store.value, b);
      expect(store.writes, 2);
      expect(opens, 0);
      r.dispose();
    },
  );
  test(
    '8C process recreation and usable auth handoff once; no UID persisted',
    () async {
      final store = MemoryPendingInviteStore();
      String? uid;
      final tokens = <String>[];
      FamilyLinkRouter create() => FamilyLinkRouter(
        currentUid: () => uid,
        canNavigate: () => true,
        open: (v) async {
          tokens.add(v);
        },
        notice: (_) {},
        pendingStore: store,
      );
      var r = create();
      await r.restore();
      await r.receive(link(code));
      r.dispose();
      r = create();
      await r.restore();
      await r.resume();
      expect(tokens, isEmpty);
      uid = 'eventually-authenticated-account';
      await r.resume();
      await r.resume();
      expect(tokens, [code]);
      expect(store.value, isNull);
      uid = null;
      await r.resume();
      uid = 'another-account';
      await r.resume();
      expect(tokens, [code]);
      r.dispose();
    },
  );
  test(
    '8C cancelled or failed login retains token; explicit local dismiss clears',
    () async {
      final store = MemoryPendingInviteStore();
      var opens = 0;
      final r = FamilyLinkRouter(
        currentUid: () => null,
        canNavigate: () => true,
        open: (_) async {
          opens++;
        },
        notice: (_) {},
        pendingStore: store,
      );
      await r.receive(link(code));
      await r.resume();
      await r.resume();
      expect(store.value, code);
      await r.cancelPending();
      expect(store.value, isNull);
      expect(opens, 0);
      r.dispose();
    },
  );
  test('8C authenticated direct link makes no persistence write', () async {
    final store = MemoryPendingInviteStore();
    var opens = 0;
    final r = FamilyLinkRouter(
      currentUid: () => 'u',
      canNavigate: () => true,
      open: (_) async {
        opens++;
      },
      notice: (_) {},
      pendingStore: store,
    );
    await r.restore();
    await r.receive(link(code));
    expect(opens, 1);
    expect(store.writes, 0);
    expect(store.clears, 0);
    r.dispose();
  });
  test('8C delete failure blocks ownership and retries safely', () async {
    final store = MemoryPendingInviteStore()
      ..value = code
      ..failClear = true;
    var opens = 0;
    final r = FamilyLinkRouter(
      currentUid: () => 'u',
      canNavigate: () => true,
      open: (_) async {
        opens++;
      },
      notice: (_) {},
      pendingStore: store,
    );
    await r.restore();
    await r.resume();
    expect(opens, 0);
    expect(store.value, code);
    expect(r.storageError, isNotNull);
    store.failClear = false;
    await r.restore();
    await r.resume();
    expect(opens, 1);
    expect(store.value, isNull);
    r.dispose();
  });
  test(
    '8C login dialog blocks resume until normal navigation returns',
    () async {
      final store = MemoryPendingInviteStore()..value = code;
      var canNavigate = false;
      var opens = 0;
      final r = FamilyLinkRouter(
        currentUid: () => 'u',
        canNavigate: () => canNavigate,
        open: (_) async {
          opens++;
        },
        notice: (_) {},
        pendingStore: store,
      );
      await r.restore();
      await r.resume();
      expect(store.value, code);
      expect(opens, 0);
      canNavigate = true;
      await r.resume();
      expect(opens, 1);
      r.dispose();
    },
  );
  test('8C failed replacement does not silently auto-open old A', () async {
    final store = MemoryPendingInviteStore();
    String? uid;
    var opens = 0;
    final r = FamilyLinkRouter(
      currentUid: () => uid,
      canNavigate: () => true,
      open: (_) async {
        opens++;
      },
      notice: (_) {},
      pendingStore: store,
    );
    await r.receive(link(code));
    store.failWrite = true;
    await r.receive(link('${'B' * 42}A'));
    uid = 'u';
    await r.resume();
    expect(opens, 0);
    expect(r.storageError, isNotNull);
    r.dispose();
  });

  const channel = MethodChannel('kuktam/family_links');
  Future<void> pending() async {
    final done = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('pending'),
          ),
          (_) => done.complete(),
        );
    await done.future;
  }

  Future<void> mount(
    WidgetTester t,
    AuthEvents auth,
    JoinRepo repo,
    MemoryPendingInviteStore store,
    List<String> inbox,
  ) async {
    final nav = GlobalKey<NavigatorState>();
    final messenger = GlobalKey<ScaffoldMessengerState>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => inbox.isEmpty ? null : inbox.removeAt(0),
        );
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await auth.events.close();
      await repo.events.close();
    });
    await t.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        scaffoldMessengerKey: messenger,
        navigatorObservers: [textShareNavigation],
        builder: (_, child) => FamilyLinkHost(
          navigator: nav,
          messenger: messenger,
          currentUid: () => auth.currentUser?.uid,
          pendingStore: store,
          repository: repo,
          child: child!,
        ),
        home: AuthGate(
          authRepository: auth,
          mainBuilder: (_) => const Scaffold(body: Text('Admitted')),
        ),
      ),
    );
    await t.pump();
    auth.emit(null);
    await t.pumpAndSettle();
  }

  for (final method in ['email', 'google', 'registration']) {
    for (final cold in [true, false]) {
      testWidgets(
        '8C $method ${cold ? 'cold' : 'warm'} normal auth gate resumes exactly once',
        (t) async {
          final auth = AuthEvents();
          final repo = JoinRepo();
          final store = MemoryPendingInviteStore();
          final inbox = <String>[if (cold) link(code)];
          await mount(t, auth, repo, store, inbox);
          if (!cold) {
            inbox.add(link(code));
            await pending();
            await t.pumpAndSettle();
          }
          expect(store.value, code);
          expect(repo.actions, isEmpty);
          if (method != 'google') {
            auth.emit(TestUser(false, ['password']));
            await t.pumpAndSettle();
            expect(repo.actions, isEmpty);
            expect(store.value, code);
            auth.emit(null);
            await t.pumpAndSettle();
          }
          auth.emit(
            TestUser(true, [method == 'google' ? 'google.com' : 'password']),
          );
          await t.pumpAndSettle();
          expect(repo.actions, ['preview']);
          expect(repo.tokens, [code]);
          expect(store.value, isNull);
          inbox.add(link(code));
          await pending();
          await t.pumpAndSettle();
          expect(repo.actions, ['preview']);
        },
      );
    }
  }
  testWidgets('8C pending banner cancel does not call Family backend', (
    t,
  ) async {
    final auth = AuthEvents();
    final repo = JoinRepo();
    final store = MemoryPendingInviteStore();
    await mount(t, auth, repo, store, [link(code)]);
    await t.tap(find.text('Meghívó elvetése'));
    await t.pumpAndSettle();
    expect(store.value, isNull);
    auth.emit(TestUser(true, ['google.com']));
    await t.pumpAndSettle();
    expect(repo.actions, isEmpty);
  });
  for (final error in [
    'NOT_FOUND',
    'EXPIRED',
    'USED',
    'REVOKED',
    'UNAVAILABLE',
  ]) {
    testWidgets('8C $error uses existing error UX after route ownership', (
      t,
    ) async {
      final auth = AuthEvents();
      final repo = JoinRepo();
      final store = MemoryPendingInviteStore();
      repo.preview = () async {
        throw FamilyJoinException(error);
      };
      await mount(t, auth, repo, store, [link(code)]);
      auth.emit(TestUser(true, ['google.com']));
      await t.pumpAndSettle();
      expect(repo.actions, ['preview']);
      expect(store.value, isNull);
      expect(find.text(FamilyJoinException(error).message), findsOneWidget);
      if (error == 'UNAVAILABLE') {
        repo.preview = () async => FamilyInvitePreview(null, DateTime(2027), 0);
        await t.tap(find.text('Meghívó ellenőrzése'));
        await t.pumpAndSettle();
        expect(repo.tokens, [code, code]);
      }
    });
  }
  test('8C failed B replacement retry saves B, never resurrects A', () async {
    final store = MemoryPendingInviteStore();
    String? uid;
    final opened = <String>[];
    final r = FamilyLinkRouter(
      currentUid: () => uid,
      canNavigate: () => true,
      open: (v) async {
        opened.add(v);
      },
      notice: (_) {},
      pendingStore: store,
    );
    await r.receive(link(code));
    store.failWrite = true;
    final b = '${'B' * 42}A';
    await r.receive(link(b));
    uid = 'u';
    await r.resume();
    expect(opened, isEmpty);
    store.failWrite = false;
    await r.retryPending();
    await r.resume();
    expect(opened, [b]);
    expect(store.value, isNull);
    r.dispose();
  });
  testWidgets(
    '8C restored pending at app recreation resumes through normal auth gate',
    (t) async {
      final auth = AuthEvents();
      final repo = JoinRepo();
      final store = MemoryPendingInviteStore()..value = code;
      await mount(t, auth, repo, store, []);
      expect(repo.actions, isEmpty);
      expect(find.text('Meghívó elvetése'), findsOneWidget);
      auth.emit(TestUser(true, ['google.com']));
      await t.pumpAndSettle();
      expect(repo.tokens, [code]);
      expect(store.value, isNull);
    },
  );
}
