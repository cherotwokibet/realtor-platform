import 'package:jaspr/server.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:share_pages/share_pages.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

import 'listing_page_test.dart' show flat, tenant;

const stay = ShareListing(
  id: 'listing-002',
  slug: 'studio-westlands-stay',
  title: 'Studio, Westlands',
  purpose: Purpose.shortStay,
  type: 'studio',
  beds: 1,
  baths: 1,
  priceKES: 6500,
  area: 'westlands',
  lat: -1.2641,
  lng: 36.8029,
);

Future<shelf.Response> get(String path, String tenantId) => Future.value(
      shareHandler(tenant(tenantId), InMemoryListingSource(const [flat, stay]))(shelf.Request('GET', Uri.parse('https://x$path'))),
    );

void main() {
  setUpAll(Jaspr.initializeApp);

  // realtime-estates has shortStay off, demo-homes has it on.
  test('a listing for a switched-off purpose is a 404; an enabled one is served', () async {
    expect((await get('/listing/${stay.slug}', 'realtime-estates')).statusCode, 404);
    expect((await get('/listing/${flat.slug}', 'realtime-estates')).statusCode, 200);
    expect((await get('/listing/${stay.slug}', 'demo-homes')).statusCode, 200);
  });

  test('its actions are 404s too, so nothing can be sent for it', () async {
    final res = await shareHandler(tenant('realtime-estates'), InMemoryListingSource(const [stay]))(
      shelf.Request('GET', Uri.parse('https://x/go/whatsapp/${stay.slug}')),
    );
    expect(res.statusCode, 404);
  });

  test('home page and sitemap leave it out', () async {
    final home = await (await get('/', 'realtime-estates')).readAsString();
    expect(home, contains(flat.title));
    expect(home, isNot(contains(stay.title)));
    final map = await (await get('/sitemap.xml', 'realtime-estates')).readAsString();
    expect(map, contains('/listing/${flat.slug}'));
    expect(map, isNot(contains(stay.slug)));
    final demoMap = await (await get('/sitemap.xml', 'demo-homes')).readAsString();
    expect(demoMap, contains(stay.slug));
  });

  test('core: Features.allowsPurpose follows the switches', () {
    final f = tenant('realtime-estates').features;
    expect(f.allowsPurpose(Purpose.rent), isTrue);
    expect(f.allowsPurpose(Purpose.shortStay), isFalse);
  });
}
