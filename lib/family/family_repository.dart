import 'family_state.dart';

abstract interface class FamilyRepository {
  Future<FamilyState> load();

  /// Session invalidation only; no member/household listeners.
  Stream<void> get sessionChanges;
}
