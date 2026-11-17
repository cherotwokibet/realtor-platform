import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtor_app/src/account/account_data.dart';
import 'package:realtor_app/src/app.dart';
import 'package:realtor_app/src/listing/demo_listings.dart';
import 'package:realtor_app/src/providers.dart';
import 'package:realtor_app/src/saved/favourites.dart';
import 'package:realtor_core/realtor_core.dart';

import 'favourites_test.dart' show MemoryStore;

TenantConfig tenant() =>
    TenantConfig.fromJson(jsonDecode(File('../../tenants/realtime-estates.json').readAsStringSync()) as Map<String, Object?>);

/// A lead repository that can fail like the Functions do.
/// Demo listings, with three photos on each.
class ThreePhotos extends DemoListingRepository {
  @override
  Future<ListingDetail?> bySlug(String slug) async {
    final d = await super.bySlug(slug);
    return d == null ? null : ListingDetail(summary: d.summary, description: d.description, photos: const ['https://x/1.webp', 'https://x/2.webp', 'https://x/3.webp'], videos: videos);
  }

  List<ListingVideo> videos = const [];
}

class FailingLeads extends DemoLeadRepository {
  FailingLeads(this.error);
  final LeadException error;
  @override
  Future<BookedViewing> bookViewing({required String listingId, required String slot, required String name, required String phone}) =>
      Future.error(error);
}

late DemoLeadRepository leads;
late List<Uri> opened;

Future<void> open(WidgetTester tester, String path, {LeadRepository? repo, Size size = const Size(412, 1600), TenantConfig? tenantConfig, ListingRepository? listings}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  leads = DemoLeadRepository();
  opened = [];
  await tester.pumpWidget(ProviderScope(
    overrides: [
      tenantProvider.overrideWithValue(tenantConfig ?? tenant()),
      leadRepositoryProvider.overrideWithValue(repo ?? leads),
      if (listings != null) listingRepositoryProvider.overrideWithValue(listings),
      favouritesStoreProvider.overrideWithValue(MemoryStore()),
      urlOpenerProvider.overrideWithValue((uri) async {
        opened.add(uri);
        return true;
      }),
      // Monday 26 Oct 2026, 09:00 in Nairobi.
      clockProvider.overrideWithValue(() => DateTime.utc(2026, 10, 26, 6)),
    ],
    child: const RealtorApp(),
  ));
  ProviderScope.containerOf(tester.element(find.byType(RealtorApp))).read(routerProvider).go(path);
  await tester.pumpAndSettle();
}

const kilimani = '/listing/2-bedroom-apartment-kilimani';

/// The page's own (vertical) scroll, not a row of cards or the map.
final page = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;

