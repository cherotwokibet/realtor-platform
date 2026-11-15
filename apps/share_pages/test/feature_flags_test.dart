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

/// A tenant with short stays switched off (whatever its file says today).
final TenantConfig noStays = () {
  final t = tenant('realtime-estates');
  return t.withFeatures(t.features.copyWith({Feature.shortStay: false}));
}();

Future<shelf.Response> get(String path, TenantConfig t) => Future.value(
      shareHandler(t, InMemoryListingSource(const [flat, stay]))(shelf.Request('GET', Uri.parse('https://x$path'))),
    );

void main() {
  setUpAll(Jaspr.initializeApp);

  // demo-homes has shortStay on.
  test('a listing for a switched-off purpose is a 404; an enabled one is served', () async {
    expect((await get('/listing/${stay.slug}', noStays)).statusCode, 404);
    expect((await get('/listing/${flat.slug}', noStays)).statusCode, 200);
    expect((await get('/listing/${stay.slug}', tenant('demo-homes'))).statusCode, 200);
  });

  test('its actions are 404s too, so nothing can be sent for it', () async {
    final res = await shareHandler(noStays, InMemoryListingSource(const [stay]))(
      shelf.Request('GET', Uri.parse('https://x/go/whatsapp/${stay.slug}')),
    );
    expect(res.statusCode, 404);
  });

  test('home page and sitemap leave it out', () async {
    final home = await (await get('/', noStays)).readAsString();
    expect(home, contains(flat.title));
    expect(home, isNot(contains(stay.title)));
    final map = await (await get('/sitemap.xml', noStays)).readAsString();
    expect(map, contains('/listing/${flat.slug}'));
    expect(map, isNot(contains(stay.slug)));
    final demoMap = await (await get('/sitemap.xml', tenant('demo-homes'))).readAsString();
    expect(demoMap, contains(stay.slug));
  });

  test('core: Features.allowsPurpose follows the switches', () {
    final f = noStays.features;
    expect(f.allowsPurpose(Purpose.rent), isTrue);
    expect(f.allowsPurpose(Purpose.shortStay), isFalse);
  });
}
