import 'package:firebase_auth/firebase_auth.dart';
import 'package:realtor_core/realtor_core.dart';

import '../session.dart';

/// Email + password and Google sign-in (D14). The staff role comes from the
/// ID token's claims, which only the setStaffRole Function sets.
class FirebaseAdminAuth implements AdminAuth {
  FirebaseAdminAuth(this._auth);

  final FirebaseAuth _auth;

  @override
  Stream<Session> get sessions => _auth.idTokenChanges().asyncMap(_sessionFor);

  Future<Session> _sessionFor(User? user) async {
    if (user == null) return const SignedOut();
    final claims = (await user.getIdTokenResult()).claims ?? const {};
    final staff = StaffUser.fromClaims(user.uid, user.displayName ?? user.email ?? user.uid, claims);
    return staff == null ? NotStaff(user.email) : SignedIn(staff);
  }

  @override
  List<StaffUser> get demoAccounts => const [];

  @override
  Future<void> signInAs(StaffUser user) => throw UnsupportedError('demo accounts only');

  @override
  Future<void> signInWithPassword(String email, String password) => _run(() => _auth.signInWithEmailAndPassword(email: email, password: password));

  @override
  Future<void> createAccount(String email, String password) => _run(() => _auth.createUserWithEmailAndPassword(email: email, password: password));

  @override
  Future<void> sendPasswordReset(String email) => _run(() => _auth.sendPasswordResetEmail(email: email));

  @override
  Future<void> signInWithGoogle() => _run(() => _auth.signInWithPopup(GoogleAuthProvider()));

  Future<void> _run(Future<Object?> Function() action) async {
    try {
      await action();
    } on FirebaseAuthException catch (e) {
      // Closing the Google window is not an error worth showing.
      if (e.code == 'popup-closed-by-user' || e.code == 'cancelled-popup-request') return;
      throw SignInException(signInMessage(e.code, e.message));
    }
  }

  @override
  Future<void> refresh() async {
    await _auth.currentUser?.reload();
    await _auth.currentUser?.getIdToken(true);
  }

  @override
  String? get email => _auth.currentUser?.email;

  @override
  bool get hasPassword => _auth.currentUser?.providerData.any((p) => p.providerId == 'password') ?? false;

  @override
  Future<void> changePassword(String current, String next) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) throw SignInException('Sign in again first.');
    try {
      await user.reauthenticateWithCredential(EmailAuthProvider.credential(email: user.email!, password: current));
      await user.updatePassword(next);
    } on FirebaseAuthException catch (e) {
      throw SignInException(switch (e.code) {
        'invalid-credential' || 'wrong-password' => 'Your current password is not right.',
        _ => signInMessage(e.code, e.message),
      });
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();
}

/// What to tell the person for a Firebase Auth error code.
String signInMessage(String code, String? fallback) => switch (code) {
      'invalid-credential' || 'wrong-password' || 'user-not-found' => 'That email and password do not match an account.',
      'invalid-email' => 'That email address does not look right.',
      'email-already-in-use' => 'There is already an account with that email. Sign in instead.',
      'weak-password' => 'Choose a longer password (at least 8 characters).',
      'too-many-requests' => 'Too many attempts. Wait a few minutes, or reset your password.',
      'user-disabled' => 'This account has been switched off. Ask the owner.',
      'popup-blocked' => 'The browser blocked the Google window. Allow pop-ups for this site and try again.',
      'operation-not-allowed' => 'This way of signing in is not switched on for this project yet.',
      'network-request-failed' => 'No connection. Check the internet and try again.',
      _ => fallback ?? 'Could not sign in ($code).',
    };
