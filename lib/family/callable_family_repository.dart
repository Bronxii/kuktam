import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'family_repository.dart';
import 'family_state.dart';

class CallableFamilyRepository implements FamilyRepository {
  CallableFamilyRepository({FirebaseAuth? auth, FirebaseFunctions? functions})
    : _auth = auth ?? FirebaseAuth.instance,
      _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1') {
    _uid = _auth.currentUser?.uid;
  }
  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;
  late final String? _uid;

  @override
  Stream<void> get sessionChanges => _auth
      .authStateChanges()
      .map((user) => user?.uid)
      .distinct()
      .where((uid) => uid != _uid)
      .map((_) {});

  @override
  Future<FamilyState> load() async {
    final uid = _uid;
    if (uid == null || _auth.currentUser?.uid != uid) {
      throw const FamilyReadException(FamilyFailure.signedOut);
    }
    var changed = false;
    final subscription = sessionChanges.listen((_) => changed = true);
    void check() {
      if (changed || _auth.currentUser?.uid != uid) {
        throw const FamilyReadException(FamilyFailure.signedOut);
      }
    }

    try {
      final result = await _functions
          .httpsCallable(
            'getFamilyShareState',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
          )
          .call<Object?>({});
      check();
      return FamilyState.fromResponse(result.data, uid);
    } on FirebaseFunctionsException catch (error) {
      check();
      if (error.code == 'failed-precondition' &&
          [
            'IN_PROGRESS',
            'FAMILY_PREPARING',
            'FAMILY_DISSOLVING',
          ].contains(error.message)) {
        return FamilyState.inProgress(uid);
      }
      throw FamilyReadException(
        ['unavailable', 'deadline-exceeded'].contains(error.code)
            ? FamilyFailure.network
            : FamilyFailure.unavailable,
      );
    } on FamilyReadException {
      rethrow;
    } catch (_) {
      throw const FamilyReadException(FamilyFailure.unavailable);
    } finally {
      await subscription.cancel();
    }
  }
}
