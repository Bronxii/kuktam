import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/family/family_state.dart';
import 'package:kuktam/family/callable_family_repository.dart';
import 'fakes.dart';

Map<String, Object?> response({String role = 'owner', int count = 2}) => {
  'schemaVersion': 1,
  'familyActive': true,
  'role': role,
  'members': List.generate(
    count,
    (n) => {
      'memberId': n == 0 ? 'a' : 'm$n',
      'role': n == 0 ? 'owner' : 'member',
      'email': n == 0 ? 'owner@example.test' : null,
      'displayIdentity': n == 0 ? 'owner@example.test' : 'Ismeretlen tag',
    },
  ),
};
void main() {
  test('7A no active Family including historical-only read response', () {
    final state = FamilyState.fromResponse({
      'schemaVersion': 1,
      'familyActive': false,
    }, 'a');
    expect(state.status, FamilyStatus.privateOnly);
    expect(state.owner, isNull);
  });
  test(
    '7A owner and member roles come from authoritative membership response',
    () {
      expect(
        FamilyState.fromResponse(response(), 'a').status,
        FamilyStatus.activeOwner,
      );
      final member = FamilyState.fromResponse(response(role: 'member'), 'm1');
      expect(member.status, FamilyStatus.activeMember);
      expect(member.owner!.uid, 'a');
      expect(member.participants.last.label, 'Ismeretlen tag');
      expect(() => member.participants.clear(), throwsUnsupportedError);
    },
  );
  for (final defect in [
    'version',
    'role',
    'missingSelf',
    'duplicate',
    'twoOwners',
    'none',
    'over8',
    'privateMembers',
  ]) {
    test('7A malformed $defect fails closed', () {
      final data = response();
      if (defect == 'version') data['schemaVersion'] = 99;
      if (defect == 'role') data['role'] = 'member';
      if (defect == 'missingSelf') {
        (data['members'] as List)[0]['memberId'] = 'other';
      }
      if (defect == 'duplicate') (data['members'] as List)[1]['memberId'] = 'a';
      if (defect == 'twoOwners') (data['members'] as List)[1]['role'] = 'owner';
      if (defect == 'none') data['members'] = [];
      if (defect == 'over8') data['members'] = response(count: 9)['members'];
      if (defect == 'privateMembers') data['familyActive'] = false;
      expect(
        () => FamilyState.fromResponse(data, 'a'),
        throwsA(isA<FamilyReadException>()),
      );
    });
  }
  test(
    '7A one empty read-only callable no mutation and no lingering subscription',
    () async {
      final auth = TestAuth(), functions = Functions();
      addTearDown(auth.events.close);
      functions.callable.reply = () async => response();
      final repo = CallableFamilyRepository(auth: auth, functions: functions);
      expect((await repo.load()).status, FamilyStatus.activeOwner);
      expect(functions.names, ['getFamilyShareState']);
      expect(functions.callable.sent, [{}]);
      expect(auth.events.hasListener, false);
    },
  );
  for (final code in ['IN_PROGRESS', 'FAMILY_PREPARING', 'FAMILY_DISSOLVING']) {
    test('7A backend $code maps to in-progress without writes', () async {
      final auth = TestAuth(), functions = Functions();
      addTearDown(auth.events.close);
      functions.callable.reply = () async => throw FirebaseFunctionsException(
        code: 'failed-precondition',
        message: code,
      );
      expect(
        (await CallableFamilyRepository(
          auth: auth,
          functions: functions,
        ).load()).status,
        FamilyStatus.inProgress,
      );
      expect(functions.names, ['getFamilyShareState']);
    });
  }
  test(
    '7A errors mapped network and unavailable without raw details',
    () async {
      final auth = TestAuth(), functions = Functions();
      addTearDown(auth.events.close);
      final repo = CallableFamilyRepository(auth: auth, functions: functions);
      for (final code in ['unavailable', 'failed-precondition']) {
        functions.callable.reply = () async => throw FirebaseFunctionsException(
          code: code,
          message: 'PRIVATE-DETAILS',
        );
        await expectLater(
          repo.load(),
          throwsA(
            isA<FamilyReadException>().having(
              (e) => e.reason,
              'reason',
              code == 'unavailable'
                  ? FamilyFailure.network
                  : FamilyFailure.unavailable,
            ),
          ),
        );
      }
    },
  );
  test('7A anonymous makes no call', () async {
    final auth = TestAuth()..currentUser = null, functions = Functions();
    addTearDown(auth.events.close);
    await expectLater(
      CallableFamilyRepository(auth: auth, functions: functions).load(),
      throwsA(isA<FamilyReadException>()),
    );
    expect(functions.names, isEmpty);
  });
  test(
    '7A account switch and switch-back discard in-flight response',
    () async {
      final auth = TestAuth(), functions = Functions();
      addTearDown(auth.events.close);
      final pending = Completer<Object?>();
      functions.callable.reply = () => pending.future;
      final future = CallableFamilyRepository(
        auth: auth,
        functions: functions,
      ).load();
      final check = expectLater(future, throwsA(isA<FamilyReadException>()));
      auth.switchTo('b');
      auth.switchTo('a');
      pending.complete(response());
      await check;
    },
  );
}
