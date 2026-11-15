import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtor_app/src/app.dart';
import 'package:realtor_app/src/providers.dart';
import 'package:realtor_core/realtor_core.dart';

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
    for (final label in ['Home', 'Rent', 'Buy', 'Saved', 'Log in / Sign up']) {
      expect(find.descendant(of: nav, matching: find.text(label)), findsOneWidget, reason: label);
    }
    final list = tester.getSize(find.byType(ListView).first);
    expect(list.width, lessThanOrEqualTo(1200));

    // The wide home page: the realtor's two bands.
    expect(find.byKey(const Key('home-hero')), findsOneWidget);
    expect(find.byKey(const Key('home-banner')), findsOneWidget);

    await tester.tap(find.descendant(of: nav, matching: find.text('Buy')));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(RealtorApp)));
    expect(container.read(routerProvider).state.uri.path, '/buy');
    expect(nav, findsOneWidget, reason: 'the bar stays over the results');
  });

  testWidgets('the filter row searches with what was picked', (tester) async {
    // A tenant without conversational search gets the filter row.
    await pumpAt(tester, const Size(1600, 1000), tenantId: 'realtime-estates');
    for (final label in ['Property type', 'Bedrooms', 'Top price a month']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    await tester.enterText(find.byType(TextField).first, 'Kilimani');
    await tester.tap(find.text('Bedrooms'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2+').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Search'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(RealtorApp)));
    final uri = container.read(routerProvider).state.uri;
    expect(uri.path, '/rent/kilimani');
    expect(uri.queryParameters['beds'], '2');
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
}
