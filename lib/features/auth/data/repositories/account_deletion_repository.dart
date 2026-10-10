import 'dart:async';
import 'account_deletion_gateway.dart';
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
  }) : _auth = firebaseAuth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _authRepository = AuthRepository(
         firebaseAuth: firebaseAuth,
         googleSignIn: googleSignIn,
       );

  /// Null preserves the released legacy flow; no undeployed endpoint is called.
  final AccountDeletionGateway? coordination;
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final AuthRepository _authRepository;
  bool _deleting = false;

  bool get requiresPassword => _authRepository.isEmailPasswordUser;

  Future<void> deleteCurrentAccount({String? password}) async {
    if (_deleting) throw StateError('Deletion already running');
    _deleting = true;
    StreamSubscription<User?>? sessionWatch;
    try {
      final user = _auth.currentUser;
      if (user == null) throw StateError('No authenticated user');
      final uid = user.uid;
      var sessionChanged = false;
      if (coordination != null) {
        sessionWatch = _auth.authStateChanges().listen((current) {
          if (current?.uid != uid) sessionChanged = true;
        });
      }
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
      if (coordination != null) {
        await coordination!.begin();
        checkOwner();
      }
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
      if (coordination == null) {
        await user.delete();
      } else {
        final result = await coordination!.finalize();
        // Backend completion may itself remove the current Auth session.
        // Never perform local provider cleanup against a replacement account.
        if (_auth.currentUser != null) checkOwner();
        if (result != DeletionCompletion.completed) {
          throw DeletionResumeRequired(result);
        }
      }
      // Auth deletion succeeded. Provider cleanup cannot turn it into failure.
      if (hasGoogle) {
        try {
          await _authRepository.cleanUpGoogleAfterAccountDeletion();
        } catch (_) {
          // No automatic/silent Google sign-in exists in this application.
        }
      }
    } finally {
      unawaited(sessionWatch?.cancel());
      _deleting = false;
    }
  }
}
