import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/features/auth/data/repositories/account_deletion_gateway.dart';
import 'package:kuktam/features/auth/data/repositories/account_deletion_repository.dart';
import 'account_deletion_test.dart' show Fixture;

class Gateway implements AccountDeletionGateway {
  int begins = 0, finalizes = 0;
  Future<void> Function()? onBegin;
  Future<DeletionCompletion> Function()? onFinalize;
  @override
  Future<void> begin() async {
    begins++;
    await onBegin?.call();
  }

  @override
  Future<DeletionCompletion> finalize() async {
    finalizes++;
    return await onFinalize?.call() ?? DeletionCompletion.completed;
  }
}

AccountDeletionRepository modern(Fixture f, Gateway g) =>
    AccountDeletionRepository(
      firebaseAuth: f.auth,
      firestore: f.db,
      googleSignIn: f.google,
      coordination: g,
    );
void main() {
  test(
    'confirmed begin clears local access before cleanup; failed begin does not',
    () async {
      final f = Fixture(), g = Gateway();
      var cleared = 0;
      final shoppingUids = <String>[];
      final repo = AccountDeletionRepository(
        firebaseAuth: f.auth,
        firestore: f.db,
        googleSignIn: f.google,
        coordination: g,
        onLocalShoppingDeletionAccepted: (uid) async {
          expect(g.begins, 2);
          expect(uid, f.user.uid);
          expect(f.db.deleted, isEmpty);
          shoppingUids.add(uid);
        },
        onDeletionStarted: () async {
          expect(f.db.deleted, isEmpty);
          cleared++;
        },
      );
      g.onBegin = () async {
        throw StateError('offline');
      };
      await expectLater(
        repo.deleteCurrentAccount(password: 'secret'),
        throwsStateError,
      );
      expect(cleared, 0);
      expect(shoppingUids, isEmpty);
      g.onBegin = null;
      await repo.deleteCurrentAccount(password: 'secret');
      expect(cleared, 1);
      expect(shoppingUids, [f.user.uid]);
      expect(f.user.deletes, 0);
    },
  );
  test(
    'session logout and replacement during finalize cannot clean provider state',
    () async {
      final f = Fixture(), g = Gateway();
      g.onFinalize = () async {
        f.auth.user = null;
        f.auth.events.add(null);
        await Future<void>.delayed(Duration.zero);
        f.auth.user = f.user;
        f.auth.events.add(f.user);
        await Future<void>.delayed(Duration.zero);
        return DeletionCompletion.completed;
      };
      await expectLater(
        modern(f, g).deleteCurrentAccount(password: 'secret'),
        throwsA(isA<DeletionResumeRequired>()),
      );
      expect(f.auth.currentUser, f.user);
      expect(f.user.deletes, 0);
    },
  );

  test('reauth failure never begins coordinated deletion', () async {
    final f = Fixture(), g = Gateway();
    f.user.failReauth = true;
    await expectLater(
      modern(f, g).deleteCurrentAccount(password: 'secret'),
      throwsA(anything),
    );
    expect(g.begins, 0);
    expect(f.db.deleted, isEmpty);
    expect(f.user.deletes, 0);
  });
  test('begin failure leaves content intact and no finalize', () async {
    final f = Fixture(),
        g = Gateway()
          ..onBegin = () async {
            throw StateError('offline');
          };
    await expectLater(
      modern(f, g).deleteCurrentAccount(password: 'secret'),
      throwsA(anything),
    );
    expect(g.begins, 1);
    expect(g.finalizes, 0);
    expect(f.db.deleted, isEmpty);
    expect(f.user.deletes, 0);
  });
  test(
    'begin precedes content, finalize follows complete cleanup, no client Auth delete',
    () async {
      final f = Fixture(), g = Gateway();
      g.onBegin = () async {
        expect(f.user.reauths, 1);
        expect(f.db.deleted, isEmpty);
      };
      g.onFinalize = () async {
        expect(f.db.paths.where((p) => p.startsWith('users/owner')), isEmpty);
        return DeletionCompletion.completed;
      };
      await modern(f, g).deleteCurrentAccount(password: 'secret');
      expect(g.begins, 1);
      expect(g.finalizes, 1);
      expect(f.user.deletes, 0);
      expect(f.db.paths, contains('users/other/recipes/r'));
    },
  );
  test(
    'interrupted accepted cleanup leaves durable continuation and signs out',
    () async {
      final f = Fixture(), g = Gateway(), repo = modern(f, g);
      f.db.failCollection = 'users/owner/shopping';
      await expectLater(
        repo.deleteCurrentAccount(password: 'secret'),
        throwsA(anything),
      );
      expect(g.finalizes, 0);
      expect(f.user.deletes, 0);
      expect(f.auth.currentUser, isNull);
      expect(g.begins, 1);
      expect(g.finalizes, 0);
      expect(f.user.deletes, 0);
    },
  );
  for (final outcome in [
    DeletionCompletion.cleanupIncomplete,
    DeletionCompletion.retryRequired,
    DeletionCompletion.supportRequired,
  ]) {
    test(
      'finalize $outcome is resumable, not successful local Auth deletion',
      () async {
        final f = Fixture(), g = Gateway()..onFinalize = () async => outcome;
        final repo = modern(f, g);
        await expectLater(
          repo.deleteCurrentAccount(password: 'secret'),
          throwsA(isA<DeletionResumeRequired>()),
        );
        expect(f.user.deletes, 0);
        expect(f.auth.currentUser, isNull);
        expect(g.begins, 1);
        expect(g.finalizes, 1);
      },
    );
  }
  test(
    'finalize network failure becomes durable continuation without another delete',
    () async {
      final f = Fixture(),
          g = Gateway()
            ..onFinalize = () async {
              throw StateError('network');
            };
      final repo = modern(f, g);
      await expectLater(
        repo.deleteCurrentAccount(password: 'secret'),
        throwsA(anything),
      );
      expect(f.user.deletes, 0);
      expect(f.auth.currentUser, isNull);
      expect(g.finalizes, 1);
    },
  );
  test(
    'logout then same UID login during begin is fenced by session event',
    () async {
      final f = Fixture(), g = Gateway();
      g.onBegin = () async {
        f.auth.user = null;
        f.auth.events.add(null);
        await Future<void>.delayed(Duration.zero);
        f.auth.user = f.user;
        f.auth.events.add(f.user);
      };
      await expectLater(
        modern(f, g).deleteCurrentAccount(password: 'secret'),
        throwsA(anything),
      );
      expect(f.db.deleted, isEmpty);
      expect(g.finalizes, 0);
      expect(f.user.deletes, 0);
    },
  );
  test(
    'backend successful deletion may remove Auth session while finalize returns',
    () async {
      final f = Fixture(), g = Gateway();
      g.onFinalize = () async {
        f.auth.user = null;
        f.auth.events.add(null);
        return DeletionCompletion.completed;
      };
      await modern(f, g).deleteCurrentAccount(password: 'secret');
      expect(f.user.deletes, 0);
    },
  );
  test('default composition has no direct Auth deletion fallback', () async {
    final f = Fixture();
    final repo = AccountDeletionRepository(
      firebaseAuth: f.auth,
      firestore: f.db,
      googleSignIn: f.google,
    );
    // No Firebase Functions mock is installed: fail closed at begin, not legacy.
    await expectLater(
      repo.deleteCurrentAccount(password: 'secret'),
      throwsA(anything),
    );
    expect(f.db.deleted, isEmpty);
    expect(f.user.deletes, 0);
  });
}
