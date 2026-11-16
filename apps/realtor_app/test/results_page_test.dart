import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtor_app/src/ad_slot.dart';
import 'package:realtor_app/src/app.dart';
import 'package:realtor_app/src/providers.dart';
import 'package:realtor_app/src/search/demo_search.dart';
import 'package:realtor_app/src/search/results_screen.dart';
import 'package:realtor_core/realtor_core.dart';

import 'feature_flags_test.dart' show tenantWith;

ListingSummary home(int i, {List<String> photos = const [], List<String> amenities = const [], bool verified = false, bool plan = false}) => ListingSummary(
      id: 'h$i',
      slug: 'home-$i',
      title: 'Home $i',
      purpose: Purpose.rent,
      type: 'apartment',
      beds: 2,
      baths: 1,
      priceKES: 10000 * i,
      area: 'kilimani',
      lat: -1.29,
      lng: 36.78,
      verified: verified,
      amenities: amenities,
      photos: photos,
      hasFloorPlan: plan,
    );

/// Demo Homes with every feature on (but for [features]) and, unlike the
/// file, an office phone and WhatsApp number.
TenantConfig tenantWithNumbers(Map<Feature, bool> features) {
  final json = jsonDecode(File('../../tenants/demo-homes.json').readAsStringSync()) as Map<String, Object?>;
  (json['contact'] as Map<String, Object?>)
    ..['phone'] = '+254700000001'
    ..['whatsapp'] = '+254700000001';
  final t = TenantConfig.fromJson(json);
  return t.withFeatures(tenantWith(features).features);
}

Future<List<Uri>> pump(WidgetTester tester, Size size, List<ListingSummary> homes, {Map<Feature, bool> features = const {}, String at = '/rent'}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final opened = <Uri>[];
  await tester.pumpWidget(ProviderScope(
    overrides: [
      tenantProvider.overrideWithValue(tenantWithNumbers(features)),
      listingSearchProvider.overrideWithValue(DemoListingSearch(homes)),
      urlOpenerProvider.overrideWithValue((uri) async {
        opened.add(uri);
        return true;
      }),
    ],
    child: const RealtorApp(),
  ));
  ProviderScope.containerOf(tester.element(find.byType(RealtorApp))).read(routerProvider).go(at);
  await tester.pumpAndSettle();
  return opened;
}

String location(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(RealtorApp))).read(routerProvider).state.uri.toString();

