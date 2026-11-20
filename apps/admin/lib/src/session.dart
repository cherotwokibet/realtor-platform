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

  /// Reads the role again (after an owner changed it), and the name.
  Future<void> refresh();

  /// The signed-in account's email, if any.
  String? get email;

  /// True when the account signs in with a password (not only Google).
  bool get hasPassword;

  /// Checks [current], then sets [next]. Throws [SignInException] with what to fix.
  Future<void> changePassword(String current, String next);

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

  @override
  String? get email => switch (_session) { SignedIn(:final user) => '${user.uid.replaceFirst('demo-', '')}@example.com', _ => null };

  @override
  bool get hasPassword => true;

  /// Demo: "wrong" is the wrong current password; anything else works.
  @override
  Future<void> changePassword(String current, String next) async {
    if (current == 'wrong') throw SignInException('Your current password is not right.');
    if (next.length < 8) throw SignInException('Choose a longer password (at least 8 characters).');
  }

  /// Demo: the new name shows at once, as a token refresh would show it.
  void rename(String name) {
    if (_session case SignedIn(:final user)) _set(SignedIn(StaffUser(uid: user.uid, name: name, role: user.role, agentId: user.agentId)));
  }
}
