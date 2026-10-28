import 'dart:convert';

import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_tokens/realtor_tokens.dart';

import 'fonts.dart';
import 'listing.dart';

/// Layout only; every colour, font and radius comes from the tenant's CSS
/// variables (packages/tokens), so a re-brand needs no change here.
const pageCss = '''
*{box-sizing:border-box}
body{margin:0;background:var(--color-background);color:var(--color-text);font-family:var(--font-body);font-size:var(--text-body);line-height:1.5}
main{max-width:720px;margin:0 auto;padding:16px}
header{padding:12px 16px;background:var(--color-surface);border-bottom:1px solid var(--color-border)}
header img{height:36px;width:auto;display:block}
h1{font-family:var(--font-display);font-size:var(--text-headline);color:var(--color-ink);margin:16px 0 4px;line-height:1.2}
h2{font-family:var(--font-display);font-size:var(--text-title);color:var(--color-ink);margin:24px 0 8px}
.price{font-size:var(--text-title);color:var(--color-primary);font-weight:600;margin:0 0 8px}
.facts{color:var(--color-text-muted);margin:0 0 16px}
.badge{display:inline-block;background:var(--color-accent);color:var(--color-on-accent);border-radius:var(--radius-sm);padding:2px 8px;font-size:var(--text-caption)}
.photos{display:grid;gap:8px;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));margin:16px 0}
.photos img{width:100%;height:auto;border-radius:var(--radius-md);background:var(--color-surface-alt)}
.cta{display:flex;flex-wrap:wrap;gap:8px;margin:24px 0}
.cta a{flex:1 1 200px;text-align:center;padding:14px 16px;border-radius:var(--radius-sm);text-decoration:none;font-weight:600}
.open{background:var(--color-primary);color:var(--color-on-primary)}
.wa{border:1px solid var(--color-border-strong);color:var(--color-ink)}
.cards{list-style:none;padding:0;display:grid;gap:8px}
.cards a{display:block;padding:12px 16px;background:var(--color-surface);border:1px solid var(--color-border);border-radius:var(--radius-md);text-decoration:none;color:var(--color-ink)}
.cards .price{font-size:var(--text-body-large);margin:4px 0 0}
.enquire label{display:block;margin:12px 0 4px;font-weight:600}
.enquire input[type=text],.enquire input[type=tel],.enquire textarea,.enquire select{width:100%;padding:12px;border:1px solid var(--color-border-strong);border-radius:var(--radius-sm);font:inherit;background:var(--color-surface);color:var(--color-text)}
.enquire .consent{display:flex;gap:8px;align-items:flex-start;font-weight:400}
.enquire button{margin-top:16px;width:100%;padding:14px;border:0;border-radius:var(--radius-sm);background:var(--color-primary);color:var(--color-on-primary);font:inherit;font-weight:600}
.enquire .hp{position:absolute;left:-9999px}
.error{color:var(--color-error);margin:4px 0 0}
.notice{padding:12px 16px;border-radius:var(--radius-sm);background:var(--color-primary-soft);color:var(--color-ink)}
.agent{display:flex;gap:12px;align-items:center}
.agent img{width:72px;height:72px;border-radius:50%;object-fit:cover;background:var(--color-surface-alt)}
.areas{list-style:none;padding:0;display:flex;flex-wrap:wrap;gap:8px}
.areas a{display:inline-block;padding:6px 12px;border:1px solid var(--color-border);border-radius:var(--radius-sm);text-decoration:none;color:var(--color-ink)}
ul{padding-left:20px}
''';

/// JSON-LD safe to embed in a `<script>` tag: every `<` is written as the
/// JSON escape `\u003c`, so page text can never close the script.
String jsonLdScript(Map<String, Object?> data) =>
    '<script type="application/ld+json">${jsonEncode(data).replaceAll('<', '\\u003c')}</script>';

/// Shared head (canonical, Open Graph, JSON-LD, tenant CSS) and header.
Component sharePage({
  required TenantConfig tenant,
  required String title,
  required String description,
  required String canonical,
  required String ogImage,
  required Map<String, Object?> jsonLd,
  required List<Component> body,
}) {
  return Document(
    title: title,
    lang: tenant.defaultLocale.split('-').first,
    viewport: 'width=device-width, initial-scale=1',
    meta: {'description': description, 'theme-color': hex(tenant.brand.colors.primary)},
    head: [
      link(rel: 'canonical', href: canonical),
      for (final (k, v) in [
        ('og:type', 'website'),
        ('og:site_name', tenant.name),
        ('og:title', title),
        ('og:description', description),
        ('og:url', canonical),
        ('og:image', ogImage),
      ])
        meta(attributes: {'property': k}, content: v),
      const meta(name: 'twitter:card', content: 'summary_large_image'),
      RawText(jsonLdScript(jsonLd)),
      RawText('<style>${fontFaceCss(tenant)}\n${Tokens(tenant).toCss()}$pageCss</style>'),
    ],
    body: Component.fragment([
      header([
        a(href: '/', [
          img(src: logoPath, alt: tenant.name, height: 36),
        ]),
      ]),
      main_(body),
    ]),
  );
}

/// Price with its period, as cards and listing pages show it.
List<Component> priceText(ShareListing l) => [
      Component.text(formatKes(l.priceKES)),
      if (l.purpose != Purpose.sale) Component.text(l.purpose == Purpose.rent ? ' /month' : ' /night'),
    ];

/// A list of listing cards linking to their share pages.
Component listingCards(List<ShareListing> listings) => ul(classes: 'cards', [
      for (final l in listings)
        li([
          a(href: '/listing/${l.slug}', [
            Component.text(l.title),
            p(classes: 'price', priceText(l)),
          ]),
        ]),
    ]);
