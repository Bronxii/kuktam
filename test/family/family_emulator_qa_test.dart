// Real Firestore/handler bridge; only native SDK transport/auth UID is substituted.
// ignore_for_file: subtype_of_sealed_class
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/family/callable_family_repository.dart';
import 'package:kuktam/family/family_state.dart';
import 'package:kuktam/family/family_join.dart';
import 'package:kuktam/family/family_mutation.dart';
import 'package:kuktam/family/family_invite_link.dart';
import 'fakes.dart';
import 'pending_invite_fake.dart';

class Bridge {
  late Process process;
  String? loseResponse;
  late StreamIterator<String> lines;
  Future<void> start() async {
    if (Platform.environment['FIRESTORE_EMULATOR_HOST'] != '127.0.0.1:8088' ||
        Platform.environment['GCLOUD_PROJECT'] != 'demo-kuktam-local') {
      throw StateError('Local demo emulator required');
    }
    process = await Process.start('node', [
      'functions/scripts/family-qa-bridge.cjs',
    ]);
    lines = StreamIterator(
      process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );
    process.stderr.drain<void>(); // Never echo SDK diagnostics/credentials.
  }

  Future<dynamic> call(String name, {String? uid, dynamic data}) async {
    process.stdin.writeln(jsonEncode({'name': name, 'uid': uid, 'data': data}));
    if (!await lines.moveNext().timeout(const Duration(seconds: 30))) {
      throw StateError('Bridge terminated');
    }
    final result = jsonDecode(lines.current) as Map;
    if (result['error'] case final Map error) {
      throw FirebaseFunctionsException(
        code: error['code'] as String,
        message: error['message'] as String,
      );
    }
    if (loseResponse == name) {
      loseResponse = null;
      throw FirebaseFunctionsException(
        code: 'unavailable',
        message: 'Local simulated lost response',
      );
    }
    return result['data'];
  }

  Future<void> close() async {
    process.kill();
    await lines.cancel();
  }
}

class WireFunctions implements FirebaseFunctions {
  WireFunctions(this.bridge, this.auth);
  final Bridge bridge;
  final TestAuth auth;
  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      WireCall(bridge, auth, name);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected SDK call');
}

class WireCall implements HttpsCallable {
  WireCall(this.bridge, this.auth, this.name);
  final Bridge bridge;
  final TestAuth auth;
  final String name;
  @override
  Future<HttpsCallableResult<T>> call<T>([dynamic parameters]) async =>
      Result<T>(
        (await bridge.call(name, uid: auth.currentUser?.uid, data: parameters))
            as T,
      );
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected SDK call');
}

