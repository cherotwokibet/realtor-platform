import 'dart:convert';
import 'dart:io';

import 'package:jaspr/server.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'agent_page.dart';
import 'app_links.dart';
import 'area_page.dart';
import 'fonts.dart';
import 'home_page.dart';
import 'lead_api.dart';
import 'listing.dart';
import 'listing_page.dart';
import 'review_page.dart';
import 'site_page.dart';
import 'seo.dart';

final _slug = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');
final _docId = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

/// Routes: `/`, `/listing/<slug>` (+ POST `/listing/<slug>/enquire` and
/// `/listing/<slug>/viewing`),
/// `/go/whatsapp/<slug>`, `/area/<slug>`, `/agent/<id>`, `/sitemap.xml`,
/// `/robots.txt` and the App Links / Universal Links files in `/.well-known/`. Without [leads] there is no enquiry form and WhatsApp
/// taps are not counted. With [fontsDir] the tenant's bundled fonts are served
/// at `/fonts/<Family>-<Weight>.ttf`, which the pages' `@font-face` rules use.
/// With [brandDir] the header logo is served at [logoPath].
/// Unless [indexable] (dev and stage), robots.txt turns every crawler away and
/// each response says noindex, so test copies never show up in search.
shelf.Handler shareHandler(TenantConfig tenant, ListingSource source,
    {LeadApi? leads, DateTime Function()? now, String? fontsDir, String? brandDir, bool indexable = true}) {
  final clock = now ?? DateTime.now;
  Future<shelf.Response> listingPage(shelf.Request req, ShareListing listing,
      {EnquiryFormState? form, EnquiryFormState? viewingForm, int status = 200}) async {
    // "Show free times": ?day=YYYY-MM-DD asks openSlots for that day.
    final day = req.url.queryParameters['day'];
    final times = leads != null && day != null && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day)
        ? await leads.openTimes(listingId: listing.id, day: day)
        : null;
    final (agent, area) = await (
      listing.agentId == null || !_docId.hasMatch(listing.agentId!) ? Future<ShareAgent?>.value() : source.agent(listing.agentId!),
      listing.purpose == Purpose.rent && _slug.hasMatch(listing.area) ? source.area(listing.area) : Future<ShareArea?>.value(),
    ).wait;
    final q = req.url.queryParameters;
    final enquiry = leads == null ? null : form ?? EnquiryFormState(sent: q['sent'] == '1');
    final viewing = leads == null ? null : viewingForm ?? EnquiryFormState(sent: q['booked'] == '1');
    final r = await renderComponent(
      ListingPage(
        tenant: tenant,
        listing: listing,
        agent: agent,
        enquiry: enquiry,
        viewing: viewing,
        viewingDays: viewingDays(clock()),
        areaMedianRentKES: area?.medianRentKES,
        freeTimes: times == null ? null : (day: day!, times: times),
      ),
      request: req,
    );
    bool own(EnquiryFormState? f) => f != null && (f.sent || f.values.isNotEmpty);
    return _html(r, status: status, private: own(enquiry) || own(viewing) || times != null);
  }

  final router = Router()
    ..get('/healthz', (shelf.Request _) => shelf.Response.ok('ok'))
    ..get('/', (shelf.Request req) async {
      final (listings, areas) = await (source.latestLive(), source.areas()).wait;
      return _html(await renderComponent(HomePage(tenant: tenant, listings: listings, areas: areas), request: req));
    })
    ..get('/listing/<slug>', (shelf.Request req, String slug) async {
      if (!_slug.hasMatch(slug) || slug.length > 80) return _notFound(tenant);
      final listing = await source.bySlug(slug);
      if (listing == null) return _notFound(tenant);
      return listingPage(req, listing);
    })
    ..post('/listing/<slug>/enquire', (shelf.Request req, String slug) async {
      if (leads == null || !_slug.hasMatch(slug) || slug.length > 80) return _notFound(tenant);
      final listing = await source.bySlug(slug);
      if (listing == null) return _notFound(tenant);
      final body = await _formBody(req);
      if (body == null) return shelf.Response(413, body: 'form too large');
      final thanks = shelf.Response.seeOther('/listing/$slug?sent=1#enquire', headers: {'cache-control': 'no-store'});
      if ((body['website'] ?? '').isNotEmpty) return thanks; // honeypot: a bot
      final (:enquiry, :errors) = Enquiry.parse(body);
      final values = {for (final k in const ['phone', 'name', 'message', 'consent']) k: body[k] ?? ''};
      if (enquiry == null) return listingPage(req, listing, form: EnquiryFormState(values: values, errors: errors), status: 400);
      try {
        await leads.createLead(listingId: listing.id, phone: enquiry.phone, name: enquiry.name, message: enquiry.message);
      } on LeadApiException catch (e) {
        // Personal data stays out of logs: only the status is printed.
        stderr.writeln('createLead failed: ${e.status}');
        if (e.status == 'NOT_FOUND') return _notFound(tenant);
        if (e.status == 'RESOURCE_EXHAUSTED') {
          return listingPage(req, listing, form: EnquiryFormState(values: values, notice: _tooMany(tenant)), status: 429);
        }
        return listingPage(req, listing, form: EnquiryFormState(values: values, failed: true), status: 503);
      } on Exception catch (e) {
        stderr.writeln('createLead failed: ${e.runtimeType}');
        return listingPage(req, listing, form: EnquiryFormState(values: values, failed: true), status: 503);
      }
      return thanks;
    })
    ..post('/listing/<slug>/viewing', (shelf.Request req, String slug) async {
      if (leads == null || !_slug.hasMatch(slug) || slug.length > 80) return _notFound(tenant);
      final listing = await source.bySlug(slug);
      if (listing == null) return _notFound(tenant);
      final body = await _formBody(req);
      if (body == null) return shelf.Response(413, body: 'form too large');
      final booked = shelf.Response.seeOther('/listing/$slug?booked=1#viewing', headers: {'cache-control': 'no-store'});
      if ((body['website'] ?? '').isNotEmpty) return booked; // honeypot: a bot
      final (:request, :errors) = ViewingRequest.parse(body);
      final values = {for (final k in const ['day', 'time', 'name', 'phone', 'consent']) k: body[k] ?? ''};
      EnquiryFormState again({String? notice, bool failed = false}) => EnquiryFormState(values: values, notice: notice, failed: failed);
      if (request == null) {
        return listingPage(req, listing, viewingForm: EnquiryFormState(values: values, errors: errors), status: 400);
      }
      try {
        await leads.bookViewing(listingId: listing.id, slot: request.slot, name: request.name, phone: request.phone, message: request.message);
      } on LeadApiException catch (e) {
        stderr.writeln('bookViewing failed: ${e.status}');
        return switch (e.status) {
          'NOT_FOUND' => _notFound(tenant),
          'ALREADY_EXISTS' => listingPage(req, listing, viewingForm: again(notice: 'That time is taken. Please pick another.'), status: 409),
          'RESOURCE_EXHAUSTED' => listingPage(req, listing, viewingForm: again(notice: _tooMany(tenant)), status: 429),
          // The Function explains which slot rule failed ("slot: book at least 2 hours ahead").
          'INVALID_ARGUMENT' when e.message.startsWith('slot: ') =>
            listingPage(req, listing, viewingForm: again(notice: 'Please pick another time: ${e.message.substring(6)}.'), status: 400),
          _ => listingPage(req, listing, viewingForm: again(failed: true), status: 503),
        };
      } on Exception catch (e) {
        stderr.writeln('bookViewing failed: ${e.runtimeType}');
        return listingPage(req, listing, viewingForm: again(failed: true), status: 503);
      }
      return booked;
    })
    ..get('/review/<token>', (shelf.Request req, String token) async {
      if (leads == null || !reviewToken.hasMatch(token)) return _notFound(tenant);
      final thanks = req.url.queryParameters['sent'] == '1';
      return _private(await renderComponent(ReviewPage(tenant: tenant, token: token, thanks: thanks), request: req));
    })
    ..post('/review/<token>', (shelf.Request req, String token) async {
      if (leads == null || !reviewToken.hasMatch(token)) return _notFound(tenant);
      final body = await _formBody(req);
      if (body == null) return shelf.Response(413, body: 'form too large');
      final values = {for (final k in const ['rating', 'comment', 'name']) k: body[k] ?? ''};
      Future<shelf.Response> again(ReviewFormState f, int status) async =>
          _private(await renderComponent(ReviewPage(tenant: tenant, token: token, state: f), request: req), status: status);
      final answers = parseReview(body);
      if (answers == null) return again(ReviewFormState(values: values, error: 'Pick from 1 to 5 stars.'), 400);
      try {
        await leads.submitReview(token: token, rating: answers.rating, comment: answers.comment, name: answers.name);
      } on LeadApiException catch (e) {
        stderr.writeln('submitReview failed: ${e.status}');
        return switch (e.status) {
          'NOT_FOUND' => again(const ReviewFormState(closed: 'This review link is not valid.'), 404),
          'ALREADY_EXISTS' => again(const ReviewFormState(closed: 'A review was already left with this link. Thank you.'), 409),
          'FAILED_PRECONDITION' => again(const ReviewFormState(closed: 'This review link has expired.'), 410),
          _ => again(ReviewFormState(values: values, error: 'Sorry, we could not send that just now. Please try again.'), 503),
        };
      } on Exception catch (e) {
        stderr.writeln('submitReview failed: ${e.runtimeType}');
        return again(ReviewFormState(values: values, error: 'Sorry, we could not send that just now. Please try again.'), 503);
      }
      return shelf.Response.seeOther('/review/$token?sent=1', headers: {'cache-control': 'no-store'});
    })
    ..get('/go/whatsapp/<slug>', (shelf.Request req, String slug) async {
      if (!_slug.hasMatch(slug) || slug.length > 80) return _notFound(tenant);
      final listing = await source.bySlug(slug);
      if (listing == null) return _notFound(tenant);
      final canonical = ListingSeo(tenant, listing).canonical;
      final wa = tenant.whatsappLink('Hi, I saw "${listing.title}" ($canonical). Is it still available?');
      if (wa == null) return shelf.Response.found('/listing/$slug');
      // Counting the tap must never stop the visitor reaching WhatsApp.
      try {
        await leads?.logTap(listingId: listing.id, channel: 'whatsapp');
      } on Exception catch (e) {
        stderr.writeln('logContactTap failed: ${e.runtimeType}');
      }
      return shelf.Response.found(wa.toString(), headers: {'cache-control': 'no-store', 'x-robots-tag': 'noindex'});
    })
    ..get('/agent/<id>', (shelf.Request req, String id) async {
      if (!_docId.hasMatch(id)) return _notFound(tenant);
      final (agent, listings, reviews) = await (source.agent(id), source.liveByAgent(id), source.reviews(id)).wait;
      if (agent == null) return _notFound(tenant);
      return _html(await renderComponent(AgentPage(tenant: tenant, agent: agent, listings: listings, reviews: reviews), request: req));
    })
    ..get('/area/<slug>', (shelf.Request req, String slug) async {
      if (!_slug.hasMatch(slug) || slug.length > 80) return _notFound(tenant);
      final (area, listings) = await (source.area(slug), source.liveInArea(slug)).wait;
      if (area == null) return _notFound(tenant);
      return _html(await renderComponent(AreaPage(tenant: tenant, area: area, listings: listings), request: req));
    })
    ..get('/sitemap.xml', (shelf.Request _) async {
      final entries = await source.sitemapEntries();
      return shelf.Response.ok(sitemapXml(tenant, entries), headers: {
        'content-type': 'application/xml; charset=utf-8',
        'cache-control': 'public, max-age=3600',
      });
    })
    // Served as JSON with no redirect, as Android and iOS require.
    ..get('/.well-known/assetlinks.json', (shelf.Request _) => _json(assetLinks(tenant)))
    ..get('/.well-known/apple-app-site-association', (shelf.Request _) => _json(appleAppSiteAssociation(tenant)))
    ..get('/robots.txt', (shelf.Request _) => shelf.Response.ok(
          indexable
              ? 'User-agent: *\nAllow: /\nDisallow: /go/\nDisallow: /review/\nSitemap: https://${tenant.shareDomain}/sitemap.xml\n'
              : 'User-agent: *\nDisallow: /\n',
          headers: {'content-type': 'text/plain; charset=utf-8', 'cache-control': 'public, max-age=86400'},
        ));
  if (fontsDir != null) router.get('/fonts/<file>', (shelf.Request _, String file) => serveFont(tenant, fontsDir, file));
  if (brandDir != null) router.get(logoPath, (shelf.Request _) => serveLogo(tenant, brandDir));
  // Last: one-segment paths left over may be site pages (/about, /privacy...).
  router.get('/<page>', (shelf.Request req, String page) async {
    if (!sitePageSlugs.contains(page)) return _notFound(tenant);
    final found = await source.page(page);
    if (found == null) return _notFound(tenant);
    return _html(await renderComponent(
      SitePageView(tenant: tenant, page: (slug: page, title: found.title, body: found.body, updatedAt: found.updatedAt)),
      request: req,
    ));
  });
  // Footer links to published site pages, read at most every 5 minutes.
  DateTime? footerAt;
  Future<void> refreshFooter() async {
    final now = clock();
    if (footerAt != null && now.difference(footerAt!) < const Duration(minutes: 5)) return;
    footerAt = now;
    try {
      final pages = await source.publishedPages();
      footerPages = [for (final s in sitePageSlugs) ...pages.where((p) => p.slug == s)];
    } on Exception {
      // Keep the last list; pages still open without the footer.
    }
  }

  return (shelf.Request req) async {
    await refreshFooter();
    final r = _secured(await router.call(req));
    return indexable ? r : r.change(headers: {'x-robots-tag': 'noindex'});
  };
}

