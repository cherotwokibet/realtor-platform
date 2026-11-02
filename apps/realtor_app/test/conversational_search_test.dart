import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtor_core/realtor_core.dart';

import 'feature_flags_test.dart' show currentPath, pumpApp, tenantWith;

void main() {
  testWidgets('typed search becomes filters, shown as chips that can be removed (P7-s01)', (tester) async {
    await pumpApp(tester, tenantWith({}));
    await tester.enterText(find.byType(TextField).first, '2br Kilimani under 70k with parking');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(currentPath(tester), '/rent/kilimani');
    expect(find.text('2 bedroom apartment, Kilimani'), findsOneWidget);
    for (final chip in ['Kilimani', '2+ bed', 'up to ${formatKes(70000)}', 'parking']) {
      expect(find.widgetWithText(InputChip, chip), findsOneWidget, reason: chip);
    }
    await tester.tap(find.byTooltip('Remove up to ${formatKes(70000)}'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, 'up to ${formatKes(70000)}'), findsNothing);
    expect(find.widgetWithText(InputChip, 'parking'), findsOneWidget);
  });

  testWidgets('with aiSearch off, the box is a plain text search', (tester) async {
    await pumpApp(tester, tenantWith({Feature.aiSearch: false}));
    await tester.enterText(find.byType(TextField).first, '2br Kilimani');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(currentPath(tester), '/rent');
    expect(find.widgetWithText(InputChip, '"2br kilimani"'), findsNothing);
    expect(find.widgetWithText(InputChip, '"2br Kilimani"'), findsOneWidget);
  });
}
