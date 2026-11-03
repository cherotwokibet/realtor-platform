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

  /// `listingId/event`, as logged.
  final recommendations = <String>[];

  @override
  Future<void> logRecommendation({required String listingId, required String event}) async {
    if (fail != null) throw fail!;
    recommendations.add('$listingId/$event');
  }
  final viewings = <Map<String, String?>>[];
  LeadApiException? fail;

  /// The fee each booking gets, as the Functions would set it (0: free).
  int feeKES = 0;

  @override
  Future<({String viewingId, int feeKES})> bookViewing({
    required String listingId,
    required String slot,
    required String name,
    required String phone,
    String? message,
  }) async {
    if (fail != null) throw fail!;
    viewings.add({'listingId': listingId, 'slot': slot, 'name': name, 'phone': phone, 'message': message});
    return (viewingId: 'agent-x_${viewings.length}', feeKES: feeKES);
  }

  final payments = <String>[];
  LeadApiException? payFail;

  @override
  Future<void> payViewingFee({required String viewingId}) async {
    if (payFail != null) throw payFail!;
    payments.add(viewingId);
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

  final reviews = <Map<String, Object?>>[];

  /// Day -> free times; a day missing means openSlots couldn't answer.
  final free = <String, List<String>>{};

  @override
  Future<List<String>?> openTimes({required String listingId, required String day}) async => free[day];

  @override
  Future<void> submitReview({required String token, required int rating, String? comment, String? name}) async {
    if (fail != null) throw fail!;
    reviews.add({'token': token, 'rating': rating, 'comment': comment, 'name': name});
  }
}

late FakeLeads fake;

// Monday 26 Oct 2026, 09:00 in Nairobi.
final now = DateTime.utc(2026, 10, 26, 6);

Future<shelf.Response> send(String method, String path, {String? form, bool withLeads = true, TenantConfig? tenantConfig, ShareListing listing = flat}) async {
  final handler = shareHandler(tenantConfig ?? tenant, InMemoryListingSource([listing]), leads: withLeads ? fake : null, now: () => now);
  return handler(shelf.Request(method, Uri.parse('https://x$path'),
      body: form, headers: form == null ? null : {'content-type': 'application/x-www-form-urlencoded'}));
}

const enquire = '/listing/2-bedroom-apartment-kilimani/enquire';

