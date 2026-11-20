import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';

import 'home_screen.dart' show homePhotoAsset;
import 'providers.dart';
import 'support/site_services.dart';

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
  const AdSlot({super.key, this.tall = false, this.banner = false, this.index = 0});

  /// Which slot this is on the page: running adverts take turns by it.
  final int index;

  /// A box for the side of a wide page; otherwise a band across the list.
  final bool tall;

  /// The home page's photo band as the advert: words and Enquire now over
  /// the photo, the width of the page.
  final bool banner;

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
    // A running advert from the admin's Ads page, if any, takes the slot;
    // otherwise the realtor's own banner shows.
    final running = [
      for (final a in ref.watch(runningAdsProvider).value ?? const <AdRow>[])
        if (a.showsOn(banner ? 'home' : 'results')) a
    ];
    final ad = running.isEmpty ? null : running[index % running.length];
    final title = ad?.title ?? promo?.title ?? 'Advertise here';
    final body = ad == null ? (promo?.text ?? 'Reach people looking for a home with ${tenant.name}.') : ad.text;
    final photoUrl = ad?.image == null ? null : ref.read(siteServicesProvider).imageUrl(ad!.image!);
    final hasPhoto = photoUrl != null || (ad == null && (promo?.hasImage ?? false));
    final open = ref.read(urlOpenerProvider);
    // Enquiries go to the advert's link, else the realtor on WhatsApp, or by email until there is a number.
    final enquire = (ad?.linkUrl == null ? null : Uri.tryParse(ad!.linkUrl!)) ??
        tenant.whatsappLink('Hello ${tenant.name}, I saw your advert: $title') ??
        Uri(scheme: 'mailto', path: tenant.email, queryParameters: {'subject': title});
    final plain = ColoredBox(color: b.primarySoft);
    Widget photo() => photoUrl != null
        ? Image.network(photoUrl, fit: BoxFit.cover, excludeFromSemantics: true, errorBuilder: (_, __, ___) => plain)
        : Image.asset(homePhotoAsset('banner', 1), fit: BoxFit.cover, excludeFromSemantics: true, errorBuilder: (_, __, ___) => plain);
    // As Property Finder lays its adverts out among the homes: a card the
    // width of a home's, the photo marked AD and fading into the card, the
    // advertiser's logo, a bold title, a line or two, and Enquire now.
    if (banner) {
      // The home page's photo band, carrying the advert: the photo under a
      // veil, the bold line and its words on the left, and Enquire now in
      // the bottom right corner.
      final wide = MediaQuery.sizeOf(context).width >= 760;
      final onPhoto = scheme.surface;
      // The words on the left, lined up with the hero's above.
      final words = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(title,
            key: const Key('ad-title'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: text.titleLarge?.copyWith(color: onPhoto, fontWeight: FontWeight.w700)),
        SizedBox(height: b.spacing.xs),
        Text(body, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.bodyLarge?.copyWith(color: onPhoto)),
      ]);
      final button = FilledButton.icon(
        key: const Key('ad-enquire'),
        style: FilledButton.styleFrom(
          backgroundColor: scheme.surface,
          foregroundColor: scheme.primary,
          minimumSize: const Size(0, 44),
          padding: EdgeInsets.symmetric(horizontal: b.spacing.xl),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(b.radiusSm)),
          textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        onPressed: () => open(enquire),
        iconAlignment: IconAlignment.end,
        icon: const Icon(Icons.arrow_forward, size: 18),
        label: const Text('Enquire now'),
      );
      return Semantics(
        container: true,
        label: 'Advert',
        child: Material(
          key: const Key('ad-card'),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(b.radiusMd)),
          child: InkWell(
            onTap: () => open(enquire),
            child: Stack(children: [
              Positioned.fill(
                child: hasPhoto ? photo() : ColoredBox(color: scheme.primary),
              ),
              // Darker behind the words, lighter towards the right, so the photo shows.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [scheme.scrim.withValues(alpha: 0.7), scheme.scrim.withValues(alpha: 0.25)]),
                  ),
                ),
              ),
              // The words on the left, high in the band as the hero's are;
              // Enquire now in the bottom right corner.
              ConstrainedBox(
                constraints: BoxConstraints(minHeight: wide ? 168 : 0, minWidth: double.infinity),
                child: Padding(
                  // The hero's padding, so the two bands' words start at the same place.
                  padding: EdgeInsets.fromLTRB(b.spacing.xl, b.spacing.xl, b.spacing.lg, b.spacing.lg),
                  child: wide
                      ? Stack(children: [
                          Padding(
                            padding: EdgeInsets.only(top: b.spacing.sm, right: 220, bottom: 56),
                            child: Align(alignment: Alignment.topLeft, child: words),
                          ),
                          Positioned(right: 0, bottom: 0, child: button),
                        ])
                      : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          words,
                          SizedBox(height: b.spacing.lg),
                          Align(alignment: Alignment.bottomRight, child: button),
                        ]),
                ),
              ),
            ]),
          ),
        ),
      );
    }
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
                if (hasPhoto) photo() else plain,
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
                // The advertiser's name on their advert; the realtor's logo on its own.
                if (ad != null && ad.advertiser.isNotEmpty)
                  Text(ad.advertiser, key: const Key('ad-advertiser'), style: text.labelLarge?.copyWith(color: b.textMuted, fontWeight: FontWeight.w700))
                else
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Image.asset(b.logoAsset, height: 40, filterQuality: FilterQuality.medium, semanticLabel: tenant.name),
                  ),
                SizedBox(height: b.spacing.sm),
                Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700, height: 1.35)),
                SizedBox(height: b.spacing.sm),
                Text(
                  body,
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
