import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/features/auth/data/repositories/callable_account_deletion_gateway.dart';
import 'package:kuktam/features/auth/data/repositories/account_deletion_gateway.dart';
import 'package:kuktam/monetization/callable_gateways.dart';

void main() {
  test('exact deletion callable names and no caller-supplied UID', () async {
    final calls = <String>[];
    final gateway = CallableAccountDeletionGateway((name) async {
      calls.add(name);
      return {
        'schemaVersion': 1,
        'outcome': name == 'beginAccountDeletion'
            ? 'deletionStarted'
            : 'deletionCompleted',
      };
    });
    await gateway.begin();
    expect(await gateway.finalize(), DeletionCompletion.completed);
    expect(calls, ['beginAccountDeletion', 'finalizeAccountDeletion']);
  });
  for (final outcome in ['deletionAlreadyInProgress', 'alreadyDeleted']) {
    test('begin accepts idempotent $outcome', () async {
      await CallableAccountDeletionGateway(
        (_) async => {'schemaVersion': 1, 'outcome': outcome},
      ).begin();
    });
  }
  for (final outcome in [
    'cleanupRetryRequired',
    'authDeleteRetryRequired',
    'busy',
  ]) {
    test('finalize $outcome remains resumable', () async {
      expect(
        await CallableAccountDeletionGateway(
          (_) async => {'schemaVersion': 1, 'outcome': outcome},
        ).finalize(),
        DeletionCompletion.retryRequired,
      );
    });
  }
  test('malformed and auth errors cannot report success', () async {
    for (final raw in [
      <String, Object?>{},
      {'schemaVersion': 1, 'outcome': 'surprise'},
      {'schemaVersion': 1, 'error': 'recentAuthRequired'},
    ]) {
      final gateway = CallableAccountDeletionGateway((_) async => raw);
      await expectLater(gateway.begin(), throwsA(isA<TransportFailure>()));
      await expectLater(gateway.finalize(), throwsA(isA<TransportFailure>()));
    }
  });
  test(
    'production gateway refuses invalid session before SDK/network access',
    () async {
      final gateway = CallableAccountDeletionGateway.production(
        canStart: () => false,
        canComplete: () => false,
      );
      await expectLater(gateway.begin(), throwsA(isA<TransportFailure>()));
      await expectLater(gateway.finalize(), throwsA(isA<TransportFailure>()));
    },
  );
}
