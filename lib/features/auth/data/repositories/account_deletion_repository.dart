import 'dart:async';
import '../../../../core/account_deletion_signal.dart';
import 'account_deletion_gateway.dart';
import 'callable_account_deletion_gateway.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'auth_repository.dart';

/// Deletes only the authenticated user's known Kuktám data, then their account.
/// Commits are intentionally retryable; Firestore and Auth are not atomic.
class AccountDeletionRepository {
  AccountDeletionRepository({
    FirebaseAuth? firebaseAuth,
    FirebaseFirestore? firestore,
    GoogleSignIn? googleSignIn,
    this.coordination,
    this.onDeletionStarted,
    this.onLocalShoppingDeletionAccepted,
  }) : _auth = firebaseAuth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _authRepository = AuthRepository(
         firebaseAuth: firebaseAuth,
         googleSignIn: googleSignIn,
       );

  /// Optional test adapter. Null selects the production coordinated gateway.
  final AccountDeletionGateway? coordination;
  final Future<void> Function()? onDeletionStarted;
  final Future<void> Function(String uid)? onLocalShoppingDeletionAccepted;
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final AuthRepository _authRepository;
  bool _deleting = false;

  bool get requiresPassword => _authRepository.isEmailPasswordUser;

  Future<void> deleteCurrentAccount({String? password}) async {
    if (_deleting) throw StateError('Deletion already running');
    _deleting = true;
    AccountDeletionSignal.begin();
    StreamSubscription<User?>? sessionWatch;
    var accepted = false;
    String? deletingUid;
    var sessionChanged = false;
    var replacementSeen = false;
    try {
      final user = _auth.currentUser;
      if (user == null) throw StateError('No authenticated user');
      final uid = user.uid;
      deletingUid = uid;
      sessionWatch = _auth.authStateChanges().listen((current) {
        if (current?.uid != uid) sessionChanged = true;
        if (current != null && (current.uid != uid || sessionChanged)) {
          replacementSeen = true;
        }
      });
      final hasGoogle = user.providerData.any(
        (p) => p.providerId == 'google.com',
      );
      await _authRepository.reauthenticateForAccountDeletion(
        password: password,
      );
      void checkOwner() {
        if (sessionChanged || _auth.currentUser?.uid != uid) {
          throw StateError('Authenticated user changed');
        }
      }

      checkOwner();
      final gateway =
          coordination ??
          CallableAccountDeletionGateway.production(
            canStart: () => !sessionChanged && _auth.currentUser?.uid == uid,
            canComplete: () =>
                !replacementSeen &&
                (_auth.currentUser == null ||
                    (!sessionChanged && _auth.currentUser?.uid == uid)),
          );
      await gateway.begin();
      accepted = true;
      checkOwner();
      await onLocalShoppingDeletionAccepted?.call(uid);
      checkOwner();
      await onDeletionStarted?.call();
      checkOwner();
      final root = _firestore.collection('users').doc(uid);
      for (final name in ['recipes', 'shopping']) {
        // Re-read the first remaining page: no cursor skips after deletion.
        while (true) {
          checkOwner();
          final page = await root
              .collection(name)
              .limit(200)
              .get(const GetOptions(source: Source.server));
          if (page.docs.isEmpty) break;
          checkOwner();
          final batch = _firestore.batch();
          for (final doc in page.docs) {
            batch.delete(doc.reference);
          }
          await batch.commit();
        }
      }
      checkOwner();
      final rootSnapshot = await root.get(
        const GetOptions(source: Source.server),
      );
      checkOwner();
      if (rootSnapshot.exists) await root.delete();
      checkOwner();
      {
        final result = await gateway.finalize();
        // Backend completion may itself remove the current Auth session.
        // Never perform local provider cleanup against a replacement account.
        if (replacementSeen) throw StateError('Authenticated user changed');
        if (_auth.currentUser != null) checkOwner();
        if (result != DeletionCompletion.completed) {
          throw DeletionResumeRequired(result);
        }
      }
      if (_auth.currentUser?.uid == uid && !replacementSeen) {
        await _auth.signOut();
      }
      // Auth deletion succeeded. Provider cleanup cannot turn it into failure.
      if (hasGoogle && _auth.currentUser == null) {
        try {
          await _authRepository.cleanUpGoogleAfterAccountDeletion();
        } catch (_) {
          // No automatic/silent Google sign-in exists in this application.
        }
      }
    } catch (error) {
      if (!accepted) rethrow;
      // Once begin is acknowledged, backend work is durable. Never invite a
      // second delete tap because cleanup/finalize has not converged yet.
      // A replacement session must never be signed out by this operation.
      if (!replacementSeen &&
          !sessionChanged &&
          _auth.currentUser?.uid == deletingUid) {
        try {
          await _auth.signOut();
        } catch (_) {
          // A local sign-out failure cannot undo the accepted backend job.
        }
      }
      throw DeletionResumeRequired(
        error is DeletionResumeRequired
            ? error.outcome
            : DeletionCompletion.retryRequired,
      );
    } finally {
      unawaited(sessionWatch?.cancel());
      _deleting = false;
      AccountDeletionSignal.end();
    }
  }
}
