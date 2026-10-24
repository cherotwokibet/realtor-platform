import 'dart:convert';

import 'package:jaspr/server.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'agent_page.dart';
import 'area_page.dart';
import 'home_page.dart';
import 'listing.dart';
import 'listing_page.dart';

final _slug = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');
final _docId = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

/// Routes: `/`, `/listing/<slug>`, `/area/<slug>`, `/agent/<id>`,
/// `/sitemap.xml`, `/robots.txt`.
shelf.Handler shareHandler(TenantConfig tenant, ListingSource source) {
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
      final agent = listing.agentId == null || !_docId.hasMatch(listing.agentId!) ? null : await source.agent(listing.agentId!);
      return _html(await renderComponent(ListingPage(tenant: tenant, listing: listing, agent: agent), request: req));
    })
    ..get('/agent/<id>', (shelf.Request req, String id) async {
      if (!_docId.hasMatch(id)) return _notFound(tenant);
      final (agent, listings) = await (source.agent(id), source.liveByAgent(id)).wait;
      if (agent == null) return _notFound(tenant);
      return _html(await renderComponent(AgentPage(tenant: tenant, agent: agent, listings: listings), request: req));
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
    ..get('/robots.txt', (shelf.Request _) => shelf.Response.ok(
          'User-agent: *\nAllow: /\nSitemap: https://${tenant.shareDomain}/sitemap.xml\n',
          headers: {'content-type': 'text/plain; charset=utf-8', 'cache-control': 'public, max-age=86400'},
        ));
  return router.call;
}

shelf.Response _html(ResponseLike r) => shelf.Response(r.statusCode, body: r.body, headers: {
      ...r.headers,
      'content-type': 'text/html; charset=utf-8',
      // Hosting CDN keeps it for 10 min; browsers re-check after 5.
      'cache-control': 'public, max-age=300, s-maxage=600',
    });

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
