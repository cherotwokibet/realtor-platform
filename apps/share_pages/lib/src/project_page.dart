import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:realtor_core/realtor_core.dart';

import 'listing.dart';
import 'page_shell.dart';

const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/// `2028-06` -> `June 2028`; anything else as it is.
String completionLabel(String yyyyMm) {
  final m = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(yyyyMm);
  final month = m == null ? null : int.tryParse(m.group(2)!);
  if (month == null || month < 1 || month > 12) return yyyyMm;
  return '${_months[month - 1]} ${m!.group(1)}';
}

/// `2 bed apartment`, `Studio`, `Plot`.
String unitLabel(ProjectUnit unit) {
  final type = unit.type;
  if (type == 'studio' || unit.beds == 0) return type[0].toUpperCase() + type.substring(1);
  return '${unit.beds} bed $type';
}

/// `/projects`: every published off-plan project, cheapest first.
class ProjectsPage extends StatelessComponent {
  const ProjectsPage({required this.tenant, required this.projects, super.key});
  final TenantConfig tenant;
  final List<ShareProject> projects;

  @override
  Component build(BuildContext context) {
    final canonical = 'https://${tenant.shareDomain}/projects';
    final description = projects.isEmpty
        ? 'Off-plan homes from ${tenant.name}: new projects will be listed here.'
        : '${projects.length} off-plan ${projects.length == 1 ? 'project' : 'projects'} from ${tenant.name}, '
            'from ${formatKes(projects.first.fromKES)}.';
    return sharePage(
      tenant: tenant,
      title: 'Off-plan projects · ${tenant.name}',
      description: description,
      canonical: canonical,
      ogImage: 'https://${tenant.appDomain}/og.png',
      jsonLd: {
        '@context': 'https://schema.org',
        '@type': 'ItemList',
        'url': canonical,
        'itemListElement': [
          for (final (i, pr) in projects.indexed)
            {'@type': 'ListItem', 'position': i + 1, 'url': 'https://${tenant.shareDomain}/project/${pr.slug}', 'name': pr.name},
        ],
      },
      body: [
        const h1([Component.text('Off-plan projects')]),
        p([Component.text(description)]),
        if (projects.isNotEmpty)
          ul(classes: 'cards', [
            for (final pr in projects)
              li([
                a(href: '/project/${pr.slug}', [
                  Component.text(pr.name),
                  p(classes: 'price', [Component.text('From ${formatKes(pr.fromKES)} · ready ${completionLabel(pr.completion)}')]),
                ]),
              ]),
          ]),
      ],
    );
  }
}

/// `/project/<slug>`: units with from-prices, the payment plan and handover.
class ProjectPage extends StatelessComponent {
  const ProjectPage({required this.tenant, required this.project, this.areaName, super.key});
  final TenantConfig tenant;
  final ShareProject project;

  /// The area's display name, when its guide exists.
  final String? areaName;

  @override
  Component build(BuildContext context) {
    final pr = project;
    final canonical = 'https://${tenant.shareDomain}/project/${pr.slug}';
    final where = areaName ?? pr.area;
    final description = '${pr.name} by ${pr.developer} in $where: from ${formatKes(pr.fromKES)}, '
        'ready ${completionLabel(pr.completion)}. Off-plan, from ${tenant.name}.';
    final wa = tenant.whatsappLink('Hi ${tenant.name}, I am interested in ${pr.name} ($canonical).');
    return sharePage(
      tenant: tenant,
      title: '${pr.name} · Off-plan from ${formatKes(pr.fromKES)} · ${tenant.name}',
      description: description,
      canonical: canonical,
      ogImage: 'https://${tenant.appDomain}/og.png',
      jsonLd: {
        '@context': 'https://schema.org',
        '@type': 'ApartmentComplex',
        'name': pr.name,
        'url': canonical,
        'description': pr.summary.isEmpty ? description : pr.summary,
        'address': {'@type': 'PostalAddress', 'addressLocality': where, 'addressCountry': 'KE'},
        'offers': {
          '@type': 'AggregateOffer',
          'priceCurrency': 'KES',
          'lowPrice': pr.fromKES,
          'offerCount': pr.units.fold<int>(0, (n, unit) => n + unit.available),
        },
      },
      body: [
        h1([Component.text(pr.name)]),
        p(classes: 'facts', [
          Component.text('By ${pr.developer} · '),
          if (areaName != null) a(href: '/area/${pr.area}', [Component.text(where)]) else Component.text(where),
          Component.text(' · Ready ${completionLabel(pr.completion)}'),
        ]),
        p(classes: 'price', [Component.text('From ${formatKes(pr.fromKES)}')]),
        if (pr.summary.isNotEmpty) p([Component.text(pr.summary)]),
        const h2([Component.text('Units')]),
        table([
          const thead([
            tr([
              th([Component.text('Unit')]),
              th([Component.text('Size')]),
              th([Component.text('From')]),
              th([Component.text('Available')]),
            ]),
          ]),
          tbody([
            for (final unit in pr.units)
              tr([
                td([Component.text(unitLabel(unit))]),
                td([Component.text(unit.sizeSqm == null ? '—' : '${unit.sizeSqm} m²')]),
                td([Component.text(formatKes(unit.fromKES))]),
                td([Component.text(unit.available == 0 ? 'Sold out' : '${unit.available}')]),
              ]),
          ]),
        ]),
        const h2([Component.text('Payment plan')]),
        ol([
          for (final s in pr.paymentPlan) li([Component.text('${s.stage}: ${s.percent}%')]),
        ]),
        const p(classes: 'facts', [
          Component.text('Prices and dates are the developer\'s and can change; ask for the sale agreement before paying.'),
        ]),
        div(classes: 'cta', [
          if (wa != null) a(href: wa.toString(), classes: 'wa', const [Component.text('Ask on WhatsApp')]),
          const a(href: '/projects', classes: 'open', [Component.text('All projects')]),
        ]),
      ],
    );
  }
}
