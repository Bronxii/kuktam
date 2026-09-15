import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class EmailVerificationRequiredException implements Exception {
  const EmailVerificationRequiredException();
}

class AuthRepository {
  static bool requiresEmailVerification(User? user) =>
      user != null &&
      !user.emailVerified &&
      user.providerData.any((provider) => provider.providerId == 'password');

  AuthRepository({
    FirebaseAuth? firebaseAuth,
    GoogleSignIn? googleSignIn,
  })  : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
        _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  final FirebaseAuth _firebaseAuth;
  final GoogleSignIn _googleSignIn;

  // The Google SDK must be initialized once per instance, including reauth.
  static final _googleInitializations = Expando<Future<void>>();

  Future<void> _initializeGoogle() =>
      _googleInitializations[_googleSignIn] ??= _googleSignIn.initialize(
        serverClientId:
            '44537266968-55u1b9ekc1k5293af999qogt57i4mic6.apps.googleusercontent.com',
      );

  Future<void> reauthenticateForAccountDeletion({String? password}) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) throw StateError('No authenticated user');
    final providers = user.providerData.map((p) => p.providerId);
    final AuthCredential credential;
    if (providers.contains('password')) {
      if (user.email == null || password == null || password.isEmpty) {
        throw FirebaseAuthException(code: 'invalid-credential');
      }
      credential = EmailAuthProvider.credential(
        email: user.email!, password: password,
      );
    } else if (providers.contains('google.com')) {
      await _initializeGoogle();
      // Request fresh credentials; cancellation does not sign out Firebase.
      await _googleSignIn.signOut();
      final account = await _googleSignIn.authenticate();
      credential = GoogleAuthProvider.credential(
        idToken: account.authentication.idToken,
      );
    } else {
      throw FirebaseAuthException(code: 'unsupported-provider');
    }
    await user.reauthenticateWithCredential(credential);
    if (_firebaseAuth.currentUser?.uid != user.uid) {
      throw StateError('Authenticated user changed');
    }
  }

  Future<void> cleanUpGoogleAfterAccountDeletion() async {
    await _initializeGoogle();
    await _googleSignIn.signOut();
  }

  User? get currentUser => _firebaseAuth.currentUser;
  bool get isEmailPasswordUser {
    final user = _firebaseAuth.currentUser;

    if (user == null) {
      return false;
    }

    return user.providerData.any(
          (provider) => provider.providerId == 'password',
    );
  }

  Stream<User?> authStateChanges() {
    return _firebaseAuth.authStateChanges();
  }
  Future<UserCredential> signInWithGoogle() async {
    await _initializeGoogle();

    final googleUser = await _googleSignIn.authenticate();

    final googleAuthentication = googleUser.authentication;

    final credential = GoogleAuthProvider.credential(
      idToken: googleAuthentication.idToken,
    );

    return _firebaseAuth.signInWithCredential(credential);
  }
  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final credential = await _firebaseAuth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    if (requiresEmailVerification(credential.user)) {
      await _firebaseAuth.signOut();
      throw const EmailVerificationRequiredException();
    }
    return credential;
  }
  Future<UserCredential> registerWithEmail({
    required String email,
    required String password,
  }) async {
    final userCredential =
    await _firebaseAuth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    await userCredential.user?.sendEmailVerification();
    await _firebaseAuth.signOut();

    return userCredential;
  }
  Future<void> resetPassword(String email) async {
    try {
      await _firebaseAuth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (error) {
      // Keep the response identical when account enumeration protection is off.
      if (error.code != 'user-not-found') {
        rethrow;
      }
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _firebaseAuth.signOut();
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _firebaseAuth.currentUser;

    if (user == null || user.email == null) {
      throw Exception('Nincs bejelentkezett felhasználó.');
    }

    final credential = EmailAuthProvider.credential(
      email: user.email!,
      password: currentPassword,
    );

    await user.reauthenticateWithCredential(credential);
    await user.updatePassword(newPassword);
  }

  Future<void> changeEmail({
    required String currentPassword,
    required String newEmail,
  }) async {
    final user = _firebaseAuth.currentUser;
    final currentEmail = user?.email;

    if (user == null || currentEmail == null) {
      throw Exception('Nincs bejelentkezett felhasználó.');
    }

    final credential = EmailAuthProvider.credential(
      email: currentEmail,
      password: currentPassword,
    );

    await user.reauthenticateWithCredential(credential);

    await user.verifyBeforeUpdateEmail(
      newEmail.trim(),
    );
  }
}
