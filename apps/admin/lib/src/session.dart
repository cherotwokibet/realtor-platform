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

/// Sign-in for the admin: Firebase email + password or Google on Hosting,
/// demo accounts everywhere else. Passwords go straight to Firebase Auth;
/// the admin never stores or logs them.
abstract interface class AdminAuth {
  /// The current session first, then every change.
  Stream<Session> get sessions;

  /// Accounts to pick from on the sign-in screen; empty with real sign-in.
  List<StaffUser> get demoAccounts;

  /// Demo only.
  Future<void> signInAs(StaffUser user);

  Future<void> signInWithPassword(String email, String password);

  /// Makes an account with no role; an owner then gives it one.
  Future<void> createAccount(String email, String password);

  /// Emails a link to set a new password.
  Future<void> sendPasswordReset(String email);

  Future<void> signInWithGoogle();

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
  Future<void> signInWithPassword(String email, String password) => throw UnsupportedError('demo accounts only');

  @override
  Future<void> createAccount(String email, String password) => throw UnsupportedError('demo accounts only');

  @override
  Future<void> sendPasswordReset(String email) => throw UnsupportedError('demo accounts only');

  @override
  Future<void> signInWithGoogle() => throw UnsupportedError('demo accounts only');

  @override
  Future<void> refresh() async {}
}
