import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtor_app/src/app.dart';

import 'feature_flags_test.dart' show currentPath, menuLabel, navLabel, pumpApp, tenantWith;

/// Back (the arrow, or the phone's back) goes where people expect (P4).
void main() {
  Future<void> back(WidgetTester tester) async {
    // The listing page's bar has its own back chevron; other screens the usual arrow.
    final bar = find.byKey(const Key('bar-back'));
    await tester.tap(bar.evaluate().isNotEmpty ? bar : find.byType(BackButton));
    await tester.pumpAndSettle();
  }

  testWidgets('Search → results → home → back steps back one screen at a time', (tester) async {
    await pumpApp(tester, tenantWith({}));
    await tester.tap(find.widgetWithText(ActionChip, 'Apartment'));
    await tester.pumpAndSettle();
    expect(currentPath(tester), '/rent/apartments');
    await tester.tap(find.text('2 bedroom apartment, Kilimani'));
    await tester.pumpAndSettle();
    expect(currentPath(tester), '/listing/2-bedroom-apartment-kilimani');
    await back(tester);
    expect(currentPath(tester), '/rent/apartments');
    await back(tester);
    expect(currentPath(tester), '/');
  });

  testWidgets('changing filters does not pile up: Back leaves the results', (tester) async {
    await pumpApp(tester, tenantWith({}));
    await tester.enterText(find.byType(TextField).first, '2br Kilimani under 70k with parking');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove parking'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove 2+ bed'));
    await tester.pumpAndSettle();
    expect(currentPath(tester), '/rent/kilimani');
    await back(tester);
    expect(currentPath(tester), '/');
  });

  testWidgets('a screen opened from a link has a back arrow to Home', (tester) async {
    await pumpApp(tester, tenantWith({}));
    ProviderScope.containerOf(tester.element(find.byType(RealtorApp))).read(routerProvider).go('/listing/2-bedroom-apartment-kilimani');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bar-back')), findsOneWidget);
    await back(tester);
    expect(currentPath(tester), '/');
  });

  testWidgets('Off-plan → a project → back to the list', (tester) async {
    await pumpApp(tester, tenantWith({}));
    await tester.tap(await menuLabel(tester, 'Off-plan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sample Gardens'));
    await tester.pumpAndSettle();
    await back(tester);
    expect(currentPath(tester), '/off-plan');
  });

  testWidgets("the phone's back on another tab goes to Search, not out of the app", (tester) async {
    await pumpApp(tester, tenantWith({}));
    await tester.tap(navLabel('Account'));
    await tester.pumpAndSettle();
    expect(currentPath(tester), '/account');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(currentPath(tester), '/');
  });

  testWidgets("the phone's back on a pushed screen pops it", (tester) async {
    await pumpApp(tester, tenantWith({}));
    await tester.tap(find.widgetWithText(ActionChip, 'Apartment'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(currentPath(tester), '/');
  });
}
