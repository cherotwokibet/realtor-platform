import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:realtor_core/realtor_core.dart';

import 'listing.dart';
import 'page_shell.dart';
import 'seo.dart';

class ListingPage extends StatelessComponent {
  const ListingPage({required this.tenant, required this.listing, this.agent, super.key});
  final TenantConfig tenant;
  final ShareListing listing;

  /// The listing's agent when still active; links to their page.
  final ShareAgent? agent;

  @override
  Component build(BuildContext context) {
    final seo = ListingSeo(tenant, listing);
    final l = listing;
    final facts = [
      if (l.beds > 0) '${l.beds} bed',
      if (l.baths > 0) '${l.baths} bath',
      [if (l.estate != null) l.estate!, ListingSeo.placeName(l.area)].join(', '),
    ].join(' · ');
    final wa = tenant.whatsappLink('Hi, I saw "${l.title}" (${seo.canonical}). Is it still available?');

    return sharePage(
      tenant: tenant,
      title: seo.title,
      description: seo.description,
      canonical: seo.canonical,
      ogImage: seo.ogImage,
      jsonLd: seo.jsonLd,
      body: [
        if (l.verified) const span(classes: 'badge', [Component.text('Verified')]),
        h1([Component.text(l.title)]),
        p(classes: 'price', priceText(l)),
        p(classes: 'facts', [Component.text(facts)]),
        if (l.photos.isNotEmpty)
          div(classes: 'photos', [
            for (final (i, ph) in l.photos.take(6).indexed)
              img(
                src: seo.mediaUrl(ph.card),
                alt: '${l.title}, photo ${i + 1}',
                width: 800,
                height: 600,
                attributes: {'loading': i == 0 ? 'eager' : 'lazy', 'decoding': 'async'},
              ),
          ]),
        p([Component.text(seo.description)]),
        if (l.amenities.isNotEmpty) ul([for (final am in l.amenities) li([Component.text(am)])]),
        div(classes: 'cta', [
          a(href: seo.appUrl, classes: 'open', const [Component.text('Open in app')]),
          if (wa != null) a(href: wa.toString(), classes: 'wa', const [Component.text('Ask on WhatsApp')]),
        ]),
        if (agent != null) p([const Component.text('Listed by '), a(href: '/agent/${agent!.id}', [Component.text(agent!.name)])]),
        p([a(href: '/area/${l.area}', [Component.text('More homes in ${ListingSeo.placeName(l.area)}')])]),
      ],
    );
  }
}
