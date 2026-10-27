import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/family/callable_family_repository.dart';
import 'package:kuktam/family/family_mutation.dart';
import 'package:kuktam/family/family_screen.dart';
import 'package:kuktam/family/family_state.dart';
import 'package:kuktam/pro/monetization_host.dart';
import 'package:kuktam/pro/pro_controller.dart';
import 'fakes.dart';
import 'family_screen_test.dart' show Repo;
import 'family_test.dart' show response;

class Pro extends ChangeNotifier implements ProController {
  Pro(this.isPro);
  @override
  final bool isPro;
  @override
  bool get checking => false;
  @override
  String get statusLabel => 'Pro';
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected Pro call');
}

class Mutations extends Repo {
  int creates = 0, invites = 0;
  Future<FamilyCreation> Function() create = () async =>
      FamilyCreation.complete;
  Future<FamilyInviteResult> Function() invite = () async =>
      FamilyInviteResult(code: 'A' * 43, expiresAt: DateTime(2027));
  @override
  Future<FamilyCreation> createFamily() {
    creates++;
    return create();
  }

  @override
  Future<FamilyInviteResult> createInvite() {
    invites++;
    return invite();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Map<String, Object?> inviteResponse() => {
    'schemaVersion': 1,
    'inviteId': 'a' * 64,
    'token': 'A' * 43,
    'expiresAt': 1800000000000,
  };
  test(
    '7B exact callable names, empty payload, strict responses and no retries',
    () async {
      final auth = TestAuth(), functions = Functions();
      addTearDown(auth.events.close);
      final repo = CallableFamilyRepository(auth: auth, functions: functions);
      functions.callable.reply = () async => {
        'schemaVersion': 1,
        'operationId': 'create_${'a' * 64}',
        'outcome': 'DONE',
      };
      expect(await repo.createFamily(), FamilyCreation.complete);
      functions.callable.reply = () async => inviteResponse();
      expect((await repo.createInvite()).code, 'A' * 43);
      expect(functions.names, ['createFamilyShare', 'createFamilyInvite']);
      expect(functions.callable.sent, [{}, {}]);
      functions.callable.reply = () async => {
        'schemaVersion': 1,
        'operationId': 'create_${'a' * 64}',
        'outcome': 'COPY',
      };
      expect(await repo.createFamily(), FamilyCreation.inProgress);
      functions.callable.reply = () async => {'token': 'secret'};
      await expectLater(
        repo.createInvite(),
        throwsA(isA<FamilyMutationException>()),
      );
      expect(functions.names.length, 4);
      expect(auth.events.hasListener, false);
    },
  );
  for (final entry in {
    'proRequired': FamilyMutationFailure.proRequired,
    'OWNER_NOT_PRO': FamilyMutationFailure.proRequired,
    'alreadyFamily': FamilyMutationFailure.alreadyFamily,
    'IN_PROGRESS': FamilyMutationFailure.inProgress,
    'accountUnavailable': FamilyMutationFailure.accountUnavailable,
    'FAMILY_FULL': FamilyMutationFailure.capacity,
    'PENDING_LIMIT': FamilyMutationFailure.pendingLimit,
    'NOT_OWNER': FamilyMutationFailure.notOwner,
    'raw secret backend error': FamilyMutationFailure.unavailable,
  }.entries) {
    test('7B safe error ${entry.key}', () async {
      final auth = TestAuth(), functions = Functions();
      addTearDown(auth.events.close);
      functions.callable.reply = () async => throw FirebaseFunctionsException(
        code: 'failed-precondition',
        message: entry.key,
      );
      await expectLater(
        CallableFamilyRepository(
          auth: auth,
          functions: functions,
        ).createInvite(),
        throwsA(
          isA<FamilyMutationException>().having(
            (e) => e.reason,
            'reason',
            entry.value,
          ),
        ),
      );
      expect(functions.names.length, 1);
    });
  }
  test('7B mutation response discarded after auth ABA', () async {
    final auth = TestAuth(),
        functions = Functions(),
        barrier = Completer<Object?>();
    addTearDown(auth.events.close);
    functions.callable.reply = () => barrier.future;
    final future = CallableFamilyRepository(
      auth: auth,
      functions: functions,
    ).createInvite();
    auth.switchTo('b');
    auth.switchTo('a');
    barrier.complete(inviteResponse());
    await expectLater(
      future,
      throwsA(
        isA<FamilyMutationException>().having(
          (e) => e.reason,
          'reason',
          FamilyMutationFailure.signedOut,
        ),
      ),
    );
  });
  test('7B pending inventory parsed bounded and owner-only', () {
    final raw = response()
      ..['invites'] = [
        {'status': 'PENDING', 'expiresAt': 1800000000000},
      ];
    expect(FamilyState.fromResponse(raw, 'a').pendingInvites.length, 1);
    raw['invites'] = [
      {'status': 'USED', 'expiresAt': 1800000000000},
    ];
    expect(
      () => FamilyState.fromResponse(raw, 'a'),
      throwsA(isA<FamilyReadException>()),
    );
  });
  Future<void> show(WidgetTester t, Mutations repo, {bool pro = true}) async {
    final controller = Pro(pro);
    addTearDown(controller.dispose);
    addTearDown(repo.events.close);
    await t.pumpWidget(
      ProScope(
        controller: controller,
        child: MaterialApp(home: FamilyScreen(repository: repo)),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets(
    '7B Pro create confirmation busy double tap authoritative refresh',
    (t) async {
      final repo = Mutations(), barrier = Completer<FamilyCreation>();
      repo.create = () => barrier.future;
      await show(t, repo);
      await t.tap(find.text('Család létrehozása'));
      await t.pump(const Duration(milliseconds: 250));
      expect(repo.creates, 0);
      expect(find.byType(AlertDialog), findsOneWidget);
      await t.tap(find.text('Létrehozás'));
      await t.pump();
      await t.tap(find.text('Család létrehozása'));
      await t.pump();
      expect(repo.creates, 1);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      repo.reply = () async =>
          FamilyState.fromResponse(response(count: 1), 'a');
      barrier.complete(FamilyCreation.complete);
      await t.pumpAndSettle();
      expect(find.text('Aktív család'), findsOneWidget);
      expect(find.text('Család létrehozása'), findsNothing);
      expect(repo.calls, 2);
      expect(find.text('Tag meghívása'), findsOneWidget);
    },
  );
  testWidgets('7B non Pro locked no create and existing Pro entry', (t) async {
    final repo = Mutations();
    await show(t, repo, pro: false);
    expect(find.text('Család létrehozása'), findsNothing);
    expect(find.text('Pro megtekintése'), findsOneWidget);
    expect(repo.creates, 0);
  });
  testWidgets('7B create cancel and backend error retains retry', (t) async {
    final repo = Mutations()
      ..create = () async => throw const FamilyMutationException(
        FamilyMutationFailure.proRequired,
      );
    await show(t, repo);
    await t.tap(find.text('Család létrehozása'));
    await t.pump(const Duration(milliseconds: 250));
    await t.tap(find.text('Mégse'));
    await t.pumpAndSettle();
    expect(repo.creates, 0);
    await t.tap(find.text('Család létrehozása'));
    await t.pump(const Duration(milliseconds: 250));
    await t.tap(find.text('Létrehozás'));
    await t.pumpAndSettle();
    expect(
      find.text(
        const FamilyMutationException(
          FamilyMutationFailure.proRequired,
        ).message,
      ),
      findsOneWidget,
    );
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(repo.calls, 1);
  });
  testWidgets('7B invite no email busy duplicate guard result and clipboard', (
    t,
  ) async {
    final repo = Mutations()
      ..reply = () async => FamilyState.fromResponse(response(), 'a');
    final barrier = Completer<FamilyInviteResult>();
    repo.invite = () => barrier.future;
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await show(t, repo);
    expect(find.byType(TextField), findsNothing);
    await t.tap(find.text('Tag meghívása'));
    await t.pump();
    await t.tap(find.text('Tag meghívása'));
    await t.pump();
    expect(repo.invites, 1);
    barrier.complete(
      FamilyInviteResult(code: 'A' * 43, expiresAt: DateTime(2027)),
    );
    await t.pumpAndSettle();
    expect(find.text('Meghívó elkészült'), findsOneWidget);
    expect(repo.calls, 2);
    await t.ensureVisible(find.text('Kód másolása'));
    await t.tap(find.text('Kód másolása'));
    await t.pumpAndSettle();
    expect(copied, 'A' * 43);
  });
  for (final reason in [
    FamilyMutationFailure.capacity,
    FamilyMutationFailure.notOwner,
    FamilyMutationFailure.proRequired,
    FamilyMutationFailure.unavailable,
  ]) {
    testWidgets('7B invite safe error $reason and retry', (t) async {
      final repo = Mutations()
        ..reply = () async => FamilyState.fromResponse(response(), 'a');
      repo.invite = () async => throw FamilyMutationException(reason);
      await show(t, repo);
      await t.tap(find.text('Tag meghívása'));
      await t.pumpAndSettle();
      expect(
        find.text(FamilyMutationException(reason).message),
        findsOneWidget,
      );
      expect(find.text('Meghívó elkészült'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(repo.invites, 1);
      await t.ensureVisible(find.text('Tag meghívása'));
      await t.tap(find.text('Tag meghívása'));
      await t.pumpAndSettle();
      expect(repo.invites, 2);
    });
  }
  for (final mode in ['member', 'progress', 'full']) {
    testWidgets('7B $mode blocks mutations', (t) async {
      final repo = Mutations()
        ..reply = () async => mode == 'progress'
            ? FamilyState.inProgress('a')
            : FamilyState.fromResponse(
                response(
                  role: mode == 'member' ? 'member' : 'owner',
                  count: mode == 'full' ? 8 : 2,
                ),
                mode == 'member' ? 'm1' : 'a',
              );
      await show(t, repo);
      expect(find.text('Család létrehozása'), findsNothing);
      if (mode == 'full') {
        expect(
          t
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Tag meghívása'),
              )
              .onPressed,
          isNull,
        );
      } else {
        expect(find.text('Tag meghívása'), findsNothing);
      }
      expect(repo.creates + repo.invites, 0);
    });
  }

  test('7B anonymous cannot invoke mutations', () async {
    final auth = TestAuth()..currentUser = null, functions = Functions();
    addTearDown(auth.events.close);
    final repo = CallableFamilyRepository(auth: auth, functions: functions);
    await expectLater(
      repo.createFamily(),
      throwsA(isA<FamilyMutationException>()),
    );
    await expectLater(
      repo.createInvite(),
      throwsA(isA<FamilyMutationException>()),
    );
    expect(functions.names, isEmpty);
  });
  test('7B invalid invite response fails closed', () {
    for (final change in [
      {'schemaVersion': 2},
      {'inviteId': 'bad'},
      {'token': 'bad'},
      {'expiresAt': -1},
    ]) {
      expect(
        () => FamilyInviteResult.fromResponse({...inviteResponse(), ...change}),
        throwsA(isA<FamilyMutationException>()),
      );
    }
  });
  testWidgets('7B incomplete creation refreshes to progress not fake owner', (
    t,
  ) async {
    final repo = Mutations();
    repo.create = () async {
      repo.reply = () async => FamilyState.inProgress('a');
      return FamilyCreation.inProgress;
    };
    await show(t, repo);
    await t.tap(find.text('Család létrehozása'));
    await t.pump(const Duration(milliseconds: 250));
    await t.tap(find.text('Létrehozás'));
    await t.pumpAndSettle();
    expect(find.text('Folyamatban lévő családi művelet'), findsOneWidget);
    expect(find.text('Tag meghívása'), findsNothing);
    expect(repo.calls, 2);
  });
  testWidgets('7B session change discards late invite and blocks all actions', (
    t,
  ) async {
    final repo = Mutations()
      ..reply = () async => FamilyState.fromResponse(response(), 'a');
    final barrier = Completer<FamilyInviteResult>();
    repo.invite = () => barrier.future;
    await show(t, repo);
    await t.tap(find.text('Tag meghívása'));
    await t.pump();
    repo.events.add(null);
    barrier.complete(
      FamilyInviteResult(code: 'A' * 43, expiresAt: DateTime(2027)),
    );
    await t.pumpAndSettle();
    expect(
      find.text('A bejelentkezés megváltozott. Nyisd meg újra ezt az oldalt.'),
      findsOneWidget,
    );
    expect(find.text('Kód másolása'), findsNothing);
    expect(repo.calls, 1);
  });
  testWidgets('7B pending invites read-only and small screen', (t) async {
    t.view.physicalSize = const Size(360, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final raw = response()
      ..['invites'] = [
        {'status': 'PENDING', 'expiresAt': 1800000000000},
      ];
    final repo = Mutations()
      ..reply = () async => FamilyState.fromResponse(raw, 'a');
    await show(t, repo);
    expect(find.text('Függő meghívó'), findsOneWidget);
    await t.drag(find.byType(ListView), const Offset(0, -300));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(repo.calls, 1);
    expect(repo.invites, 0);
  });
}
