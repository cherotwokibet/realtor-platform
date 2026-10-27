import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtor_admin/src/app.dart';
import 'package:realtor_admin/src/firebase/firebase_auth.dart';
import 'package:realtor_admin/src/providers.dart';
import 'package:realtor_admin/src/session.dart';
import 'package:realtor_core/realtor_core.dart';

TenantConfig tenant() => TenantConfig.fromJson(
    jsonDecode(File('../../tenants/realtime-estates.json').readAsStringSync()) as Map<String, Object?>);

/// Password and Google sign-in without Firebase.
class FakeAuth implements AdminAuth {
  FakeAuth({this.failWith});

  final _changes = StreamController<Session>.broadcast();
  final calls = <String>[];
  var refreshed = 0;
  final String? failWith;

  void emit(Session s) => _changes.add(s);

  Future<void> _call(String what) async {
    if (failWith != null) throw SignInException(failWith!);
    calls.add(what);
  }

  @override
  Stream<Session> get sessions => _changes.stream;
  @override
  List<StaffUser> get demoAccounts => const [];
  @override
  Future<void> signInWithPassword(String email, String password) => _call('signIn $email $password');
  @override
  Future<void> createAccount(String email, String password) => _call('create $email $password');
  @override
  Future<void> sendPasswordReset(String email) => _call('reset $email');
  @override
  Future<void> signInWithGoogle() => _call('google');
  @override
  Future<void> refresh() async => refreshed++;
  @override
  Future<void> signInAs(StaffUser user) => throw UnsupportedError('');
  @override
  Future<void> signOut() async => emit(const SignedOut());
}

late ProviderContainer container;

Future<void> open(WidgetTester tester, FakeAuth auth, {Session first = const SignedOut()}) async {
  tester.view.physicalSize = const Size(1280, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  container = ProviderContainer(overrides: [
    tenantProvider.overrideWithValue(tenant()),
    adminAuthProvider.overrideWithValue(auth),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const AdminApp()));
  await tester.pump();
  auth.emit(first);
  await tester.pumpAndSettle();
}

String location() => container.read(routerProvider).routerDelegate.currentConfiguration.uri.path;

Finder field(String label) => find.widgetWithText(TextField, label);

void main() {
  testWidgets('signs in with email and password', (tester) async {
    final auth = FakeAuth();
    await open(tester, auth);
    expect(find.text('Wanjiku Mwangi'), findsNothing);
    final signIn = find.widgetWithText(FilledButton, 'Sign in');
    expect(tester.widget<FilledButton>(signIn).onPressed, isNull);
    await tester.enterText(field('Work email'), ' boss@example.com ');
    await tester.enterText(field('Password'), 'pa55word');
    await tester.pump();
    await tester.tap(signIn);
    await tester.pumpAndSettle();
    expect(auth.calls, ['signIn boss@example.com pa55word']);
    auth.emit(const SignedIn(StaffUser(uid: 'u', name: 'Boss', role: StaffRole.owner)));
    await tester.pumpAndSettle();
    expect(location(), '/leads');
  });

  testWidgets('creates an account only with a password of at least 8 characters', (tester) async {
    final auth = FakeAuth();
    await open(tester, auth);
    await tester.tap(find.text('New here? Create an account'));
    await tester.pump();
    await tester.enterText(field('Work email'), 'new@example.com');
    await tester.enterText(field('Password'), 'short');
    await tester.pump();
    final create = find.widgetWithText(FilledButton, 'Create account');
    expect(tester.widget<FilledButton>(create).onPressed, isNull);
    await tester.enterText(field('Password'), 'longer-pass');
    await tester.pump();
    await tester.tap(create);
    await tester.pumpAndSettle();
    expect(auth.calls, ['create new@example.com longer-pass']);
  });

  testWidgets('sends a password reset once an email is typed', (tester) async {
    final auth = FakeAuth();
    await open(tester, auth);
    final forgot = find.widgetWithText(TextButton, 'Forgot password?');
    expect(tester.widget<TextButton>(forgot).onPressed, isNull);
    await tester.enterText(field('Work email'), 'boss@example.com');
    await tester.pump();
    await tester.tap(forgot);
    await tester.pumpAndSettle();
    expect(auth.calls, ['reset boss@example.com']);
    expect(find.textContaining('a link to set a new password is on its way'), findsOneWidget);
  });

  testWidgets('continues with Google', (tester) async {
    final auth = FakeAuth();
    await open(tester, auth);
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(auth.calls, ['google']);
  });

  testWidgets('shows why sign-in failed and never shows the password', (tester) async {
    final auth = FakeAuth(failWith: 'That email and password do not match an account.');
    await open(tester, auth);
    await tester.enterText(field('Work email'), 'boss@example.com');
    await tester.enterText(field('Password'), 'secret-typed');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('That email and password do not match an account.'), findsOneWidget);
    expect(tester.widget<TextField>(field('Password')).obscureText, isTrue);
  });

  testWidgets('an account with no staff role waits for an owner, and can check again', (tester) async {
    final auth = FakeAuth();
    await open(tester, auth, first: const NotStaff('new@example.com'));
    expect(location(), signInPath);
    expect(find.textContaining('new@example.com, but it has no staff role yet'), findsOneWidget);
    await tester.tap(find.text('Check again'));
    await tester.pumpAndSettle();
    expect(auth.refreshed, 1);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
  });

  testWidgets('a deep link survives start-up and opens once the role is known', (tester) async {
    final auth = FakeAuth();
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    container = ProviderContainer(overrides: [
      tenantProvider.overrideWithValue(tenant()),
      adminAuthProvider.overrideWithValue(auth),
    ]);
    addTearDown(container.dispose);
    container.read(routerProvider).go('/listings');
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const AdminApp()));
    await tester.pump();
    expect(location(), '/listings');
    auth.emit(const SignedIn(StaffUser(uid: 'u', name: 'Boss', role: StaffRole.manager)));
    await tester.pumpAndSettle();
    expect(location(), '/listings');
  });

  test('Firebase error codes become plain messages', () {
    expect(signInMessage('invalid-credential', null), 'That email and password do not match an account.');
    expect(signInMessage('operation-not-allowed', null), contains('not switched on'));
    expect(signInMessage('something-new', 'Raw message'), 'Raw message');
    expect(signInMessage('something-new', null), 'Could not sign in (something-new).');
  });
}
