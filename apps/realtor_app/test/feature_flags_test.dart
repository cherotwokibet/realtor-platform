import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtor_app/src/app.dart';
import 'package:realtor_app/src/providers.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';

/// Demo Homes with every switch on, then one switched off per test.
TenantConfig tenantWith(Map<Feature, bool> changes) {
  final t = TenantConfig.fromJson(
    jsonDecode(File('../../tenants/demo-homes.json').readAsStringSync()) as Map<String, Object?>,
  );
  final allOn = t.features.copyWith({for (final f in Feature.values) f: true});
  return t.withFeatures(allOn.copyWith(changes));
}

Future<void> pumpApp(WidgetTester tester, TenantConfig tenant) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [tenantProvider.overrideWithValue(tenant)],
    child: const RealtorApp(),
  ));
  await tester.pumpAndSettle();
}

String currentPath(WidgetTester tester) {
  final container = ProviderScope.containerOf(tester.element(find.byType(RealtorApp)));
  return container.read(routerProvider).state.uri.path;
}

Finder navLabel(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

// M-Pesa has no customer UI yet (payments come later, in the Functions); its
// only gate was on the old placeholder card, so it is not checked here.
void main() {
  testWidgets('with every feature on, each one shows', (tester) async {
    await pumpApp(tester, tenantWith({}));
    for (final f in [Feature.ads, Feature.aiSearch]) {
      expect(find.byKey(FeatureGate.keyFor(f)), findsOneWidget, reason: f.name);
    }
    for (final label in ['Rent', 'Buy', 'Short stay']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(navLabel('Off-plan'), findsOneWidget);
    expect(navLabel('Chat'), findsOneWidget);
  });

  for (final f in [Feature.ads, Feature.aiSearch]) {
    testWidgets('turning off ${f.name} removes its UI', (tester) async {
      await pumpApp(tester, tenantWith({f: false}));
      expect(find.byKey(FeatureGate.keyFor(f)), findsNothing);
    });
  }

  testWidgets('turning off ads removes the Featured slot', (tester) async {
    await pumpApp(tester, tenantWith({Feature.ads: false}));
    expect(find.text('Featured'), findsNothing);
  });

  for (final (feature, label) in [(Feature.sale, 'Buy'), (Feature.shortStay, 'Short stay')]) {
    testWidgets('turning off ${feature.name} removes the $label search', (tester) async {
      await pumpApp(tester, tenantWith({feature: false}));
      expect(find.text(label), findsNothing);
    });
  }

  for (final (feature, label, path) in [(Feature.offPlan, 'Off-plan', '/off-plan'), (Feature.chat, 'Chat', '/chat')]) {
    testWidgets('turning off ${feature.name} removes its menu entry and route', (tester) async {
      await pumpApp(tester, tenantWith({feature: false}));
      expect(navLabel(label), findsNothing);
      final container = ProviderScope.containerOf(tester.element(find.byType(RealtorApp)));
      container.read(routerProvider).go(path);
      await tester.pumpAndSettle();
      expect(currentPath(tester), '/', reason: 'deep link to a disabled section goes home');
    });

    testWidgets('with ${feature.name} on, $path opens', (tester) async {
      await pumpApp(tester, tenantWith({}));
      await tester.tap(navLabel(label));
      await tester.pumpAndSettle();
      expect(currentPath(tester), path);
    });
  }
}