void main() {
  setUpAll(Jaspr.initializeApp);
  setUp(() => fake = FakeLeads());

  test('similar homes count on the web: a 1x1 image when shown, a redirect when opened; counts only', () async {
    const near = ShareListing(
        id: 'listing-near', slug: 'near-flat', title: 'Near flat', purpose: Purpose.rent, type: 'apartment',
        beds: 2, baths: 1, priceKES: 62000, area: 'kilimani', lat: 0, lng: 0);
    Future<shelf.Response> get(String path, {bool withLeads = true}) =>
        Future.value(shareHandler(tenant, InMemoryListingSource(const [flat, near]), leads: withLeads ? fake : null, now: () => now)(
            shelf.Request('GET', Uri.parse('https://x$path'))));

    final html = await (await get('/listing/${flat.slug}')).readAsString();
    expect(html, contains('href="/go/similar/${flat.id}/near-flat"'));
    expect(html, contains('src="/go/similar-shown/${flat.id}.gif"'));
    expect(fake.recommendations, isEmpty, reason: 'rendering the page counts nothing; the image does');

    final pixel = await get('/go/similar-shown/${flat.id}.gif');
    expect((pixel.statusCode, pixel.headers['content-type'], pixel.headers['cache-control']), (200, 'image/gif', 'no-store'));
    expect((await pixel.read().expand((b) => b).toList()).take(6), 'GIF89a'.codeUnits);

    final open = await get('/go/similar/${flat.id}/near-flat');
    expect((open.statusCode, open.headers['location'], open.headers['x-robots-tag']), (302, '/listing/near-flat', 'noindex'));
    await Future<void>.delayed(Duration.zero);
    expect(fake.recommendations, ['${flat.id}/shown', '${flat.id}/opened']);

    // A failed count still takes the visitor to the home; bad ids count nothing.
    fake.fail = LeadApiException('UNAVAILABLE', 'down');
    expect((await get('/go/similar/${flat.id}/near-flat')).statusCode, 302);
    fake.fail = null;
    await get('/go/similar-shown/..%2Fx.gif');
    expect(fake.recommendations.length, 2);

    // Without the Functions: plain links, no image.
    final plain = await (await get('/listing/${flat.slug}', withLeads: false)).readAsString();
    expect(plain, contains('href="/listing/near-flat"'));
    expect(plain, isNot(contains('similar-shown')));
  });

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

  test('a rate-limited enquiry says so (429) instead of asking to try again', () async {
    fake.fail = LeadApiException('RESOURCE_EXHAUSTED', 'too many requests, try again in a while');
    final r = await send('POST', enquire, form: 'phone=0712345678&consent=yes');
    expect(r.statusCode, 429);
    final html = await r.readAsString();
    expect(html, contains('We already have a few requests from you this hour.'));
    expect(html, isNot(contains('Please try again')));
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

  group('free times', () {
    const page = '/listing/2-bedroom-apartment-kilimani';
    test('"Show free times" lists only that day\'s free times, keeps the day, and is not cached', () async {
      fake.free['2026-10-27'] = ['08:00', '15:30'];
      final r = await send('GET', '$page?day=2026-10-27');
      final html = await r.readAsString();
      expect(r.headers['cache-control'], contains('no-store'));
      expect(html, contains('Free times on Tue 27 Oct'));
      expect(html, contains('<input type="hidden" name="day" value="2026-10-27"'));
      expect(html, contains('<option value="15:30">15:30</option>'));
      expect(html, isNot(contains('<option value="10:00">10:00</option>')));
    });

    test('a full day says so; when openSlots fails, every time is offered; without a day, pick one first', () async {
      fake.free['2026-10-28'] = [];
      expect(await (await send('GET', '$page?day=2026-10-28')).readAsString(), contains('No free times that day.'));
      final plain = await (await send('GET', page)).readAsString();
      expect(plain, contains('Show free times'));
      expect(plain, isNot(contains('name="time"')), reason: 'times show once a day is picked');
      expect(await (await send('GET', '$page?day=2026-10-29')).readAsString(), contains('<option value="10:00">10:00</option>'));
      expect(await (await send('GET', '$page?day=junk')).readAsString(), isNot(contains('name="time"')), reason: 'not a day: pick again');
    });
  });

  group('reviews', () {
    const link = '/review/abcdefghijklmnopqrstuvwx';

    test('the link opens a private, unindexed form; a rating is required; then thanks', () async {
      final page = await send('GET', link);
      expect(page.statusCode, 200);
      expect(page.headers['x-robots-tag'], 'noindex');
      expect(page.headers['cache-control'], contains('no-store'));
      expect(await page.readAsString(), contains('name="rating" value="5"'));

      final missing = await send('POST', link, form: 'comment=Great');
      expect(missing.statusCode, 400);
      expect(await missing.readAsString(), contains('Pick from 1 to 5 stars.'));
      expect(fake.reviews, isEmpty);

      final ok = await send('POST', link, form: 'rating=4&comment=On+time&name=Akinyi');
      expect(ok.statusCode, 303);
      expect(ok.headers['location'], '$link?sent=1');
      expect(fake.reviews.single, {'token': 'abcdefghijklmnopqrstuvwx', 'rating': 4, 'comment': 'On time', 'name': 'Akinyi'});
      expect(await (await send('GET', '$link?sent=1')).readAsString(), contains('Thank you'));
    });

    test('used, expired and unknown links say so without a form; bad tokens are 404', () async {
      fake.fail = LeadApiException('ALREADY_EXISTS', 'used');
      final used = await send('POST', link, form: 'rating=5');
      expect(used.statusCode, 409);
      expect(await used.readAsString(), allOf(contains('already left'), isNot(contains('name="rating"'))));
      fake.fail = LeadApiException('FAILED_PRECONDITION', 'expired');
      expect((await send('POST', link, form: 'rating=5')).statusCode, 410);
      expect((await send('GET', '/review/short')).statusCode, 404);
      expect((await send('GET', link, withLeads: false)).statusCode, 404);
    });
  });

  test('robots.txt keeps crawlers off /go/ and /review/', () async {
    expect(await (await send('GET', '/robots.txt')).readAsString(), contains('Disallow: /review/'));
  });

  test('robots.txt keeps crawlers off /go/', () async {
    expect(await (await send('GET', '/robots.txt')).readAsString(), contains('Disallow: /go/'));
  });

  group('book a viewing', () {
    const viewing = '/listing/2-bedroom-apartment-kilimani/viewing';
    const ok = 'day=2026-10-27&time=10%3A30&name=Amina&phone=0712+345+678&consent=yes&website=';

    group('with an M-Pesa viewing fee (P6-s01)', () {
      final mpesa = () {
        final j = jsonDecode(File('../../tenants/realtime-estates.json').readAsStringSync()) as Map<String, Object?>;
        (j['features']! as Map)['mpesa'] = true;
        return TenantConfig.fromJson(j);
      }();
      final paid = ShareListing(
        id: flat.id, slug: flat.slug, title: flat.title, purpose: flat.purpose, type: flat.type, beds: flat.beds,
        baths: flat.baths, priceKES: flat.priceKES, area: flat.area, lat: flat.lat, lng: flat.lng, viewingFeeKES: 500,
      );

      test('the page shows the fee; a booking with a fee offers M-Pesa, which goes to the Functions with only the viewing', () async {
        fake.feeKES = 500;
        final page = await (await send('GET', '/listing/2-bedroom-apartment-kilimani', tenantConfig: mpesa, listing: paid)).readAsString();
        expect(page, contains('Viewing fee: KES 500, paid by M-Pesa after you book'));
        final r = await send('POST', viewing, form: ok, tenantConfig: mpesa, listing: paid);
        expect(r.statusCode, 303);
        expect(r.headers['location'], '/listing/2-bedroom-apartment-kilimani?booked=1&pay=agent-x_1#viewing');
        final offer = await send('GET', '/listing/2-bedroom-apartment-kilimani?booked=1&pay=agent-x_1', tenantConfig: mpesa, listing: paid);
        expect(offer.headers['cache-control'], contains('no-store'));
        final html = await offer.readAsString();
        expect(html, contains('action="/listing/2-bedroom-apartment-kilimani/pay#viewing"'));
        expect(html, contains('<input type="hidden" name="viewingId" value="agent-x_1"'));
        expect(html, contains('Pay KES 500 with M-Pesa'));
        final pay = await send('POST', '/listing/2-bedroom-apartment-kilimani/pay', form: 'viewingId=agent-x_1', tenantConfig: mpesa, listing: paid);
        expect(pay.statusCode, 303);
        expect(pay.headers['location'], '/listing/2-bedroom-apartment-kilimani?booked=1&paying=1#viewing');
        expect(fake.payments, ['agent-x_1']);
        final done = await (await send('GET', '/listing/2-bedroom-apartment-kilimani?booked=1&paying=1', tenantConfig: mpesa, listing: paid)).readAsString();
        expect(done, contains('enter your M-Pesa PIN to pay the viewing fee of KES 500'));
      });

      test('a refused prompt says so and keeps the button; bad ids and M-Pesa off are refused', () async {
        fake.payFail = LeadApiException('UNAVAILABLE', 'down');
        final r = await send('POST', '/listing/2-bedroom-apartment-kilimani/pay', form: 'viewingId=agent-x_1', tenantConfig: mpesa, listing: paid);
        expect(r.statusCode, 503);
        final html = await r.readAsString();
        expect(html, contains('M-Pesa did not take the request'));
        expect(html, contains('Pay KES 500 with M-Pesa'));
        expect((await send('POST', '/listing/2-bedroom-apartment-kilimani/pay', form: 'viewingId=..%2Fx', tenantConfig: mpesa, listing: paid)).statusCode, 400);
        expect((await send('POST', '/listing/2-bedroom-apartment-kilimani/pay', form: 'viewingId=agent-x_1', listing: paid)).statusCode, 404,
            reason: 'M-Pesa off');
        fake.payFail = null;
        fake.feeKES = 500;
        final free = await send('POST', viewing, form: ok, listing: paid);
        expect(free.headers['location'], '/listing/2-bedroom-apartment-kilimani?booked=1#viewing', reason: 'no pay step while M-Pesa is off');
        expect(await (await send('GET', '/listing/2-bedroom-apartment-kilimani', listing: paid)).readAsString(), isNot(contains('Viewing fee')));
      });
    });

    test('the form offers the next 12 viewing days (no Sundays) and half-hour slots 08:00-17:30', () async {
      final html = await (await send('GET', '/listing/2-bedroom-apartment-kilimani')).readAsString();
      expect(html, contains('<option value="2026-10-26">Mon 26 Oct</option>'));
      expect(html, isNot(contains('value="2026-11-01"')), reason: 'Sunday');
      expect(html, contains('<option value="2026-11-07">Sat 7 Nov</option>'), reason: '12th viewing day');
      expect(html, isNot(contains('action="/listing/2-bedroom-apartment-kilimani/viewing#viewing"')), reason: 'the day comes first, once');
      final day = await (await send('GET', '/listing/2-bedroom-apartment-kilimani?day=2026-10-27')).readAsString();
      expect(day, contains('action="/listing/2-bedroom-apartment-kilimani/viewing#viewing"'));
      expect('id="f-day"'.allMatches(day).length + 'id="v-day"'.allMatches(day).length, 1, reason: 'one day picker');
      expect(day, contains('<option value="2026-10-27" selected>Tue 27 Oct</option>'));
      expect(day, contains('Change day'));
      expect(day, contains('<option value="08:00">08:00</option>'));
      expect(day, contains('<option value="17:30">17:30</option>'));
      expect(day, isNot(contains('value="18:00"')));
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
      fake.fail = LeadApiException('RESOURCE_EXHAUSTED', 'too many requests, try again in a while');
      final limited = await send('POST', viewing, form: ok);
      expect(limited.statusCode, 429);
      expect(await limited.readAsString(), contains('We already have a few requests from you this hour.'));
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

    test('on Cloud Run it calls the twins with an ID token for each URL', () async {
      final seen = <http.Request>[];
      final audiences = <Uri>[];
      final api = CallableLeadApi(
        functionsBase('rte-realtor-dev'),
        idToken: (aud) async {
          audiences.add(aud);
          return 'tok';
        },
        client: MockClient((req) async {
          seen.add(req);
          return http.Response('{"result":{}}', 200);
        }),
      );
      await api.createLead(listingId: 'listing-001', phone: '+254712345678');
      await api.logTap(listingId: 'listing-001', channel: 'call');
      await api.bookViewing(listingId: 'listing-001', slot: '2026-10-27T10:30:00+03:00', name: 'Amina', phone: '+254712345678');
      await api.payViewingFee(viewingId: 'agent-x_1');
      expect([for (final r in seen) r.url.path], ['/shareCreateLead', '/shareLogContactTap', '/shareBookViewing', '/payments-shareStartViewingPayment']);
      expect(jsonDecode(seen.last.body), {'data': {'viewingId': 'agent-x_1'}}, reason: 'no amount, no phone');
      expect(audiences, [for (final r in seen) r.url]);
      expect(seen.first.headers['authorization'], 'Bearer tok');
      expect(jsonDecode(seen.first.body)['data']['consent'], true);
    });

    test('openSlots is called plainly (public, no twin, no token) and read back', () async {
      late http.Request seen;
      final api = CallableLeadApi(
        functionsBase('demo-project'),
        idToken: (aud) async => 'tok',
        client: MockClient((req) async {
          seen = req;
          return http.Response('{"result":{"times":["08:00","15:30"]}}', 200);
        }),
      );
      expect(await api.openTimes(listingId: 'l1', day: '2026-10-27'), ['08:00', '15:30']);
      expect(seen.url.path, '/openSlots');
      expect(seen.headers.containsKey('authorization'), isFalse);
      final down = CallableLeadApi(functionsBase('demo-project'), client: MockClient((req) async => http.Response('', 503)));
      expect(await down.openTimes(listingId: 'l1', day: '2026-10-27'), isNull);
    });

    test('metadata ID tokens are fetched per audience and reused for 50 minutes', () async {
      var now = DateTime(2026, 10, 28, 12);
      final asked = <Uri>[];
      final tokens = MetadataIdTokens(
        now: () => now,
        client: MockClient((req) async {
          asked.add(req.url);
          expect(req.headers['Metadata-Flavor'], 'Google');
          return http.Response('t${asked.length}\n', 200);
        }),
      );
      final a = Uri.parse('https://europe-west1-p.cloudfunctions.net/shareCreateLead');
      expect(await tokens(a), 't1');
      expect(await tokens(a), 't1');
      expect(asked.single.queryParameters['audience'], '$a');
      expect(asked.single.host, 'metadata.google.internal');
      now = now.add(const Duration(minutes: 51));
      expect(await tokens(a), 't2');
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
