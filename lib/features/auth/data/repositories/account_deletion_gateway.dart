/// Authenticated transport owns UID selection. No client cleanup evidence is sent.
abstract interface class AccountDeletionGateway {
  Future<void> begin();

  /// Server verifies content and completes or reports resumable progress.
  Future<DeletionCompletion> finalize();
}

enum DeletionCompletion {
  completed,
  cleanupIncomplete,
  retryRequired,
  supportRequired,
}

class DeletionResumeRequired implements Exception {
  const DeletionResumeRequired(this.outcome);
  final DeletionCompletion outcome;
}
