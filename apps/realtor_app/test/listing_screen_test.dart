import 'dart:convert';
import 'dart:io';

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
class FailingLeads extends DemoLeadRepository {
  FailingLeads(this.error);
  final LeadException error;
  @override
  Future<void> bookViewing({required String listingId, required String slot, required String name, required String phone}) =>
      Future.error(error);
}

late DemoLeadRepository leads;
late List<Uri> opened;

Future<void> open(WidgetTester tester, String path, {LeadRepository? repo}) async {
  tester.view.physicalSize = const Size(412, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  leads = DemoLeadRepository();
  opened = [];
  await tester.pumpWidget(ProviderScope(
    overrides: [
      tenantProvider.overrideWithValue(tenant()),
      leadRepositoryProvider.overrideWithValue(repo ?? leads),
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
}
