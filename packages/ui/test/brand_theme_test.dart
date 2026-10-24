import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';

TenantConfig load(String id) => TenantConfig.fromJson(
      jsonDecode(File('../../tenants/$id.json').readAsStringSync()) as Map<String, Object?>,
    );

void main() {
  test('theme takes colours from the tenant, not from code', () {
    final rte = buildBrandTheme(load('realtime-estates'));
    final demo = buildBrandTheme(load('demo-homes'));
    expect(rte.colorScheme.primary, const Color(0xFF5E0202));
    expect(demo.colorScheme.primary, const Color(0xFF0F5257));
    expect(rte.extension<BrandExtension>()!.accent, const Color(0xFFD1992A));
    expect(rte.textTheme.titleLarge!.fontFamily, 'Poppins');
    expect(demo.textTheme.titleLarge!.fontFamily, 'Manrope');
  });

  testWidgets('PriceText and VerifiedBadge render with the brand', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildBrandTheme(load('realtime-estates')),
      home: Scaffold(
        body: Column(children: [
          const PriceText(45000, period: 'month'),
          VerifiedBadge(verifiedAt: DateTime(2026, 10, 24)),
        ]),
      ),
    ));
    expect(find.textContaining('KES 45,000'), findsOneWidget);
    expect(find.text('Verified'), findsOneWidget);
  });
}
