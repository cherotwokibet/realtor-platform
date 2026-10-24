import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_tokens/realtor_tokens.dart';

import 'listing.dart';
import 'seo.dart';

/// Layout only; every colour, font and radius comes from the tenant's CSS
/// variables (packages/tokens), so a re-brand needs no change here.
const pageCss = '''
*{box-sizing:border-box}
body{margin:0;background:var(--color-background);color:var(--color-text);font-family:var(--font-body);font-size:var(--text-body);line-height:1.5}
main{max-width:720px;margin:0 auto;padding:16px}
header{padding:12px 16px;background:var(--color-surface);border-bottom:1px solid var(--color-border)}
header img{height:36px;width:auto;display:block}
h1{font-family:var(--font-display);font-size:var(--text-headline);color:var(--color-ink);margin:16px 0 4px;line-height:1.2}
.price{font-size:var(--text-title);color:var(--color-primary);font-weight:600;margin:0 0 8px}
.facts{color:var(--color-text-muted);margin:0 0 16px}
.badge{display:inline-block;background:var(--color-accent);color:var(--color-on-accent);border-radius:var(--radius-sm);padding:2px 8px;font-size:var(--text-caption)}
.photos{display:grid;gap:8px;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));margin:16px 0}
.photos img{width:100%;height:auto;border-radius:var(--radius-md);background:var(--color-surface-alt)}
.cta{display:flex;flex-wrap:wrap;gap:8px;margin:24px 0}
.cta a{flex:1 1 200px;text-align:center;padding:14px 16px;border-radius:var(--radius-sm);text-decoration:none;font-weight:600}
.open{background:var(--color-primary);color:var(--color-on-primary)}
.wa{border:1px solid var(--color-border-strong);color:var(--color-ink)}
ul{padding-left:20px}
''';

class ListingPage extends StatelessComponent {
  const ListingPage({required this.tenant, required this.listing, super.key});
  final TenantConfig tenant;
  final ShareListing listing;

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

    return Document(
      title: seo.title,
      lang: tenant.defaultLocale.split('-').first,
      viewport: 'width=device-width, initial-scale=1',
      meta: {'description': seo.description, 'theme-color': hex(tenant.brand.colors.primary)},
      head: [
        link(rel: 'canonical', href: seo.canonical),
        for (final (k, v) in [
          ('og:type', 'website'),
          ('og:site_name', tenant.name),
          ('og:title', seo.title),
          ('og:description', seo.description),
          ('og:url', seo.canonical),
          ('og:image', seo.ogImage),
        ])
          meta(attributes: {'property': k}, content: v),
        const meta(name: 'twitter:card', content: 'summary_large_image'),
        RawText(seo.jsonLdScript),
        RawText('<style>${Tokens(tenant).toCss()}$pageCss</style>'),
      ],
      body: Component.fragment([
        header([
          a(href: 'https://${tenant.shareDomain}/', [
            img(src: 'https://${tenant.appDomain}/assets/assets/tenant/logo-horizontal.png', alt: tenant.name, height: 36),
          ]),
        ]),
        main_([
          if (l.verified) const span(classes: 'badge', [Component.text('Verified')]),
          h1([Component.text(l.title)]),
          p(classes: 'price', [
            Component.text(formatKes(l.priceKES)),
            if (l.purpose != Purpose.sale) Component.text(l.purpose == Purpose.rent ? ' /month' : ' /night'),
          ]),
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
        ]),
      ]),
    );
  }
}
