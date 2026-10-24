import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtor_app/src/app.dart';
import 'package:realtor_app/src/providers.dart';
import 'package:realtor_core/realtor_core.dart';

Future<void> pumpAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final tenant = TenantConfig.fromJson(
    jsonDecode(File('../../tenants/demo-homes.json').readAsStringSync()) as Map<String, Object?>,
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

  testWidgets('desktop web gets a side rail and content no wider than 1200', (tester) async {
    await pumpAt(tester, const Size(1600, 1000));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    final list = tester.getSize(find.byType(ListView).first);
    expect(list.width, lessThanOrEqualTo(1200));
  });
}
