import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtor_admin/src/app.dart';
import 'package:realtor_admin/src/providers.dart';
import 'package:realtor_admin/src/session.dart';
import 'package:realtor_core/realtor_core.dart';

TenantConfig tenant() => TenantConfig.fromJson(
    jsonDecode(File('../../tenants/realtime-estates.json').readAsStringSync()) as Map<String, Object?>);

/// Email-link sign-in without Firebase.
class FakeLinkAuth implements AdminAuth {
  FakeLinkAuth({this.openedFromLink = false, this.rememberedEmail, this.failWith});

  final _changes = StreamController<Session>.broadcast();
  final sent = <String>[];
  final completed = <String>[];
  var refreshed = 0;
  final String? failWith;

  void emit(Session s) => _changes.add(s);

  @override
  Stream<Session> get sessions => _changes.stream;
  @override
  List<StaffUser> get demoAccounts => const [];
  @override
  final bool openedFromLink;
  @override
  final String? rememberedEmail;

  @override
  Future<void> sendSignInLink(String email) async {
    if (failWith != null) throw SignInException(failWith!);
    sent.add(email);
  }

  @override
  Future<void> completeSignIn(String email) async {
    if (failWith != null) throw SignInException(failWith!);
    completed.add(email);
  }

  @override
  Future<void> refresh() async => refreshed++;
  @override
  Future<void> signInAs(StaffUser user) => throw UnsupportedError('');
  @override
  Future<void> signOut() async => emit(const SignedOut());
}

late ProviderContainer container;

Future<void> open(WidgetTester tester, FakeLinkAuth auth, {Session first = const SignedOut()}) async {
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

void main() {
  testWidgets('emails a link, then says where it went', (tester) async {
    final auth = FakeLinkAuth();
    await open(tester, auth);
    expect(find.text('Wanjiku Mwangi'), findsNothing);
    final send = find.widgetWithText(FilledButton, 'Email me a link');
    expect(tester.widget<FilledButton>(send).onPressed, isNull);
    await tester.enterText(find.byType(TextField), ' boss@example.com ');
    await tester.pump();
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(auth.sent, ['boss@example.com']);
    expect(find.textContaining('We sent a sign-in link to boss@example.com'), findsOneWidget);
  });

  testWidgets('opened from the link in the same browser, it finishes by itself', (tester) async {
    final auth = FakeLinkAuth(openedFromLink: true, rememberedEmail: 'boss@example.com');
    await open(tester, auth);
    expect(auth.completed, ['boss@example.com']);
    auth.emit(const SignedIn(StaffUser(uid: 'u', name: 'Boss', role: StaffRole.owner)));
    await tester.pumpAndSettle();
    expect(location(), '/leads');
  });

  testWidgets('opened from the link elsewhere, it asks for the email first', (tester) async {
    final auth = FakeLinkAuth(openedFromLink: true);
    await open(tester, auth);
    expect(auth.completed, isEmpty);
    await tester.enterText(find.byType(TextField), 'boss@example.com');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(auth.completed, ['boss@example.com']);
  });

  testWidgets('shows why sign-in failed', (tester) async {
    final auth =
        FakeLinkAuth(openedFromLink: true, rememberedEmail: 'boss@example.com', failWith: 'This link has expired.');
    await open(tester, auth);
    expect(find.text('This link has expired.'), findsOneWidget);
  });

  testWidgets('an account with no staff role waits for an owner, and can check again', (tester) async {
    final auth = FakeLinkAuth();
    await open(tester, auth, first: const NotStaff('new@example.com'));
    expect(location(), signInPath);
    expect(find.textContaining('new@example.com, but it has no staff role yet'), findsOneWidget);
    await tester.tap(find.text('Check again'));
    await tester.pumpAndSettle();
    expect(auth.refreshed, 1);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Email me a link'), findsOneWidget);
  });

  testWidgets('a deep link survives start-up and opens once the role is known', (tester) async {
    final auth = FakeLinkAuth();
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
}
