import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtor_app/src/app.dart';
import 'package:realtor_app/src/providers.dart';
import 'package:realtor_app/src/search/demo_search.dart';

import 'listing_screen_test.dart' show tenant;

Future<(ProviderContainer, List<Uri>)> open(WidgetTester tester, String path) async {
  tester.view.physicalSize = const Size(412, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final opened = <Uri>[];
  final c = ProviderContainer(overrides: [
    tenantProvider.overrideWithValue(tenant()),
    urlOpenerProvider.overrideWithValue((uri) async {
      opened.add(uri);
      return true;
    }),
  ]);
  addTearDown(c.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const RealtorApp()));
  await tester.pumpAndSettle();
  c.read(routerProvider).go(path);
  await tester.pumpAndSettle();
  return (c, opened);
}

void main() {
  testWidgets('an area page shows its guide and its homes', (tester) async {
    final area = demoListings.first.area;
    await open(tester, '/area/$area');
    expect(find.textContaining('Homes in '), findsOneWidget);
    expect(find.textContaining('A demo guide'), findsOneWidget);
    expect(find.text(demoListings.first.title), findsOneWidget);
  });

  testWidgets('an agent page shows the profile, contacts and their homes', (tester) async {
    final (_, opened) = await open(tester, '/agent/agent-wanjiku');
    expect(find.text('Wanjiku Mwangi'), findsWidgets);
    expect(find.textContaining('EARB reg.'), findsOneWidget);
    await tester.tap(find.text('WhatsApp'));
    await tester.pump();
    expect(opened.single.host, 'wa.me');
    expect(find.byType(Card), findsWidgets);
  });

  testWidgets('unknown area or agent says so', (tester) async {
    await open(tester, '/agent/agent-ghost');
    expect(find.text('This agent is not here any more.'), findsOneWidget);
  });
}