void main() {
  test(
    '9A real repository/handler/emulator create ADD leave rejoin DELETE remove dissolution',
    () async {
      final bridge = Bridge();
      await bridge.start();
      addTearDown(bridge.close);
      await bridge.call('fixture');
      await bridge.call('signIn', uid: 'owner');
      final ownerAuth = TestAuth()..switchTo('owner');
      final guestAuth = TestAuth()..switchTo(null);
      addTearDown(ownerAuth.events.close);
      addTearDown(guestAuth.events.close);
      final owner = CallableFamilyRepository(
        auth: ownerAuth,
        functions: WireFunctions(bridge, ownerAuth),
      );
      late CallableFamilyRepository guest;
      Future<void> workers(int count) async {
        for (var i = 0; i < count; i++) {
          await bridge.call('worker');
        }
      }

      Future<Map> inspect(String uid) async =>
          await bridge.call('inspect', uid: uid) as Map;
      Future<void> join(FamilyInviteResult invite, FamilyJoinMode mode) async {
        final parsed = familyInviteToken(invite.inviteUrl);
        // Compare boolean only so a failed expectation never prints credentials.
        expect(parsed == invite.code, isTrue);
        expect(
          (await guest.previewInvite(parsed!)).itemCount,
          (await guest.previewInvite(invite.code)).itemCount,
        );
        if (mode == FamilyJoinMode.add) {
          bridge.loseResponse = 'acceptFamilyInvite';
          await expectLater(
            guest.startJoin(invite.code, mode),
            throwsA(isA<FamilyJoinException>()),
          );
          expect((await guest.load()).status, FamilyStatus.inProgress);
        }
        // Same token retry recovers the already admitted logical JOIN.
        final handle = await guest.startJoin(invite.code, mode);
        await guest.prepareJoin(handle);
        var confirmed = false;
        for (var i = 0; i < 40; i++) {
          final progress = await guest.readJoin(handle);
          if (progress.terminal) {
            expect(progress.status, 'DONE');
            break;
          }
          if (progress.needsConsent) {
            expect(mode, FamilyJoinMode.delete);
            expect(confirmed, isFalse);
            // Backend is waiting: no DELETE before this explicit consent.
            expect(await bridge.call('privateCount'), 2);
            await guest.confirmJoinDelete(progress);
            confirmed = true;
          }
          await workers(1);
        }
        expect((await guest.load()).status, FamilyStatus.activeMember);
        expect(confirmed, mode == FamilyJoinMode.delete);
      }

      expect((await owner.load()).status, FamilyStatus.privateOnly);
      final initial = await inspect('guest');
      expect(initial['context']['householdId'], initial['privateId']);
      await owner.createFamily();
      await workers(5);
      expect((await owner.load()).status, FamilyStatus.activeOwner);
      final a = await owner.createInvite();
      final pending = MemoryPendingInviteStore();
      var previews = 0;
      final previewFinished = Completer<void>();
      final router = FamilyLinkRouter(
        currentUid: () => guestAuth.currentUser?.uid,
        canNavigate: () => true,
        pendingStore: pending,
        notice: (_) {},
        open: (token) async {
          previews++;
          await guest.previewInvite(token);
          previewFinished.complete();
        },
      );
      addTearDown(router.dispose);
      await router.receive(a.inviteUrl);
      await router.receive(a.inviteUrl);
      expect(previews, 0);
      expect(pending.value == a.code, isTrue);
      final session = await bridge.call('signIn', uid: 'guest') as Map;
      guestAuth.switchTo(session['uid'] as String);
      guest = CallableFamilyRepository(
        auth: guestAuth,
        functions: WireFunctions(bridge, guestAuth),
      );
      await router.resume();
      await previewFinished.future;
      await router.resume();
      expect(previews, 1);
      expect(pending.value, isNull);
      await bridge.call('seedPrivate');
      await join(a, FamilyJoinMode.add);
      final family = await inspect('guest');
      expect(family['context']['householdId'] != family['privateId'], isTrue);
      expect(family['privateCount'], 0);
      expect((family['items'] as List).length, 2);
      expect(
        (family['items'] as List).any((x) => x['quantity'] == 3000),
        isTrue,
      );
      final oldMember = (await guest.load()).participants.singleWhere(
        (m) => m.uid == 'guest',
      );
      await guest.leaveFamily(oldMember);
      expect((await guest.load()).status, FamilyStatus.privateOnly);
      expect(
        (await inspect('guest'))['context']['householdId'],
        initial['privateId'],
      );
      expect((await inspect('owner'))['items'], family['items']);
      final b = await owner.createInvite();
      expect(a.code != b.code, isTrue);
      await bridge.call('seedPrivate');
      await join(b, FamilyJoinMode.delete);
      final current = (await guest.load()).participants.singleWhere(
        (m) => m.uid == 'guest',
      );
      expect(
        current.membershipInviteId != oldMember.membershipInviteId,
        isTrue,
      );
      await expectLater(
        owner.removeMember(oldMember),
        throwsA(
          isA<FamilyExitException>().having(
            (e) => e.code,
            'code',
            'STALE_MEMBERSHIP',
          ),
        ),
      );
      // A completed self-leave retry may return historical DONE; stale new remove must reject.
      expect((await guest.load()).status, FamilyStatus.activeMember);
      expect((await inspect('owner'))['items'], family['items']);
      await owner.removeMember(current);
      expect((await guest.load()).status, FamilyStatus.privateOnly);
      expect((await owner.load()).participants.length, 1);
      expect((await owner.load()).status, FamilyStatus.activeOwner);
      bridge.loseResponse = 'startFamilyDissolution';
      await expectLater(
        owner.startDissolution(),
        throwsA(isA<FamilyDissolutionException>()),
      );
      expect((await owner.load()).status, FamilyStatus.inProgress);
      await workers(60);
      expect((await owner.load()).status, FamilyStatus.privateOnly);
      expect((await guest.load()).status, FamilyStatus.privateOnly);
      final finalOwner = await inspect('owner');
      expect(finalOwner['context']['householdId'], finalOwner['privateId']);
      expect((finalOwner['items'] as List).length, 2);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
