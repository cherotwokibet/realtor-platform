import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtor_app/src/app.dart';
import 'package:realtor_app/src/providers.dart';
import 'package:realtor_core/realtor_core.dart';

/// Every tenant file runs the same app with zero code changes.
void main() {
  final tenants = [
    for (final f in Directory('../../tenants').listSync().whereType<File>().where((f) => f.path.endsWith('.json')))
      TenantConfig.fromJson(jsonDecode(f.readAsStringSync()) as Map<String, Object?>),
  ]..sort((a, b) => a.id.compareTo(b.id));

  test('there is more than one tenant to prove the clone', () => expect(tenants.length, greaterThanOrEqualTo(2)));

  for (final tenant in tenants) {
    testWidgets('${tenant.id}: home shows its own brand and Kenyan property types', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [tenantProvider.overrideWithValue(tenant)],
        child: const RealtorApp(),
      ));
      await tester.pump();
      // The hero says the realtor's own words, or its tagline when it has none.
      expect(find.text(tenant.home.hero?.title ?? tenant.tagline ?? tenant.name), findsOneWidget);
      expect(find.text('Bedsitter'), findsWidgets);
      if (tenant.features.rent) expect(find.text('Rent'), findsOneWidget);
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.title, tenant.name);
      expect(app.theme!.colorScheme.primary, Color(tenant.brand.colors.primary));
      expect(app.theme!.textTheme.bodyMedium!.fontFamily, tenant.brand.bodyFont);
    });
  }
}
