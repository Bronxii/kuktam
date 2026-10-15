import 'package:cloud_functions/cloud_functions.dart';
import '../../../../monetization/callable_gateways.dart';
import 'account_deletion_gateway.dart';

/// Operation-scoped; Firebase SDK supplies authentication, never a body UID.
final class CallableAccountDeletionGateway implements AccountDeletionGateway {
  CallableAccountDeletionGateway(this.call);
  final Future<Object?> Function(String name) call;

  factory CallableAccountDeletionGateway.production({
    required bool Function() canStart,
    required bool Function() canComplete,
  }) => CallableAccountDeletionGateway((name) async {
    if (!canStart()) throw const TransportFailure('unauthenticated');
    final result = await FirebaseFunctions.instanceFor(region: 'europe-west1')
        .httpsCallable(
          name,
          options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
        )
        .call<Object?>(<String, Object?>{});
    if (!(name == 'finalizeAccountDeletion' ? canComplete() : canStart())) {
      throw const TransportFailure('unauthenticated');
    }
    return result.data;
  });

  @override
  Future<void> begin() async {
    final result = responseMap(await call('beginAccountDeletion'), {
      'schemaVersion',
      'outcome',
    });
    if (!{
      'deletionStarted',
      'deletionAlreadyInProgress',
      'alreadyDeleted',
    }.contains(result['outcome'])) {
      throw const TransportFailure('internalMalformed');
    }
  }

  @override
  Future<DeletionCompletion> finalize() async {
    final result = responseMap(await call('finalizeAccountDeletion'), {
      'schemaVersion',
      'outcome',
    });
    return switch (result['outcome']) {
      'deletionCompleted' || 'alreadyDeleted' => DeletionCompletion.completed,
      'cleanupIncomplete' => DeletionCompletion.cleanupIncomplete,
      'cleanupRetryRequired' ||
      'authDeleteRetryRequired' ||
      'busy' => DeletionCompletion.retryRequired,
      'supportRequired' => DeletionCompletion.supportRequired,
      _ => throw const TransportFailure('internalMalformed'),
    };
  }
}
