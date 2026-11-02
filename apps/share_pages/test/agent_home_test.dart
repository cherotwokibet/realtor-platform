import 'dart:convert';

import 'package:jaspr/server.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:share_pages/share_pages.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

import 'area_sitemap_test.dart' show kilimani, tenant;
import 'listing_page_test.dart' show flat;

const wanjiku = ShareAgent(
  id: 'agent-wanjiku',
  name: 'Wanjiku Mwangi',
  earbNo: 'EARB/1234',
  phone: '+254700000101',
  whatsapp: '+254700000101',
  languages: ['en', 'sw'],
  responseMins: 15,
);

const byWanjiku = ShareListing(
  id: 'listing-002',
  slug: 'bedsitter-kasarani',
  title: 'Bedsitter, Kasarani',
  purpose: Purpose.rent,
  type: 'bedsitter',
  beds: 0,
  baths: 1,
  priceKES: 9000,
  depositMonths: 1,
  area: 'kasarani',
  lat: -1.22,
  lng: 36.9,
  agentId: 'agent-wanjiku',
);

Future<String> page(String path, {int status = 200}) async {
  final source = InMemoryListingSource(const [byWanjiku, flat], areas: const [kilimani], agents: const [wanjiku], agentReviews: {
    'agent-wanjiku': [(rating: 4, comment: 'On time & honest <3', name: 'Akinyi', at: DateTime(2026, 10, 27))],
  });
  final r = await shareHandler(tenant, source)(shelf.Request('GET', Uri.parse('https://x$path')));
  expect(r.statusCode, status, reason: path);
  return r.readAsString();
}

Map<Object?, Object?> jsonLd(String html) =>
    jsonDecode(RegExp(r'<script type="application/ld\+json">(.*?)</script>', dotAll: true).firstMatch(html)!.group(1)!) as Map;

void main() {
  setUpAll(Jaspr.initializeApp);

  test('agent page shows EARB number, languages, contacts and their homes only', () async {
    final html = await page('/agent/agent-wanjiku');
    expect(html, contains('<h1>Wanjiku Mwangi</h1>'));
    expect(html, contains('EARB reg. EARB/1234 · Speaks English and Kiswahili · Usually replies within 15 min'));
    expect(html, contains('href="https://wa.me/254700000101?text='));
    expect(html, contains('href="tel:+254700000101"'));
    expect(html, contains('href="/listing/bedsitter-kasarani"'));
    expect(html, isNot(contains('href="/listing/2-bedroom-apartment-kilimani"')));
    expect(html, contains('<link href="https://realtimeestates.co.ke/agent/agent-wanjiku" rel="canonical"/>'));
    final ld = jsonLd(html);
    expect(ld['@type'], 'RealEstateAgent');
    expect(ld['knowsLanguage'], ['en', 'sw']);
    expect((ld['parentOrganization'] as Map)['name'], tenant.name);
  });

  test('unknown or malformed agent ids are 404s', () async {
    await page('/agent/agent-nobody', status: 404);
    await page('/agent/..%2Fsecrets', status: 404);
  });

  test('listing pages link to their active agent', () async {
    final html = await page('/listing/bedsitter-kasarani');
    expect(html, contains('Listed by <a href="/agent/agent-wanjiku">Wanjiku Mwangi</a>'));
    expect(await page('/listing/2-bedroom-apartment-kilimani'), isNot(contains('Listed by')));
  });

  test('home page lists new homes and areas, linking into the app', () async {
    final html = await page('/');
    expect(html, contains('<h1>${tenant.name}</h1>'));
    expect(html, contains('href="/listing/bedsitter-kasarani"'));
    expect(html, contains('href="/area/kilimani"'));
    expect(html, contains('href="https://${tenant.appDomain}/rent"'));
    expect(jsonLd(html)['url'], 'https://${tenant.shareDomain}/');
  });

  test('sitemap lists active agents', () async {
    expect(await page('/sitemap.xml'), contains('<loc>https://realtimeestates.co.ke/agent/agent-wanjiku</loc>'));
  });

  test("approved reviews show on the agent's page, escaped", () async {
    final html = await page('/agent/agent-wanjiku');
    expect(html, contains('What clients say'));
    expect(html, contains('★★★★☆'));
    expect(html, contains('On time &amp; honest &lt;3'));
    expect(html, contains('Akinyi'));
  });
}
