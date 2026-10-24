import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jaspr/server.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:share_pages/share_pages.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

import 'listing_page_test.dart' show flat;

/// realtime-estates with a WhatsApp number (the real one is still TBC).
final tenant = () {
  final j = jsonDecode(File('../../tenants/realtime-estates.json').readAsStringSync()) as Map<String, Object?>;
  (j['contact']! as Map)['whatsapp'] = '+254700000999';
  return TenantConfig.fromJson(j);
}();

class FakeLeads implements LeadApi {
  final leads = <Map<String, String?>>[];
  final taps = <String>[];
  LeadApiException? fail;

  @override
  Future<void> createLead({required String listingId, required String phone, String? name, String? message}) async {
    if (fail != null) throw fail!;
    leads.add({'listingId': listingId, 'phone': phone, 'name': name, 'message': message});
  }

  @override
  Future<void> logTap({required String listingId, required String channel}) async {
    if (fail != null) throw fail!;
    taps.add('$listingId/$channel');
  }
}

late FakeLeads fake;

Future<shelf.Response> send(String method, String path, {String? form, bool withLeads = true}) async {
  final handler = shareHandler(tenant, InMemoryListingSource(const [flat]), leads: withLeads ? fake : null);
  return handler(shelf.Request(method, Uri.parse('https://x$path'),
      body: form, headers: form == null ? null : {'content-type': 'application/x-www-form-urlencoded'}));
}

const enquire = '/listing/2-bedroom-apartment-kilimani/enquire';

