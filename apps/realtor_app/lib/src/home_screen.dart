import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';

import 'package:go_router/go_router.dart';

import 'nav.dart';
import 'providers.dart';
import 'search/purpose.dart';
import 'search/recent_searches.dart';
import 'search/results_screen.dart';

/// First screen: a photo hero with the search over it, the realtor's
/// promotion, property types, the newest live homes and a footer, with
/// brand, words and features from the tenant's data.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Purpose _purpose = Purpose.rent;

  static const _types = ['bedsitter', 'single-room', 'apartment', 'maisonette', 'townhouse', 'hostel'];

  // The filter row under the hero (plain search; conversational search has its own field).
  final _area = TextEditingController();
  String? _type;
  int? _minBeds, _maxPrice;

  @override
  void dispose() {
    _area.dispose();
    super.dispose();
  }

  void _clear() => setState(() {
        _area.clear();
        _type = null;
        _minBeds = null;
        _maxPrice = null;
      });

  /// Top prices offered for each purpose (KES): a month, in all, or a night.
  static List<int> _prices(Purpose p) => switch (p) {
        Purpose.rent => const [10000, 20000, 30000, 50000, 80000, 120000, 200000],
        Purpose.sale => const [3000000, 5000000, 10000000, 20000000, 50000000],
        Purpose.shortStay => const [3000, 5000, 8000, 12000, 20000],
      };

  void _search({String? q, String? type}) {
    // Plain search: an exact area name ("Ruaka") is that area, so results
    // and alerts match the area rather than the words.
    final typed = q?.trim().toLowerCase();
    final names = ref.read(areaNamesProvider).value ?? const <String, String>{};
    final area = typed == null || typed.isEmpty
        ? null
        : names.entries.where((e) => e.value.toLowerCase() == typed || e.key == typed.replaceAll(' ', '-')).map((e) => e.key).firstOrNull;
    context.push(ListingFilters(
      purpose: _purpose,
      q: area == null && typed != null && typed.isNotEmpty ? q : null,
      types: [if (type != null) type],
      areas: [if (area != null) area],
      minBeds: _minBeds,
      maxPriceKES: _maxPrice,
    ).toUri().toString());
  }

  /// Conversational search (P7-s01): "2br Kilimani under 60k with parking"
  /// becomes filters; the results screen shows each one as a chip to remove.
  void _ask(String text) {
    final features = ref.read(tenantProvider).features;
    final parsed = parseSearch(
      text,
      purpose: _purpose,
      areas: ref.read(areaNamesProvider).value ?? const {},
      allowed: {for (final p in Purpose.values) if (features.isOn(p.feature)) p},
    );
    context.push(parsed.filters.toUri().toString());
  }

  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(tenantProvider);
    // Area names for typed searches, loaded before anyone presses search.
    ref.watch(areaNamesProvider);
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final purposes = [for (final p in Purpose.values) if (tenant.features.isOn(p.feature)) p];
    if (!purposes.contains(_purpose) && purposes.isNotEmpty) _purpose = purposes.first;
    if (_maxPrice != null && !_prices(_purpose).contains(_maxPrice)) _maxPrice = null;
    final whatsapp = tenant.whatsappLink('Hello ${tenant.name}, I am looking for a home.');
    final wide = MediaQuery.sizeOf(context).width >= wideLayoutFrom;
    final hero = tenant.home.hero ?? HomeBand(title: tenant.tagline ?? tenant.name);
    final banner = tenant.home.banner;
    final listProperty = tenant.whatsappLink('Hello ${tenant.name}, I would like to list my property with you.');

    final searchCard = Card(
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(b.spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (purposes.length > 1) ...[
              Wrap(spacing: b.spacing.sm, children: [
                for (final p in purposes)
                  ChoiceChip(
                    label: Text(p.label),
                    selected: p == _purpose,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _purpose = p),
                  ),
              ]),
              SizedBox(height: b.spacing.md),
            ],
            FeatureGate(
              feature: Feature.aiSearch,
              orElse: _Filters(
                area: _area,
                type: _type,
                minBeds: _minBeds,
                maxPrice: _maxPrice,
                types: _types,
                prices: _prices(_purpose),
                period: _purpose.period,
                onType: (v) => setState(() => _type = v),
                onBeds: (v) => setState(() => _minBeds = v),
                onPrice: (v) => setState(() => _maxPrice = v),
                onSearch: () => _search(q: _area.text, type: _type),
                onClear: _clear,
              ),
              child: TextField(
                textInputAction: TextInputAction.search,
                onSubmitted: _ask,
                decoration: const InputDecoration(
                  hintText: 'Try "2br Kilimani under 60k with parking"',
                  prefixIcon: Icon(Icons.auto_awesome),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    final promo = <Widget>[
      if (banner != null) ...[
        _PhotoBand(
          key: const Key('home-banner'),
          band: banner,
          asset: homeBannerAsset,
          minHeight: 120,
          onTap: listProperty == null ? null : () => ref.read(urlOpenerProvider)(listProperty),
        ),
        SizedBox(height: b.spacing.xl),
      ],
    ];
    final types = <Widget>[
      Text('Browse by type', style: text.titleLarge),
      SizedBox(height: b.spacing.md),
      Wrap(
        spacing: b.spacing.sm,
        runSpacing: b.spacing.sm,
        children: [for (final t in _types) ActionChip(label: Text(typeName(t)), onPressed: () => _search(type: t))],
      ),
    ];

    return Scaffold(
      // Wide screens have the logo in the top navigation instead.
      appBar: wide
          ? null
          : AppBar(
              toolbarHeight: 64,
              title: Image.asset(b.logoAsset, height: 48, filterQuality: FilterQuality.medium, semanticLabel: tenant.name),
              centerTitle: false,
            ),
      body: ListView(
        padding: EdgeInsets.all(b.spacing.gutter),
        children: [
          _PhotoBand(key: const Key('home-hero'), band: hero, asset: homeHeroAsset, minHeight: wide ? 220 : 120, large: true),
          // The search sits over the bottom edge of the photo.
          Transform.translate(
            offset: Offset(0, -b.spacing.xl),
            child: Padding(padding: EdgeInsets.symmetric(horizontal: wide ? b.spacing.xl : b.spacing.sm), child: searchCard),
          ),
          // Wide screens show the promotion first, as a second photo band;
          // phones show the property types first, so they stay on the first screen.
          if (wide) ...promo,
          ...types,
          const RecentSearches(),
          if (!wide) ...[SizedBox(height: b.spacing.xl), ...promo],
          FeatureGate(
            feature: Feature.ads,
            child: Padding(
              padding: EdgeInsets.only(top: b.spacing.xl),
              child: Card(
                color: b.primarySoft,
                child: ListTile(
                  leading: const Icon(Icons.campaign_outlined),
                  title: Text('Featured', style: text.labelSmall),
                  subtitle: Text('Promoted listings appear here', style: text.bodyMedium),
                ),
              ),
            ),
          ),
          SizedBox(height: b.spacing.xl),
          _Newest(purpose: _purpose, onSeeAll: () => _search()),
          SizedBox(height: b.spacing.xl),
          _Footer(purposes: purposes),
        ],
      ),
      // In-app chat lives in its own section when on; otherwise WhatsApp handoff.
      bottomNavigationBar: !tenant.features.chat && whatsapp != null
          ? SafeArea(
              child: Padding(
                padding: EdgeInsets.all(b.spacing.md),
                child: FilledButton.icon(
                  onPressed: () => ref.read(urlOpenerProvider)(whatsapp),
                  icon: const Icon(Icons.chat),
                  label: const Text('Enquire on WhatsApp'),
                ),
              ),
            )
          : null,
    );
  }
}

/// The home page photos `tenant prepare` bundles when the tenant names some.
String get homeHeroAsset => '${tenantAssetDir()}/home-hero.webp';
String get homeBannerAsset => '${tenantAssetDir()}/home-banner.webp';

/// A band with the realtor's words over a photo, or over the brand colour
/// when the tenant has no photo (or it fails to load).
class _PhotoBand extends StatelessWidget {
  const _PhotoBand({super.key, required this.band, required this.asset, required this.minHeight, this.large = false, this.onTap});
  final HomeBand band;
  final String asset;
  final double minHeight;
  final bool large;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final plain = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [scheme.primary, Color.lerp(scheme.primary, scheme.scrim, 0.45)!]),
      ),
    );
    // On a photo the words sit on a dark veil; on the brand colour they use its own text colour.
    final onPhoto = band.hasImage;
    final ink = onPhoto ? scheme.surface : scheme.onPrimary;
    return ClipRRect(
      borderRadius: BorderRadius.circular(b.radiusMd),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              Positioned.fill(
                child: onPhoto ? Image.asset(asset, fit: BoxFit.cover, excludeFromSemantics: true, errorBuilder: (_, __, ___) => plain) : plain,
              ),
              if (onPhoto) Positioned.fill(child: ColoredBox(color: scheme.scrim.withValues(alpha: 0.45))),
              ConstrainedBox(
                constraints: BoxConstraints(minHeight: minHeight, minWidth: double.infinity),
                child: Padding(
                  // The hero leaves room at the bottom for the search card over its edge.
                  padding: EdgeInsets.fromLTRB(b.spacing.xl, b.spacing.xl, b.spacing.xl, large ? b.spacing.xl * 2 : b.spacing.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(band.title, style: (large ? text.headlineMedium : text.titleLarge)?.copyWith(color: ink)),
                      if (band.text != null) ...[
                        SizedBox(height: b.spacing.sm),
                        Text(band.text!, style: text.bodyLarge?.copyWith(color: ink)),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Area, type, bedrooms and top price, then Search and Clear, in one row on
/// wide screens; on phones just the area and Search.
class _Filters extends StatelessWidget {
  const _Filters({
    required this.area,
    required this.type,
    required this.minBeds,
    required this.maxPrice,
    required this.types,
    required this.prices,
    required this.period,
    required this.onType,
    required this.onBeds,
    required this.onPrice,
    required this.onSearch,
    required this.onClear,
  });
  final TextEditingController area;
  final String? type, period;
  final int? minBeds, maxPrice;
  final List<String> types;
  final List<int> prices;
  final ValueChanged<String?> onType;
  final ValueChanged<int?> onBeds, onPrice;
  final VoidCallback onSearch, onClear;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    // A new key when the value is cleared from outside, so the menu shows it.
    Widget menu<T>(String label, T? value, List<(T, String)> options, ValueChanged<T?> onChanged) => DropdownButtonFormField<T?>(
          key: ValueKey('$label-$value'),
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [
            DropdownMenuItem<T?>(value: null, child: const Text('Any')),
            for (final (v, name) in options) DropdownMenuItem<T?>(value: v, child: Text(name, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: onChanged,
        );
    final fields = <Widget>[
      TextField(
        controller: area,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => onSearch(),
        decoration: const InputDecoration(
          hintText: 'Area or estate, e.g. Kilimani, Ruaka',
          prefixIcon: Icon(Icons.search),
        ),
      ),
      menu<String>('Property type', type, [for (final t in types) (t, typeName(t))], onType),
      menu<int>('Bedrooms', minBeds, const [(1, '1+'), (2, '2+'), (3, '3+'), (4, '4+')], onBeds),
      menu<int>(
        period == null ? 'Top price' : 'Top price a $period',
        maxPrice,
        [for (final p in prices) (p, formatKes(p))],
        onPrice,
      ),
    ];
    final search = FilledButton.icon(onPressed: onSearch, icon: const Icon(Icons.search), label: const Text('Search'));
    final clear = TextButton(onPressed: onClear, child: const Text('Clear'));
    return LayoutBuilder(builder: (context, c) {
      // Phones keep the first screen short: the area and Search here, and
      // the other filters on the results screen.
      if (c.maxWidth < 760) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [fields[0], SizedBox(height: b.spacing.sm), search]);
      }
      return Row(children: [
        Expanded(flex: 3, child: fields[0]),
        for (final f in fields.skip(1)) ...[SizedBox(width: b.spacing.sm), Expanded(flex: 2, child: f)],
        SizedBox(width: b.spacing.md),
        search,
        SizedBox(width: b.spacing.xs),
        clear,
      ]);
    });
  }
}

/// Contacts and links at the foot of the home page. The site pages (About,
/// Privacy, …) live on the share site and open in the browser.
class _Footer extends ConsumerWidget {
  const _Footer({required this.purposes});
  final List<Purpose> purposes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(tenantProvider);
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final open = ref.read(urlOpenerProvider);
    Widget link(String label, VoidCallback onTap) => InkWell(
          onTap: onTap,
          child: Padding(padding: EdgeInsets.symmetric(vertical: b.spacing.xs), child: Text(label, style: text.bodyMedium)),
        );
    Widget column(String title, List<Widget> children) => SizedBox(
          width: 240,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: text.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
            SizedBox(height: b.spacing.sm),
            ...children,
          ]),
        );
    return Container(
      key: const Key('home-footer'),
      decoration: BoxDecoration(color: b.surfaceAlt, borderRadius: BorderRadius.circular(b.radiusMd)),
      padding: EdgeInsets.all(b.spacing.xl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: b.spacing.xl, runSpacing: b.spacing.xl, children: [
          column(tenant.name, [
            if (tenant.tagline != null) Text(tenant.tagline!, style: text.bodyMedium),
            if (tenant.phone != 'TBC') link('Call ${tenant.phone}', () => open(Uri(scheme: 'tel', path: tenant.phone))),
            link(tenant.email, () => open(Uri(scheme: 'mailto', path: tenant.email))),
          ]),
          column('Browse', [
            for (final p in purposes) link('Homes ${p.heading}', () => context.push('/${p.pathSegment}')),
          ]),
          column('About us', [
            for (final (slug, name) in const [('about', 'About'), ('contact', 'Contact'), ('faq', 'FAQs'), ('privacy', 'Privacy'), ('terms', 'Terms')])
              link(name, () => open(Uri.https(tenant.shareDomain, '/$slug'))),
          ]),
        ]),
        SizedBox(height: b.spacing.lg),
        Text('© ${ref.read(clockProvider)().year} ${tenant.name}', style: text.bodySmall),
      ]),
    );
  }
}

/// The newest few homes for [purpose]; nothing at all while loading, on an
/// error or when there are none, so the search above stays the focus.
class _Newest extends ConsumerWidget {
  const _Newest({required this.purpose, required this.onSeeAll});
  final Purpose purpose;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hits = ref.watch(searchResultsProvider(ListingFilters(purpose: purpose))).value?.hits ?? const [];
    if (hits.isEmpty) return const SizedBox.shrink();
    final b = context.brand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(child: Text('Newest ${purpose.heading}', style: Theme.of(context).textTheme.titleLarge)),
          TextButton(onPressed: onSeeAll, child: const Text('See all')),
        ]),
        SizedBox(height: b.spacing.sm),
        // Three across on wide screens, one under another on phones.
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth >= 900 ? 3 : 1;
          final gap = b.spacing.md;
          final width = (c.maxWidth - gap * (cols - 1)) / cols;
          return Wrap(spacing: gap, runSpacing: gap, children: [
            for (final l in hits.take(cols == 1 ? 3 : 6)) SizedBox(width: width, child: ListingCard(listing: l, stacked: true)),
          ]);
        }),
      ],
    );
  }
}
