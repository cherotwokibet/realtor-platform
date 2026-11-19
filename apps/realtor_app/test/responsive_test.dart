import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtor_app/src/account/account_data.dart';
import 'package:realtor_app/src/app.dart';
import 'package:realtor_app/src/providers.dart';
import 'package:realtor_app/src/saved/favourites.dart';
import 'package:realtor_core/realtor_core.dart';

import 'favourites_test.dart' show MemoryStore;

Future<void> pumpAt(WidgetTester tester, Size size, {String tenantId = 'demo-homes'}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final tenant = TenantConfig.fromJson(
    jsonDecode(File('../../tenants/$tenantId.json').readAsStringSync()) as Map<String, Object?>,
  );
  await tester.pumpWidget(ProviderScope(overrides: [tenantProvider.overrideWithValue(tenant)], child: const RealtorApp()));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('phones get a bottom bar', (tester) async {
    await pumpAt(tester, const Size(412, 900));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('desktop web gets a top bar with Home and each purpose, and content no wider than 1200', (tester) async {
    await pumpAt(tester, const Size(1600, 1000));
    final nav = find.byKey(const Key('top-nav'));
    expect(nav, findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    for (final label in ['Home', 'Rent', 'Buy', 'Log in / Sign up']) {
      expect(find.descendant(of: nav, matching: find.text(label)), findsOneWidget, reason: label);
    }
    expect(find.descendant(of: nav, matching: find.text('Saved')), findsNothing, reason: 'only for signed-in customers');
    // The page scrolls across the window (its scrollbar at the edge); the content keeps to 1200.
    expect(tester.getSize(find.byType(CustomScrollView).first).width, 1600);
    expect(tester.getSize(find.byKey(const Key('home-hero'))).width, lessThanOrEqualTo(1200));

    // The wide home page: the realtor's two bands.
    expect(find.byKey(const Key('home-hero')), findsOneWidget);
    expect(find.byKey(const Key('home-banner')), findsOneWidget);

    await tester.tap(find.descendant(of: nav, matching: find.text('Buy')));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(RealtorApp)));
    expect(container.read(routerProvider).state.uri.path, '/buy');
    expect(nav, findsOneWidget, reason: 'the bar stays over the results');
  });

  testWidgets('desktop home scrolls as a whole: the top menu goes with it; the advert is a low band; rows slide with arrows', (tester) async {
    await pumpAt(tester, const Size(1400, 900), tenantId: 'realtime-estates');
    final nav = find.byKey(const Key('top-nav'));
    expect(nav.hitTestable(), findsOneWidget);
    final hot = find.byKey(const Key('hot-row'));
    await tester.scrollUntilVisible(hot, 300, scrollable: find.byType(Scrollable).first);
    // Four across; an arrow brings the rest.
    expect(find.byKey(const Key('row-back')), findsNothing);
    final more = find.descendant(of: hot, matching: find.byKey(const Key('row-more')));
    if (more.evaluate().isNotEmpty) {
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(find.descendant(of: hot, matching: find.byKey(const Key('row-back'))), findsOneWidget);
    }
    final ad = find.byKey(const Key('ad-card'));
    await tester.scrollUntilVisible(ad, 300, scrollable: find.byType(Scrollable).first);
    expect(tester.getSize(ad).height, lessThanOrEqualTo(180), reason: 'a low band, not a full-width photo');
    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(nav.hitTestable(), findsNothing, reason: 'the menu scrolled away with the page');
  });

  testWidgets('the filter row searches with what was picked', (tester) async {
    // A tenant without conversational search gets the filter row.
    await pumpAt(tester, const Size(1600, 1000), tenantId: 'realtime-estates');
    for (final label in ['Property type', 'Bedrooms', 'Top price a month']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    // Areas are suggested while typing; picking one fills the box.
    await tester.enterText(find.byKey(const Key('home-area')), 'kil');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('area-suggestions')), findsOneWidget);
    await tester.tap(find.byKey(const Key('area-suggestion-kilimani')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Kilimani'), findsOneWidget);
    await tester.tap(find.text('Bedrooms'));
    await tester.pumpAndSettle();
    expect(find.text('4 +').last, findsOneWidget);
    await tester.tap(find.text('2').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Top price a month'));
    await tester.pumpAndSettle();
    expect(find.text('KES 60,000 +').last, findsOneWidget);
    await tester.tap(find.text('KES 30,000').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Search'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(RealtorApp)));
    final uri = container.read(routerProvider).state.uri;
    expect(uri.path, '/rent/kilimani');
    expect(uri.queryParameters['bd'], '2', reason: 'exactly 2 bedrooms');
    expect(uri.queryParameters['max'], '30000');
  });

  testWidgets('BnB shows in the bar only for a tenant that offers short stays', (tester) async {
    await pumpAt(tester, const Size(1600, 1000));
    final demo = TenantConfig.fromJson(jsonDecode(File('../../tenants/demo-homes.json').readAsStringSync()) as Map<String, Object?>);
    final nav = find.byKey(const Key('top-nav'));
    expect(find.descendant(of: nav, matching: find.text('BnB')), demo.features.shortStay ? findsOneWidget : findsNothing);
  });

  testWidgets('a band with several photos shows them in turn; with motion turned off, only the first', (tester) async {
    Future<Finder> heroPhoto(int i) async => find.byKey(ValueKey('hero-$i'));
    await pumpAt(tester, const Size(1600, 1000), tenantId: 'realtime-estates');
    expect(await heroPhoto(0), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
    // Loading the next photo happens off the test's clock.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
    await tester.pumpAndSettle();
    expect(await heroPhoto(1), findsOneWidget, reason: 'the second photo after one turn');

    final tenant = TenantConfig.fromJson(jsonDecode(File('../../tenants/realtime-estates.json').readAsStringSync()) as Map<String, Object?>);
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(1600, 1000), disableAnimations: true),
      child: ProviderScope(key: UniqueKey(), overrides: [tenantProvider.overrideWithValue(tenant)], child: const RealtorApp()),
    ));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 15));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
    await tester.pumpAndSettle();
    expect(await heroPhoto(0), findsOneWidget, reason: 'still the first photo');
  });

  testWidgets('Saved joins the top bar once signed in; on phones its tab asks a visitor to sign in', (tester) async {
    final account = DemoAccount();
    final tenant = TenantConfig.fromJson(jsonDecode(File('../../tenants/demo-homes.json').readAsStringSync()) as Map<String, Object?>);
    Future<void> pump(Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        key: UniqueKey(),
        overrides: [
          tenantProvider.overrideWithValue(tenant),
          demoAccountProvider.overrideWithValue(account),
          favouritesStoreProvider.overrideWithValue(MemoryStore()),
        ],
        child: const RealtorApp(),
      ));
      await tester.pumpAndSettle();
    }

    await pump(const Size(1600, 1000));
    final top = find.byKey(const Key('top-nav'));
    expect(find.descendant(of: top, matching: find.text('Saved')), findsNothing, reason: 'wide, signed out');
    await account.signInWithGoogle();
    await tester.pumpAndSettle();
    expect(find.descendant(of: top, matching: find.text('Saved')), findsOneWidget, reason: 'wide, signed in');
    await account.signOut();
    await tester.pumpAndSettle();

    await pump(const Size(412, 900));
    final bar = find.byType(NavigationBar);
    for (final label in ['Home', 'Search', 'Saved', 'Account']) {
      expect(find.descendant(of: bar, matching: find.text(label)), findsOneWidget, reason: label);
    }
    await tester.tap(find.descendant(of: bar, matching: find.text('Saved')));
    await tester.pumpAndSettle();
    final router = ProviderScope.containerOf(tester.element(find.byType(RealtorApp))).read(routerProvider);
    expect(router.state.uri.path, '/account', reason: 'signed out: sign in first');
    await tester.tap(find.descendant(of: bar, matching: find.text('Search')));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/rent', reason: 'Search opens Rent first');
    await account.signInWithGoogle();
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: bar, matching: find.text('Saved')));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/saved');
    await account.signOut();
    await tester.pumpAndSettle();
  });
}
