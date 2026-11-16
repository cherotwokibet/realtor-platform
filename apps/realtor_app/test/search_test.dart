import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtor_app/src/app.dart';
import 'package:realtor_app/src/listing/listing_screen.dart';
import 'package:realtor_app/src/places/place_screens.dart';
import 'package:realtor_app/src/providers.dart';
import 'package:realtor_app/src/search/demo_search.dart';
import 'package:realtor_app/src/search/results_screen.dart';
import 'package:realtor_core/realtor_core.dart';

TenantConfig tenant(String id) => TenantConfig.fromJson(jsonDecode(File('../../tenants/$id.json').readAsStringSync()) as Map<String, Object?>);

Future<GoRouterHarness> open(WidgetTester tester, String location, {String tenantId = 'demo-homes', TenantConfig? as}) async {
  tester.view.physicalSize = const Size(412, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(overrides: [tenantProvider.overrideWithValue(as ?? tenant(tenantId))], child: const RealtorApp()));
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
  String get location => _c.read(routerProvider).state.uri.toString();
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
      final screen = switch (path.split('/')[1]) { 'listing' => ListingScreen, 'area' => AreaScreen, _ => AgentScreen };
      expect(find.byType(screen), findsOneWidget, reason: path);
    }
  });

  testWidgets('a shared link opens straight into its results', (tester) async {
    await open(tester, '/rent/apartments/kilimani?beds=2');
    expect(find.text('Apartments to rent in Kilimani'), findsOneWidget);
    expect(find.text('2 bedroom apartment, Kilimani'), findsOneWidget);
    expect(find.text('1 home'), findsOneWidget);
  });

  testWidgets('picking a type in the filters changes the URL', (tester) async {
    final h = await open(tester, '/rent');
    await tester.ensureVisible(find.byKey(const Key('filter-type')));
    await tester.tap(find.byKey(const Key('filter-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hostel').last);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(h.location, '/rent/hostels');
    expect(find.text('Student hostel bed, Kasarani'), findsOneWidget);
  });

  testWidgets('the home search box opens results', (tester) async {
    final h = await open(tester, '/');
    await tester.enterText(find.byType(TextField), 'kasarani');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    // Demo Homes has aiSearch on, so a known area name becomes the area filter.
    expect(h.location, '/rent/kasarani');
    expect(find.text('2 homes'), findsOneWidget);
  });

  testWidgets('a purpose the tenant does not offer goes home', (tester) async {
    final json = jsonDecode(File('../../tenants/demo-homes.json').readAsStringSync()) as Map<String, Object?>;
    (json['features'] as Map<String, Object?>)['shortStay'] = false;
    final h = await open(tester, '/short-stay', as: TenantConfig.fromJson(json));
    expect(h.location, '/');
  });

  testWidgets('a malformed results URL goes home', (tester) async {
    final h = await open(tester, '/rent/Not%20A%20Slug');
    expect(h.location, '/');
  });

  testWidgets('home shows the newest real homes, not a placeholder', (tester) async {
    final h = await open(tester, '/');
    expect(find.text('Sample listing'), findsNothing);
    expect(find.text('Newest to rent'), findsOneWidget);
    expect(find.byType(ListingCard), findsNWidgets(3));
    await tester.tap(find.text('See all'));
    await tester.pumpAndSettle();
    expect(h.location, startsWith('/rent'));
  });

  testWidgets('home WhatsApp button: hidden until a number exists, then opens wa.me', (tester) async {
    final json = jsonDecode(File('../../tenants/realtime-estates.json').readAsStringSync()) as Map<String, Object?>;
    await tester.pumpWidget(ProviderScope(overrides: [tenantProvider.overrideWithValue(TenantConfig.fromJson(json))], child: const RealtorApp()));
    await tester.pumpAndSettle();
    expect(find.text('Enquire on WhatsApp'), findsNothing);

    (json['contact'] as Map<String, Object?>)['whatsapp'] = '+254700000000';
    final opened = <Uri>[];
    await tester.pumpWidget(ProviderScope(
      key: UniqueKey(),
      overrides: [
        tenantProvider.overrideWithValue(TenantConfig.fromJson(json)),
        urlOpenerProvider.overrideWithValue((u) async {
          opened.add(u);
          return true;
        }),
      ],
      child: const RealtorApp(),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enquire on WhatsApp'));
    expect(opened.single.host, 'wa.me');
    expect(opened.single.path, '/254700000000');
  });
}