void main() {
  setUpAll(Jaspr.initializeApp);
  setUp(() => fake = FakeLeads());

  test('listing page has the enquiry form with the consent tick, and WhatsApp goes through /go', () async {
    final html = await (await send('GET', '/listing/2-bedroom-apartment-kilimani')).readAsString();
    expect(html, contains('action="/listing/2-bedroom-apartment-kilimani/enquire#enquire"'));
    expect(html, contains('keep my details for up to 24 months (Data Protection Act 2019)'));
    expect(html, contains('name="consent"'));
    expect(html, matches(RegExp(r'<a [^>]*href="/go/whatsapp/2-bedroom-apartment-kilimani"[^>]*rel="nofollow"|<a [^>]*rel="nofollow"[^>]*href="/go/whatsapp/')));
  });

  test('without the Functions there is no form and WhatsApp links straight to wa.me', () async {
    final html = await (await send('GET', '/listing/2-bedroom-apartment-kilimani', withLeads: false)).readAsString();
    expect(html, isNot(contains('name="consent"')));
    expect(html, contains('href="https://wa.me/254700000999?text='));
    expect((await send('POST', enquire, form: 'phone=0712345678&consent=yes', withLeads: false)).statusCode, 404);
  });

  test('a valid enquiry is sent with a normalised phone, then redirects to a thank-you', () async {
    final r = await send('POST', enquire, form: 'phone=0712+345+678&name=Amina&message=Is+it+still+free%3F&consent=yes&website=');
    expect(r.statusCode, 303);
    expect(r.headers['location'], '/listing/2-bedroom-apartment-kilimani?sent=1#enquire');
    expect(fake.leads.single, {'listingId': 'listing-001', 'phone': '+254712345678', 'name': 'Amina', 'message': 'Is it still free?'});

    final thanks = await send('GET', '/listing/2-bedroom-apartment-kilimani?sent=1');
    expect(thanks.headers['cache-control'], 'private, no-store');
    expect(await thanks.readAsString(), contains('Thank you. Realtime Estates'));
  });

  test('no consent tick or a bad phone: nothing is sent and the form comes back with errors', () async {
    final r = await send('POST', enquire, form: 'phone=0712345678&name=Amina');
    expect(r.statusCode, 400);
    expect(r.headers['cache-control'], 'private, no-store');
    final html = await r.readAsString();
    expect(html, contains('Tick the box so we may contact you.'));
    expect(html, contains('value="0712345678"'), reason: 'keeps what was typed');
    final bad = await (await send('POST', enquire, form: 'phone=020+123456&consent=yes')).readAsString();
    expect(bad, contains('Enter a Kenyan mobile number'));
    expect(fake.leads, isEmpty);
  });

  test('typed text is escaped when the form comes back', () async {
    final html = await (await send('POST', enquire, form: 'phone=x&name=%22%3E%3Cscript%3Ealert(1)%3C%2Fscript%3E')).readAsString();
    expect(html, isNot(contains('<script>alert(1)')));
  });

  test('bots that fill the hidden field get a thank-you and store nothing', () async {
    final r = await send('POST', enquire, form: 'phone=0712345678&consent=yes&website=http%3A%2F%2Fspam');
    expect(r.statusCode, 303);
    expect(fake.leads, isEmpty);
  });

  test('a Functions failure keeps the visitor on the page with a WhatsApp fallback', () async {
    fake.fail = LeadApiException('UNAVAILABLE', 'down');
    final r = await send('POST', enquire, form: 'phone=0712345678&consent=yes');
    expect(r.statusCode, 503);
    expect(await r.readAsString(), contains('Please try again or ask on WhatsApp'));
    fake.fail = LeadApiException('NOT_FOUND', 'listing is not available');
    expect((await send('POST', enquire, form: 'phone=0712345678&consent=yes')).statusCode, 404);
  });

  test('oversized forms are refused', () async {
    expect((await send('POST', enquire, form: 'message=${'a' * 9000}&consent=yes')).statusCode, 413);
  });

  test('/go/whatsapp counts the tap and redirects to WhatsApp with the listing link', () async {
    final r = await send('GET', '/go/whatsapp/2-bedroom-apartment-kilimani');
    expect(r.statusCode, 302);
    final to = Uri.parse(r.headers['location']!);
    expect(to.host, 'wa.me');
    expect(to.path, '/254700000999');
    expect(to.queryParameters['text'], contains('https://realtimeestates.co.ke/listing/2-bedroom-apartment-kilimani'));
    expect(r.headers['x-robots-tag'], 'noindex');
    expect(fake.taps, ['listing-001/whatsapp']);

    fake.fail = LeadApiException('UNAVAILABLE', 'down');
    expect((await send('GET', '/go/whatsapp/2-bedroom-apartment-kilimani')).statusCode, 302, reason: 'counting never blocks WhatsApp');
    expect((await send('GET', '/go/whatsapp/no-such-home')).statusCode, 404);
  });

  test('robots.txt keeps crawlers off /go/', () async {
    expect(await (await send('GET', '/robots.txt')).readAsString(), contains('Disallow: /go/'));
  });

  group('CallableLeadApi', () {
    test('speaks the callable protocol', () async {
      late http.Request seen;
      final api = CallableLeadApi(functionsBase('rte-realtor-prod'), client: MockClient((req) async {
        seen = req;
        return http.Response('{"result":{"leadId":"l1"}}', 200);
      }));
      await api.createLead(listingId: 'listing-001', phone: '+254712345678', name: 'Amina');
      expect(seen.url.toString(), 'https://europe-west1-rte-realtor-prod.cloudfunctions.net/createLead');
      expect(jsonDecode(seen.body), {
        'data': {'listingId': 'listing-001', 'channel': 'form', 'contact': {'phone': '+254712345678', 'name': 'Amina'}, 'consent': true},
      });
      await api.logTap(listingId: 'listing-001', channel: 'whatsapp');
      expect(seen.url.path, '/logContactTap');
      expect(jsonDecode(seen.body), {'data': {'listingId': 'listing-001', 'channel': 'whatsapp'}});
    });

    test('turns callable errors into LeadApiException', () async {
      final api = CallableLeadApi(Uri.parse('http://127.0.0.1:5001/demo-realtor/europe-west1/'), client: MockClient((req) async {
        expect(req.url.path, '/demo-realtor/europe-west1/createLead');
        return http.Response('{"error":{"status":"INVALID_ARGUMENT","message":"consent: Invalid input"}}', 400);
      }));
      await expectLater(
        api.createLead(listingId: 'l', phone: '+254712345678'),
        throwsA(isA<LeadApiException>().having((e) => e.status, 'status', 'INVALID_ARGUMENT')),
      );
    });
  });

  test('functionsRegion matches the region the Functions deploy to', () {
    final rules = File('../../functions/src/listing-rules.ts').readAsStringSync();
    expect(rules, contains("REGION = '$functionsRegion'"));
  });
}
