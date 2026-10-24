import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtor_app/src/app.dart';
import 'package:realtor_app/src/providers.dart';
import 'package:realtor_core/realtor_core.dart';

void main() {
  testWidgets('home shows the tenant tagline and Kenyan property types', (tester) async {
    final tenant = TenantConfig.fromJson(
      jsonDecode(File('../../tenants/realtime-estates.json').readAsStringSync()) as Map<String, Object?>,
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [tenantProvider.overrideWithValue(tenant)],
      child: const RealtorApp(),
    ));
    await tester.pump();
    expect(find.text('Live where you love'), findsOneWidget);
    expect(find.text('Bedsitter'), findsOneWidget);
    expect(find.text('Rent'), findsOneWidget);
  });
}
