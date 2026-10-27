import 'dart:async';

import 'package:realtor_core/realtor_core.dart';

/// Who is using the admin.
sealed class Session {
  const Session();
}

/// Until sign-in reports who (if anyone) is using the admin.
class Starting extends Session {
  const Starting();
}

class SignedOut extends Session {
  const SignedOut();
}

/// Signed in, but the account has no staff role (yet): an owner adds it.
class NotStaff extends Session {
  const NotStaff(this.email);
  final String? email;
}

class SignedIn extends Session {
  const SignedIn(this.user);
  final StaffUser user;
}

/// Sign-in for the admin: Firebase email link on Hosting, demo accounts
/// everywhere else.
abstract interface class AdminAuth {
  /// The current session first, then every change.
  Stream<Session> get sessions;

  /// Accounts to pick from on the sign-in screen; empty with real sign-in.
  List<StaffUser> get demoAccounts;

  /// Demo only.
  Future<void> signInAs(StaffUser user);

  /// Emails a one-time sign-in link back to this admin.
  Future<void> sendSignInLink(String email);

  /// True when the admin was opened from a sign-in link.
  bool get openedFromLink;

  /// The email the link was sent to from this browser, if remembered.
  String? get rememberedEmail;

  /// Finishes signing in from the link the admin was opened with.
  Future<void> completeSignIn(String email);

  /// Reads the role again (after an owner changed it).
  Future<void> refresh();

  Future<void> signOut();
}

/// Thrown when sign-in fails in a way the person can fix.
class SignInException implements Exception {
  SignInException(this.message);
  final String message;
  @override
  String toString() => 'SignInException: $message';
}

/// Picks one of [demoAccounts]; nothing leaves the browser.
class DemoAuth implements AdminAuth {
  DemoAuth(this.demoAccounts);

  @override
  final List<StaffUser> demoAccounts;
  Session _session = const SignedOut();
  final _changes = StreamController<Session>.broadcast(sync: true);

  @override
  Stream<Session> get sessions async* {
    yield _session;
    yield* _changes.stream;
  }

  void _set(Session s) => _changes.add(_session = s);

  @override
  Future<void> signInAs(StaffUser user) async => _set(SignedIn(user));

  @override
  Future<void> signOut() async => _set(const SignedOut());

  @override
  Future<void> sendSignInLink(String email) => throw UnsupportedError('demo accounts only');

  @override
  bool get openedFromLink => false;

  @override
  String? get rememberedEmail => null;

  @override
  Future<void> completeSignIn(String email) => throw UnsupportedError('demo accounts only');

  @override
  Future<void> refresh() async {}
}
