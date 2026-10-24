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
}
