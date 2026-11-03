import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtor_app/src/app.dart';
import 'package:realtor_app/src/listing/demo_listings.dart';
import 'package:realtor_app/src/providers.dart';
import 'package:realtor_core/realtor_core.dart';

TenantConfig tenant() =>
    TenantConfig.fromJson(jsonDecode(File('../../tenants/realtime-estates.json').readAsStringSync()) as Map<String, Object?>);

/// A lead repository that can fail like the Functions do.
/// Demo listings, with three photos on each.
class ThreePhotos extends DemoListingRepository {
  @override
  Future<ListingDetail?> bySlug(String slug) async {
    final d = await super.bySlug(slug);
    return d == null ? null : ListingDetail(summary: d.summary, description: d.description, photos: const ['https://x/1.webp', 'https://x/2.webp', 'https://x/3.webp']);
  }
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

void main() {
  testWidgets('a listing link opens the listing: price, facts, deposit, agent and actions', (tester) async {
    await open(tester, kilimani);
    expect(find.text('2 bedroom apartment, Kilimani'), findsWidgets);
    expect(find.text('2 bed · 2 bath · Kilimani'), findsOneWidget);
    expect(find.text('Deposit: 2 months'), findsOneWidget);
    expect(find.textContaining('A 2-bedroom, 2-bathroom apartment to let in Kilimani.'), findsOneWidget, reason: 'the description (P7-s02)');
    expect(find.text('Listed by Wanjiku Mwangi'), findsOneWidget);
    for (final action in ['WhatsApp', 'Call', 'Enquire', 'Book a viewing']) {
      expect(find.text(action), findsOneWidget, reason: action);
    }
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

  testWidgets('similar homes: close ones from the same area show; none close, no section', (tester) async {
    await open(tester, '/listing/bedsitter-near-kasarani-stadium');
    await tester.scrollUntilVisible(find.text('Similar homes'), 300);
    expect(find.text('Student hostel bed, Kasarani'), findsOneWidget);
    await tester.tap(find.text('Student hostel bed, Kasarani'));
    await tester.pumpAndSettle();
    expect(find.text('Student hostel bed, Kasarani'), findsWidgets);
    final router = ProviderScope.containerOf(tester.element(find.byType(RealtorApp))).read(routerProvider);
    expect(router.state.uri.path, '/listing/student-hostel-bed-kasarani');
    expect(leads.recommendations, ['demo-2/shown', 'demo-2/opened'], reason: 'counted once shown, once opened; the hostel bed has none');

    await open(tester, kilimani);
    expect(find.text('Similar homes'), findsNothing, reason: 'no other rental near KES 65,000 shares its area or type');
  });

  testWidgets('on desktop the photos sit beside the details, within the content width', (tester) async {
    await open(tester, kilimani, size: const Size(1900, 1000));
    final photos = tester.getRect(find.byKey(const ValueKey('listing-photos')));
    final whatsapp = tester.getRect(find.text('WhatsApp'));
    expect(whatsapp.left, greaterThan(photos.right));
    expect(whatsapp.bottom, lessThan(1000));
    expect(photos.width, lessThan(1200));
  });

  testWidgets('on a phone the photos come first, full width', (tester) async {
    await open(tester, kilimani);
    final photos = tester.getRect(find.byKey(const ValueKey('listing-photos')));
    expect(photos.width, 412);
    expect(tester.getRect(find.text('WhatsApp')).top, greaterThan(photos.bottom));
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

  testWidgets('more than one photo: a count, arrows and keys move through them', (tester) async {
    await open(tester, kilimani, listings: ThreePhotos(), size: const Size(1400, 1000));
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
    await tester.drag(find.byType(PageView), const Offset(-500, 0), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget);
  });
}
