import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/family/callable_family_repository.dart';
import 'package:kuktam/family/family_join.dart';
import 'package:kuktam/family/family_mutation.dart';
import 'package:kuktam/family/family_join_screen.dart';
import 'package:kuktam/family/family_screen.dart';
import 'package:kuktam/family/family_state.dart';
import 'fakes.dart';
import 'family_screen_test.dart' show Repo;
import 'family_test.dart' show response;

final code = 'A' * 43;
final handle = FamilyJoinHandle(
  'join_${sha256.convert(utf8.encode('a'))}',
  sha256.convert(utf8.encode(code)).toString(),
  FamilyJoinMode.delete,
);
Map<String, Object?> previewResponse() => {
  'schemaVersion': 1,
  'code': 'VALID',
  'eligible': true,
  'inviteState': 'PENDING',
  'expiresAt': 1800000000000,
  'privateShoppingItemCount': 0,
  'owner': {'email': 'owner@example.test'},
};
Map<String, Object?> progressResponse(
  FamilyJoinHandle h, {
  bool committed = false,
}) => {
  'schemaVersion': 1,
  ...h.request,
  'mode': h.mode.wire,
  'phase': committed
      ? 'COMMITTED_TRANSFER'
      : 'SOURCE_FENCED_WAITING_CONFIRMATION',
  'status': 'READY',
  'committedAt': committed ? 1700000000000 : null,
  'sourceEpoch': 'epoch',
  'snapshotHash': 'b' * 64,
  'sourceItemCount': 0,
  'consentVersion': 1,
};

class JoinRepo extends Repo {
  final actions = <String>[];
  final tokens = <String>[];
  final modes = <FamilyJoinMode>[];
  Future<FamilyInvitePreview> Function() preview = () async =>
      FamilyInvitePreview('owner@example.test', DateTime(2027), 0);
  Future<void> Function()? start;
  FamilyJoinProgress? progress;
  bool committed = false, aborted = false, active = false;
  Future<void> Function()? confirmEffect, cancelEffect;
  JoinRepo() {
    reply = () async => active
        ? FamilyState.fromResponse(response(role: 'member'), 'm1')
        : FamilyState.fromResponse({
            'schemaVersion': 1,
            'familyActive': false,
          }, 'm1');
  }
  @override
  Future<FamilyInvitePreview> previewInvite(String code) async {
    actions.add('preview');
    tokens.add(code);
    return preview();
  }

  @override
  Future<FamilyJoinHandle> startJoin(String code, FamilyJoinMode mode) async {
    actions.add('start');
    tokens.add(code);
    modes.add(mode);
    await start?.call();
    return FamilyJoinHandle(handle.operationId, handle.inviteId, mode);
  }

  FamilyJoinProgress value(FamilyJoinHandle h) =>
      progress ??
      FamilyJoinProgress(
        h,
        committed ? 'COMMITTED_TRANSFER' : 'SOURCE_FENCED_WAITING_CONFIRMATION',
        aborted ? 'ABORTED' : 'READY',
        committed,
        epoch: 'epoch',
        hash: 'b' * 64,
        count: 0,
      );
  @override
  Future<FamilyJoinProgress> prepareJoin(FamilyJoinHandle h) async {
    actions.add('prepare');
    return value(h);
  }

  @override
  Future<FamilyJoinProgress> readJoin(FamilyJoinHandle h) async {
    actions.add('state');
    return value(h);
  }

  @override
  Future<void> confirmJoinDelete(FamilyJoinProgress p) async {
    actions.add('confirm');
    if (confirmEffect != null) {
      await confirmEffect!();
      return;
    }
    expect(p.consent['sourceItemCount'], 0);
    committed = true;
  }

