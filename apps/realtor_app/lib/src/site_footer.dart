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
/// dark band across the window with the site pages, the ways to browse, the
/// realtor's contacts and the year, and a button back to the top.
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
    final ink = scheme.onInverseSurface;
    final purposes = [
      for (final p in Purpose.values)
        if (tenant.features.isOn(p.feature)) p
    ];
    Widget link(String label, VoidCallback onTap, {bool caps = false}) => InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: b.spacing.xs),
            child: Text(
              caps ? label.toUpperCase() : label,
              style:
                  (caps ? text.labelLarge : text.bodyMedium)?.copyWith(color: ink, fontWeight: caps ? FontWeight.w700 : null, letterSpacing: caps ? 0.6 : null),
            ),
          ),
        );
    Widget separated(List<Widget> items) => Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: b.spacing.xs,
          children: [
            for (final (i, w) in items.indexed) ...[
              if (i > 0)
                Padding(
                    padding: EdgeInsets.symmetric(horizontal: b.spacing.sm),
                    child: Text('|', style: text.labelLarge?.copyWith(color: ink.withValues(alpha: 0.5)))),
              w,
            ],
          ],
        );
    final top = Scrollable.maybeOf(context);
    return Material(
      key: const Key('site-footer'),
      color: scheme.inverseSurface,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: b.spacing.xl),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              separated([for (final (slug, name) in sitePages) link(name, () => open(Uri.https(tenant.shareDomain, '/$slug')), caps: true)]),
              SizedBox(height: b.spacing.md),
              separated([for (final p in purposes) link('Homes ${p.heading}', () => context.go('/${p.pathSegment}'))]),
              SizedBox(height: b.spacing.sm),
              separated([
                if (tenant.phone != 'TBC') link('Call ${tenant.phone}', () => open(Uri(scheme: 'tel', path: tenant.phone))),
                link(tenant.email, () => open(Uri(scheme: 'mailto', path: tenant.email))),
              ]),
              SizedBox(height: b.spacing.lg),
              Row(children: [
                Expanded(child: Text('© ${ref.read(clockProvider)().year} ${tenant.name}', style: text.bodySmall?.copyWith(color: ink.withValues(alpha: 0.8)))),
                if (top != null)
                  TextButton.icon(
                    key: const Key('to-top'),
                    style: TextButton.styleFrom(foregroundColor: ink),
                    onPressed: () => top.position.animateTo(0, duration: const Duration(milliseconds: 500), curve: Curves.easeInOutCubic),
                    iconAlignment: IconAlignment.end,
                    icon: CircleAvatar(radius: 14, backgroundColor: ink, child: Icon(Icons.keyboard_arrow_up, size: 20, color: scheme.inverseSurface)),
                    label: const Text('TOP'),
                  ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
