import 'dart:convert';
import 'dart:io';

import 'package:jaspr/server.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:share_pages/share_pages.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

TenantConfig tenant(String id) =>
    TenantConfig.fromJson(jsonDecode(File('../../tenants/$id.json').readAsStringSync()) as Map<String, Object?>);

const flat = ShareListing(
  id: 'listing-001',
  slug: '2-bedroom-apartment-kilimani',
  title: '2 bedroom apartment, Kilimani',
  purpose: Purpose.rent,
  type: 'apartment',
  beds: 2,
  baths: 2,
  priceKES: 65000,
  depositMonths: 2,
  area: 'kilimani',
  estate: 'Argwings Kodhek',
  lat: -1.2901,
  lng: 36.7846,
  amenities: ['parking', 'borehole'],
  photos: [(card: 'media/listings/listing-001/abc/card.webp', full: 'media/listings/listing-001/abc/full.webp')],
  verified: true,
);

Future<shelf.Response> get(String path, {String tenantId = 'realtime-estates', List<ShareListing> listings = const [flat]}) =>
    Future.value(shareHandler(tenant(tenantId), InMemoryListingSource(listings))(shelf.Request('GET', Uri.parse('https://x$path'))));

String? attr(String html, String property) =>
    RegExp('<meta property="$property" content="([^"]*)"').firstMatch(html)?.group(1);

