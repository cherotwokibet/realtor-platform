import 'dart:convert';
import 'dart:io';

import 'package:jaspr/server.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:share_pages/share_pages.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

import 'listing_page_test.dart' show flat;

final tenant = TenantConfig.fromJson(
  jsonDecode(File('../../tenants/realtime-estates.json').readAsStringSync()) as Map<String, Object?>,
);

const kilimani = ShareArea(
  slug: 'kilimani',
  name: 'Kilimani',
  county: 'Nairobi',
  lat: -1.2921,
  lng: 36.7856,
  guide: 'Leafy, central, close to Yaya Centre.',
  amenities: ['Yaya Centre', 'Nairobi Hospital nearby'],
  medianRentKES: 75000,
);

Future<shelf.Response> get(String path) => Future.value(
      shareHandler(tenant, InMemoryListingSource(const [flat], areas: const [kilimani]))(shelf.Request('GET', Uri.parse('https://x$path'))),
    );

void main() {
  setUpAll(Jaspr.initializeApp);

  test('area page lists its live homes and links into the app search', () async {
    final r = await get('/area/kilimani');
    expect(r.statusCode, 200);
    final html = await r.readAsString();
    expect(html, contains('<h1>Homes in Kilimani</h1>'));
    expect(html, contains('Typical rent: KES 75,000 a month'));
    expect(html, contains('<li>Yaya Centre</li>'));
    expect(html, contains('href="/listing/2-bedroom-apartment-kilimani"'));
    expect(html, contains('href="https://app.realtimeestates.co.ke/rent/kilimani"'));
    final ld = jsonDecode(RegExp(r'<script type="application/ld\+json">(.*?)</script>', dotAll: true).firstMatch(html)!.group(1)!) as Map;
    expect(ld['@type'], 'Place');
    expect((((ld['subjectOf'] as Map)['itemListElement'] as List).single as Map)['url'], 'https://realtimeestates.co.ke/listing/2-bedroom-apartment-kilimani');
  });

  test("a rental below its area's typical rent says so; without a median it says nothing", () async {
    final html = await (await get('/listing/${flat.slug}')).readAsString();
    expect(html, contains('13% below the typical rent in Kilimani (KES 75,000 a month)'));
    final bare = shareHandler(tenant, InMemoryListingSource(const [flat]));
    final plain = await (await bare(shelf.Request('GET', Uri.parse('https://x/listing/${flat.slug}')))).readAsString();
    expect(plain, isNot(contains('typical rent')));
  });

  test('listing pages link back to their area', () async {
    final html = await (await get('/listing/2-bedroom-apartment-kilimani')).readAsString();
    expect(html, contains('href="/area/kilimani"'));
  });

  test('unknown area is a 404', () async {
    expect((await get('/area/atlantis')).statusCode, 404);
  });

  test('sitemap.xml lists home, areas and live listings', () async {
    final r = await get('/sitemap.xml');
    expect(r.headers['content-type'], startsWith('application/xml'));
    final xml = await r.readAsString();
    expect(xml, startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
    expect(xml, contains('<loc>https://realtimeestates.co.ke/</loc>'));
    expect(xml, contains('<loc>https://realtimeestates.co.ke/area/kilimani</loc>'));
    expect(xml, contains('<loc>https://realtimeestates.co.ke/listing/2-bedroom-apartment-kilimani</loc>'));
  });

  test('sitemap lastmod is W3C datetime and URLs are XML-escaped', () {
    final xml = sitemapXml(tenant, [(path: '/listing/a&b', lastModified: DateTime.utc(2026, 10, 24, 9, 30, 15, 123), purpose: null)]);
    expect(xml, contains('<loc>https://realtimeestates.co.ke/listing/a&amp;b</loc><lastmod>2026-10-24T09:30:15Z</lastmod>'));
  });

  test('robots.txt points at the sitemap', () async {
    final r = await get('/robots.txt');
    expect(await r.readAsString(), contains('Sitemap: https://realtimeestates.co.ke/sitemap.xml'));
    expect(r.headers['x-robots-tag'], isNull);
  });

  test('outside prod, crawlers are turned away from every page', () async {
    final h = shareHandler(tenant, InMemoryListingSource(const [flat], areas: const [kilimani]), indexable: false);
    Future<shelf.Response> dev(String path) => Future.value(h(shelf.Request('GET', Uri.parse('https://x$path'))));
    expect(await (await dev('/robots.txt')).readAsString(), 'User-agent: *\nDisallow: /\n');
    for (final path in ['/', '/listing/${flat.slug}', '/area/kilimani', '/sitemap.xml', '/missing']) {
      expect((await dev(path)).headers['x-robots-tag'], 'noindex', reason: path);
    }
  });

  test('published site pages render as plain text and show in every footer; drafts and others are 404', () async {
    final src = InMemoryListingSource(const [flat], areas: const [kilimani])
      ..sitePages = {
        'privacy': (title: 'Privacy notice', body: '# Who we are\nRealtime Estates <b>Ltd</b>.\nNairobi.\n\n- your rights\n- our duties'),
      };
    final h = shareHandler(tenant, src);
    Future<shelf.Response> go(String path) => Future.value(h(shelf.Request('GET', Uri.parse('https://x$path'))));
    final html = await (await go('/privacy')).readAsString();
    expect(html, contains('<h1>Privacy notice</h1>'));
    expect(html, contains('<h2>Who we are</h2>'));
    expect(html, contains('<p>Realtime Estates &lt;b&gt;Ltd&lt;/b&gt;. Nairobi.</p>'));
    expect(html, contains('<li>your rights</li>'));
    expect(await (await go('/')).readAsString(), contains('href="/privacy"'));
    expect((await go('/about')).statusCode, 404);
    expect((await go('/secret')).statusCode, 404);
    expect((await go('/robots.txt')).statusCode, 200);
    expect((await go('/sitemap.xml')).statusCode, 200);
  });
}
