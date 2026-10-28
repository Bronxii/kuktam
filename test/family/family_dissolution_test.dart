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

FamilyState owner([int count = 2]) =>
    FamilyState.fromResponse(response(count: count), 'a');
FamilyState privateState() =>
    FamilyState.fromResponse({'schemaVersion': 1, 'familyActive': false}, 'a');

class DissolveRepo extends Repo {
  DissolveRepo(this.current) {
    reply = () async => current;
  }
  FamilyState current;
  int starts = 0;
  Future<void> Function()? effect;
  @override
  Future<void> startDissolution() async {
    starts++;
    await effect?.call();
  }
}

Future<void> show(WidgetTester t, DissolveRepo r) async {
  addTearDown(r.events.close);
  await t.pumpWidget(MaterialApp(home: FamilyScreen(repository: r)));
  await t.pumpAndSettle();
}

Future<void> open(WidgetTester t) async {
  final action = find.widgetWithText(OutlinedButton, 'Család megszüntetése');
  await t.ensureVisible(action);
  await t.tap(action);
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

Future<void> confirm(WidgetTester t) async {
  await t.tap(
    find.widgetWithText(FilledButton, 'Család végleges megszüntetése'),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

void noActions() {
  for (final text in [
    'Család megszüntetése',
    'Tag meghívása',
    'Kilépés a családból',
    'Család létrehozása',
    'Meghívókód megadása',
  ]) {
    expect(find.text(text), findsNothing);
  }
  expect(find.byTooltip('Tag kezelése'), findsNothing);
}

void main() {
  test('7E exact empty callable no household or phase calls', () async {
    final auth = TestAuth(), functions = Functions();
    addTearDown(auth.events.close);
    functions.callable.reply = () async => {
      'schemaVersion': 1,
      'operationId': 'opaque-backend-id',
      'outcome': 'IN_PROGRESS',
    };
    await CallableFamilyRepository(
      auth: auth,
      functions: functions,
    ).startDissolution();
    expect(functions.names, ['startFamilyDissolution']);
    expect(functions.callable.sent, [{}]);
  });
  for (final code in [
    'NOT_OWNER',
    'IN_PROGRESS',
    'ACCOUNT_UNAVAILABLE',
    'FEATURE_DISABLED',
    'INTEGRITY_REQUIRES_OPERATOR',
    'raw-secret-backend-message',
  ]) {
    test('7E safe typed mapping $code', () async {
      final auth = TestAuth(), functions = Functions();
      addTearDown(auth.events.close);
      functions.callable.reply = () async => throw FirebaseFunctionsException(
        code: 'failed-precondition',
        message: code,
      );
      final repo = CallableFamilyRepository(auth: auth, functions: functions);
      await expectLater(
        repo.startDissolution(),
        throwsA(
          isA<FamilyDissolutionException>().having(
            (e) => e.message,
            'safe copy',
            isNot(contains(code)),
          ),
        ),
      );
    });
  }
  test('7E malformed acceptance rejected', () async {
    final auth = TestAuth(), functions = Functions();
    addTearDown(auth.events.close);
    functions.callable.reply = () async => {
      'schemaVersion': 1,
      'outcome': 'DONE',
    };
    await expectLater(
      CallableFamilyRepository(
        auth: auth,
        functions: functions,
      ).startDissolution(),
      throwsA(isA<FamilyDissolutionException>()),
    );
  });
  for (final count in [1, 2, 8]) {
    testWidgets('7E owner with $count participants one action and one start', (
      t,
    ) async {
      final r = DissolveRepo(owner(count));
      r.effect = () async {
        r.current = FamilyState.inProgress('a');
      };
      await show(t, r);
      await t.scrollUntilVisible(
        find.widgetWithText(OutlinedButton, 'Család megszüntetése'),
        300,
      );
      expect(find.text('Család megszüntetése'), findsOneWidget);
      await open(t);
      expect(r.starts, 0);
      expect(find.byType(AlertDialog), findsOneWidget);
      await confirm(t);
      await t.pumpAndSettle();
      expect(r.starts, 1);
      expect(r.calls, 2);
      noActions();
      expect(find.text('Folyamatban lévő családi művelet'), findsOneWidget);
    });
  }
  for (final state in [
    FamilyState.fromResponse(response(role: 'member'), 'm1'),
    privateState(),
    FamilyState.inProgress('a'),
  ]) {
    testWidgets('7E no dissolve for ${state.status}', (t) async {
      final r = DissolveRepo(state);
      await show(t, r);
      expect(find.text('Család megszüntetése'), findsNothing);
      expect(r.starts, 0);
    });
  }
  testWidgets('7E cancel confirmation sends nothing', (t) async {
    final r = DissolveRepo(owner());
    await show(t, r);
    await open(t);
    await t.tap(find.text('Mégse'));
    await t.pumpAndSettle();
    expect(r.starts, 0);
    expect(r.calls, 1);
  });
  testWidgets(
    '7E in flight disables duplicate and conflicting admin actions without optimistic completion',
    (t) async {
      final r = DissolveRepo(owner()), pending = Completer<void>();
      r.effect = () => pending.future;
      await show(t, r);
      await open(t);
      await confirm(t);
      expect(r.starts, 1);
      expect(r.calls, 1);
      expect(find.text('Aktív család'), findsOneWidget);
      expect(
        t
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Család megszüntetése'),
            )
            .onPressed,
        isNull,
      );
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Tag meghívása'),
            )
            .onPressed,
        isNull,
      );
      expect(
        t
            .widget<PopupMenuButton<String>>(
              find.byKey(const ValueKey('family-member-menu-m1')),
            )
            .enabled,
        isFalse,
      );
      await t.tap(find.text('Család megszüntetése'));
      expect(r.starts, 1);
      r.current = privateState();
      pending.complete();
      await t.pumpAndSettle();
      expect(r.calls, 2);
      expect(find.text('Még nem vagy család tagja'), findsOneWidget);
    },
  );
  for (final lost in [false, true]) {
    for (final complete in [false, true]) {
      testWidgets(
        '7E accepted/lost=$lost completed=$complete refresh decides state',
        (t) async {
          final r = DissolveRepo(owner());
          r.effect = () async {
            r.current = complete ? privateState() : FamilyState.inProgress('a');
            if (lost) throw StateError('private raw error');
          };
          await show(t, r);
          await open(t);
          await confirm(t);
          await t.pumpAndSettle();
          expect(r.starts, 1);
          expect(r.calls, 2);
          expect(find.text('Aktív család'), findsNothing);
          expect(find.textContaining('private raw error'), findsNothing);
          expect(
            find.text(
              complete
                  ? 'Még nem vagy család tagja'
                  : 'Folyamatban lévő családi művelet',
            ),
            findsOneWidget,
          );
          if (!complete) noActions();
        },
      );
    }
  }
  testWidgets(
    '7E owner after lost response requires new explicit confirmation to retry',
    (t) async {
      final r = DissolveRepo(owner());
      r.effect = () async {
        throw const FamilyDissolutionException('NOT_OWNER');
      };
      await show(t, r);
      await open(t);
      await confirm(t);
      await t.pumpAndSettle();
      expect(r.starts, 1);
      expect(r.calls, 2);
      expect(
        find.text(const FamilyDissolutionException('NOT_OWNER').message),
        findsOneWidget,
      );
      r.effect = () async {
        r.current = FamilyState.inProgress('a');
      };
      await open(t);
      expect(r.starts, 1);
      await confirm(t);
      await t.pumpAndSettle();
      expect(r.starts, 2);
      noActions();
    },
  );
  testWidgets('7E failed refresh hides stale owner controls', (t) async {
    final r = DissolveRepo(owner());
    r.effect = () async {
      r.reply = () async =>
          throw const FamilyReadException(FamilyFailure.network);
      throw StateError('raw');
    };
    await show(t, r);
    await open(t);
    await confirm(t);
    await t.pumpAndSettle();
    noActions();
    expect(r.starts, 1);
    expect(find.text('raw'), findsNothing);
  });
  for (final source in [
    'manual owner',
    'member reopen',
    'Pro loss',
    'account deletion',
  ]) {
    testWidgets('7E $source progress reopen and authoritative completion', (
      t,
    ) async {
      final r = DissolveRepo(FamilyState.inProgress('a'));
      await show(t, r);
      noActions();
      expect(r.starts, 0);
      r.current = privateState();
      await t.tap(find.byTooltip('Frissítés'));
      await t.pumpAndSettle();
      expect(find.text('Még nem vagy család tagja'), findsOneWidget);
      expect(r.starts, 0);
    });
  }
  testWidgets(
    '7E session changes during confirmation cannot start dissolution',
    (t) async {
      final r = DissolveRepo(owner());
      await show(t, r);
      await open(t);
      r.events.add(null);
      await t.pump();
      await confirm(t);
      await t.pumpAndSettle();
      expect(r.starts, 0);
    },
  );
  testWidgets(
    '7E unknown backend error remains safe and never retries automatically',
    (t) async {
      final r = DissolveRepo(owner());
      r.effect = () async {
        throw StateError('private-backend-token');
      };
      await show(t, r);
      await open(t);
      await confirm(t);
      await t.pumpAndSettle();
      expect(find.textContaining('private-backend-token'), findsNothing);
      expect(
        find.text(const FamilyDissolutionException('UNAVAILABLE').message),
        findsOneWidget,
      );
      expect(r.starts, 1);
      expect(r.calls, 2);
    },
  );
  testWidgets(
    '7E accepted response waits for read and never invents completion',
    (t) async {
      final r = DissolveRepo(owner()), read = Completer<FamilyState>();
      r.effect = () async {
        r.reply = () => read.future;
      };
      await show(t, r);
      await open(t);
      await confirm(t);
      expect(r.starts, 1);
      expect(r.calls, 2);
      expect(find.text('Még nem vagy család tagja'), findsNothing);
      noActions();
      read.complete(privateState());
      await t.pumpAndSettle();
      expect(find.text('Még nem vagy család tagja'), findsOneWidget);
    },
  );
  testWidgets('7E confirmation supports small screen', (t) async {
    t.view.physicalSize = const Size(360, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final r = DissolveRepo(owner(1));
    await show(t, r);
    await open(t);
    expect(find.text('Család végleges megszüntetése'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.tap(find.text('Mégse'));
    await t.pumpAndSettle();
    expect(r.starts, 0);
  });
}
