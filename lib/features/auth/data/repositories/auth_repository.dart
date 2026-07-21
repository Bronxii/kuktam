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

  Stream<User?> authStateChanges() {
    return _firebaseAuth.authStateChanges();
  }
  Future<UserCredential> signInWithGoogle() async {
    await _googleSignIn.initialize();

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
}