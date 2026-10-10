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
    'interrupted content cleanup resumes via idempotent begin, never early finalize',
    () async {
      final f = Fixture(), g = Gateway(), repo = modern(f, g);
      f.db.failCollection = 'users/owner/shopping';
      await expectLater(
        repo.deleteCurrentAccount(password: 'secret'),
        throwsA(anything),
      );
      expect(g.finalizes, 0);
      expect(f.user.deletes, 0);
      f.db.failCollection = null;
      await repo.deleteCurrentAccount(password: 'secret');
      expect(g.begins, 2);
      expect(g.finalizes, 1);
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
        g.onFinalize = () async => DeletionCompletion.completed;
        await repo.deleteCurrentAccount(password: 'secret');
        expect(g.begins, 2);
        expect(g.finalizes, 2);
      },
    );
  }
  test(
    'finalize network failure can retry without repeating destructive Auth call',
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
      g.onFinalize = () async => DeletionCompletion.completed;
      await repo.deleteCurrentAccount(password: 'secret');
      expect(g.finalizes, 2);
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
  test(
    'default composition remains legacy without missing endpoint dependency',
    () async {
      final f = Fixture();
      expect(f.repo.coordination, isNull);
      await f.repo.deleteCurrentAccount(password: 'secret');
      expect(f.user.deletes, 1);
    },
  );
}
