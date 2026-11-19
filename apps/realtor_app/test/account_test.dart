import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtor_app/src/account/account_data.dart';
import 'package:realtor_app/src/account/account_screen.dart';
import 'package:realtor_app/src/app.dart';
import 'package:realtor_app/src/providers.dart';
import 'package:realtor_app/src/search/demo_search.dart';
import 'package:realtor_core/realtor_core.dart';

import 'listing_screen_test.dart' show tenant;

class MemoryPendingEmail implements PendingEmail {
  String? email;
  @override
  Future<String?> read() async => email;
  @override
  Future<void> write(String? e) async => email = e;
}

late DemoAccount account;
late MemoryPendingEmail pending;

Future<ProviderContainer> open(WidgetTester tester, String path, {Uri? openedAt}) async {
  tester.view.physicalSize = const Size(412, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final c = ProviderContainer(overrides: [
    tenantProvider.overrideWithValue(tenant()),
    demoAccountProvider.overrideWithValue(account),
    pendingEmailProvider.overrideWithValue(pending),
    openedAtProvider.overrideWithValue(openedAt ?? Uri.parse('https://app.example$path')),
  ]);
  addTearDown(c.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const RealtorApp()));
  await tester.pumpAndSettle();
  c.read(routerProvider).go(path);
  await tester.pumpAndSettle();
  return c;
}

void main() {
  setUp(() {
    account = DemoAccount();
    pending = MemoryPendingEmail();
  });

  test('alerts keep only what they can match on', () {
    const f = ListingFilters(purpose: Purpose.rent, q: 'quiet', types: ['apartment'], areas: ['kilimani'], minBeds: 2, maxPriceKES: 60000);
    expect(alertFilters(f), {
      'purpose': 'rent',
      'types': ['apartment'],
      'areas': ['kilimani'],
      'minBeds': 2,
      'maxPriceKES': 60000
    });
    expect(describeSearch(filtersFromAlert(alertFilters(f))), 'Rent · Apartment · Kilimani · 2+ bed · up to KES 60,000');
  });

  testWidgets('signed out, "Get alerts" asks to sign in; the emailed link signs in on this device', (tester) async {
    await open(tester, '/rent/apartments');
    await tester.tap(find.text('Get alerts for new matches'));
    await tester.pumpAndSettle();
    expect(find.text('Email me a sign-in link'), findsOneWidget);
    expect(find.text('Sign in to get alerts for: Rent · Apartment'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('email')), 'amina@example.com');
    await tester.tap(find.text('Email me a sign-in link'));
    await tester.pumpAndSettle();
    expect(account.sentLinks, ['amina@example.com']);
    expect(pending.email, 'amina@example.com');
    expect(find.textContaining('Check amina@example.com'), findsOneWidget);
  });

  testWidgets('Account links to the site pages on the share site', (tester) async {
    final opened = <Uri>[];
    tester.view.physicalSize = const Size(412, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(overrides: [
      tenantProvider.overrideWithValue(tenant()),
      demoAccountProvider.overrideWithValue(account),
      pendingEmailProvider.overrideWithValue(pending),
      openedAtProvider.overrideWithValue(Uri.parse('https://app.example/account')),
      urlOpenerProvider.overrideWithValue((u) async {
        opened.add(u);
        return true;
      }),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const RealtorApp()));
    c.read(routerProvider).go('/account');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Privacy'));
    expect(opened.single.toString(), 'https://realtimeestates.co.ke/privacy');
  });

  testWidgets('opening the link signs in; alerts show in Account and the saved search under Saved > Searches', (tester) async {
    pending.email = 'amina@example.com';
    final c = await open(tester, '/account', openedAt: Uri.parse('https://app.example/account?mode=signIn&oobCode=abc&apiKey=k'));
    expect(find.text('amina@example.com'), findsOneWidget);
    expect(pending.email, isNull);

    c.read(routerProvider).go('/rent/apartments/kilimani');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Get alerts for new matches'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Saved: Rent · Apartment · Kilimani'), findsOneWidget);

    final l = demoListings.firstWhere((l) => l.purpose == Purpose.rent);
    account.addAlert(
        (id: 'a1', slug: l.slug, title: l.title, priceKES: l.priceKES, purpose: l.purpose, area: l.area, createdAt: DateTime(2026, 10, 29), read: false));
    c.read(routerProvider).go('/account');
    await tester.pumpAndSettle();
    await tester.tap(find.text(l.title));
    await tester.pumpAndSettle();
    expect(c.read(routerProvider).state.uri.path, '/listing/${l.slug}');

    // Account links to the saved searches; they are listed under Saved > Searches.
    c.read(routerProvider).go('/account');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Saved searches and alerts'));
    await tester.tap(find.text('Saved searches and alerts'));
    await tester.pumpAndSettle();
    expect(c.read(routerProvider).state.uri.toString(), '/saved?tab=searches');
    expect(find.text('Apartment to rent'), findsOneWidget);
    expect(find.text('Kilimani'), findsOneWidget);
    await tester.tap(find.byTooltip('Stop these alerts'));
    await tester.pumpAndSettle();
    expect(find.textContaining('then tap "Get alerts"'), findsOneWidget);
  });

  testWidgets('on a phone, the emailed link opens the app at /__/auth/links and signs in', (tester) async {
    pending.email = 'amina@example.com';
    final c = await open(tester, '/');
    const inner = 'https://demo-app.web.app/__/auth/action?mode=signIn&oobCode=abc&apiKey=k';
    c.read(routerProvider).go(Uri(path: '/__/auth/links', queryParameters: {'link': inner}).toString());
    await tester.pumpAndSettle();
    expect(find.text('amina@example.com'), findsOneWidget);
    expect(pending.email, isNull);
    expect(c.read(routerProvider).state.uri.path, '/account');
  });

  testWidgets('after signing in, Account offers the search "Get alerts" was tapped on', (tester) async {
    final c = await open(tester, '/rent/apartments/kilimani');
    await tester.tap(find.text('Get alerts for new matches'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Get alerts for Rent · Apartment · Kilimani'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Saved: Rent · Apartment · Kilimani'), findsOneWidget);
    expect(find.text('Get alerts for Rent · Apartment · Kilimani'), findsNothing);
    expect(c.read(pendingAlertProvider), isNull);
    c.read(routerProvider).go('/saved?tab=searches');
    await tester.pumpAndSettle();
    expect(find.text('Apartment to rent'), findsOneWidget, reason: 'listed under Saved > Searches');
  });

  testWidgets('Account says what an alert will match when the search had typed words', (tester) async {
    await open(tester, '/rent?q=near+the+mall');
    await tester.tap(find.text('Get alerts for new matches'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to get alerts for: Rent'), findsOneWidget);
    expect(find.text('Alerts match the filters, not the words "near the mall".'), findsOneWidget);
  });
}