void main() {
  testWidgets('a listing link opens the listing: price, facts, deposit, agent and actions', (tester) async {
    await open(tester, kilimani);
    expect(find.text('2 bedroom apartment, Kilimani'), findsWidgets);
    for (final fact in ['Apartment', '2 beds', '2 baths', 'Kilimani']) {
      expect(find.text(fact), findsWidgets, reason: fact);
    }
    await tester.scrollUntilVisible(find.byKey(const Key('extra-payments')), 300, scrollable: page);
    expect(find.text('2 months · KES 130,000'), findsOneWidget, reason: 'the deposit, among the extra payments');
    expect(find.text('KES 3,000 a month'), findsOneWidget, reason: 'the service charge');
    expect(find.textContaining('A 2-bedroom, 2-bathroom apartment to let in Kilimani.'), findsOneWidget, reason: 'the description (P7-s02)');
    expect(find.text('Listed by Wanjiku Mwangi'), findsOneWidget);
    for (final action in ['WhatsApp', 'Call', 'Enquire', 'Book a viewing']) {
      expect(find.text(action), findsOneWidget, reason: action);
    }
    for (final section in ['Property details', 'Tips for your safety', 'Extra payments', 'Description', 'Location']) {
      expect(find.text(section), findsOneWidget, reason: section);
    }
    await tester.scrollUntilVisible(find.byKey(const Key('site-footer')), 400, scrollable: page);
    expect(find.byKey(const Key('site-footer')), findsOneWidget);
  });

  testWidgets('an unknown listing says so and offers a way back', (tester) async {
    await open(tester, '/listing/no-such-home');
    expect(find.text('This home is no longer available.'), findsOneWidget);
    expect(find.text('See all homes'), findsOneWidget);
  });

  testWidgets('WhatsApp and Call count the tap and open the agent with the listing link', (tester) async {
    await open(tester, kilimani);
    await tester.tap(find.text('WhatsApp'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Call'));
    await tester.pumpAndSettle();
    expect(leads.taps, ['demo-1/whatsapp', 'demo-1/call']);
    expect(opened[0].host, 'wa.me');
    expect(opened[0].path, '/254700000101');
    expect(opened[0].queryParameters['text'], contains('https://realtimeestates.co.ke/listing/2-bedroom-apartment-kilimani'));
    expect(opened[1].toString(), 'tel:+254700000101');
  });

  testWidgets('an enquiry needs a Kenyan phone and the consent tick, then is sent', (tester) async {
    await open(tester, kilimani);
    await tester.tap(find.text('Enquire'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('phone')), '020 123456');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Enter a Kenyan mobile number'), findsOneWidget);
    expect(find.text('Tick the box so we may contact you.'), findsOneWidget);
    expect(find.textContaining('keep my details for up to 24 months'), findsOneWidget);
    expect(leads.enquiries, isEmpty);

    await tester.enterText(find.byKey(const Key('phone')), '0712 345 678');
    await tester.enterText(find.byKey(const Key('message')), 'Is it still free?');
    await tester.tap(find.byKey(const Key('consent')));
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(leads.enquiries.single, {'listingId': 'demo-1', 'phone': '+254712345678', 'name': null, 'message': 'Is it still free?'});
    expect(find.textContaining('Thank you. Realtime Estates'), findsOneWidget);
  });

  testWidgets('a viewing request sends the chosen Nairobi slot', (tester) async {
    await open(tester, kilimani);
    await tester.tap(find.text('Book a viewing'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('day')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tue 27 Oct').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('name')), 'Amina');
    await tester.enterText(find.byKey(const Key('phone')), '+254 712 345678');
    await tester.tap(find.byKey(const Key('consent')));
    await tester.tap(find.text('Request viewing'));
    await tester.pumpAndSettle();
    expect(leads.viewings.single, {'listingId': 'demo-1', 'slot': '2026-10-27T10:00:00+03:00', 'name': 'Amina', 'phone': '+254712345678'});
    expect(find.textContaining('Viewing requested.'), findsOneWidget);
  });

  testWidgets('only free times are offered; a full day says so and cannot be sent', (tester) async {
    final busy = DemoLeadRepository()..taken.addAll({'2026-10-27 10:00', '2026-10-27 08:00'});
    for (final t in viewingTimes) {
      busy.taken.add('2026-10-28 $t');
    }
    await open(tester, kilimani, repo: busy);
    await tester.tap(find.text('Book a viewing'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('day')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tue 27 Oct').last);
    await tester.pumpAndSettle();
    expect(find.text('08:30'), findsOneWidget, reason: '10:00 is taken, so the first free time is picked');
    await tester.tap(find.text('08:30'));
    await tester.pumpAndSettle();
    expect(find.text('10:00'), findsNothing);
    expect(find.text('08:00'), findsNothing);
    await tester.tap(find.text('10:30').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('day')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wed 28 Oct').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('no-times')), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Request viewing')).onPressed, isNull);
  });

  testWidgets('a taken slot keeps the sheet open and says why', (tester) async {
    await open(tester, kilimani, repo: FailingLeads(LeadException('already-exists', 'that time is taken')));
    await tester.tap(find.text('Book a viewing'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('name')), 'Amina');
    await tester.enterText(find.byKey(const Key('phone')), '0712345678');
    await tester.tap(find.byKey(const Key('consent')));
    await tester.tap(find.text('Request viewing'));
    await tester.pumpAndSettle();
    expect(find.text('That time is taken. Please pick another.'), findsOneWidget);
    expect(find.text('Request viewing'), findsOneWidget);
  });

  testWidgets('recommended: close ones first; with none close, the newest of the same purpose', (tester) async {
    await open(tester, '/listing/bedsitter-near-kasarani-stadium');
    await tester.scrollUntilVisible(find.text('Recommended for you'), 300, scrollable: page);
    expect(find.text('Student hostel bed, Kasarani'), findsOneWidget);
    await tester.ensureVisible(find.text('Student hostel bed, Kasarani'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Student hostel bed, Kasarani'));
    await tester.pumpAndSettle();
    expect(find.text('Student hostel bed, Kasarani'), findsWidgets);
    final router = ProviderScope.containerOf(tester.element(find.byType(RealtorApp))).read(routerProvider);
    expect(router.state.uri.path, '/listing/student-hostel-bed-kasarani');
    expect(leads.recommendations.take(2), ['demo-2/shown', 'demo-2/opened'], reason: 'counted once shown, once opened');

    // With nothing close, the row still fills with the newest homes to rent.
    await open(tester, kilimani);
    await tester.scrollUntilVisible(find.text('Recommended for you'), 300, scrollable: page);
    final row = find.byKey(const Key('recommended'));
    expect(find.descendant(of: row, matching: find.text('Bedsitter near Kasarani stadium')), findsOneWidget);
    expect(find.descendant(of: row, matching: find.text('2 bedroom apartment, Kilimani')), findsNothing, reason: 'never the home itself');
  });

  testWidgets('on desktop: the photo mosaic within the page width, the contact card beside the details', (tester) async {
    await open(tester, kilimani, listings: ThreePhotos(), size: const Size(1900, 1000));
    final photos = tester.getRect(find.byKey(const ValueKey('listing-photos')));
    final card = tester.getRect(find.byKey(const Key('contact-card')));
    final details = tester.getRect(find.byKey(const Key('property-details')));
    expect(photos.width, lessThanOrEqualTo(1100));
    expect(card.top, greaterThan(photos.bottom));
    expect(card.left, greaterThan(details.right));
    expect(tester.getRect(find.descendant(of: find.byKey(const Key('contact-card')), matching: find.text('Enquire'))).bottom, lessThan(1000),
        reason: 'contact in view without scrolling');
    expect(find.byKey(const Key('share')), findsOneWidget);
    expect(find.byKey(const Key('save')), findsOneWidget);
  });

  testWidgets('desktop: a photo opens the gallery (Photos and Map), a gallery photo opens the viewer, Back returns to the gallery', (tester) async {
    await open(tester, kilimani, listings: ThreePhotos(), size: const Size(1600, 1000));
    await tester.tap(find.byKey(const Key('gallery-count')));
    await tester.pumpAndSettle();
    expect(find.text('Photos (3)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('gallery-tab-map')));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byKey(const Key('gallery')), matching: find.byKey(const Key('listing-map'))), findsOneWidget);
    await tester.tap(find.byKey(const Key('gallery-tab-photos')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gallery-photo-1')));
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    await tester.tap(find.byKey(const Key('back-to-gallery')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('photo-viewer')), findsNothing);
    expect(find.byKey(const Key('gallery')), findsOneWidget);
  });

  testWidgets('Save keeps the home; Share copies its link', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await open(tester, kilimani, size: const Size(1600, 1000));
    await tester.tap(find.byKey(const Key('share')));
    await tester.pumpAndSettle();
    expect(copied, ['https://realtimeestates.co.ke/listing/2-bedroom-apartment-kilimani']);
    expect(find.textContaining('Link copied'), findsOneWidget);
    await tester.tap(find.byKey(const Key('save')));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byKey(const Key('save')), matching: find.text('Saved')), findsOneWidget);
  });

  testWidgets('on a phone the photos come first, full width', (tester) async {
    await open(tester, kilimani);
    final photos = tester.getRect(find.byKey(const ValueKey('listing-photos')));
    expect(photos.width, 412);
    expect(tester.getRect(find.text('WhatsApp')).top, greaterThan(photos.bottom));
    expect(tester.getRect(find.text('WhatsApp')).bottom, lessThanOrEqualTo(1600), reason: 'Call and WhatsApp stay in the bottom bar');
  });

  testWidgets('a viewing with a fee offers M-Pesa to the booking phone (P6-s01)', (tester) async {
    final json = jsonDecode(File('../../tenants/realtime-estates.json').readAsStringSync()) as Map<String, Object?>;
    (json['features']! as Map<String, Object?>)['mpesa'] = true;
    final repo = DemoLeadRepository()..viewingFeeKES = 500;
    await open(tester, kilimani, repo: repo, tenantConfig: TenantConfig.fromJson(json));
    await tester.tap(find.text('Book a viewing'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('name')), 'Amina');
    await tester.enterText(find.byKey(const Key('phone')), '0712 345 678');
    await tester.tap(find.byKey(const Key('consent')));
    await tester.tap(find.text('Request viewing'));
    await tester.pumpAndSettle();
    expect(find.textContaining('viewing fee of KES 500'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pay')));
    await tester.pumpAndSettle();
    expect(repo.payments, ['demo-1/+254712345678']);
    expect(find.textContaining('enter your M-Pesa PIN to pay KES 500'), findsOneWidget);
  });

  testWidgets('without M-Pesa on, a fee is never offered', (tester) async {
    final repo = DemoLeadRepository()..viewingFeeKES = 500;
    await open(tester, kilimani, repo: repo);
    await tester.tap(find.text('Book a viewing'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('name')), 'Amina');
    await tester.enterText(find.byKey(const Key('phone')), '0712 345 678');
    await tester.tap(find.byKey(const Key('consent')));
    await tester.tap(find.text('Request viewing'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pay')), findsNothing);
    expect(repo.payments, isEmpty);
  });

  testWidgets('more than one photo: the viewer has a count, arrows, keys and a mouse drag', (tester) async {
    await open(tester, kilimani, listings: ThreePhotos(), size: const Size(1400, 1000));
    await tester.tap(find.byKey(const Key('gallery-count')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gallery-photo-0')));
    await tester.pumpAndSettle();
    expect(find.text('1 / 3'), findsOneWidget);
    expect(find.byKey(const Key('Previous photo')), findsNothing, reason: 'on the first photo');
    await tester.tap(find.byKey(const Key('Next photo')));
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    await tester.tap(find.byKey(const Key('Next photo')));
    await tester.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget);
    expect(find.byKey(const Key('Next photo')), findsNothing, reason: 'on the last photo');
    await tester.tap(find.byKey(const Key('Previous photo')));
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    // A mouse drag also turns the page on the web.
    await tester.drag(find.descendant(of: find.byKey(const Key('photo-viewer')), matching: find.byType(PageView)), const Offset(-900, 0), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget);
  });

  testWidgets('a video comes after the photos, as a poster with a play button', (tester) async {
    final repo = ThreePhotos()..videos = const [ListingVideo(hls: 'https://x/v/master.m3u8', mp4: 'https://x/v/video.mp4', poster: 'https://x/v/poster.jpg')];
    await open(tester, kilimani, listings: repo, size: const Size(1400, 1000));
    await tester.tap(find.byKey(const Key('gallery-count')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gallery-photo-0')));
    await tester.pumpAndSettle();
    expect(find.text('1 / 4'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const Key('Next photo')));
      await tester.pumpAndSettle();
    }
    expect(find.text('4 / 4'), findsOneWidget);
    expect(find.byKey(const Key('play-video')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Play .*video 1$')), findsOneWidget);
  });

  testWidgets('a phone: tapping the photos opens them full screen, with the count', (tester) async {
    await open(tester, kilimani, listings: ThreePhotos());
    expect(find.text('1 / 3'), findsOneWidget, reason: 'the strip counts too');
    await tester.tap(find.byKey(const ValueKey('listing-photos')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('photo-viewer')), findsOneWidget);
    expect(find.byKey(const Key('back-to-gallery')), findsNothing, reason: 'phones open the viewer straight away');
  });

  testWidgets('breadcrumbs: Back to search, then Home > Apartments to rent > the area > the home, each opening that search', (tester) async {
    await open(tester, kilimani, size: const Size(1600, 1000));
    final crumbs = find.byKey(const Key('breadcrumbs'));
    for (final c in ['Back to search', 'Apartments to rent', 'Kilimani', '2 bedroom apartment, Kilimani']) {
      expect(find.descendant(of: crumbs, matching: find.text(c)), findsOneWidget, reason: c);
    }
    await tester.tap(find.descendant(of: crumbs, matching: find.text('Kilimani')));
    await tester.pumpAndSettle();
    final router = ProviderScope.containerOf(tester.element(find.byType(RealtorApp))).read(routerProvider);
    expect(router.state.uri.path, '/rent/apartments/kilimani');
  });

  testWidgets('desktop: a mosaic photo opens the gallery at that photo; Video plays at once, with no extra screen', (tester) async {
    final repo = ThreePhotos()..videos = const [ListingVideo(hls: 'https://x/v/master.m3u8', mp4: 'https://x/v/video.mp4', poster: 'https://x/v/poster.jpg')];
    await open(tester, kilimani, listings: repo, size: const Size(1600, 1000));
    await tester.tap(find.bySemanticsLabel('Open the gallery at photo 3 of 4'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('gallery')), findsOneWidget);
    Navigator.of(tester.element(find.byKey(const Key('gallery')))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gallery-video')));
    await tester.pump();
    expect(find.byKey(const Key('photo-viewer')), findsOneWidget);
    expect(find.byKey(const Key('play-video')), findsNothing, reason: 'no poster to tap: it is already playing');
    expect(find.byKey(const Key('video-player')), findsOneWidget);
  });

  testWidgets('the map zooms with its buttons and opens full screen', (tester) async {
    await open(tester, kilimani, size: const Size(1600, 1000));
    await tester.scrollUntilVisible(find.byKey(const Key('map-zoom-in')), 300, scrollable: page);
    await tester.ensureVisible(find.byKey(const Key('listing-map')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('map-zoom-in')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('map-full-screen')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('listing-map')), findsNWidgets(2), reason: 'the page map and the full-screen one');
  });

  testWidgets('reviews: the approved ones with their average; writing one needs sign-in, then waits to be checked', (tester) async {
    final reviews = DemoListingReviews();
    final account = DemoAccount();
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        tenantProvider.overrideWithValue(tenant()),
        listingReviewsProvider.overrideWithValue(reviews),
        demoAccountProvider.overrideWithValue(account),
        favouritesStoreProvider.overrideWithValue(MemoryStore()),
      ],
      child: const RealtorApp(),
    ));
    ProviderScope.containerOf(tester.element(find.byType(RealtorApp))).read(routerProvider).go(kilimani);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('write-review')), 300, scrollable: page);
    await tester.ensureVisible(find.byKey(const Key('write-review')));
    await tester.pumpAndSettle();
    expect(find.text('Reviews (2)'), findsOneWidget);
    expect(find.text('4.5'), findsOneWidget);
    expect(find.text('After a viewing'), findsOneWidget);

    await tester.tap(find.byKey(const Key('write-review')));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to review this home.'), findsOneWidget);

    await account.signInWithGoogle();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('write-review')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('send-review')));
    await tester.pump();
    expect(find.text('Choose from 1 to 5 stars.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('star-4')));
    await tester.enterText(find.byKey(const Key('review-comment')), 'Water every day, friendly caretaker.');
    await tester.enterText(find.byKey(const Key('review-name')), 'Wanjiru Kamau');
    await tester.tap(find.byKey(const Key('send-review')));
    await tester.pumpAndSettle();
    expect(reviews.pending.single.rating, 4);
    expect(find.textContaining('shows once it has been checked'), findsOneWidget);
    expect(find.text('Reviews (2)'), findsOneWidget, reason: 'not shown until approved');
  });
}
