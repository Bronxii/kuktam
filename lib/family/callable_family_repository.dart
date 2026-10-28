import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'family_join.dart';
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

  Future<Object?> _mutate(
    String name, {
    Map<String, Object?> data = const {},
    bool join = false,
  }) async {
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
          .call<Object?>(data);
      check();
      return result.data;
    } on FirebaseFunctionsException catch (error) {
      check();
      if (join) throw FamilyJoinException(error.message ?? 'UNAVAILABLE');
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
    } on FamilyJoinException {
      rethrow;
    } on FamilyMutationException {
      rethrow;
    } catch (_) {
      throw const FamilyMutationException(FamilyMutationFailure.unavailable);
    } finally {
      await subscription.cancel();
    }
  }

  @override
  Future<FamilyInvitePreview> previewInvite(String code) async =>
      FamilyInvitePreview.parse(
        await _mutate(
          'previewFamilyInvite',
          data: {'token': code.trim()},
          join: true,
        ),
      );
  @override
  Future<FamilyJoinHandle> startJoin(String code, FamilyJoinMode mode) async {
    final token = code.trim();
    final raw = await _mutate(
      'acceptFamilyInvite',
      data: {'token': token, 'mode': mode.wire},
      join: true,
    );
    if (raw is! Map ||
        raw['schemaVersion'] != 1 ||
        raw['operationId'] is! String ||
        (raw['operationId'] as String).isEmpty ||
        (raw['operationId'] as String).length > 128 ||
        (raw['operationId'] as String).trim() != raw['operationId'] ||
        (raw['operationId'] as String).contains('/')) {
      throw const FamilyJoinException('UNAVAILABLE');
    }
    if (raw['outcome'] == 'ABORTED') throw const FamilyJoinException('REVOKED');
    if (![
      'RESERVED',
      'READY_FOR_TRANSFER',
      'SNAPSHOT_SOURCE',
      'SOURCE_FENCED_WAITING_CONFIRMATION',
      'COMMITTED_TRANSFER',
      'CLEAN_SOURCE',
      'TRANSFER_COMPLETE',
      'ACTIVE',
      'DONE',
      'IN_PROGRESS',
      'notDueOrBusy',
      'retry',
      'OPERATOR',
    ].contains(raw['outcome'])) {
      throw const FamilyJoinException('UNAVAILABLE');
    }
    return FamilyJoinHandle(
      raw['operationId'] as String,
      sha256.convert(utf8.encode(token)).toString(),
      mode,
    );
  }

  @override
  Future<FamilyJoinProgress> prepareJoin(FamilyJoinHandle handle) async =>
      FamilyJoinProgress.parse(
        await _mutate(
          'prepareFamilyJoinTransfer',
          data: handle.request,
          join: true,
        ),
        handle,
      );
  @override
  Future<FamilyJoinProgress> readJoin(FamilyJoinHandle handle) async =>
      FamilyJoinProgress.parse(
        await _mutate(
          'getFamilyJoinTransferState',
          data: handle.request,
          join: true,
        ),
        handle,
      );
  @override
  Future<void> confirmJoinDelete(FamilyJoinProgress progress) async {
    final raw = await _mutate(
      'confirmFamilyJoinDelete',
      data: progress.consent,
      join: true,
    );
    if (raw is! Map ||
        raw['schemaVersion'] != 1 ||
        ![
          'COMMITTED_TRANSFER',
          'CLEAN_SOURCE',
          'TRANSFER_COMPLETE',
          'ACTIVE',
          'IN_PROGRESS',
          'ABORTED',
        ].contains(raw['outcome'])) {
      throw const FamilyJoinException('UNAVAILABLE');
    }
  }

  @override
  Future<void> cancelJoin(FamilyJoinHandle handle) async {
    final raw = await _mutate(
      'cancelFamilyJoin',
      data: handle.request,
      join: true,
    );
    if (raw is! Map ||
        raw['schemaVersion'] != 1 ||
        !['ABORTED', 'IN_PROGRESS'].contains(raw['outcome'])) {
      throw const FamilyJoinException('UNAVAILABLE');
    }
  }
}
