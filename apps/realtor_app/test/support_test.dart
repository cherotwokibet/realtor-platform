import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtor_app/src/app.dart';
import 'package:realtor_app/src/providers.dart';
import 'package:realtor_app/src/support/site_services.dart';
import 'package:realtor_core/realtor_core.dart';

import 'listing_screen_test.dart' show tenant;

/// Help & feedback (the admin's Support inbox) and adverts from the admin's Ads page.
void main() {
  late DemoSiteServices services;

  Future<ProviderContainer> open(WidgetTester tester, String path, {Size size = const Size(412, 1400)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(overrides: [tenantProvider.overrideWithValue(tenant()), siteServicesProvider.overrideWithValue(services)]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const RealtorApp()));
    await tester.pumpAndSettle();
    c.read(routerProvider).go(path);
    await tester.pumpAndSettle();
    return c;
  }

  setUp(() => services = DemoSiteServices());

  testWidgets('Help & feedback: what is wrong first, then the message goes with the page it came from', (tester) async {
    await open(tester, '/help?from=/rent');
    await tester.tap(find.byKey(const Key('help-send')));
    await tester.pumpAndSettle();
    expect(find.text('Write a little more (at least 5 characters).'), findsOneWidget);
    await tester.tap(find.byKey(const Key('help-kind-problem')));
    await tester.enterText(find.byKey(const Key('help-message')), 'The map does not load on my phone');
    await tester.enterText(find.byKey(const Key('help-phone')), '0712 3');
    await tester.tap(find.byKey(const Key('help-send')));
    await tester.pumpAndSettle();
    expect(find.text('A Kenyan mobile, e.g. 0712 345 678.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('help-phone')), '0712 345 678');
    await tester.tap(find.byKey(const Key('help-send')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('help-sent')), findsOneWidget);
    expect(services.sent.single, {'kind': 'problem', 'message': 'The map does not load on my phone', 'phone': '+254712345678', 'page': '/rent'});
  });

  testWidgets('the footer offers Help & feedback', (tester) async {
    await open(tester, '/', size: const Size(1280, 2000));
    final link = find.text('Help & feedback');
    await tester.dragUntilVisible(link, find.byType(CustomScrollView).first, const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(find.text('How can we help?'), findsOneWidget);
  });

  testWidgets("a running ad from the admin takes the home page's advert band; a paused or ended one does not", (tester) async {
    services.demoAds = const [
      AdRow(id: 'a1', title: 'Riverside Gardens: now letting', text: 'Two and three bedrooms.', advertiser: 'Riverside Ltd', placement: 'home'),
      AdRow(id: 'a2', title: 'Paused one', placement: 'both', active: false),
      AdRow(id: 'a3', title: 'Old one', placement: 'both', endsOn: '2020-01-01'),
    ];
    await open(tester, '/', size: const Size(1280, 2400));
    final title = find.byKey(const Key('ad-title'));
    await tester.scrollUntilVisible(title, 300, scrollable: find.byType(Scrollable).first);
    expect(tester.widget<Text>(title).data, 'Riverside Gardens: now letting');
    expect(find.text('Paused one'), findsNothing);
    expect(find.text('Old one'), findsNothing);
  });
}
