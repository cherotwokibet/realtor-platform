import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:realtor_core/realtor_core.dart';

import 'listing.dart';
import 'page_shell.dart';
import 'seo.dart';

/// `/area/<slug>`: the realtor's guide to a neighbourhood and its live homes.
class AreaPage extends StatelessComponent {
  const AreaPage({required this.tenant, required this.area, required this.listings, super.key});
  final TenantConfig tenant;
  final ShareArea area;
  final List<ShareListing> listings;

  @override
  Component build(BuildContext context) {
    final canonical = 'https://${tenant.shareDomain}/area/${area.slug}';
    final median = area.medianRentKES == null ? '' : ' Typical rent ${formatKes(area.medianRentKES!)} a month.';
    final description =
        '${listings.length} ${listings.length == 1 ? 'home' : 'homes'} in ${area.name}, ${area.county}, from ${tenant.name}.$median';
    final first = listings.where((l) => l.photos.isNotEmpty).firstOrNull;
    final seoOfFirst = first == null ? null : ListingSeo(tenant, first);

    return sharePage(
      tenant: tenant,
      title: 'Homes in ${area.name} · ${tenant.name}',
      description: description,
      canonical: canonical,
      ogImage: seoOfFirst?.ogImage ?? 'https://${tenant.appDomain}/og.png',
      jsonLd: {
        '@context': 'https://schema.org',
        '@type': 'Place',
        'name': area.name,
        'url': canonical,
        'address': {'@type': 'PostalAddress', 'addressLocality': area.name, 'addressRegion': area.county, 'addressCountry': 'KE'},
        'geo': {'@type': 'GeoCoordinates', 'latitude': area.lat, 'longitude': area.lng},
        'subjectOf': {
          '@type': 'ItemList',
          'itemListElement': [
            for (final (i, l) in listings.indexed)
              {'@type': 'ListItem', 'position': i + 1, 'url': ListingSeo(tenant, l).canonical, 'name': l.title},
          ],
        },
      },
      body: [
        h1([Component.text('Homes in ${area.name}')]),
        p(classes: 'facts', [Component.text('${area.county} · ${listings.length} live ${listings.length == 1 ? 'listing' : 'listings'}')]),
        if (area.medianRentKES != null) p([Component.text('Typical rent: ${formatKes(area.medianRentKES!)} a month')]),
        if (area.guide.isNotEmpty) p([Component.text(area.guide)]),
        if (listings.isNotEmpty) ...[
          const h2([Component.text('Available now')]),
          listingCards(listings),
        ],
        div(classes: 'cta', [
          a(href: 'https://${tenant.appDomain}/rent/${area.slug}', classes: 'open', [Component.text('Search ${area.name} in the app')]),
        ]),
      ],
    );
  }
}