/// Shown when the rate limits in Functions refuse a form (P6-s05).
String _tooMany(TenantConfig tenant) =>
    'We already have a few requests from you this hour. ${tenant.name} will be in touch; you can also ask on WhatsApp.';

/// Headers on every response. The pages run no script (JSON-LD is a data
/// block), load styles inline, fonts from `/fonts/` and images from the media
/// CDN, post forms only to themselves and are never framed.
const securityHeaders = {
  'content-security-policy': "default-src 'none'; img-src 'self' https: data:; style-src 'unsafe-inline'; font-src 'self'; "
      "form-action 'self'; base-uri 'none'; frame-ancestors 'none'",
  'x-content-type-options': 'nosniff',
  'x-frame-options': 'DENY',
  'referrer-policy': 'strict-origin-when-cross-origin',
  'permissions-policy': 'camera=(), microphone=(), geolocation=(), payment=()',
};

shelf.Response _secured(shelf.Response r) => r.change(headers: {
      for (final e in securityHeaders.entries)
        if (!r.headers.containsKey(e.key)) e.key: e.value,
    });

/// Review pages: never cached, never indexed (the link is personal).
shelf.Response _private(ResponseLike r, {int? status}) =>
    _html(r, status: status, private: true).change(headers: {'x-robots-tag': 'noindex'});

