import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/family/family_invite_link.dart';
import 'package:kuktam/family/family_link_host.dart';
import 'package:kuktam/family/family_join_screen.dart';
import 'package:kuktam/family/family_state.dart';
import 'package:kuktam/family/family_join.dart';
import 'family_join_test.dart' show JoinRepo, code;
import 'family_test.dart' show response;

String link(String token) =>
    'https://kuktam-67768.web.app/family/invite?token=$token';
const channel = MethodChannel('kuktam/family_links');
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('8B canonical token round trip exact', () {
    expect(familyInviteToken(link(code)), code);
    final mixed = '${'aB-_' * 10}xyA';
    expect(familyInviteToken(link(mixed)), mixed);
  });
  final invalid = <String>[
    link(code).replaceFirst('https', 'http'),
    link(code).replaceFirst('kuktam-67768.web.app', 'evil.test'),
    link(code).replaceFirst('/family/invite', '/family/other'),
    'https://kuktam-67768.web.app/family/invite',
    'https://kuktam-67768.web.app/family/invite?token=',
    '${link(code)}&token=$code',
    '${link(code)}&code=$code',
    '${link(code)}#fragment',
    'https://[',
    link(code).replaceFirst('.app', '.app:443'),
    link(code).replaceFirst('https://', 'https://user@'),
    link(code).replaceFirst('?token', '/?token'),
    link(code).replaceFirst('token=A', 'token=%41'),
    ' ${link(code)}',
    '${link(code)}\n',
    link('B' * 43),
  ];
  for (var i = 0; i < invalid.length; i++) {
    test('8B invalid variant $i never opens preview', () async {
      var calls = 0;
      final router = FamilyLinkRouter(
        currentUid: () => 'u',
        canNavigate: () => true,
        open: (_) async {
          calls++;
        },
        notice: (_) {},
      );
      expect(familyInviteToken(invalid[i]), isNull);
      await router.receive(invalid[i]);
      expect(calls, 0);
    });
  }
  test('8B bounded dedup and deliberate same invite retry', () async {
    var now = DateTime(2026);
    var calls = 0;
    final router = FamilyLinkRouter(
      currentUid: () => 'u',
      canNavigate: () => true,
      open: (_) async {
        calls++;
      },
      notice: (_) {},
      now: () => now,
    );
    await router.receive(link(code));
    await router.receive(link(code));
    expect(calls, 1);
    now = now.add(const Duration(seconds: 6));
    await router.receive(link(code));
    expect(calls, 2);
  });
  test(
    '8B active route never replaced by duplicate or different token',
    () async {
      final done = Completer<void>();
      var calls = 0;
      final router = FamilyLinkRouter(
        currentUid: () => 'u',
        canNavigate: () => true,
        open: (_) {
          calls++;
          return done.future;
        },
        notice: (_) {},
      );
      final first = router.receive(link(code));
      await router.receive(link(code));
      await router.receive(link('${'B' * 42}A'));
      expect(calls, 1);
      done.complete();
      await first;
    },
  );
  test('8B signed out drops token and does not continue after login', () async {
    String? uid;
    var calls = 0;
    final notices = <String>[];
    final router = FamilyLinkRouter(
      currentUid: () => uid,
      canNavigate: () => true,
      open: (_) async {
        calls++;
      },
      notice: notices.add,
    );
    await router.receive(link(code));
    expect(notices.single, contains('Jelentkezz be'));
    uid = 'u';
    expect(calls, 0);
    await router.receive(link(code));
    expect(calls, 1);
  });

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
    JoinRepo repo,
    List<String> inbox, {
    String? uid = 'm1',
  }) async {
    final nav = GlobalKey<NavigatorState>();
    final messenger = GlobalKey<ScaffoldMessengerState>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'take');
          expect(call.arguments, isNull);
          return inbox.isEmpty ? null : inbox.removeAt(0);
        });
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await repo.events.close();
    });
    await t.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        scaffoldMessengerKey: messenger,
        builder: (_, child) => FamilyLinkHost(
          navigator: nav,
          messenger: messenger,
          currentUid: () => uid,
          repository: repo,
          child: child!,
        ),
        home: const Scaffold(body: Text('Home')),
      ),
    );
    await t.pumpAndSettle();
  }

  for (final cold in [true, false]) {
    testWidgets(
      '8B ${cold ? 'cold' : 'warm'} adapter to existing 7C preview once',
      (t) async {
        final repo = JoinRepo();
        final inbox = <String>[if (cold) link(code)];
        await mount(t, repo, inbox);
        if (!cold) {
          inbox.add(link(code));
          await pending();
          await t.pumpAndSettle();
        }
        expect(find.byType(FamilyJoinScreen), findsOneWidget);
        expect(repo.tokens, [code]);
        expect(repo.actions, ['preview']);
        inbox.add(link(code));
        await pending();
        await t.pumpAndSettle();
        expect(repo.actions, ['preview']);
        inbox.add(link('${'B' * 42}A'));
        await pending();
        await t.pumpAndSettle();
        expect(repo.actions, ['preview']);
        expect(find.byType(FamilyJoinScreen), findsOneWidget);
      },
    );
  }
  testWidgets('8B invalid native event causes zero backend reads/preview', (
    t,
  ) async {
    final repo = JoinRepo();
    await mount(t, repo, [invalid.first]);
    expect(repo.calls, 0);
    expect(repo.actions, isEmpty);
    expect(find.byType(FamilyJoinScreen), findsNothing);
  });
  testWidgets('8B signed-out adapter shows notice without preview', (t) async {
    final repo = JoinRepo();
    await mount(t, repo, [link(code)], uid: null);
    expect(repo.calls, 0);
    expect(repo.actions, isEmpty);
    expect(
      find.text('Jelentkezz be, majd nyisd meg újra a meghívólinket.'),
      findsOneWidget,
    );
  });
  for (final role in ['owner', 'member', 'progress']) {
    testWidgets('8B $role authoritative state blocks new JOIN preview', (
      t,
    ) async {
      final repo = JoinRepo();
      repo.reply = () async => role == 'progress'
          ? FamilyState.inProgress('m1')
          : FamilyState.fromResponse(
              response(role: role),
              role == 'owner' ? 'a' : 'm1',
            );
      await mount(t, repo, [link(code)]);
      expect(repo.calls, 1);
      expect(repo.actions, isEmpty);
      expect(find.byType(FamilyJoinScreen), findsNothing);
    });
  }
  Future<void> tap(WidgetTester t, String label) async {
    await t.ensureVisible(find.text(label));
    await t.tap(find.text(label));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    await t.pump(const Duration(milliseconds: 300));
  }

  testWidgets(
    '8B link ADD committed JOIN rejects second link and completes via 7C',
    (t) async {
      final repo = JoinRepo()..committed = true;
      final inbox = [link(code)];
      await mount(t, repo, inbox);
      await tap(t, 'Saját listám hozzáadása');
      await tap(t, 'Csatlakozás indítása');
      expect(repo.modes, isEmpty);
      await tap(t, 'Hozzáadás és csatlakozás');
      expect(repo.modes, [FamilyJoinMode.add]);
      expect(find.text('Csatlakozás megszakítása'), findsNothing);
      inbox.add(link('${'B' * 42}A'));
      await pending();
      await t.pumpAndSettle();
      expect(repo.actions.where((a) => a == 'preview').length, 1);
      expect(repo.modes.length, 1);
      repo.active = true;
      await tap(t, 'Állapot frissítése');
      expect(find.text('Tag vagy · 2 résztvevő'), findsOneWidget);
    },
  );
  testWidgets('8B link DELETE empty-list second consent still mandatory', (
    t,
  ) async {
    final repo = JoinRepo();
    await mount(t, repo, [link(code)]);
    await tap(t, 'Saját listám eldobása');
    await tap(t, 'Csatlakozás indítása');
    expect(repo.modes, [FamilyJoinMode.delete]);
    expect(repo.actions, isNot(contains('confirm')));
    await tap(t, 'Eldobás megerősítése');
    await tap(t, 'Mégse');
    expect(repo.actions, isNot(contains('confirm')));
    await tap(t, 'Eldobás megerősítése');
    await tap(t, 'Csatlakozás és saját lista eldobása');
    expect(repo.actions.where((a) => a == 'confirm').length, 1);
    repo.active = true;
    await tap(t, 'Állapot frissítése');
    expect(find.text('Tag vagy · 2 résztvevő'), findsOneWidget);
  });
  testWidgets('8B failed initial Family read may retry without losing link', (
    t,
  ) async {
    final repo = JoinRepo();
    final reply = repo.reply;
    repo.reply = () async {
      throw const FamilyReadException(FamilyFailure.network);
    };
    await mount(t, repo, [link(code)]);
    expect(repo.actions, isEmpty);
    repo.reply = reply;
    await tap(t, 'Újrapróbálás');
    expect(repo.tokens, [code]);
  });
}
