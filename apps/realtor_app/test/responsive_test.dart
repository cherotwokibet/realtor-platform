import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtor_app/src/account/account_data.dart';
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
    for (final label in ['Home', 'Rent', 'Buy', 'Log in / Sign up']) {
      expect(find.descendant(of: nav, matching: find.text(label)), findsOneWidget, reason: label);
    }
    expect(find.descendant(of: nav, matching: find.text('Saved')), findsNothing, reason: 'only for signed-in customers');
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

  testWidgets('Saved joins the top bar and the bottom bar once signed in', (tester) async {
    final account = DemoAccount();
    for (final (size, bar) in [(const Size(1600, 1000), find.byKey(const Key('top-nav'))), (const Size(412, 900), find.byType(NavigationBar))]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final tenant = TenantConfig.fromJson(jsonDecode(File('../../tenants/demo-homes.json').readAsStringSync()) as Map<String, Object?>);
      await tester.pumpWidget(ProviderScope(
        key: UniqueKey(),
        overrides: [tenantProvider.overrideWithValue(tenant), demoAccountProvider.overrideWithValue(account)],
        child: const RealtorApp(),
      ));
      await tester.pumpAndSettle();
      expect(find.descendant(of: bar, matching: find.text('Saved')), findsNothing, reason: '$size signed out');
      await account.signInWithGoogle();
      await tester.pumpAndSettle();
      expect(find.descendant(of: bar, matching: find.text('Saved')), findsOneWidget, reason: '$size signed in');
      await account.signOut();
      await tester.pumpAndSettle();
    }
  });
}
