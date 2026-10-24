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
    final xml = sitemapXml(tenant, [(path: '/listing/a&b', lastModified: DateTime.utc(2026, 10, 24, 9, 30, 15, 123))]);
    expect(xml, contains('<loc>https://realtimeestates.co.ke/listing/a&amp;b</loc><lastmod>2026-10-24T09:30:15Z</lastmod>'));
  });

  test('robots.txt points at the sitemap', () async {
    expect(await (await get('/robots.txt')).readAsString(), contains('Sitemap: https://realtimeestates.co.ke/sitemap.xml'));
  });
}
