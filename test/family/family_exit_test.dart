import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/family/callable_family_repository.dart';
import 'package:kuktam/family/family_mutation.dart';
import 'package:kuktam/family/family_screen.dart';
import 'package:kuktam/family/family_state.dart';
import 'fakes.dart';
import 'family_test.dart' show response;
import 'family_screen_test.dart' show Repo;

FamilyState active(bool owner, {int count = 2, String? binding}) {
  final raw = response(role: owner ? 'owner' : 'member', count: count);
  if (binding != null) {
    (raw['members'] as List)[1]['membershipInviteId'] = binding;
  }
  return FamilyState.fromResponse(raw, owner ? 'a' : 'm1');
}

FamilyState privateState() =>
    FamilyState.fromResponse({'schemaVersion': 1, 'familyActive': false}, 'm1');

class ExitRepo extends Repo {
  ExitRepo(this.current) {
    reply = () async => current;
  }
  FamilyState current;
  final targets = <FamilyParticipant>[];
  final removals = <bool>[];
  Future<void> Function(FamilyParticipant, bool)? effect;
  @override
  Future<void> leaveFamily(FamilyParticipant m) => exit(m, false);
  @override
  Future<void> removeMember(FamilyParticipant m) => exit(m, true);
  Future<void> exit(FamilyParticipant m, bool remove) async {
    targets.add(m);
    removals.add(remove);
    await effect?.call(m, remove);
  }
}

Future<void> show(WidgetTester t, ExitRepo r) async {
  addTearDown(r.events.close);
  await t.pumpWidget(MaterialApp(home: FamilyScreen(repository: r)));
  await t.pumpAndSettle();
}

