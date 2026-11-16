import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';

import 'home_screen.dart' show homePhotoAsset;
import 'providers.dart';

/// A space for an advert, shown only to tenants with adverts on. Until the
/// realtor sells the space it carries their own promotion (the home page's
/// banner), or an invitation to advertise. It is always marked "Advert", so
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
    final onPhoto = promo?.hasImage ?? false;
    final ink = onPhoto ? scheme.surface : scheme.onSurface;
    final plain = ColoredBox(color: b.primarySoft);
    final open = ref.read(urlOpenerProvider);
    return Semantics(
      container: true,
      label: 'Advert',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(b.radiusMd),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () => open(Uri(scheme: 'mailto', path: tenant.email, queryParameters: {'subject': promo?.title ?? 'Advertising with ${tenant.name}'})),
            child: Stack(children: [
              Positioned.fill(
                child: onPhoto
                    ? Image.asset(homePhotoAsset('banner', 1), fit: BoxFit.cover, excludeFromSemantics: true, errorBuilder: (_, __, ___) => plain)
                    : plain,
              ),
              if (onPhoto) Positioned.fill(child: ColoredBox(color: scheme.scrim.withValues(alpha: 0.5))),
              ConstrainedBox(
                constraints: BoxConstraints(minHeight: tall ? 250 : 120, minWidth: double.infinity),
                child: Padding(
                  padding: EdgeInsets.all(b.spacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(b.radiusSm)),
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: b.spacing.sm, vertical: 2),
                          child: Text('Advert', style: text.labelSmall),
                        ),
                      ),
                      SizedBox(height: b.spacing.sm),
                      Text(promo?.title ?? 'Advertise here', style: text.titleMedium?.copyWith(color: ink)),
                      SizedBox(height: b.spacing.xs),
                      Text(promo?.text ?? 'Reach people looking for a home with ${tenant.name}.', style: text.bodyMedium?.copyWith(color: ink)),
                    ],
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
