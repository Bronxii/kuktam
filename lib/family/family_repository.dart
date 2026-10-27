import 'family_state.dart';
import 'family_join.dart';
import 'family_mutation.dart';

abstract interface class FamilyRepository {
  Future<FamilyState> load();
  Future<FamilyInvitePreview> previewInvite(String code);
  Future<FamilyJoinHandle> startJoin(String code, FamilyJoinMode mode);
  Future<FamilyJoinProgress> prepareJoin(FamilyJoinHandle handle);
  Future<FamilyJoinProgress> readJoin(FamilyJoinHandle handle);
  Future<void> confirmJoinDelete(FamilyJoinProgress progress);
  Future<void> cancelJoin(FamilyJoinHandle handle);
  Future<FamilyCreation> createFamily();
  Future<FamilyInviteResult> createInvite();

  /// Session invalidation only; no member/household listeners.
  Stream<void> get sessionChanges;
}
