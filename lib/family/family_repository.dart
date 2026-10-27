import 'family_state.dart';
import 'family_mutation.dart';

abstract interface class FamilyRepository {
  Future<FamilyState> load();
  Future<FamilyCreation> createFamily();
  Future<FamilyInviteResult> createInvite();

  /// Session invalidation only; no member/household listeners.
  Stream<void> get sessionChanges;
}