void main() {
  setUpAll(Jaspr.initializeApp);

  test('a listing page is plain HTML with its own title, price and photo', () async {
    final r = await get('/listing/2-bedroom-apartment-kilimani');
    expect(r.statusCode, 200);
    expect(r.headers['cache-control'], contains('s-maxage'));
    final html = await r.readAsString();
    expect(html, contains('<h1>2 bedroom apartment, Kilimani</h1>'));
    expect(html, contains('KES 65,000'));
    expect(html, contains('<html lang="en">'));
    expect(html, matches(RegExp(r'<link (?=[^>]*rel="canonical")(?=[^>]*href="https://realtimeestates.co.ke/listing/2-bedroom-apartment-kilimani")')));
    expect(html, contains('Argwings Kodhek, Kilimani'));
    expect(html, contains('href="https://app.realtimeestates.co.ke/listing/2-bedroom-apartment-kilimani"'), reason: 'Open in app');
  });

  test('WhatsApp / Open Graph preview shows the photo and price', () async {
    final html = await (await get('/listing/2-bedroom-apartment-kilimani')).readAsString();
    expect(attr(html, 'og:title'), contains('KES 65,000 a month'));
    expect(attr(html, 'og:image'), 'https://firebasestorage.googleapis.com/v0/b/rte-realtor-prod-media/o/media%2Flistings%2Flisting-001%2Fabc%2Ffull.webp?alt=media');
    mediaProject = 'rte-realtor-dev';
    addTearDown(() => mediaProject = null);
    expect(tenantMediaUrl(tenant('realtime-estates'), 'media/x.webp'), 'https://firebasestorage.googleapis.com/v0/b/rte-realtor-dev-media/o/media%2Fx.webp?alt=media');
    expect(attr(html, 'og:url'), 'https://realtimeestates.co.ke/listing/2-bedroom-apartment-kilimani');
  });

  test('JSON-LD is a valid RealEstateListing', () async {
    final html = await (await get('/listing/2-bedroom-apartment-kilimani')).readAsString();
    final json = RegExp(r'<script type="application/ld\+json">(.*?)</script>', dotAll: true).firstMatch(html)!.group(1)!;
    final ld = jsonDecode(json) as Map<String, Object?>;
    expect(ld['@type'], 'RealEstateListing');
    final offer = ld['offers']! as Map<String, Object?>;
    expect(offer['price'], 65000);
    expect(offer['priceCurrency'], 'KES');
    expect((ld['about']! as Map)['numberOfBedrooms'], 2);
  });

  test('page stays under the 100 KB doneWhen budget', () async {
    final r = await get('/listing/2-bedroom-apartment-kilimani');
    expect((await r.read().expand((c) => c).toList()).length, lessThan(100 * 1024));
  });

  test('user text is escaped, and cannot break out of the JSON-LD script', () async {
    const evil = ShareListing(
      id: 'x', slug: 'evil', title: '<img src=x onerror=alert(1)> </script><script>alert(2)</script>',
      purpose: Purpose.sale, type: 'land', beds: 0, baths: 0, priceKES: 1, area: 'ruaka', lat: 0, lng: 0,
    );
    final html = await (await get('/listing/evil', listings: [evil])).readAsString();
    expect(html, isNot(contains('<img src=x')));
    expect(html, isNot(contains('<script>alert(2)')));
    expect('</script>'.allMatches(html).length, 1, reason: 'only the JSON-LD script closes');
    final json = RegExp(r'<script type="application/ld\+json">(.*?)</script>', dotAll: true).firstMatch(html)!.group(1)!;
    expect((jsonDecode(json) as Map)['name'], evil.title, reason: 'escaping keeps the data intact');
  });

  test("the agent's description shows paragraph by paragraph, escaped (P7-s02)", () async {
    const described = ShareListing(
      id: 'd', slug: 'described', title: 'Quiet flat in Ruaka', purpose: Purpose.rent, type: 'apartment', beds: 1, baths: 1,
      priceKES: 25000, area: 'ruaka', lat: 0, lng: 0, description: 'Near the market.\n\nWater all week <b>always</b>.',
    );
    final html = await (await get('/listing/described', listings: [described])).readAsString();
    expect(html, contains('<p>Near the market.</p>'));
    expect(html, contains('<p>Water all week &lt;b&gt;always&lt;/b&gt;.</p>'));
  });

  test('unknown and malformed slugs are 404s', () async {
    expect((await get('/listing/no-such-home')).statusCode, 404);
    expect((await get('/listing/Bad%20Slug')).statusCode, 404);
  });

  test('the same page re-brands per tenant with no code change', () async {
    final a = await (await get('/listing/2-bedroom-apartment-kilimani')).readAsString();
    final b = await (await get('/listing/2-bedroom-apartment-kilimani', tenantId: 'demo-homes')).readAsString();
    expect(a, contains('--color-primary: #5E0202'));
    expect(b, contains('--color-primary: #0F5257'));
    expect(b, contains('Demo Homes'));
    expect(b, isNot(contains('Realtime')));
  });

  test('a listing video plays with no script: HLS first, then the MP4, poster and controls; the CSP allows media', () async {
    const withVideo = ShareListing(
      id: 'listing-001', slug: '2-bedroom-apartment-kilimani', title: '2 bedroom apartment, Kilimani', purpose: Purpose.rent,
      type: 'apartment', beds: 2, baths: 2, priceKES: 65000, area: 'kilimani', lat: -1.29, lng: 36.78,
      videos: [(hls: 'media/listings/listing-001/v1/hls/master.m3u8', mp4: 'media/listings/listing-001/v1/video.mp4', poster: 'media/listings/listing-001/v1/poster.jpg')],
    );
    final html = await (await get('/listing/${withVideo.slug}', listings: const [withVideo])).readAsString();
    expect(html, contains('<video'));
    expect(html, contains('controls'));
    expect(html, contains('preload="none"'));
    expect(html, contains('poster.jpg?alt=media'));
    final hls = html.indexOf('type="application/vnd.apple.mpegurl"'), mp4 = html.indexOf('type="video/mp4"');
    expect(hls, greaterThan(0));
    expect(mp4, greaterThan(hls), reason: 'browsers take the first source they can play');
    expect(securityHeaders['content-security-policy'], contains('media-src https:'));
    expect(await (await get('/listing/${flat.slug}')).readAsString(), isNot(contains('<video')), reason: 'no video, no player');
  });

  test('every response carries the security headers, and pages run no script the CSP would block', () async {
    for (final path in ['/listing/${flat.slug}', '/listing/missing', '/robots.txt', '/sitemap.xml', '/']) {
      final res = await get(path);
      for (final e in securityHeaders.entries) {
        expect(res.headers[e.key], e.value, reason: '$path ${e.key}');
      }
    }
    final html = await (await get('/listing/${flat.slug}')).readAsString();
    final scripts = RegExp(r'<script([^>]*)>').allMatches(html).map((m) => m.group(1)!.trim()).toList();
    expect(scripts, everyElement('type="application/ld+json"'));
    expect(html, isNot(contains('<link rel="stylesheet"')));
    expect(RegExp(r'<[^>]+\son[a-z]+=').hasMatch(html), isFalse);
  });
}