  @override
  Future<void> cancelJoin(FamilyJoinHandle h) async {
    actions.add('cancel');
    if (cancelEffect != null) {
      await cancelEffect!();
      return;
    }
    aborted = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('7C exact callables payloads consent and stable identity', () async {
    final auth = TestAuth(), functions = Functions();
    addTearDown(auth.events.close);
    final repo = CallableFamilyRepository(auth: auth, functions: functions);
    functions.callable.reply = () async => previewResponse();
    await repo.previewInvite('  $code  ');
    expect(functions.callable.sent.last, {'token': code});
    functions.callable.reply = () async => {
      'schemaVersion': 1,
      'operationId': handle.operationId,
      'outcome': 'READY_FOR_TRANSFER',
    };
    final h = await repo.startJoin(code, FamilyJoinMode.delete);
    expect(h.inviteId, handle.inviteId);
    expect(functions.callable.sent.last, {'token': code, 'mode': 'DELETE'});
    functions.callable.reply = () async => progressResponse(h);
    final p = await repo.prepareJoin(h);
    await repo.readJoin(h);
    functions.callable.reply = () async => {
      'schemaVersion': 1,
      'outcome': 'COMMITTED_TRANSFER',
    };
    await repo.confirmJoinDelete(p);
    expect(functions.callable.sent.last, {
      ...h.request,
      'sourceEpoch': 'epoch',
      'snapshotHash': 'b' * 64,
      'sourceItemCount': 0,
      'consentVersion': 1,
    });
    functions.callable.reply = () async => {
      'schemaVersion': 1,
      'outcome': 'ABORTED',
    };
    await repo.cancelJoin(h);
    expect(functions.names, [
      'previewFamilyInvite',
      'acceptFamilyInvite',
      'prepareFamilyJoinTransfer',
      'getFamilyJoinTransferState',
      'confirmFamilyJoinDelete',
      'cancelFamilyJoin',
    ]);
  });
  for (final reason in [
    'NOT_FOUND',
    'EXPIRED',
    'USED',
    'REVOKED',
    'FAMILY_FULL',
    'ALREADY_MEMBER',
    'ALREADY_IN_FAMILY',
    'IN_PROGRESS',
    'ACCOUNT_UNAVAILABLE',
    'OWNER_NOT_PRO',
    'FEATURE_DISABLED',
  ]) {
    test('7C preview maps $reason', () async {
      final auth = TestAuth(), functions = Functions();
      addTearDown(auth.events.close);
      functions.callable.reply = () async => {
        'schemaVersion': 1,
        'code': reason,
        'eligible': false,
      };
      await expectLater(
        CallableFamilyRepository(
          auth: auth,
          functions: functions,
        ).previewInvite(code),
        throwsA(
          isA<FamilyJoinException>().having((e) => e.code, 'code', reason),
        ),
      );
    });
  }
  test('7C raw backend error never in user message', () async {
    final auth = TestAuth(), functions = Functions();
    addTearDown(auth.events.close);
    functions.callable.reply = () async => throw FirebaseFunctionsException(
      code: 'unavailable',
      message: 'SECRET server detail',
    );
    try {
      await CallableFamilyRepository(
        auth: auth,
        functions: functions,
      ).previewInvite(code);
      fail('expected error');
    } on FamilyJoinException catch (e) {
      expect(e.message, isNot(contains('SECRET')));
    }
  });
  test('7C malformed progress cannot expose consent or cancellation', () {
    for (final patch in [
      {'operationId': 'other'},
      {'sourceItemCount': -1},
      {'snapshotHash': 'bad'},
      {'phase': 'COMMITTED_TRANSFER'},
      {'mode': 'ADD'},
    ]) {
      expect(
        () => FamilyJoinProgress.parse({
          ...progressResponse(handle),
          ...patch,
        }, handle),
        throwsA(isA<FamilyJoinException>()),
      );
    }
    final p = FamilyJoinProgress.parse(
      progressResponse(handle, committed: true),
      handle,
    );
    expect(p.canCancel, false);
    expect(p.needsConsent, false);
  });
  Future<void> open(WidgetTester t, JoinRepo repo) async {
    addTearDown(repo.events.close);
    await t.pumpWidget(MaterialApp(home: FamilyScreen(repository: repo)));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Meghívókód megadása'));
    await t.tap(find.text('Meghívókód megadása'));
    await t.pumpAndSettle();
  }

  Future<void> tap(WidgetTester t, String label, {bool settle = true}) async {
    await t.ensureVisible(find.text(label));
    await t.tap(find.text(label));
    if (settle) {
      await t.pumpAndSettle();
    } else {
      await t.pump(const Duration(milliseconds: 250));
    }
  }

  Future<void> preview(WidgetTester t, JoinRepo r) async {
    await open(t, r);
    await t.enterText(find.byType(TextField), '  $code  ');
    await tap(t, 'Meghívó ellenőrzése');
  }

  testWidgets('7C Free entry validation trim and preview no default choice', (
    t,
  ) async {
    final r = JoinRepo();
    await open(t, r);
    expect(find.byType(FamilyJoinScreen), findsOneWidget);
    await tap(t, 'Meghívó ellenőrzése');
    expect(r.actions, isEmpty);
    expect(find.text('Adj meg egy érvényes meghívókódot.'), findsOneWidget);
    await t.enterText(find.byType(TextField), '  $code  ');
    await tap(t, 'Meghívó ellenőrzése');
    expect(r.tokens, [code]);
    expect(find.text('Érvényes meghívó'), findsOneWidget);
    expect(find.text('Tulajdonos: owner@example.test'), findsOneWidget);
    await t.ensureVisible(find.text('Csatlakozás indítása'));
    expect(
      t
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Csatlakozás indítása'),
          )
          .onPressed,
      isNull,
    );
  });
  for (final state in ['owner', 'member', 'progress']) {
    testWidgets('7C $state no join entry', (t) async {
      final r = JoinRepo()
        ..reply = () async => state == 'progress'
            ? FamilyState.inProgress('a')
            : FamilyState.fromResponse(
                response(role: state),
                state == 'owner' ? 'a' : 'm1',
              );
      addTearDown(r.events.close);
      await t.pumpWidget(MaterialApp(home: FamilyScreen(repository: r)));
      await t.pumpAndSettle();
      expect(find.text('Meghívókód megadása'), findsNothing);
    });
  }
  testWidgets('7C preview double submit and raw failure safe', (t) async {
    final r = JoinRepo(), barrier = Completer<FamilyInvitePreview>();
    r.preview = () => barrier.future;
    await open(t, r);
    await t.enterText(find.byType(TextField), code);
    await tap(t, 'Meghívó ellenőrzése', settle: false);
    await tap(t, 'Meghívó ellenőrzése', settle: false);
    expect(r.actions, ['preview']);
    barrier.completeError(StateError('SECRET'));
    await t.pumpAndSettle();
    expect(find.textContaining('SECRET'), findsNothing);
    expect(
      find.byType(LinearProgressIndicator),
      findsNothing,
    ); // offstage parent is excluded
    expect(
      t
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Meghívó ellenőrzése'),
          )
          .onPressed,
      isNotNull,
    );
  });
  testWidgets(
    '7C ADD deliberate confirmation forward-only and authoritative success',
    (t) async {
      final r = JoinRepo()..committed = true;
      await preview(t, r);
      await tap(t, 'Saját listám hozzáadása');
      await tap(t, 'Csatlakozás indítása', settle: false);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(r.modes, isEmpty);
      await tap(t, 'Hozzáadás és csatlakozás');
      expect(r.modes, [FamilyJoinMode.add]);
      expect(find.text('Csatlakozás folyamatban…'), findsOneWidget);
      expect(find.text('Csatlakozás megszakítása'), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
      r.active = true;
      await tap(t, 'Állapot frissítése');
      expect(find.text('Aktív család'), findsOneWidget);
      expect(find.text('Tag vagy · 2 résztvevő'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    },
  );
  testWidgets(
    '7C DELETE empty list mandatory second consent cancel and exact confirm',
    (t) async {
      final r = JoinRepo();
      await preview(t, r);
      await tap(t, 'Saját listám eldobása');
      await tap(t, 'Csatlakozás indítása');
      expect(r.modes, [FamilyJoinMode.delete]);
      expect(r.actions, isNot(contains('confirm')));
      await tap(t, 'Eldobás megerősítése', settle: false);
      expect(find.text('Saját lista eldobása?'), findsOneWidget);
      await tap(t, 'Mégse');
      expect(r.actions, isNot(contains('confirm')));
      await tap(t, 'Eldobás megerősítése', settle: false);
      await tap(t, 'Csatlakozás és saját lista eldobása');
      expect(r.actions.where((a) => a == 'confirm').length, 1);
      expect(find.text('Csatlakozás megszakítása'), findsNothing);
      expect(find.text('Eldobás megerősítése'), findsNothing);
      r.active = true;
      await tap(t, 'Állapot frissítése');
      expect(find.text('Tag vagy · 2 résztvevő'), findsOneWidget);
    },
  );
  testWidgets('7C precommit cancellation uses backend and returns private', (
    t,
  ) async {
    final r = JoinRepo();
    await preview(t, r);
    await tap(t, 'Saját listám eldobása');
    await tap(t, 'Csatlakozás indítása');
    await tap(t, 'Csatlakozás megszakítása');
    expect(r.actions, contains('cancel'));
    expect(find.text('A csatlakozás megszakadt'), findsOneWidget);
    await tap(t, 'Vissza a családi oldalra');
    expect(find.text('Még nem vagy család tagja'), findsOneWidget);
  });
  testWidgets('7C lost start response retries same token mode only', (t) async {
    final r = JoinRepo();
    int calls = 0;
    r.start = () async {
      if (calls++ == 0) throw StateError('lost ACK');
    };
    await preview(t, r);
    await tap(t, 'Saját listám eldobása');
    await tap(t, 'Csatlakozás indítása');
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.text('Csatlakozás megszakítása'), findsNothing);
    await tap(t, 'Állapot frissítése');
    expect(r.modes, [FamilyJoinMode.delete, FamilyJoinMode.delete]);
    expect(r.tokens.toSet(), {code});
    expect(find.text('Eldobás megerősítése'), findsOneWidget);
  });
  testWidgets('7C lost response already active avoids another reservation', (
    t,
  ) async {
    final r = JoinRepo();
    r.start = () async {
      r.active = true;
      throw StateError('lost ACK');
    };
    await preview(t, r);
    await tap(t, 'Saját listám hozzáadása');
    await tap(t, 'Csatlakozás indítása', settle: false);
    await tap(t, 'Hozzáadás és csatlakozás');
    await tap(t, 'Állapot frissítése');
    expect(r.modes.length, 1);
    expect(find.text('Aktív család'), findsOneWidget);
  });

  testWidgets('7C ADD cancelled confirmation sends no reservation', (t) async {
    final r = JoinRepo();
    await preview(t, r);
    await tap(t, 'Saját listám hozzáadása');
    await tap(t, 'Csatlakozás indítása', settle: false);
    await tap(t, 'Mégse');
    expect(r.modes, isEmpty);
    expect(find.byType(ChoiceChip), findsNWidgets(2));
  });
  testWidgets(
    '7C lost DELETE ACK requires state recovery not another consent',
    (t) async {
      final r = JoinRepo();
      r.confirmEffect = () async {
        r.committed = true;
        throw StateError('lost ACK');
      };
      await preview(t, r);
      await tap(t, 'Saját listám eldobása');
      await tap(t, 'Csatlakozás indítása');
      await tap(t, 'Eldobás megerősítése', settle: false);
      await tap(t, 'Csatlakozás és saját lista eldobása');
      expect(find.text('Eldobás megerősítése'), findsNothing);
      expect(find.text('Csatlakozás megszakítása'), findsNothing);
      await tap(t, 'Állapot frissítése');
      expect(r.actions.where((a) => a == 'confirm').length, 1);
      expect(find.text('Eldobás megerősítése'), findsNothing);
      expect(r.modes.length, 1);
    },
  );
  testWidgets('7C cancellation losing commit race becomes forward only', (
    t,
  ) async {
    final r = JoinRepo();
    r.cancelEffect = () async {
      r.committed = true;
    };
    await preview(t, r);
    await tap(t, 'Saját listám eldobása');
    await tap(t, 'Csatlakozás indítása');
    await tap(t, 'Csatlakozás megszakítása');
    expect(find.text('Csatlakozás megszakítása'), findsNothing);
    expect(find.text('Eldobás megerősítése'), findsNothing);
    expect(find.text('Csatlakozás folyamatban…'), findsOneWidget);
  });
  testWidgets('7C delayed start double submit sends only one mode', (t) async {
    final r = JoinRepo(), barrier = Completer<void>();
    r.start = () => barrier.future;
    await preview(t, r);
    await tap(t, 'Saját listám eldobása');
    await tap(t, 'Csatlakozás indítása', settle: false);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(r.modes, [FamilyJoinMode.delete]);
    expect(
      t
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Állapot frissítése'),
          )
          .onPressed,
      isNull,
    );
    barrier.complete();
    await t.pumpAndSettle();
    expect(r.modes.length, 1);
  });
  testWidgets('7C session switch clears code and late preview', (t) async {
    final r = JoinRepo(), barrier = Completer<FamilyInvitePreview>();
    r.preview = () => barrier.future;
    await open(t, r);
    await t.enterText(find.byType(TextField), code);
    await tap(t, 'Meghívó ellenőrzése', settle: false);
    r.events.add(null);
    barrier.complete(
      FamilyInvitePreview('secret@example.test', DateTime(2027), 0),
    );
    await t.pumpAndSettle();
    expect(find.textContaining('secret@example.test'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(r.modes, isEmpty);
  });
  testWidgets('7C small screen destructive dialog remains scrollable', (
    t,
  ) async {
    t.view.physicalSize = const Size(360, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final r = JoinRepo();
    await preview(t, r);
    await tap(t, 'Saját listám eldobása');
    await tap(t, 'Csatlakozás indítása');
    await tap(t, 'Eldobás megerősítése', settle: false);
    expect(t.takeException(), isNull);
    await tap(t, 'Mégse');
    expect(r.actions, isNot(contains('confirm')));
  });
  testWidgets(
    '7C known reservation rejection does not trap user in uncertain flow',
    (t) async {
      final r = JoinRepo();
      r.start = () async => throw const FamilyJoinException('FEATURE_DISABLED');
      await preview(t, r);
      await tap(t, 'Saját listám eldobása');
      await tap(t, 'Csatlakozás indítása');
      expect(
        find.text(const FamilyJoinException('FEATURE_DISABLED').message),
        findsOneWidget,
      );
      expect(find.byType(ChoiceChip), findsNWidgets(2));
      expect(r.actions, isNot(contains('prepare')));
    },
  );

  test('7C auth ABA discards late reservation response', () async {
    final auth = TestAuth(),
        functions = Functions(),
        barrier = Completer<Object?>();
    addTearDown(auth.events.close);
    functions.callable.reply = () => barrier.future;
    final pending = CallableFamilyRepository(
      auth: auth,
      functions: functions,
    ).startJoin(code, FamilyJoinMode.add);
    auth.switchTo('b');
    auth.switchTo('a');
    barrier.complete({
      'schemaVersion': 1,
      'operationId': handle.operationId,
      'outcome': 'READY_FOR_TRANSFER',
    });
    await expectLater(pending, throwsA(isA<FamilyMutationException>()));
    expect(functions.names, ['acceptFamilyInvite']);
  });
  testWidgets(
    '7C committed navigation return shows authoritative progress no fresh join',
    (t) async {
      final r = JoinRepo()..committed = true;
      await preview(t, r);
      await tap(t, 'Saját listám hozzáadása');
      await tap(t, 'Csatlakozás indítása', settle: false);
      await tap(t, 'Hozzáadás és csatlakozás');
      r.reply = () async => FamilyState.inProgress('m1');
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.text('Folyamatban lévő családi művelet'), findsOneWidget);
      expect(find.text('Meghívókód megadása'), findsNothing);
    },
  );
  testWidgets('7C impossible committed regression cannot reopen cancellation', (
    t,
  ) async {
    final r = JoinRepo()..committed = true;
    await preview(t, r);
    await tap(t, 'Saját listám hozzáadása');
    await tap(t, 'Csatlakozás indítása', settle: false);
    await tap(t, 'Hozzáadás és csatlakozás');
    r.committed = false;
    await tap(t, 'Állapot frissítése');
    expect(find.text('Csatlakozás megszakítása'), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(r.actions, isNot(contains('cancel')));
  });
  testWidgets(
    '7C lost preparation response reuses handle without another accept',
    (t) async {
      final r = LostPrepareRepo();
      await preview(t, r);
      await tap(t, 'Saját listám eldobása');
      await tap(t, 'Csatlakozás indítása');
      await tap(t, 'Állapot frissítése');
      expect(r.modes.length, 1);
      expect(r.actions.where((a) => a == 'prepare').length, 2);
      expect(find.text('Eldobás megerősítése'), findsOneWidget);
    },
  );
}

class LostPrepareRepo extends JoinRepo {
  bool first = true;
  @override
  Future<FamilyJoinProgress> prepareJoin(FamilyJoinHandle h) async {
    final p = await super.prepareJoin(h);
    if (first) {
      first = false;
      throw StateError('lost preparation ACK');
    }
    return p;
  }
}
