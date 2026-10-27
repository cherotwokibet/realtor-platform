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
  final viewings = <Map<String, String?>>[];
  LeadApiException? fail;

  @override
  Future<void> bookViewing({required String listingId, required String slot, required String name, required String phone, String? message}) async {
    if (fail != null) throw fail!;
    viewings.add({'listingId': listingId, 'slot': slot, 'name': name, 'phone': phone, 'message': message});
  }

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

// Monday 26 Oct 2026, 09:00 in Nairobi.
final now = DateTime.utc(2026, 10, 26, 6);

Future<shelf.Response> send(String method, String path, {String? form, bool withLeads = true}) async {
  final handler = shareHandler(tenant, InMemoryListingSource(const [flat]), leads: withLeads ? fake : null, now: () => now);
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

  group('book a viewing', () {
    const viewing = '/listing/2-bedroom-apartment-kilimani/viewing';
    const ok = 'day=2026-10-27&time=10%3A30&name=Amina&phone=0712+345+678&consent=yes&website=';

    test('the form offers the next 12 viewing days (no Sundays) and half-hour slots 08:00-17:30', () async {
      final html = await (await send('GET', '/listing/2-bedroom-apartment-kilimani')).readAsString();
      expect(html, contains('action="/listing/2-bedroom-apartment-kilimani/viewing#viewing"'));
      expect(html, contains('<option value="2026-10-26">Mon 26 Oct</option>'));
      expect(html, isNot(contains('value="2026-11-01"')), reason: 'Sunday');
      expect(html, contains('<option value="2026-11-07">Sat 7 Nov</option>'), reason: '12th viewing day');
      expect(html, contains('<option value="08:00">08:00</option>'));
      expect(html, contains('<option value="17:30">17:30</option>'));
      expect(html, isNot(contains('value="18:00"')));
    });

    test('a valid request books the slot in Nairobi time and redirects to a confirmation', () async {
      final r = await send('POST', viewing, form: ok);
      expect(r.statusCode, 303);
      expect(r.headers['location'], '/listing/2-bedroom-apartment-kilimani?booked=1#viewing');
      expect(fake.viewings.single, {
        'listingId': 'listing-001',
        'slot': '2026-10-27T10:30:00+03:00',
        'name': 'Amina',
        'phone': '+254712345678',
        'message': null,
      });
      final page = await send('GET', '/listing/2-bedroom-apartment-kilimani?booked=1');
      expect(page.headers['cache-control'], 'private, no-store');
      expect(await page.readAsString(), contains('Viewing requested.'));
    });

    test('missing name, bad phone or no consent: nothing is booked and the form keeps the choice', () async {
      final r = await send('POST', viewing, form: 'day=2026-10-27&time=10%3A30&phone=020+123');
      expect(r.statusCode, 400);
      final html = await r.readAsString();
      expect(html, contains('Enter your name'));
      expect(html, contains('Enter a Kenyan mobile number'));
      expect(html, contains('Tick the box'));
      expect(html, contains('<option value="2026-10-27" selected>'));
      expect((await send('POST', viewing, form: ok.replaceFirst('time=10%3A30', 'time=10%3A15'))).statusCode, 400);
      expect(fake.viewings, isEmpty);
    });

    test('a taken slot or a slot rule from the Function is explained; outages fall back to WhatsApp', () async {
      fake.fail = LeadApiException('ALREADY_EXISTS', 'that time is taken, pick another');
      final taken = await send('POST', viewing, form: ok);
      expect(taken.statusCode, 409);
      expect(await taken.readAsString(), contains('That time is taken. Please pick another.'));
      fake.fail = LeadApiException('INVALID_ARGUMENT', 'slot: book at least 2 hours ahead');
      expect(await (await send('POST', viewing, form: ok)).readAsString(), contains('Please pick another time: book at least 2 hours ahead.'));
      fake.fail = LeadApiException('UNAVAILABLE', 'down');
      final down = await send('POST', viewing, form: ok);
      expect(down.statusCode, 503);
      expect(await down.readAsString(), contains('Please try again or ask on WhatsApp'));
    });

    test('bots get a confirmation and book nothing', () async {
      expect((await send('POST', viewing, form: '${ok}spam')).statusCode, 303);
      expect(fake.viewings, isEmpty);
    });
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
      await api.bookViewing(listingId: 'listing-001', slot: '2026-10-27T10:30:00+03:00', name: 'Amina', phone: '+254712345678');
      expect(seen.url.path, '/bookViewing');
      expect(jsonDecode(seen.body), {
        'data': {
          'listingId': 'listing-001',
          'slot': '2026-10-27T10:30:00+03:00',
          'client': {'name': 'Amina', 'phone': '+254712345678'},
          'consent': true,
        },
      });
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
