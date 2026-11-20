import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';

import 'nav.dart';
import 'providers.dart';
import 'search/purpose.dart';

/// The site pages every footer links to, on the share site.
const sitePages = [('about', 'About us'), ('contact', 'Contact us'), ('faq', 'FAQs'), ('privacy', 'Privacy'), ('terms', 'Terms')];

/// The foot of Home, results and listing pages, as on the big portals: a
/// quiet band across the window with the logo and the realtor's line, then
/// columns to browse, about the company and to get in touch; under a rule,
/// the legal pages, the year and a way back to the top. It shows only what
/// the tenant file holds (no number until there is one).
class SiteFooter extends ConsumerWidget {
  const SiteFooter({super.key, this.width = maxContentWidth});

  /// How wide its contents run, to line up with the page above.
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(tenantProvider);
    final b = context.brand;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final open = ref.read(urlOpenerProvider);
    final purposes = [
      for (final p in Purpose.values)
        if (tenant.features.isOn(p.feature)) p
    ];
    final narrow = MediaQuery.sizeOf(context).width < 700;
    Uri page(String slug) => Uri.https(tenant.shareDomain, '/$slug');

    Widget link(String label, VoidCallback onTap, {IconData? icon}) => Padding(
          padding: EdgeInsets.symmetric(vertical: b.spacing.xs),
          child: InkWell(
            onTap: onTap,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(icon, size: 18, color: b.textMuted), SizedBox(width: b.spacing.sm)],
              Flexible(child: Text(label, style: text.bodyMedium)),
            ]),
          ),
        );
    Widget column(String title, List<Widget> links) => SizedBox(
          width: narrow ? double.infinity : 220,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            SizedBox(height: b.spacing.sm),
            ...links,
          ]),
        );
    final whatsapp = tenant.hasContactNumbers ? tenant.whatsappLink('Hello ${tenant.name}') : null;

    final brand = SizedBox(
      width: narrow ? double.infinity : 260,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Image.asset(b.logoAsset, height: 56, filterQuality: FilterQuality.medium, semanticLabel: tenant.name, alignment: Alignment.centerLeft),
        if (tenant.tagline != null) ...[SizedBox(height: b.spacing.md), Text(tenant.tagline!, style: text.bodyMedium?.copyWith(color: b.textMuted))],
        if (tenant.earbNo != null && tenant.earbNo != 'TBC') ...[
          SizedBox(height: b.spacing.sm),
          Text('EARB reg. ${tenant.earbNo}', style: text.bodySmall?.copyWith(color: b.textMuted))
        ],
      ]),
    );
    final columns = [
      column('Browse', [for (final p in purposes) link('Homes ${p.heading}', () => context.go('/${p.pathSegment}'))]),
      column('Company', [
        for (final (slug, name) in sitePages.where((p) => p.$1 != 'privacy' && p.$1 != 'terms')) link(name, () => open(page(slug))),
        link('Help & feedback', () => context.push(Uri(path: '/help', queryParameters: {'from': GoRouterState.of(context).uri.path}).toString())),
      ]),
      column('Get in touch', [
        if (tenant.hasContactNumbers) link(tenant.phone, () => open(Uri(scheme: 'tel', path: tenant.phone)), icon: Icons.call_outlined),
        if (whatsapp != null) link('WhatsApp', () => open(whatsapp), icon: Icons.chat_outlined),
        link(tenant.email, () => open(Uri(scheme: 'mailto', path: tenant.email)), icon: Icons.mail_outline),
      ]),
    ];
    final top = Scrollable.maybeOf(context);

    return Material(
      key: const Key('site-footer'),
      color: b.surfaceAlt,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width),
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, b.spacing.xxl, 24, b.spacing.lg),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Wrap(spacing: b.spacing.xxl, runSpacing: b.spacing.xl, children: [brand, ...columns]),
              SizedBox(height: b.spacing.xl),
              Divider(color: scheme.outlineVariant, height: 1),
              SizedBox(height: b.spacing.md),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: b.spacing.sm,
                children: [
                  Wrap(spacing: b.spacing.lg, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text('© ${ref.read(clockProvider)().year} ${tenant.name}', style: text.bodySmall?.copyWith(color: b.textMuted)),
                    for (final (slug, name) in sitePages.where((p) => p.$1 == 'privacy' || p.$1 == 'terms'))
                      InkWell(onTap: () => open(page(slug)), child: Text(name, style: text.bodySmall)),
                  ]),
                  if (top != null)
                    TextButton.icon(
                      key: const Key('to-top'),
                      onPressed: () => top.position.animateTo(0, duration: const Duration(milliseconds: 500), curve: Curves.easeInOutCubic),
                      iconAlignment: IconAlignment.end,
                      icon: const Icon(Icons.keyboard_arrow_up),
                      label: const Text('Back to top'),
                    ),
                ],
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
