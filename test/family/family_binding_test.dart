import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/family/callable_family_repository.dart';
import 'package:kuktam/family/family_join.dart';
import 'package:kuktam/family/family_state.dart';
import 'package:kuktam/family/family_screen.dart';
import 'fakes.dart';
import 'family_test.dart' show response;
import 'family_join_test.dart' show progressResponse, previewResponse;
import 'family_screen_test.dart' show Repo;

void main() {
  test('7D0 current member binding belongs to immutable participant', () {
    final s = FamilyState.fromResponse(
      response(role: 'member', count: 3),
      'm1',
    );
    expect(
      s.participants.firstWhere((m) => m.uid == 'm1').membershipInviteId,
      '1'.padLeft(64, '0'),
    );
    expect(s.owner!.membershipInviteId, isNull);
    expect(
      s.participants.firstWhere((m) => m.uid == 'm2').membershipInviteId,
      isNull,
    );
    final owner = FamilyState.fromResponse(response(count: 8), 'a');
    expect(
      owner.participants.where((m) => m.membershipInviteId != null).length,
      7,
    );
    for (final m in owner.participants.skip(1)) {
      expect(m.membershipInviteId, m.uid.substring(1).padLeft(64, '0'));
    }
  });
  for (final defect in ['missing', 'null', 'invalid', 'owner', 'peer']) {
    test('7D0 malformed or unauthorized binding $defect fails closed', () {
      final data = response(role: 'member', count: 3);
      final rows = data['members'] as List;
      if (defect == 'missing') rows[1].remove('membershipInviteId');
      if (defect == 'null') rows[1]['membershipInviteId'] = null;
      if (defect == 'invalid') rows[1]['membershipInviteId'] = 'bad';
      if (defect == 'owner') rows[0]['membershipInviteId'] = 'a' * 64;
      if (defect == 'peer') rows[2]['membershipInviteId'] = 'b' * 64;
      expect(
        () => FamilyState.fromResponse(data, 'm1'),
        throwsA(
          isA<FamilyReadException>().having(
            (e) => e.reason,
            'reason',
            FamilyFailure.invalidState,
          ),
        ),
      );
    });
  }
  test(
    '7D0 one callable carries binding; malformed response stays typed',
    () async {
      final auth = TestAuth(), functions = Functions();
      addTearDown(auth.events.close);
      final repo = CallableFamilyRepository(auth: auth, functions: functions);
      functions.callable.reply = () async => response();
      expect(
        (await repo.load()).participants.last.membershipInviteId,
        isNotNull,
      );
      expect(functions.names, ['getFamilyShareState']);
      expect(functions.callable.sent, [{}]);
      final bad = response();
      (bad['members'] as List)[1].remove('membershipInviteId');
      functions.callable.reply = () async => bad;
      await expectLater(repo.load(), throwsA(isA<FamilyReadException>()));
    },
  );
  testWidgets('7D0 binding stays internal and no exit controls appear', (
    t,
  ) async {
    final r = Repo()
      ..reply = () async => FamilyState.fromResponse(response(), 'a');
    addTearDown(r.events.close);
    await t.pumpWidget(MaterialApp(home: FamilyScreen(repository: r)));
    await t.pumpAndSettle();
    expect(find.textContaining('1'.padLeft(64, '0')), findsNothing);
    expect(find.text('Kilépés a családból'), findsNothing);
    expect(find.text('Tag eltávolítása'), findsNothing);
  });
  for (final mode in FamilyJoinMode.values) {
    test(
      '7D0 first A then B rejoin uses opaque server ID ${mode.name}',
      () async {
        final auth = TestAuth(), functions = Functions();
        addTearDown(auth.events.close);
        final repo = CallableFamilyRepository(auth: auth, functions: functions);
        final aId = 'join_${sha256.convert(utf8.encode('a'))}',
            bCode = 'B' * 43;
        final bInvite = sha256.convert(utf8.encode(bCode)).toString();
        final bId =
            'join_${sha256.convert(utf8.encode(jsonEncode(['a', bInvite])))}';
        for (final pair in [
          ('A' * 43, aId),
          (bCode, bId),
          ('C' * 43, 'backend-issued-future-identity'),
        ]) {
          functions.callable.reply = () async => {
            'schemaVersion': 1,
            'familyActive': false,
          };
          expect((await repo.load()).status, FamilyStatus.privateOnly);
          functions.callable.reply = () async => previewResponse();
          await repo.previewInvite(pair.$1);
          functions.callable.reply = () async => {
            'schemaVersion': 1,
            'operationId': pair.$2,
            'outcome': 'READY_FOR_TRANSFER',
          };
          final h = await repo.startJoin(pair.$1, mode);
          expect(h.operationId, pair.$2);
          functions.callable.reply = () async =>
              progressResponse(h, committed: true);
          expect((await repo.prepareJoin(h)).handle.operationId, pair.$2);
          expect(functions.callable.sent.last, h.request);
          await repo.readJoin(h);
          expect(functions.callable.sent.last, h.request);
        }
      },
    );
  }
  test(
    '7D0 lost accept response retries same token and retains returned B ID',
    () async {
      final auth = TestAuth(), functions = Functions();
      addTearDown(auth.events.close);
      final repo = CallableFamilyRepository(auth: auth, functions: functions);
      functions.callable.reply = () async =>
          throw StateError('lost acknowledgement');
      await expectLater(
        repo.startJoin('B' * 43, FamilyJoinMode.add),
        throwsException,
      );
      functions.callable.reply = () async => {
        'schemaVersion': 1,
        'operationId': 'server-B',
        'outcome': 'COMMITTED_TRANSFER',
      };
      final h = await repo.startJoin('B' * 43, FamilyJoinMode.add);
      expect(functions.callable.sent[0], functions.callable.sent[1]);
      expect(h.operationId, 'server-B');
      functions.callable.reply = () async =>
          progressResponse(h, committed: true);
      await repo.readJoin(h);
      expect(functions.callable.sent.last, {
        'operationId': 'server-B',
        'inviteId': h.inviteId,
      });
    },
  );
  for (final id in [null, '', 42, 'a/b', ' padded ', 'a' * 129]) {
    test('7D0 malformed opaque ID rejected $id', () async {
      final auth = TestAuth(), f = Functions();
      addTearDown(auth.events.close);
      f.callable.reply = () async => {
        'schemaVersion': 1,
        'operationId': id,
        'outcome': 'DONE',
      };
      await expectLater(
        CallableFamilyRepository(
          auth: auth,
          functions: f,
        ).startJoin('A' * 43, FamilyJoinMode.add),
        throwsA(isA<FamilyJoinException>()),
      );
    });
  }
}
