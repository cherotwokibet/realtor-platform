import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtor_app/src/app.dart';
import 'package:realtor_app/src/listing/listing_screen.dart';
import 'package:realtor_app/src/providers.dart';
import 'package:realtor_app/src/search/demo_search.dart';
import 'package:realtor_core/realtor_core.dart';

TenantConfig tenant(String id) =>
    TenantConfig.fromJson(jsonDecode(File('../../tenants/$id.json').readAsStringSync()) as Map<String, Object?>);

Future<GoRouterHarness> open(WidgetTester tester, String location, {String tenantId = 'demo-homes'}) async {
  tester.view.physicalSize = const Size(412, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(overrides: [tenantProvider.overrideWithValue(tenant(tenantId))], child: const RealtorApp()));
  final h = GoRouterHarness(tester);
  h.go(location);
  await tester.pumpAndSettle();
  return h;
}

class GoRouterHarness {
  GoRouterHarness(this.tester);
  final WidgetTester tester;
  ProviderContainer get _c => ProviderScope.containerOf(tester.element(find.byType(RealtorApp)));
  void go(String l) => _c.read(routerProvider).go(l);
  String get location => _c.read(routerProvider).routerDelegate.currentConfiguration.uri.toString();
}

void main() {
  group('DemoListingSearch', () {
    final s = DemoListingSearch();
    test('filters like the Typesense query', () async {
      final r = await s.search(const ListingFilters(purpose: Purpose.rent, areas: ['kilimani', 'kileleshwa'], minBeds: 2, maxPriceKES: 100000));
      expect(r.hits.map((h) => h.id), ['demo-1']);
    });
    test('facets keep the other options visible', () async {
      final r = await s.search(const ListingFilters(purpose: Purpose.rent, types: ['apartment']));
      expect(r.facets['type']!.map((f) => f.value), containsAll(['apartment', 'bedsitter', 'hostel']));
    });
    test('radius and nearest', () async {
      final r = await s.search(const ListingFilters(purpose: Purpose.rent, near: GeoRadius(-1.221, 36.897, 2), sort: ListingSort.nearest));
      expect(r.hits.every((h) => h.area == 'kasarani'), isTrue);
      expect(r.found, 2);
    });
  });

  testWidgets('every App Link path has a screen, not an error page', (tester) async {
    for (final path in ['/listing/2-bedroom-apartment-kilimani', '/area/kilimani', '/agent/agent-wanjiku']) {
      final h = await open(tester, path);
      expect(h.location, path);
      expect(find.textContaining('Page Not Found'), findsNothing, reason: path);
      expect(find.byType(path.startsWith('/listing/') ? ListingScreen : PlaceholderScreen), findsOneWidget, reason: path);
    }
  });

  testWidgets('a shared link opens straight into its results', (tester) async {
    await open(tester, '/rent/apartments/kilimani?beds=2');
    expect(find.text('Apartments to rent in Kilimani'), findsOneWidget);
    expect(find.text('2 bedroom apartment, Kilimani'), findsOneWidget);
    expect(find.text('1 home'), findsOneWidget);
  });

  testWidgets('tapping a type chip changes the URL', (tester) async {
    final h = await open(tester, '/rent');
    await tester.tap(find.textContaining('Hostel ('));
    await tester.pumpAndSettle();
    expect(h.location, '/rent/hostels');
    expect(find.text('Student hostel bed, Kasarani'), findsOneWidget);
  });

  testWidgets('the home search box opens results', (tester) async {
    final h = await open(tester, '/');
    await tester.enterText(find.byType(TextField), 'kasarani');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(h.location, '/rent?q=kasarani');
    expect(find.text('2 homes'), findsOneWidget);
  });

  testWidgets('a purpose the tenant does not offer goes home', (tester) async {
    // Realtime Estates has shortStay off.
    final h = await open(tester, '/short-stay', tenantId: 'realtime-estates');
    expect(h.location, '/');
  });

  testWidgets('a malformed results URL goes home', (tester) async {
    final h = await open(tester, '/rent/Not%20A%20Slug');
    expect(h.location, '/');
  });
}
