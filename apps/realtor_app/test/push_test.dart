import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtor_app/src/account/account_data.dart';
import 'package:realtor_app/src/account/account_screen.dart';
import 'package:realtor_app/src/account/push.dart';
import 'package:realtor_app/src/app.dart';
import 'package:realtor_app/src/firebase/firebase_push.dart';
import 'package:realtor_app/src/providers.dart';

import 'account_test.dart' show MemoryPendingEmail;
import 'listing_screen_test.dart' show tenant;

class FakeClient implements PushClient {
  bool allow = true;
  bool asked = false;
  String? current = 'tok-1';
  final refresh = StreamController<String>.broadcast();
  final taps = StreamController<Map<String, Object?>>.broadcast();
  int deleted = 0;

  @override
  Future<bool> requestPermission() async {
    asked = true;
    return allow;
  }

  @override
  Future<bool> hasPermission() async => allow && asked;
  @override
  Future<String?> token() async => current;
  @override
  Stream<String> get tokenRefresh => refresh.stream;
  @override
  Future<void> deleteToken() async => deleted++;
  @override
  Stream<Map<String, Object?>> get tapped => taps.stream;
}

/// Records calls; taps come from [taps].
class RecordingPush implements PushAlerts {
  final calls = <String>[];
  final taps = StreamController<String>.broadcast();
  @override
  Future<bool> enable(String uid) async {
    calls.add('enable $uid');
    return true;
  }

  @override
  Future<void> resume(String uid) async => calls.add('resume $uid');
  @override
  Future<void> disable(String uid) async => calls.add('disable $uid');
  @override
  Stream<String> get opened => taps.stream;
}

void main() {
  test('a phone registers its token in the shape the rules allow, refreshes it, and forgets it on sign-out', () async {
    final db = FakeFirebaseFirestore();
    final client = FakeClient();
    final push = DevicePushAlerts(client, db, platform: 'android');
    final devices = db.collection('users').doc('alice').collection('devices');

    await push.resume('alice');
    expect((await devices.get()).docs, isEmpty, reason: 'no registering before the person says yes');

    expect(await push.enable('alice'), isTrue);
    final doc = (await devices.doc('tok-1').get()).data()!;
    expect(doc.keys.toSet(), {'token', 'platform', 'updatedAt'});
    expect(doc['token'], 'tok-1');
    expect(doc['platform'], 'android');

    client.refresh.add('tok-2');
    await Future<void>.delayed(Duration.zero);
    expect((await devices.get()).docs.map((d) => d.id).toSet(), {'tok-1', 'tok-2'});

    client.current = 'tok-2';
    await push.disable('alice');
    expect((await devices.get()).docs.map((d) => d.id), ['tok-1'], reason: 'this phone\'s current token is removed; the sweep drops stale ones');
    expect(client.deleted, 1);
  });

  test('a refusal registers nothing', () async {
    final db = FakeFirebaseFirestore();
    final push = DevicePushAlerts(FakeClient()..allow = false, db, platform: 'android');
    expect(await push.enable('alice'), isFalse);
    expect((await db.collection('users').doc('alice').collection('devices').get()).docs, isEmpty);
  });

  test('taps open only paths inside the app', () async {
    final client = FakeClient();
    final push = DevicePushAlerts(client, FakeFirebaseFirestore(), platform: 'android');
    final got = <String>[];
    final sub = push.opened.listen(got.add);
    for (final p in ['/listing/2br-kilimani', 'https://evil.example/', '//evil.example', 7, null, '/account']) {
      client.taps.add({'path': p});
    }
    await Future<void>.delayed(Duration.zero);
    expect(got, ['/listing/2br-kilimani', '/account']);
    await sub.cancel();
  });

  testWidgets('saving a search turns on push, a tap opens the home, and signing out turns it off', (tester) async {
    tester.view.physicalSize = const Size(412, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final account = DemoAccount();
    final push = RecordingPush();
    final c = ProviderContainer(overrides: [
      tenantProvider.overrideWithValue(tenant()),
      demoAccountProvider.overrideWithValue(account),
      pendingEmailProvider.overrideWithValue(MemoryPendingEmail()),
      openedAtProvider.overrideWithValue(Uri.parse('https://app.example/')),
      pushAlertsProvider.overrideWithValue(push),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const RealtorApp()));
    await tester.pumpAndSettle();

    await account.signInWithGoogle();
    await tester.pumpAndSettle();
    expect(push.calls, ['resume demo-customer'], reason: 'a signed-in phone registers again on start');

    c.read(routerProvider).go('/rent/apartments');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Get alerts for new matches'));
    await tester.pumpAndSettle();
    expect(push.calls.last, 'enable demo-customer');

    push.taps.add('/listing/some-home');
    await tester.pumpAndSettle();
    expect(c.read(routerProvider).state.uri.path, '/listing/some-home');

    c.read(routerProvider).go('/account');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(push.calls.last, 'disable demo-customer');
    expect(find.text('Email me a sign-in link'), findsOneWidget);
  });
}
