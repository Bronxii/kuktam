import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'family_repository.dart';
import 'family_state.dart';
import 'family_mutation.dart';

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

  @override
  Future<FamilyCreation> createFamily() async {
    final raw = await _mutate('createFamilyShare');
    if (raw is! Map ||
        raw['schemaVersion'] != 1 ||
        raw['operationId'] is! String ||
        !RegExp(
          r'^create_[a-f0-9]{64}$',
        ).hasMatch(raw['operationId'] as String)) {
      throw const FamilyMutationException(FamilyMutationFailure.unavailable);
    }
    if (raw['outcome'] == 'DONE') return FamilyCreation.complete;
    if ([
      'READY',
      'COPY',
      'VERIFY',
      'ACTIVATE',
      'CLEAN_SOURCE',
      'FINALIZE',
      'BUSY',
      'notDueOrBusy',
      'retry',
    ].contains(raw['outcome'])) {
      return FamilyCreation.inProgress;
    }
    throw const FamilyMutationException(FamilyMutationFailure.unavailable);
  }

  @override
  Future<FamilyInviteResult> createInvite() async =>
      FamilyInviteResult.fromResponse(await _mutate('createFamilyInvite'));

  Future<Object?> _mutate(String name) async {
    final uid = _uid;
    var changed = false;
    final subscription = sessionChanges.listen((_) => changed = true);
    void check() {
      if (uid == null || changed || _auth.currentUser?.uid != uid) {
        throw const FamilyMutationException(FamilyMutationFailure.signedOut);
      }
    }

    try {
      check();
      final result = await _functions
          .httpsCallable(
            name,
            options: HttpsCallableOptions(timeout: const Duration(seconds: 65)),
          )
          .call<Object?>({});
      check();
      return result.data;
    } on FirebaseFunctionsException catch (error) {
      check();
      final reason = switch (error.message) {
        'proRequired' || 'OWNER_NOT_PRO' => FamilyMutationFailure.proRequired,
        'alreadyFamily' ||
        'ALREADY_IN_FAMILY' ||
        'ALREADY_MEMBER' => FamilyMutationFailure.alreadyFamily,
        'IN_PROGRESS' ||
        'FAMILY_PREPARING' ||
        'FAMILY_DISSOLVING' => FamilyMutationFailure.inProgress,
        'accountUnavailable' ||
        'invalidPrivateState' ||
        'initializationRequired' ||
        'ACCOUNT_UNAVAILABLE' ||
        'ACCOUNT_NOT_READY' => FamilyMutationFailure.accountUnavailable,
        'FAMILY_FULL' => FamilyMutationFailure.capacity,
        'PENDING_LIMIT' => FamilyMutationFailure.pendingLimit,
        'NOT_OWNER' => FamilyMutationFailure.notOwner,
        _ => FamilyMutationFailure.unavailable,
      };
      throw FamilyMutationException(reason);
    } on FamilyMutationException {
      rethrow;
    } catch (_) {
      throw const FamilyMutationException(FamilyMutationFailure.unavailable);
    } finally {
      await subscription.cancel();
    }
  }
}
