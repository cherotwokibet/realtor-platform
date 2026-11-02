import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtor_app/src/app.dart';
import 'package:realtor_app/src/providers.dart';
import 'package:realtor_core/realtor_core.dart';

import 'feature_flags_test.dart' show currentPath, navLabel, tenantWith;

void main() {
  testWidgets('Off-plan lists projects; a project shows units, the plan and a WhatsApp ask (P5-s06)', (tester) async {
    final opened = <Uri>[];
    final tenant = tenantWith({});
    await tester.pumpWidget(ProviderScope(
      overrides: [
        tenantProvider.overrideWithValue(tenant),
        urlOpenerProvider.overrideWithValue((uri) async {
          opened.add(uri);
          return true;
        }),
      ],
      child: const RealtorApp(),
    ));
    await tester.pumpAndSettle();
    await tester.tap(navLabel('Off-plan'));
    await tester.pumpAndSettle();
    expect(find.text('Sample Gardens'), findsOneWidget);
    expect(find.text('From KES 4,800,000'), findsOneWidget);
    await tester.tap(find.text('Sample Gardens'));
    await tester.pumpAndSettle();
    expect(currentPath(tester), '/off-plan/sample-gardens');
    expect(find.text('1 bed apartment'), findsOneWidget);
    expect(find.text('Sold out'), findsOneWidget);
    expect(find.textContaining('ready June 2028'), findsOneWidget);
    expect(find.text('3. On handover'), findsOneWidget);
    final ask = find.text('Ask on WhatsApp');
    if (tenant.whatsappLink('x') != null) {
      await tester.ensureVisible(ask);
      await tester.tap(ask);
      expect(opened.single.host, 'wa.me');
      expect(opened.single.queryParameters['text'], contains('Sample Gardens'));
    } else {
      expect(ask, findsNothing);
    }
  });

  testWidgets('with offPlan off, a project link goes home', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [tenantProvider.overrideWithValue(tenantWith({Feature.offPlan: false}))],
      child: const RealtorApp(),
    ));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(RealtorApp)));
    container.read(routerProvider).go('/off-plan/sample-gardens');
    await tester.pumpAndSettle();
    expect(currentPath(tester), '/');
  });
}
