import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthRepository {
  AuthRepository({
    FirebaseAuth? firebaseAuth,
    GoogleSignIn? googleSignIn,
  })  : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
        _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  final FirebaseAuth _firebaseAuth;
  final GoogleSignIn _googleSignIn;

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
    await _googleSignIn.initialize(
      serverClientId:
      '44537266968-55u1b9ekc1k5293af999qogt57i4mic6.apps.googleusercontent.com',
    );

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
  }) {
    return _firebaseAuth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
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