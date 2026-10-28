import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:realtor_core/realtor_core.dart';

import 'fonts.dart';

import 'listing.dart';
import 'page_shell.dart';

/// `/`: the realtor's newest homes and every area, for search engines and
/// people arriving without a link. Search itself lives in the app.
class HomePage extends StatelessComponent {
  const HomePage({required this.tenant, required this.listings, required this.areas, super.key});
  final TenantConfig tenant;
  final List<ShareListing> listings;
  final List<ShareArea> areas;

  @override
  Component build(BuildContext context) {
    final canonical = 'https://${tenant.shareDomain}/';
    final where = areas.take(3).map((ar) => ar.name).join(', ');
    final description = 'Homes to rent and buy from ${tenant.name}${where.isEmpty ? '' : ' in $where and more'}.';
    final wa = tenant.whatsappLink('Hi ${tenant.name}, I am looking for a home.');

    return sharePage(
      tenant: tenant,
      title: '${tenant.name} · Homes to rent and buy',
      description: description,
      canonical: canonical,
      ogImage: 'https://${tenant.appDomain}/og.png',
      jsonLd: {
        '@context': 'https://schema.org',
        '@type': 'RealEstateAgent',
        'name': tenant.name,
        'url': canonical,
        'logo': 'https://${tenant.shareDomain}$logoPath',
        'address': {'@type': 'PostalAddress', 'addressCountry': 'KE'},
      },
      body: [
        h1([Component.text(tenant.name)]),
        p([Component.text(description)]),
        div(classes: 'cta', [
          a(href: 'https://${tenant.appDomain}/rent', classes: 'open', const [Component.text('Search homes')]),
          if (wa != null) a(href: wa.toString(), classes: 'wa', const [Component.text('Ask on WhatsApp')]),
        ]),
        if (listings.isNotEmpty) ...[
          const h2([Component.text('New this week')]),
          listingCards(listings),
        ],
        if (areas.isNotEmpty) ...[
          const h2([Component.text('Areas')]),
          ul(classes: 'areas', [
            for (final ar in areas)
              li([
                a(href: '/area/${ar.slug}', [Component.text(ar.name)]),
              ]),
          ]),
        ],
      ],
    );
  }
}
