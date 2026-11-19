import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';

import 'home_screen.dart' show homePhotoAsset;
import 'providers.dart';

/// A space for an advert, shown only to tenants with adverts on. Until the
/// realtor sells the space it carries their own promotion (the home page's
/// banner), or an invitation to advertise. It is always marked "AD", so
/// nobody mistakes it for a listing.
///
/// Where the slots go follows what the large portals do and what ad
/// networks allow: in a results list, one after every [every] homes on
/// phones (never two on one screen, never above the first homes); beside the
/// list on wide screens, where it does not push homes down.
class AdSlot extends ConsumerWidget {
  const AdSlot({super.key, this.tall = false});

  /// A box for the side of a wide page; otherwise a band across the list.
  final bool tall;

  /// Homes between two adverts in a list.
  static const every = 5;

  static bool enabledFor(TenantConfig tenant) => tenant.features.isOn(Feature.ads);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(tenantProvider);
    if (!enabledFor(tenant)) return const SizedBox.shrink();
    final b = context.brand;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final promo = tenant.home.banner;
    final title = promo?.title ?? 'Advertise here';
    final open = ref.read(urlOpenerProvider);
    // Enquiries go to the realtor on WhatsApp, or by email until there is a number.
    final enquire = tenant.whatsappLink('Hello ${tenant.name}, I saw your advert: $title') ??
        Uri(scheme: 'mailto', path: tenant.email, queryParameters: {'subject': title});
    final plain = ColoredBox(color: b.primarySoft);
    // As Property Finder lays its adverts out among the homes: a card the
    // width of a home's, the photo marked AD and fading into the card, the
    // advertiser's logo, a bold title, a line or two, and Enquire now.
    return Semantics(
      container: true,
      label: 'Advert',
      child: Material(
        key: const Key('ad-card'),
        color: scheme.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(b.radiusMd), side: BorderSide(color: scheme.outlineVariant)),
        child: InkWell(
          onTap: () => open(enquire),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AspectRatio(
              aspectRatio: tall ? 4 / 3 : 16 / 9,
              child: Stack(fit: StackFit.expand, children: [
                if (promo?.hasImage ?? false)
                  Image.asset(homePhotoAsset('banner', 1), fit: BoxFit.cover, excludeFromSemantics: true, errorBuilder: (_, __, ___) => plain)
                else
                  plain,
                // The photo fades into the card.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 48,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [scheme.surface.withValues(alpha: 0), scheme.surface.withValues(alpha: 0.85)],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: b.spacing.md,
                  top: b.spacing.md,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: scheme.scrim.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(b.radiusSm)),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: b.spacing.sm, vertical: 2),
                      child: Text('AD', style: text.labelMedium?.copyWith(color: scheme.surface, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ]),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(b.spacing.lg, b.spacing.md, b.spacing.lg, b.spacing.lg),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Image.asset(b.logoAsset, height: 40, filterQuality: FilterQuality.medium, semanticLabel: tenant.name),
                ),
                SizedBox(height: b.spacing.sm),
                Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700, height: 1.35)),
                SizedBox(height: b.spacing.sm),
                Text(
                  promo?.text ?? 'Reach people looking for a home with ${tenant.name}.',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(height: 1.45),
                ),
                SizedBox(height: b.spacing.md),
                OutlinedButton(
                  key: const Key('ad-enquire'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(b.radiusSm)),
                    side: BorderSide(color: scheme.primary.withValues(alpha: 0.4)),
                    textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  onPressed: () => open(enquire),
                  child: const Text('Enquire now'),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
