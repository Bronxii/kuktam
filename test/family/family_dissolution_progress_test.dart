import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/family/callable_family_repository.dart';
import 'package:kuktam/family/family_screen.dart';
import 'package:kuktam/family/family_state.dart';
import 'fakes.dart';
import 'family_test.dart' show response;
import 'family_screen_test.dart' show Repo;

void main() {
  for (final scenario in [
    'PREPARED',
    'owner reopen',
    'member reopen',
    'Pro loss',
    'account deletion',
  ]) {
    testWidgets(
      '7E0 $scenario authoritative progress uses existing parser and hides actions',
      (tester) async {
        final auth = TestAuth(), functions = Functions();
        addTearDown(auth.events.close);
        functions.callable.reply = () async => throw FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'IN_PROGRESS',
        );
        final repo = CallableFamilyRepository(auth: auth, functions: functions);
        final state = await tester.runAsync(repo.load);
        final viewRepo = Repo()..reply = () async => state!;
        addTearDown(viewRepo.events.close);
        await tester.pumpWidget(
          MaterialApp(home: FamilyScreen(repository: viewRepo)),
        );
        await tester.pump();
        await tester.pumpAndSettle();
        expect(find.text('Folyamatban lévő családi művelet'), findsOneWidget);
        expect(find.text('Család létrehozása'), findsNothing);
        expect(find.text('Tag meghívása'), findsNothing);
        expect(find.text('Kilépés a családból'), findsNothing);
        expect(find.byTooltip('Tag kezelése'), findsNothing);
        expect(find.text('Meghívókód megadása'), findsNothing);
        expect(find.text('Család megszüntetése'), findsNothing);
        expect(find.text('IN_PROGRESS'), findsNothing);
        expect(find.text('PREPARED'), findsNothing);
        expect(functions.names, ['getFamilyShareState']);
        expect(functions.callable.sent, [{}]);
      },
    );
  }
  test(
    '7E0 lost start ACK read progresses to authoritative private without client phase calls',
    () async {
      final auth = TestAuth(), functions = Functions();
      addTearDown(auth.events.close);
      final repo = CallableFamilyRepository(auth: auth, functions: functions);
      functions.callable.reply = () async => throw FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'IN_PROGRESS',
      );
      expect((await repo.load()).status, FamilyStatus.inProgress);
      functions.callable.reply = () async => {
        'schemaVersion': 1,
        'familyActive': false,
      };
      expect((await repo.load()).status, FamilyStatus.privateOnly);
      expect(functions.names, ['getFamilyShareState', 'getFamilyShareState']);
    },
  );
  test('7E0 normal owner/member and historical-only remain compatible', () {
    expect(
      FamilyState.fromResponse(response(), 'a').status,
      FamilyStatus.activeOwner,
    );
    expect(
      FamilyState.fromResponse(response(role: 'member'), 'm1').status,
      FamilyStatus.activeMember,
    );
    expect(
      FamilyState.fromResponse({
        'schemaVersion': 1,
        'familyActive': false,
      }, 'a').status,
      FamilyStatus.privateOnly,
    );
  });
}
