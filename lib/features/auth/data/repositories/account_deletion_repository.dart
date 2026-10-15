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
  }) : _auth = firebaseAuth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _authRepository = AuthRepository(
         firebaseAuth: firebaseAuth,
         googleSignIn: googleSignIn,
       );

  /// Optional test adapter. Null selects the production coordinated gateway.
  final AccountDeletionGateway? coordination;
  final Future<void> Function()? onDeletionStarted;
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
    try {
      final user = _auth.currentUser;
      if (user == null) throw StateError('No authenticated user');
      final uid = user.uid;
      var sessionChanged = false;
      var replacementSeen = false;
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
    } finally {
      unawaited(sessionWatch?.cancel());
      _deleting = false;
      AccountDeletionSignal.end();
    }
  }
}