/// [private] pages show a visitor's own form input or thank-you note, so
/// the CDN must not keep them.
shelf.Response _html(ResponseLike r, {int? status, bool private = false}) => shelf.Response(status ?? r.statusCode, body: r.body, headers: {
      ...r.headers,
      'content-type': 'text/html; charset=utf-8',
      // Hosting CDN keeps it for 10 min; browsers re-check after 5.
      'cache-control': private ? 'private, no-store' : 'public, max-age=300, s-maxage=600',
    });

shelf.Response _json(Object data) => shelf.Response.ok(jsonEncode(data),
    headers: {'content-type': 'application/json', 'cache-control': 'public, max-age=3600'});

/// A urlencoded form body, or null when it is over 8 KB.
Future<Map<String, String>?> _formBody(shelf.Request req) async {
  final bytes = <int>[];
  await for (final chunk in req.read()) {
    bytes.addAll(chunk);
    if (bytes.length > 8 * 1024) return null;
  }
  try {
    return Uri.splitQueryString(utf8.decode(bytes));
  } on FormatException {
    return const {};
  }
}

/// sitemaps.org XML for the home page, every area, agent and live listing.
String sitemapXml(TenantConfig tenant, List<SitemapEntry> entries) {
  final esc = const HtmlEscape(HtmlEscapeMode.attribute);
  final base = 'https://${tenant.shareDomain}';
  final urls = [
    '  <url><loc>$base/</loc></url>',
    for (final e in entries)
      '  <url><loc>${esc.convert('$base${e.path}')}</loc>'
          '${e.lastModified == null ? '' : '<lastmod>${e.lastModified!.toUtc().toIso8601String().split('.').first}Z</lastmod>'}</url>',
  ];
  return '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls.join('\n')}\n</urlset>\n';
}

shelf.Response _notFound(TenantConfig tenant) => shelf.Response.notFound(
      utf8.encode('<!doctype html><html lang="en"><meta charset="utf-8"><title>Not found · '
          '${const HtmlEscape().convert(tenant.name)}</title><p>This page is no longer available. '
          '<a href="https://${tenant.appDomain}/">See all homes</a></p></html>'),
      headers: {'content-type': 'text/html; charset=utf-8', 'cache-control': 'public, max-age=60'},
    );
