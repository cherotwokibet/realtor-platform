import 'package:firebase_auth/firebase_auth.dart';
import 'package:realtor_core/realtor_core.dart';

import '../session.dart';
import 'email_store.dart';

/// Email-link sign-in. The staff role comes from the ID token's claims,
/// which only the setStaffRole Function sets.
class FirebaseAdminAuth implements AdminAuth {
  FirebaseAdminAuth(this._auth, {required this.link});

  final FirebaseAuth _auth;

  /// The address the admin was opened at.
  final Uri link;

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
  Future<void> signInAs(StaffUser user) => throw UnsupportedError('use an email link');

  @override
  Future<void> sendSignInLink(String email) async {
    try {
      await _auth.sendSignInLinkToEmail(
        email: email,
        actionCodeSettings:
            ActionCodeSettings(url: link.replace(path: '/sign-in', query: null).toString(), handleCodeInApp: true),
      );
      writeSignInEmail(email);
    } on FirebaseAuthException catch (e) {
      throw SignInException(e.message ?? 'Could not send the link (${e.code}).');
    }
  }

  @override
  bool get openedFromLink => _auth.isSignInWithEmailLink(link.toString());

  @override
  String? get rememberedEmail => readSignInEmail();

  @override
  Future<void> completeSignIn(String email) async {
    try {
      await _auth.signInWithEmailLink(email: email, emailLink: link.toString());
      writeSignInEmail(null);
    } on FirebaseAuthException catch (e) {
      throw SignInException(switch (e.code) {
        'invalid-action-code' ||
        'expired-action-code' =>
          'This link has expired or was already used. Ask for a new one.',
        'invalid-email' => 'That is not the email the link was sent to.',
        _ => e.message ?? 'Could not sign in (${e.code}).',
      });
    }
  }

  @override
  Future<void> refresh() async => _auth.currentUser?.getIdToken(true);

  @override
  Future<void> signOut() => _auth.signOut();
}
