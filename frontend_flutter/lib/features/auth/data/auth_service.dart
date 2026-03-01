import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  AuthService._();
  static final instance = AuthService._();

  final _auth = FirebaseAuth.instance;

  User? get user => _auth.currentUser;

  Future<void> signOut() async {
    await _auth.signOut();
    // if google sign in used, disconnect optional:
    try { await GoogleSignIn().signOut(); } catch (_) {}
  }

  // Email/password login
  Future<void> login(String email, String password) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  // Register + send verification email
  Future<void> register(String email, String password, {String? displayName}) async {
    await _auth.createUserWithEmailAndPassword(email: email, password: password);
    if (displayName != null && displayName.trim().isNotEmpty) {
      await _auth.currentUser?.updateDisplayName(displayName.trim());
    }
    await sendEmailVerification();
  }

  Future<void> sendEmailVerification() async {
    final u = _auth.currentUser;
    if (u != null && !u.emailVerified) {
      await u.sendEmailVerification();
    }
  }

  Future<void> reloadUser() async {
    await _auth.currentUser?.reload();
  }

  Future<void> sendPasswordReset(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  // Google sign in
  Future<void> signInWithGoogle() async {
    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) {
      // user canceled
      return;
    }

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    await _auth.signInWithCredential(credential);
  }
}