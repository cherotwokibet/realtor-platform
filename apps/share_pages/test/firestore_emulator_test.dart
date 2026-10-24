@Tags(['emulator'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:jaspr/server.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:share_pages/share_pages.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

/// Run inside `firebase emulators:exec` after `npm --prefix functions run seed`:
///   dart test -t emulator
void main() {
  final host = Platform.environment['FIRESTORE_EMULATOR_HOST'];
  final source = FirestoreListingSource(projectId: 'demo-realtor', emulatorHost: host);

  setUpAll(() {
    expect(host, isNotNull, reason: 'run inside firebase emulators:exec');
    Jaspr.initializeApp();
  });

  test('finds a seeded live listing by slug', () async {
    final l = await source.bySlug('2-bedroom-apartment-kilimani');
    expect(l, isNotNull);
    expect(l!.priceKES, 65000);
    expect(l.purpose, Purpose.rent);
    expect(l.verified, isTrue);
  });

  test('unknown slugs are null', () async {
    expect(await source.bySlug('no-such-home'), isNull);
  });

  test('a share page renders end to end from the emulator', () async {
    final tenant = TenantConfig.fromJson(
      jsonDecode(File('../../tenants/demo-homes.json').readAsStringSync()) as Map<String, Object?>,
    );
    final r = await shareHandler(tenant, source)(shelf.Request('GET', Uri.parse('https://x/listing/bedsitter-near-kasarani-stadium')));
    expect(r.statusCode, 200);
    expect(await r.readAsString(), contains('Bedsitter near Kasarani stadium'));
  });

  test('area pages and the sitemap come from the emulator too', () async {
    final tenant = TenantConfig.fromJson(
      jsonDecode(File('../../tenants/demo-homes.json').readAsStringSync()) as Map<String, Object?>,
    );
    final handler = shareHandler(tenant, source);
    final area = await handler(shelf.Request('GET', Uri.parse('https://x/area/kasarani')));
    expect(area.statusCode, 200);
    final html = await area.readAsString();
    expect(html, contains('Homes in Kasarani'));
    expect(html, contains('Bedsitter near Kasarani stadium'));
    final xml = await (await handler(shelf.Request('GET', Uri.parse('https://x/sitemap.xml')))).readAsString();
    expect('<url>'.allMatches(xml).length, 1 + 8 + 3 + 12, reason: 'home + 8 areas + 3 agents + 12 live listings');
  });

  test('agent and home pages come from the emulator', () async {
    final tenant = TenantConfig.fromJson(
      jsonDecode(File('../../tenants/demo-homes.json').readAsStringSync()) as Map<String, Object?>,
    );
    final handler = shareHandler(tenant, source);
    final agent = await handler(shelf.Request('GET', Uri.parse('https://x/agent/agent-wanjiku')));
    expect(agent.statusCode, 200);
    final html = await agent.readAsString();
    expect(html, contains('<h1>Wanjiku Mwangi</h1>'));
    expect('href="/listing/'.allMatches(html).length, 4, reason: 'every third of the 12 live listings');
    final listing = await (await handler(shelf.Request('GET', Uri.parse('https://x/listing/2-bedroom-apartment-kilimani')))).readAsString();
    expect(listing, contains('Listed by <a href="/agent/agent-wanjiku">'));
    final home = await (await handler(shelf.Request('GET', Uri.parse('https://x/')))).readAsString();
    expect('href="/listing/'.allMatches(home).length, 12);
    expect('href="/area/'.allMatches(home).length, 8);
  });
}
