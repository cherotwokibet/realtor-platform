import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtor_app/src/ad_slot.dart';
import 'package:realtor_app/src/app.dart';
import 'package:realtor_app/src/providers.dart';
import 'package:realtor_app/src/search/demo_search.dart';
import 'package:realtor_app/src/search/filters_sheet.dart';
import 'package:realtor_app/src/search/results_screen.dart';
import 'package:realtor_app/src/window_scroll.dart';
import 'package:realtor_core/realtor_core.dart';

import 'feature_flags_test.dart' show tenantWith;

ListingSummary home(int i, {List<String> photos = const [], List<String> amenities = const [], bool verified = false, bool plan = false, String? poster}) =>
    ListingSummary(
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
      hasVideo: poster != null,
      videoPoster: poster,
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

String location(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(RealtorApp))).read(routerProvider).state.uri.toString();

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
        // Phones: scrolling down, the top bar and the search bar both slide away;
        // a small scroll up brings the search bar straight back.
        expect(before.dy, greaterThan(0));
        expect(find.byKey(const Key('filter-location')).hitTestable(), findsNothing, reason: 'hidden while reading down');
        expect(find.byTooltip('Open navigation menu').hitTestable(), findsNothing);
        await tester.dragFrom(const Offset(200, 500), const Offset(0, 60));
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(bar).dy, 0, reason: 'back at the top of the screen');
        expect(find.byKey(const Key('filter-location')).hitTestable(), findsOneWidget);
        await tester.dragFrom(const Offset(200, 600), const Offset(0, 2000));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Open navigation menu').hitTestable(), findsOneWidget, reason: 'back at the top');
      } else {
        // The whole page scrolls: the top menu goes, the bar stops at the top.
        expect(tester.getTopLeft(bar).dy, 0);
        expect(find.byKey(const Key('top-nav')).hitTestable(), findsNothing);
        // One scroll for the page: the homes and the column beside them move together.
        expect(find.descendant(of: find.byKey(const Key('results-page')), matching: find.byType(ListView)), findsNothing);
        expect(tester.getTopLeft(find.byType(AdSlot).first).dy, lessThan(was.dy + 200));
        expect(tester.getSize(find.byKey(const Key('results-page'))).width, size.width - WindowScroll.width, reason: 'the scrollbar has its own lane');
        expect(tester.getRect(find.byKey(const Key('window-scrollbar'))).right, size.width, reason: 'at the window edge');
      }
      // Wide: More Filters is the last control in the bar. Phones: the
      // filters button comes first, then the pills.
      final last = size == phone ? 'filter-all' : 'filter-more';
      for (final key in ['filter-location', 'filter-type', 'filter-beds', 'filter-price', last]) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
      final price = tester.getTopLeft(find.byKey(const Key('filter-price'))).dx;
      final edge = tester.getTopLeft(find.byKey(Key(last))).dx;
      expect(size == phone ? edge < price : edge > price, isTrue);
    });
  }

  testWidgets('wide screens: Clear Filters and Save Search under the filters, at the right', (tester) async {
    await pump(tester, desktop, [home(1)]);
    final clear = find.byKey(const Key('filter-clear'));
    expect(tester.widget<TextButton>(clear).onPressed, isNull, reason: 'nothing to clear yet');
    expect(find.byKey(const Key('save-search')), findsOneWidget);
    expect(tester.getTopLeft(clear).dy, greaterThanOrEqualTo(tester.getBottomLeft(find.byKey(const Key('filter-location'))).dy));
    await tester.tap(find.byKey(const Key('save-search')));
    await tester.pumpAndSettle();
    expect(location(tester), '/account', reason: 'signed out: sign in first, the search kept');
  });

  testWidgets('the location box suggests areas while typing; picking one searches there', (tester) async {
    await pump(tester, desktop, [home(1)]);
    await tester.enterText(find.byKey(const Key('filter-location')), 'kil');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('area-suggestion-kilimani')));
    await tester.pumpAndSettle();
    expect(location(tester), '/rent/kilimani');
  });

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

  testWidgets('on wide screens a dropdown opens under its button; Beds & Baths are exact counts with room types first', (tester) async {
    await pump(tester, desktop, [home(1)]);
    await tester.tap(find.byKey(const Key('filter-beds')));
    await tester.pumpAndSettle();
    final popover = find.byKey(const Key('filter-popover'));
    expect(tester.getTopLeft(popover).dy, greaterThan(tester.getBottomLeft(find.byKey(const Key('filter-beds'))).dy));
    for (final label in ['Beds', 'Baths', 'Single room', 'Studio', 'Bedsitter', '7', '8+', '5', '6+']) {
      expect(find.descendant(of: popover, matching: find.text(label)), findsWidgets, reason: label);
    }
    expect(find.descendant(of: popover, matching: find.text('2+')), findsNothing, reason: 'counts are exact, not "2 or more"');
    await tester.tap(find.byKey(const Key('beds-2')));
    await tester.tap(find.byKey(const Key('beds-3')));
    await tester.tap(find.text('Studio'));
    await tester.tap(find.byKey(const Key('baths-6')));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(location(tester), '/rent/studios?bd=2%2C3&ba=6');
    expect(find.descendant(of: find.byKey(const Key('filter-beds')), matching: find.text('Studio, 2, 3 beds · 6+ baths')), findsOneWidget);
  });

  testWidgets('More Filters is lean: viewing options, and features and amenities', (tester) async {
    await pump(tester, desktop, [home(1)]);
    await tester.tap(find.byKey(const Key('filter-more')));
    await tester.pumpAndSettle();
    final popover = find.byKey(const Key('filter-popover'));
    for (final label in ['Viewing options', 'Floor plans', 'Video tours', '360° tours', 'Features & Amenities', 'Parking', 'Swimming pool']) {
      expect(find.descendant(of: popover, matching: find.text(label)), findsOneWidget, reason: label);
    }
    for (final label in ['Furnishing', 'Verified homes first', 'Verified homes only']) {
      expect(find.descendant(of: popover, matching: find.text(label)), findsNothing, reason: '$label is over the list now');
    }
    await tester.tap(find.text('Video tours'));
    await tester.tap(find.text('Parking'));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(location(tester), '/rent?amenities=parking&video=1');
    expect(find.text('More Filters (2)'), findsOneWidget);
  });

  testWidgets('over the list: All / Furnished / Unfurnished, the order, and List | Map', (tester) async {
    await pump(tester, desktop, [
      home(1, amenities: ['furnished']),
      home(2, verified: true)
    ]);
    final heading = find.byKey(const Key('list-heading'));
    expect(tester.getTopLeft(heading).dy, greaterThan(tester.getTopLeft(find.text('Homes to rent')).dy));
    await tester.tap(find.byKey(const Key('furnished-false')));
    await tester.pumpAndSettle();
    expect(location(tester), '/rent?furnished=0');
    expect(find.text('Home 1'), findsNothing);

    await tester.tap(find.byKey(const Key('sort')));
    await tester.pumpAndSettle();
    for (final label in ['Popular', 'Newest', 'Lowest price', 'Highest price', 'Verified homes first']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    await tester.tap(find.text('Verified homes first').last);
    await tester.pumpAndSettle();
    expect(location(tester), '/rent?vfirst=1&furnished=0');
    await tester.tap(find.byKey(const Key('sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lowest price').last);
    await tester.pumpAndSettle();
    expect(location(tester), '/rent?furnished=0&sort=price-asc', reason: 'another order drops verified-first');

    expect(find.descendant(of: find.byKey(const Key('filter-bar')), matching: find.text('Map')), findsNothing, reason: 'not in the search bar');
    await tester.tap(find.descendant(of: find.byKey(const Key('map-toggle')), matching: find.text('Map')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('results-page')), findsNothing, reason: 'the map view');
    await tester.tap(find.descendant(of: find.byKey(const Key('map-toggle')), matching: find.text('List')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('results-page')), findsOneWidget);
  });

  testWidgets('the location box lines up with the buttons beside it', (tester) async {
    await pump(tester, desktop, [home(1)]);
    final box = tester.getRect(find.byKey(const Key('filter-location')));
    final button = tester.getRect(find.byKey(const Key('filter-type')));
    expect(box.top, closeTo(button.top, 1));
    expect(box.height, closeTo(button.height, 1));
  });

  testWidgets('on phones the dropdowns are bottom sheets; prices show thousands with commas', (tester) async {
    await pump(tester, phone, [home(1)]);
    await tester.ensureVisible(find.byKey(const Key('filter-price')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('filter-price')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('filter-popover')), findsNothing);
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.enterText(find.byKey(const Key('filter-max-price')), '60000');
    await tester.pump();
    expect(find.text('60,000'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('filter-min-price')), '2000');
    await tester.pump();
    expect(find.text('2,000'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(location(tester), '/rent?min=2000&max=60000');
  });

  test('the thousands formatter keeps the cursor after the same digit', () {
    const f = ThousandsFormatter();
    final out = f.formatEditUpdate(TextEditingValue.empty, const TextEditingValue(text: '12345', selection: TextSelection.collapsed(offset: 3)));
    expect(out.text, '12,345');
    expect(out.selection.baseOffset, 4);
    expect(ThousandsFormatter.format('1000000'), '1,000,000');
    expect(ThousandsFormatter.format('007'), '7');
  });

  for (final size in [phone, desktop]) {
    testWidgets('a card has photos to flick through, the heart top right, and Call, WhatsApp (and Email when wide) in that order ($size)', (tester) async {
      final opened = await pump(tester, size, [
        home(1, photos: ['https://example.com/a.jpg', 'https://example.com/b.jpg', 'https://example.com/c.jpg'], poster: 'https://example.com/v.jpg'),
      ]);
      final card = find.byType(ListingCard);
      // Photos and the video, with no end: from the first, back goes to the last (the video).
      expect(find.byKey(const Key('photo-dots-0')), findsOneWidget);
      await tester.tap(find.byTooltip('Previous photo'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('photo-dots-3')), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is Image && w.semanticLabel == 'Home 1, video'), findsOneWidget);
      await tester.tap(find.byTooltip('Next photo'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('photo-dots-0')), findsOneWidget, reason: 'after the last comes the first');
      await tester.drag(find.byKey(const Key('photo-carousel')), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('photo-dots-1')), findsOneWidget);
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

      await tester.ensureVisible(find.descendant(of: card, matching: find.text('Call')));
      await tester.pumpAndSettle();
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
    expect(find.text('AD'), findsNWidgets(2));
    expect(find.text('Enquire now'), findsNWidgets(2));

    await pump(tester, const Size(412, 12000), homes, features: {Feature.ads: false});
    expect(find.text('AD'), findsNothing);
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

  testWidgets('phones keep the Map pill over the list and have no List | Map row', (tester) async {
    await pump(tester, phone, [home(1)]);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.byType(SegmentedButton<bool>), findsNothing);
    expect(find.byKey(const Key('list-heading')), findsOneWidget, reason: 'furnishing and the order still show');
  });

  testWidgets('phones: the filters button opens every filter in one sheet, which says how many homes it finds', (tester) async {
    await pump(tester, phone, [home(1), home(2, plan: true), home(3)]);
    await tester.tap(find.byKey(const Key('filter-all')));
    await tester.pumpAndSettle();
    final sheet = find.byType(BottomSheet);
    final list = find.descendant(of: sheet, matching: find.byType(Scrollable)).first;
    for (final label in ['Property type', 'Beds', 'Baths', 'Viewing options', 'Features & Amenities']) {
      await tester.scrollUntilVisible(find.descendant(of: sheet, matching: find.text(label)), 120, scrollable: list);
      expect(find.descendant(of: sheet, matching: find.text(label)), findsOneWidget, reason: label);
    }
    expect(find.text('See 3 homes'), findsOneWidget);
    // The foot: Reset all on one line beside the wide button, the same height.
    final reset = tester.getRect(find.byKey(const Key('filters-reset'))), done = tester.getRect(find.byKey(const Key('filters-done')));
    expect(reset.height, done.height);
    expect(reset.center.dy, done.center.dy);
    expect(done.width, greaterThan(reset.width));
    expect(find.text('Reset all'), findsOneWidget);
    await tester.tap(find.descendant(of: sheet, matching: find.text('Floor plans')));
    await tester.pumpAndSettle();
    expect(find.text('See 1 home'), findsOneWidget);
    await tester.tap(find.byKey(const Key('filters-done')));
    await tester.pumpAndSettle();
    expect(location(tester), '/rent?plan=1');
    expect(find.byType(Badge), findsNothing, reason: 'no number');
    expect(find.byTooltip('Filters (some set)'), findsOneWidget, reason: 'the button shows filters are set');
  });

  testWidgets('phones: the top bar has the menu, the logo and Log in; Saved once signed in', (tester) async {
    await pump(tester, phone, [home(1)]);
    final top = find.byKey(const Key('phone-top-bar'));
    expect(find.descendant(of: top, matching: find.byTooltip('Open navigation menu')), findsOneWidget);
    expect(find.descendant(of: top, matching: find.text('Log in')), findsOneWidget);
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('app-drawer')), findsOneWidget);
  });

  testWidgets('phones: after a filter is picked, the pill row keeps its place, then glides back to the start; Reset all filters clears them', (tester) async {
    await pump(tester, phone, [home(1), home(2)]);
    double offset() =>
        tester.state<ScrollableState>(find.descendant(of: find.byKey(const Key('filter-pills')), matching: find.byType(Scrollable))).position.pixels;
    await tester.ensureVisible(find.byKey(const Key('filter-price')));
    await tester.pumpAndSettle();
    final scrolled = offset();
    expect(scrolled, greaterThan(0));
    await tester.tap(find.byKey(const Key('filter-price')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Close'), findsNothing, reason: 'one part of the filters has no close button');
    await tester.enterText(find.byKey(const Key('filter-max-price')), '60000');
    await tester.tap(find.text('Done'));
    await tester.pump();
    await tester.pump();
    expect(offset(), closeTo(scrolled, 1), reason: 'the new page starts where the row was');
    await tester.pumpAndSettle();
    expect(offset(), 0, reason: 'then glides back to the start');
    expect(location(tester), '/rent?max=60000');

    await tester.ensureVisible(find.byKey(const Key('filter-reset-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('filter-reset-all')));
    await tester.pumpAndSettle();
    expect(location(tester), '/rent');
    expect(tester.widget<TextButton>(find.byKey(const Key('filter-reset-all'))).onPressed, isNull, reason: 'nothing left to reset');
  });
}