void main() {
  const phone = Size(412, 900), desktop = Size(1366, 900);

  test('furnished, floor plan and verified-first filter and sort like the search index', () async {
    final s = DemoListingSearch([
      home(1, amenities: ['Furnished']),
      home(2, plan: true),
      home(3, verified: true),
    ]);
    Future<List<String>> ids(ListingFilters f) async => (await s.search(f)).hits.map((h) => h.id).toList();
    expect(await ids(const ListingFilters(purpose: Purpose.rent, furnished: true)), ['h1']);
    expect(await ids(const ListingFilters(purpose: Purpose.rent, furnished: false)), ['h2', 'h3']);
    expect(await ids(const ListingFilters(purpose: Purpose.rent, floorPlan: true)), ['h2']);
    expect(await ids(const ListingFilters(purpose: Purpose.rent, verifiedFirst: true)), ['h3', 'h1', 'h2']);
  });

  for (final size in [phone, desktop]) {
    testWidgets('the search bar stays put while the homes scroll ($size)', (tester) async {
      await pump(tester, size, [for (var i = 1; i <= 12; i++) home(i)]);
      final bar = find.byKey(const Key('filter-bar'));
      final before = tester.getTopLeft(bar);
      final was = tester.getTopLeft(find.text('Home 1'));
      await tester.drag(find.text('Home 1'), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Home 1')).dy, lessThan(was.dy), reason: 'the list scrolled');
      if (size == phone) {
        expect(tester.getTopLeft(bar), before);
      } else {
        // The whole page scrolls: the top menu goes, the bar stops at the top.
        expect(tester.getTopLeft(bar).dy, 0);
        expect(find.byKey(const Key('top-nav')).hitTestable(), findsNothing);
        // One scroll for the page: the homes and the column beside them move together.
        expect(find.descendant(of: find.byKey(const Key('results-page')), matching: find.byType(ListView)), findsNothing);
        expect(tester.getTopLeft(find.byType(AdSlot).first).dy, lessThan(was.dy + 200));
        expect(tester.getSize(find.byKey(const Key('results-page'))).width, size.width, reason: 'the scrollbar is at the window edge');
      }
      for (final key in ['filter-location', 'filter-type', 'filter-beds', 'filter-price', 'filter-more']) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
      // More Filters is the last control in the bar.
      expect(tester.getTopLeft(find.byKey(const Key('filter-more'))).dx, greaterThan(tester.getTopLeft(find.byKey(const Key('filter-price'))).dx));
    });
  }

  testWidgets('typing an area in the bar searches there; other words are searched as text', (tester) async {
    await pump(tester, desktop, [home(1)]);
    await tester.enterText(find.byKey(const Key('filter-location')), 'Kilimani');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(location(tester), '/rent/kilimani');
    await tester.enterText(find.byKey(const Key('filter-location')), 'near the stadium');
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    expect(location(tester), '/rent?q=near+the+stadium');
  });

  testWidgets('on wide screens a dropdown opens under its button; More Filters has furnishing, features, amenities, verified, plans and tours', (tester) async {
    await pump(tester, desktop, [home(1)]);
    await tester.tap(find.byKey(const Key('filter-beds')));
    await tester.pumpAndSettle();
    final popover = find.byKey(const Key('filter-popover'));
    expect(tester.getTopLeft(popover).dy, greaterThan(tester.getBottomLeft(find.byKey(const Key('filter-beds'))).dy));
    await tester.tap(find.text('2+'));
    await tester.tap(find.text('Show homes'));
    await tester.pumpAndSettle();
    expect(location(tester), '/rent?beds=2');

    await tester.tap(find.byKey(const Key('filter-more')));
    await tester.pumpAndSettle();
    final sheet = find.descendant(of: find.byKey(const Key('filter-popover')), matching: find.byType(Scrollable));
    await tester.tap(find.text('Unfurnished'));
    for (final label in ['Furnishing', 'Features', 'Amenities', 'Verified homes first', 'Has a floor plan', 'Has a video or virtual tour']) {
      await tester.scrollUntilVisible(find.text(label), 80, scrollable: sheet.first);
      expect(find.text(label), findsOneWidget, reason: label);
    }
    await tester.scrollUntilVisible(find.text('Verified homes first'), -80, scrollable: sheet.first);
    await tester.tap(find.text('Verified homes first'));
    await tester.scrollUntilVisible(find.text('Has a floor plan'), 80, scrollable: sheet.first);
    await tester.tap(find.text('Has a floor plan'));
    await tester.tap(find.text('Show homes'));
    await tester.pumpAndSettle();
    expect(location(tester), '/rent?beds=2&vfirst=1&furnished=0&plan=1');
    expect(find.text('More Filters (3)'), findsOneWidget);
  });

  testWidgets('on phones the dropdowns are bottom sheets', (tester) async {
    await pump(tester, phone, [home(1)]);
    await tester.tap(find.byKey(const Key('filter-price')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('filter-popover')), findsNothing);
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.enterText(find.byKey(const Key('filter-max-price')), '60000');
    await tester.tap(find.text('Show homes'));
    await tester.pumpAndSettle();
    expect(location(tester), '/rent?max=60000');
  });

  for (final size in [phone, desktop]) {
    testWidgets('a card has photos to flick through, the heart top right, and Call, WhatsApp (and Email when wide) in that order ($size)', (tester) async {
      final opened = await pump(tester, size, [
        home(1, photos: ['https://example.com/a.jpg', 'https://example.com/b.jpg', 'https://example.com/c.jpg']),
      ]);
      final card = find.byType(ListingCard);
      // Photos: the arrow and a swipe both move on.
      expect(find.byTooltip('Previous photo'), findsNothing);
      await tester.tap(find.byTooltip('Next photo'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Previous photo'), findsOneWidget);
      await tester.drag(find.byKey(const Key('photo-carousel')), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Next photo'), findsNothing, reason: 'the last of three photos');
      expect(location(tester), '/rent', reason: 'moving through photos does not open the home');

      // Phones: Call and WhatsApp only. Wide screens add Email, last.
      final labels = size == phone ? ['Call', 'WhatsApp'] : ['Call', 'WhatsApp', 'Email'];
      final x = [for (final label in labels) tester.getCenter(find.descendant(of: card, matching: find.text(label))).dx];
      expect(x, orderedEquals([...x]..sort()));
      if (size == phone) expect(find.descendant(of: card, matching: find.text('Email')), findsNothing);
      final heart = tester.getCenter(find.descendant(of: card, matching: find.byTooltip('Save this home')));
      final box = tester.getRect(card);
      expect(box.right - heart.dx, lessThan(48));
      expect(heart.dy - box.top, lessThan(48));

      await tester.tap(find.descendant(of: card, matching: find.text('Call')));
      await tester.pump();
      expect(opened.single.scheme, 'tel');
      expect(location(tester), '/rent', reason: 'a contact button does not open the home');
    });
  }

  testWidgets('phones: an advert after every five homes, and none when adverts are off', (tester) async {
    final homes = [for (var i = 1; i <= 11; i++) home(i)];
    await pump(tester, const Size(412, 12000), homes);
    expect(find.byType(AdSlot), findsNWidgets(2));
    final ads = [for (var i = 0; i < 2; i++) tester.getTopLeft(find.byType(AdSlot).at(i)).dy];
    double top(int i) => tester.getTopLeft(find.text('Home $i')).dy;
    expect(ads[0], inExclusiveRange(top(5), top(6)));
    expect(ads[1], inExclusiveRange(top(10), top(11)));
    expect(find.text('Advert'), findsNWidgets(2));

    await pump(tester, const Size(412, 12000), homes, features: {Feature.ads: false});
    expect(find.text('Advert'), findsNothing);
  });

  testWidgets('wide screens: adverts sit beside the homes, not among them', (tester) async {
    await pump(tester, desktop, [for (var i = 1; i <= 3; i++) home(i)]);
    final ad = tester.getTopLeft(find.byType(AdSlot).first);
    expect(ad.dx, greaterThan(tester.getTopRight(find.byType(ListingCard).first).dx));
  });

  testWidgets('Rent, Buy and BnB are pages, not a dropdown in the bar; phones switch with pills over the list', (tester) async {
    await pump(tester, desktop, [home(1)]);
    expect(find.byKey(const Key('filter-purpose')), findsNothing);
    expect(find.byKey(const Key('purpose-pills')), findsNothing, reason: 'the top menu has them');

    await pump(tester, phone, [home(1)]);
    expect(find.byKey(const Key('filter-purpose')), findsNothing);
    await tester.tap(find.descendant(of: find.byKey(const Key('purpose-pills')), matching: find.text('Buy')));
    await tester.pumpAndSettle();
    expect(location(tester), '/buy');
  });

  testWidgets('Map is at the end of the search bar on wide screens, and a pill over the list on phones', (tester) async {
    await pump(tester, desktop, [home(1)]);
    final map = find.byKey(const Key('map-toggle'));
    expect(find.descendant(of: find.byKey(const Key('filter-bar')), matching: map), findsOneWidget);
    expect(tester.getTopLeft(map).dx, greaterThan(tester.getTopRight(find.byKey(const Key('filter-more'))).dx));
    expect(find.byType(FloatingActionButton), findsNothing);
    await tester.tap(map);
    await tester.pumpAndSettle();
    expect(find.descendant(of: map, matching: find.text('List')), findsOneWidget);
    await tester.tap(map);
    await tester.pumpAndSettle();

    await pump(tester, phone, [home(1)]);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('filter-bar')), matching: find.byKey(const Key('map-toggle'))), findsNothing);
  });
}
