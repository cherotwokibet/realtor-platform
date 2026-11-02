import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtor_app/src/app.dart';
import 'package:realtor_app/src/providers.dart';
import 'package:realtor_app/src/saved/favourites.dart';
import 'package:realtor_app/src/search/recent_searches.dart';
import 'package:realtor_core/realtor_core.dart';

import 'favourites_test.dart' show MemoryStore;
import 'listing_screen_test.dart' show tenant;

class MemoryRecent implements RecentSearchesStore {
  List<String> uris = [];
  @override
  Future<List<String>> load() async => uris;
  @override
  Future<void> save(List<String> uris) async => this.uris = uris;
}

void main() {
  late MemoryRecent store;
  late ProviderContainer c;

  Future<void> go(WidgetTester tester, String path) async {
    c.read(routerProvider).go(path);
    await tester.pumpAndSettle();
  }

  Future<void> start(WidgetTester tester) async {
    tester.view.physicalSize = const Size(412, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    c = ProviderContainer(overrides: [
      tenantProvider.overrideWithValue(tenant()),
      favouritesStoreProvider.overrideWithValue(MemoryStore()),
      recentSearchesStoreProvider.overrideWithValue(store),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const RealtorApp()));
    await tester.pumpAndSettle();
  }

  setUp(() => store = MemoryRecent());

  String uri(ListingFilters f) => f.toUri().toString();
  final apartments = ListingFilters(purpose: Purpose.rent, types: const ['apartment']);
  final kasarani = ListingFilters(purpose: Purpose.rent, areas: const ['kasarani'], maxPriceKES: 10000);

  testWidgets('searches are remembered newest first, once each, and offered again on home', (tester) async {
    await start(tester);
    expect(find.text('Recent searches'), findsNothing);

    await go(tester, uri(apartments));
    await go(tester, uri(ListingFilters(purpose: Purpose.rent))); // narrows nothing: not kept
    await go(tester, uri(kasarani));
    await go(tester, uri(apartments.copyWith(sort: ListingSort.priceAsc))); // same search, other sort: moves up
    expect(store.uris, [uri(apartments), uri(kasarani)]);

    await go(tester, '/');
    expect(find.text('Recent searches'), findsOneWidget);
    expect(find.text('Rent · Apartment'), findsOneWidget);
    expect(find.text('Rent · Kasarani · up to KES 10,000'), findsOneWidget);
    await tester.tap(find.text('Rent · Kasarani · up to KES 10,000'));
    await tester.pumpAndSettle();
    expect(c.read(routerProvider).routerDelegate.currentConfiguration.uri.toString(), uri(kasarani));

    await go(tester, '/');
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(find.text('Recent searches'), findsNothing);
    expect(store.uris, isEmpty);
  });

  testWidgets('keeps the last five; a damaged entry is skipped', (tester) async {
    store.uris = ['not a search', uri(apartments)];
    await start(tester);
    expect(find.text('Rent · Apartment'), findsOneWidget);
    for (final max in [10000, 20000, 30000, 40000, 50000]) {
      await go(tester, uri(ListingFilters(purpose: Purpose.rent, maxPriceKES: max)));
    }
    expect(store.uris.length, RecentSearchesNotifier.maxKept);
    expect(store.uris.first, contains('max=50000'));
    expect(store.uris.any((u) => u == uri(apartments)), isFalse);
  });
}
