import 'dart:convert';

import 'package:jaspr/server.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'listing.dart';
import 'listing_page.dart';

final _slug = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');

/// Routes: `/listing/<slug>` (P3-s03 slice 1). Area, agent and home pages follow.
shelf.Handler shareHandler(TenantConfig tenant, ListingSource source) {
  final router = Router()
    ..get('/healthz', (shelf.Request _) => shelf.Response.ok('ok'))
    ..get('/listing/<slug>', (shelf.Request req, String slug) async {
      if (!_slug.hasMatch(slug) || slug.length > 80) return _notFound(tenant);
      final listing = await source.bySlug(slug);
      if (listing == null) return _notFound(tenant);
      final r = await renderComponent(ListingPage(tenant: tenant, listing: listing), request: req);
      return shelf.Response(r.statusCode, body: r.body, headers: {
        ...r.headers,
        'content-type': 'text/html; charset=utf-8',
        // Hosting CDN keeps it for 10 min; browsers re-check after 5.
        'cache-control': 'public, max-age=300, s-maxage=600',
      });
    });
  return router.call;
}

shelf.Response _notFound(TenantConfig tenant) => shelf.Response.notFound(
      utf8.encode('<!doctype html><html lang="en"><meta charset="utf-8"><title>Not found · '
          '${const HtmlEscape().convert(tenant.name)}</title><p>This listing is no longer available. '
          '<a href="https://${tenant.appDomain}/">See all homes</a></p></html>'),
      headers: {'content-type': 'text/html; charset=utf-8', 'cache-control': 'public, max-age=60'},
    );
