import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:realtor_core/realtor_core.dart';

import 'page_shell.dart';

/// The site pages managers can publish (functions/src/api/pages.ts).
const sitePageSlugs = ['about', 'privacy', 'terms', 'faq', 'contact'];

typedef SitePage = ({String slug, String title, String body, DateTime? updatedAt});

/// Published pages for the footer: set by the server, refreshed every few
/// minutes, so a newly published page shows up without a redeploy.
List<({String slug, String title})> footerPages = const [];

/// Plain text to page parts: "# " a heading, "- " a list item, a blank
/// line a new paragraph. Text only, so nothing typed can become markup.
List<Component> pageBody(String text) {
  final out = <Component>[];
  final para = <String>[], items = <String>[];
  void flush() {
    if (para.isNotEmpty) out.add(p([Component.text(para.join(' '))]));
    if (items.isNotEmpty) out.add(ul([for (final i in items) li([Component.text(i)])]));
    para.clear();
    items.clear();
  }

  for (final raw in text.split('\n')) {
    final line = raw.trimRight();
    if (line.trim().isEmpty) {
      flush();
    } else if (line.startsWith('# ')) {
      flush();
      out.add(h2([Component.text(line.substring(2).trim())]));
    } else if (line.startsWith('- ')) {
      if (para.isNotEmpty) flush();
      items.add(line.substring(2).trim());
    } else {
      if (items.isNotEmpty) flush();
      para.add(line.trim());
    }
  }
  flush();
  return out;
}

/// `/about`, `/privacy`, ...: a published site page.
class SitePageView extends StatelessComponent {
  const SitePageView({required this.tenant, required this.page, super.key});
  final TenantConfig tenant;
  final SitePage page;

  @override
  Component build(BuildContext context) => sharePage(
        tenant: tenant,
        title: '${page.title} · ${tenant.name}',
        description: '${page.title}, ${tenant.name}.',
        canonical: 'https://${tenant.shareDomain}/${page.slug}',
        ogImage: 'https://${tenant.appDomain}/og.png',
        jsonLd: const {},
        body: [h1([Component.text(page.title)]), ...pageBody(page.body)],
      );
}