Future<void> openExit(WidgetTester t, bool remove) async {
  if (remove) {
    final menu = find.byKey(const ValueKey('family-member-menu-m1'));
    await t.ensureVisible(menu);
    await t.tap(menu);
    await t.pumpAndSettle();
    await t.tap(find.text('Tag eltávolítása'));
  } else {
    final button = find.widgetWithText(OutlinedButton, 'Kilépés a családból');
    await t.ensureVisible(button);
    await t.tap(button);
  }
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

Future<void> confirm(WidgetTester t, bool remove) async {
  await t.tap(
    find.widgetWithText(FilledButton, remove ? 'Tag eltávolítása' : 'Kilépés'),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets(
    '7D selected owner target remains paired and other member stays',
    (t) async {
      final r = ExitRepo(active(true, count: 3));
      final target = r.current.participants.firstWhere((p) => p.uid == 'm2');
      r.effect = (m, remove) async {
        expect(identical(m, target), true);
        expect(remove, true);
        r.current = active(true, count: 2);
      };
      await show(t, r);
      final menu = find.byKey(const ValueKey('family-member-menu-m2'));
      await t.ensureVisible(menu);
      await t.tap(menu);
      await t.pumpAndSettle();
      await t.tap(find.text('Tag eltávolítása'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      await confirm(t, true);
      await t.pumpAndSettle();
      expect(r.targets.single.uid, 'm2');
      expect(r.targets.single.membershipInviteId, '2'.padLeft(64, '0'));
      expect(find.byKey(const ValueKey('family-member-menu-m2')), findsNothing);
      expect(
        find.byKey(const ValueKey('family-member-menu-m1')),
        findsOneWidget,
      );
      expect(find.text('Tulajdonos vagy · 2 résztvevő'), findsOneWidget);
    },
  );
  testWidgets('7D successful response waits for authoritative refresh', (
    t,
  ) async {
    final r = ExitRepo(active(false)), pending = Completer<FamilyState>();
    r.effect = (_, _) async {
      r.reply = () => pending.future;
    };
    await show(t, r);
    await openExit(t, false);
    await confirm(t, false);
    expect(r.targets.length, 1);
    expect(r.calls, 2);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Még nem vagy család tagja'), findsNothing);
    pending.complete(privateState());
    await t.pumpAndSettle();
    expect(find.text('Még nem vagy család tagja'), findsOneWidget);
  });
  testWidgets('7D remove confirmation works on small screen', (t) async {
    t.view.physicalSize = const Size(360, 480);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final r = ExitRepo(active(true));
    await show(t, r);
    await openExit(t, true);
    expect(t.takeException(), isNull);
    final cancel = find.widgetWithText(TextButton, 'Mégse');
    await t.ensureVisible(cancel);
    await t.tap(cancel);
    await t.pumpAndSettle();
    expect(r.targets, isEmpty);
  });

  for (final remove in [false, true]) {
    test(
      '7D exact ${remove ? 'remove' : 'leave'} callable uses one participant binding',
      () async {
        final auth = TestAuth();
        if (!remove) auth.switchTo('m1');
        addTearDown(auth.events.close);
        final f = Functions()
          ..callable.reply = () async => {
            'schemaVersion': 1,
            'operationId': 'server-exit',
            'outcome': 'DONE',
          };
        final r = CallableFamilyRepository(auth: auth, functions: f),
            target = active(
              remove,
            ).participants.firstWhere((p) => p.uid == 'm1');
        if (remove) {
          await r.removeMember(target);
        } else {
          await r.leaveFamily(target);
        }
        expect(f.names, [remove ? 'removeFamilyMember' : 'leaveFamilyShare']);
        expect(f.callable.sent, [
          {
            'inviteId': target.membershipInviteId,
            if (remove) 'targetUid': target.uid,
          },
        ]);
      },
    );
    test(
      '7D ${remove ? 'remove' : 'leave'} missing binding never invokes callable',
      () async {
        final auth = TestAuth();
        if (!remove) auth.switchTo('m1');
        addTearDown(auth.events.close);
        final f = Functions(),
            r = CallableFamilyRepository(auth: auth, functions: f);
        const target = FamilyParticipant(uid: 'm1', role: FamilyRole.member);
        await expectLater(
          remove ? r.removeMember(target) : r.leaveFamily(target),
          throwsA(isA<FamilyExitException>()),
        );
        expect(f.names, isEmpty);
      },
    );
    testWidgets(
      '7D ${remove ? 'remove' : 'leave'} confirmation cancel has no effect',
      (t) async {
        final r = ExitRepo(active(remove));
        await show(t, r);
        await openExit(t, remove);
        expect(r.targets, isEmpty);
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.textContaining('privát bevásárlólist'), findsWidgets);
        if (remove) {
          expect(
            find.textContaining('fiókja és privát adatai nem törlődnek'),
            findsOneWidget,
          );
        }
        await t.tap(find.text('Mégse'));
        await t.pumpAndSettle();
        expect(r.targets, isEmpty);
        expect(r.calls, 1);
      },
    );
    testWidgets(
      '7D ${remove ? 'remove' : 'leave'} completion authoritatively refreshes',
      (t) async {
        final r = ExitRepo(active(remove));
        final target = r.current.participants.last;
        r.effect = (m, _) async {
          expect(identical(m, target), true);
          r.current = remove ? active(true, count: 1) : privateState();
        };
        await show(t, r);
        await openExit(t, remove);
        await confirm(t, remove);
        await t.pumpAndSettle();
        expect(r.targets, [target]);
        expect(r.removals, [remove]);
        expect(r.calls, 2);
        expect(
          find.text(remove ? 'Aktív család' : 'Még nem vagy család tagja'),
          findsOneWidget,
        );
        if (remove) {
          expect(find.text('Tulajdonos vagy · 1 résztvevő'), findsOneWidget);
          expect(find.byType(PopupMenuButton<String>), findsNothing);
        }
      },
    );
    testWidgets(
      '7D ${remove ? 'remove' : 'leave'} double submit and conflicting controls disabled',
      (t) async {
        final r = ExitRepo(active(remove)), pending = Completer<void>();
        r.effect = (_, _) => pending.future;
        await show(t, r);
        await openExit(t, remove);
        await confirm(t, remove);
        expect(r.targets.length, 1);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(r.calls, 1);
        if (remove) {
          expect(
            t
                .widget<PopupMenuButton<String>>(
                  find.byType(PopupMenuButton<String>),
                )
                .enabled,
            false,
          );
          expect(
            t
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Tag meghívása'),
                )
                .onPressed,
            isNull,
          );
        } else {
          expect(
            t
                .widget<OutlinedButton>(
                  find.widgetWithText(OutlinedButton, 'Kilépés a családból'),
                )
                .onPressed,
            isNull,
          );
          await t.tap(find.text('Kilépés a családból'));
        }
        expect(r.targets.length, 1);
        r.current = remove ? active(true, count: 1) : privateState();
        pending.complete();
        await t.pumpAndSettle();
        expect(r.calls, 2);
      },
    );
    for (final code in ['NOT_ACTIVE_MEMBER', 'STALE_MEMBERSHIP', 'lost']) {
      testWidgets(
        '7D ${remove ? 'remove' : 'leave'} $code completed race/ACK reconciles',
        (t) async {
          final r = ExitRepo(active(remove));
          r.effect = (_, _) async {
            r.current = remove ? active(true, count: 1) : privateState();
            if (code == 'lost') throw StateError('PRIVATE FIREBASE SECRET');
            throw FamilyExitException(code);
          };
          await show(t, r);
          await openExit(t, remove);
          await confirm(t, remove);
          await t.pumpAndSettle();
          expect(r.targets.length, 1);
          expect(r.calls, 2);
          expect(
            find.text(
              remove
                  ? 'Tulajdonos vagy · 1 résztvevő'
                  : 'Még nem vagy család tagja',
            ),
            findsOneWidget,
          );
          expect(find.textContaining('PRIVATE FIREBASE'), findsNothing);
        },
      );
    }
    testWidgets(
      '7D ${remove ? 'remove' : 'leave'} stale A refreshes B without automatic retry',
      (t) async {
        final r = ExitRepo(active(remove, binding: 'a' * 64));
        r.effect = (m, _) async {
          if (r.targets.length == 1) {
            expect(m.membershipInviteId, 'a' * 64);
            r.current = active(remove, binding: 'b' * 64);
            throw const FamilyExitException('STALE_MEMBERSHIP');
          }
          expect(m.membershipInviteId, 'b' * 64);
          r.current = remove ? active(true, count: 1) : privateState();
        };
        await show(t, r);
        await openExit(t, remove);
        await confirm(t, remove);
        await t.pumpAndSettle();
        expect(r.targets.length, 1);
        expect(
          find.textContaining('tagság időközben megváltozott'),
          findsOneWidget,
        );
        await openExit(t, remove);
        await confirm(t, remove);
        await t.pumpAndSettle();
        expect(r.targets.length, 2);
        expect(r.calls, 3);
      },
    );
    testWidgets(
      '7D ${remove ? 'remove' : 'leave'} uncertain unchanged state permits explicit same-binding retry',
      (t) async {
        final r = ExitRepo(active(remove));
        r.effect = (_, _) async {
          if (r.targets.length == 1) throw StateError('secret');
          r.current = remove ? active(true, count: 1) : privateState();
        };
        await show(t, r);
        await openExit(t, remove);
        await confirm(t, remove);
        await t.pumpAndSettle();
        expect(r.targets.length, 1);
        expect(
          find.textContaining('Nem sikerült megerősíteni'),
          findsOneWidget,
        );
        expect(find.text('secret'), findsNothing);
        await openExit(t, remove);
        await confirm(t, remove);
        await t.pumpAndSettle();
        expect(
          r.targets[0].membershipInviteId,
          r.targets[1].membershipInviteId,
        );
      },
    );
  }
  testWidgets('7D controls respect owner member private and progress states', (
    t,
  ) async {
    final r = ExitRepo(active(true));
    await show(t, r);
    expect(find.text('Kilépés a családból'), findsNothing);
    expect(find.byKey(const ValueKey('family-member-menu-a')), findsNothing);
    expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    for (final s in [
      active(false),
      privateState(),
      FamilyState.inProgress('m1'),
    ]) {
      r.current = s;
      await t.tap(find.byTooltip('Frissítés'));
      await t.pumpAndSettle();
      expect(find.byType(PopupMenuButton<String>), findsNothing);
      expect(
        find.text('Kilépés a családból'),
        s.status == FamilyStatus.activeMember ? findsOneWidget : findsNothing,
      );
    }
  });
  testWidgets(
    '7D failed authoritative refresh hides mutation controls until read retry',
    (t) async {
      final r = ExitRepo(active(false));
      r.effect = (_, _) async {
        r.reply = () async =>
            throw const FamilyReadException(FamilyFailure.network);
      };
      await show(t, r);
      await openExit(t, false);
      await confirm(t, false);
      await t.pumpAndSettle();
      expect(find.text('Kilépés a családból'), findsNothing);
      expect(find.text('A családi adatok nem érhetők el'), findsOneWidget);
      r.reply = () async => privateState();
      await t.tap(find.text('Újrapróbálás'));
      await t.pumpAndSettle();
      expect(r.targets.length, 1);
    },
  );
  testWidgets('7D session change during confirmation prevents mutation', (
    t,
  ) async {
    final r = ExitRepo(active(false));
    await show(t, r);
    await openExit(t, false);
    r.events.add(null);
    await t.pump();
    await confirm(t, false);
    await t.pumpAndSettle();
    expect(r.targets, isEmpty);
    expect(find.textContaining('bejelentkezés megváltozott'), findsOneWidget);
  });
  testWidgets('7D malformed binding read exposes no exit controls', (t) async {
    final r = ExitRepo(active(false));
    r.reply = () async {
      final raw = response(role: 'member');
      (raw['members'] as List)[1].remove('membershipInviteId');
      return FamilyState.fromResponse(raw, 'm1');
    };
    await show(t, r);
    expect(find.text('A családi adatok nem érhetők el'), findsOneWidget);
    expect(find.text('Kilépés a családból'), findsNothing);
    expect(r.targets, isEmpty);
  });
  test('7D owner/self and wrong UID cannot produce exit request', () async {
    final a = TestAuth(), f = Functions();
    addTearDown(a.events.close);
    final r = CallableFamilyRepository(auth: a, functions: f);
    for (final p in [
      const FamilyParticipant(uid: 'a', role: FamilyRole.owner),
      FamilyParticipant(
        uid: 'a',
        role: FamilyRole.member,
        membershipInviteId: 'a' * 64,
      ),
    ]) {
      await expectLater(r.removeMember(p), throwsA(isA<FamilyExitException>()));
    }
    await expectLater(
      r.leaveFamily(active(false).participants.last),
      throwsA(isA<FamilyExitException>()),
    );
    expect(f.names, isEmpty);
  });
  for (final code in [
    'STALE_MEMBERSHIP',
    'NOT_ACTIVE_MEMBER',
    'OWNER_CANNOT_LEAVE',
    'OWNER_CANNOT_REMOVE_SELF',
    'NOT_OWNER',
    'WRONG_FAMILY',
    'IN_PROGRESS',
    'ACCOUNT_UNAVAILABLE',
    'FEATURE_DISABLED',
    'INTEGRITY_REQUIRES_OPERATOR',
    'RETRYABLE_UNAVAILABLE',
    'PRIVATE SECRET',
  ]) {
    test('7D error $code maps safely', () async {
      final a = TestAuth(), f = Functions();
      addTearDown(a.events.close);
      f.callable.reply = () async => throw FirebaseFunctionsException(
        code: 'failed-precondition',
        message: code,
      );
      await expectLater(
        CallableFamilyRepository(
          auth: a,
          functions: f,
        ).removeMember(active(true).participants.last),
        throwsA(
          isA<FamilyExitException>().having(
            (e) => e.message.contains(code),
            'no raw code',
            false,
          ),
        ),
      );
    });
  }
}
