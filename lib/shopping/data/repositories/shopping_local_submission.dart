import 'dart:async';

/// Complete submission on Firestore local pending data OR server acknowledgement.
/// No timeout, retry, extra write, or claim that local acceptance is server ACK.
/// The commit error handler remains attached after the dialog closes. After an
/// app restart Firestore owns replay/rollback; this in-memory callback is gone.
Future<void> submitShoppingLocally({
  required Future<void> Function() commit,
  required Stream<bool> localAcceptance,
  required bool Function() isCurrent,
  required void Function() onSyncFailure,
}) async {
  final accepted = Completer<void>();
  void succeed() {
    if (accepted.isCompleted) return;
    if (isCurrent()) {
      accepted.complete();
    } else {
      accepted.completeError(StateError('Authenticated session changed'));
    }
  }

  void failure(Object error, StackTrace stack) {
    if (!accepted.isCompleted) {
      accepted.completeError(error, stack);
    } else if (isCurrent()) {
      onSyncFailure();
    }
  }

  final subscription = localAcceptance.listen(
    (matches) {
      if (matches) succeed();
    },
    // A listener failure is not proof that the write failed. The commit still
    // determines the outcome; never submit a duplicate to repair a listener.
    onError: (Object _, StackTrace _) {},
  );
  try {
    try {
      unawaited(commit().then<void>((_) => succeed(), onError: failure));
    } catch (error, stack) {
      failure(error, stack);
    }
    await accepted.future;
  } finally {
    unawaited(subscription.cancel());
  }
}
