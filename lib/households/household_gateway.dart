/// Platform-neutral contract. The authenticated session owns resolution;
/// callers cannot request provisioning for an arbitrary user or household.
abstract interface class HouseholdGateway {
  Future<String> ensure();
}

/// Emits authoritative context replacements and invalidations for this session.
abstract interface class ObservableHouseholdGateway
    implements HouseholdGateway {
  Stream<String> watch();
  Future<String> refresh();
}
