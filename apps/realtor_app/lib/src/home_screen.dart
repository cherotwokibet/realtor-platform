import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';

import 'package:go_router/go_router.dart';

import 'account/account_data.dart';
import 'ad_slot.dart';
import 'app.dart' show TopNav;
import 'nav.dart';
import 'phone_nav.dart';
import 'providers.dart';
import 'sections.dart';
import 'search/area_suggest.dart';
import 'search/purpose.dart';
import 'site_footer.dart';
import 'window_scroll.dart';
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

  static const _types = ['bedsitter', 'single-room', 'studio', 'apartment', 'maisonette', 'hostel'];

  /// The home search's property types, in the realtor's order.
  static const _searchTypes = ['single-room', 'bedsitter', 'studio', 'apartment'];

  // The filter row under the hero (plain search; conversational search has its own field).
  final _area = TextEditingController();
  String? _type;

  /// Bedrooms: 1, 2 or 3 exactly, or [_bedsUpFrom] and more.
  int? _beds;
  static const _bedsUpFrom = 4;

  /// The chosen top price, one of [_prices] for the purpose.
  _Price? _price;

  @override
  void dispose() {
    _area.dispose();
    super.dispose();
  }

  void _clear() => setState(() {
        _area.clear();
        _type = null;
        _beds = null;
        _price = null;
      });

  /// Top prices offered for each purpose (KES): a month, in all, or a
  /// night; the last is "that and more".
  static List<_Price> _prices(Purpose p) => switch (p) {
        Purpose.rent => const [_Price(max: 10000), _Price(max: 30000), _Price(max: 60000), _Price(min: 60000)],
        Purpose.sale => const [_Price(max: 3000000), _Price(max: 6000000), _Price(max: 10000000), _Price(min: 10000000)],
        Purpose.shortStay => const [_Price(max: 3000), _Price(max: 5000), _Price(max: 10000), _Price(min: 10000)],
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
      beds: [if (_beds != null && _beds! < _bedsUpFrom) _beds!],
      minBeds: _beds != null && _beds! >= _bedsUpFrom ? _beds : null,
      minPriceKES: _price?.min,
      maxPriceKES: _price?.max,
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
      allowed: {
        for (final p in Purpose.values)
          if (features.isOn(p.feature)) p
      },
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
    final purposes = [
      for (final p in Purpose.values)
        if (tenant.features.isOn(p.feature)) p
    ];
    if (!purposes.contains(_purpose) && purposes.isNotEmpty) _purpose = purposes.first;
    if (_price != null && !_prices(_purpose).contains(_price)) _price = null;
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
                beds: _beds,
                bedsUpFrom: _bedsUpFrom,
                price: _price,
                types: _searchTypes,
                prices: _prices(_purpose),
                period: _purpose.period,
                onType: (v) => setState(() => _type = v),
                onBeds: (v) => setState(() => _beds = v),
                onPrice: (v) => setState(() => _price = v),
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

    // One band above the property types: the advert when the tenant sells
    // advert space (marked AD, with Enquire now), else the realtor's own
    // promotion. Never both, so the same message is not shown twice.
    final promo = <Widget>[
      FeatureGate(
        feature: Feature.ads,
        orElse: banner == null
            ? const SizedBox.shrink()
            : _PhotoBand(
                key: const Key('home-banner'),
                band: banner,
                name: 'banner',
                minHeight: 120,
                onTap: listProperty == null ? null : () => ref.read(urlOpenerProvider)(listProperty),
              ),
        child: const AdSlot(banner: true),
      ),
      if (AdSlot.enabledFor(tenant) || banner != null) SizedBox(height: b.spacing.xl),
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

    // The page scrolls across the whole window, so its scrollbar is at the
    // window's edge, as on the big portals; the content keeps its width.
    final side = ((MediaQuery.sizeOf(context).width - maxContentWidth) / 2).clamp(0.0, double.infinity) + b.spacing.gutter;
    return Scaffold(
      // Wide screens have the logo in the top navigation instead.
      drawer: wide ? null : const AppDrawer(),
      // Phones: the top bar scrolls away with the page and is back at the top.
      // Wide: the page's own browser-like scrollbar, the window's full height.
      body: WindowScroll(
          enabled: wide,
          child: CustomScrollView(primary: true, slivers: [
            if (!wide) const PhoneTopBar(),
            // Wide: the top menu scrolls away with the page, as on Bayut's home page.
            if (wide)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: TopNav.height,
                  child: TopNav(
                    sections: visibleSections(enabledSections(tenant.features), signedIn: ref.watch(customerProvider).value != null),
                    location: '/',
                  ),
                ),
              ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side, b.spacing.gutter, side, b.spacing.gutter),
              sliver: SliverList.list(children: [
                _PhotoBand(key: const Key('home-hero'), band: hero, name: 'hero', minHeight: wide ? 220 : 120, large: true),
                // The search sits over the bottom edge of the photo.
                Transform.translate(
                  offset: Offset(0, -b.spacing.xl),
                  child: Padding(padding: EdgeInsets.symmetric(horizontal: wide ? b.spacing.xl : b.spacing.sm), child: searchCard),
                ),
                // The advert (or promotion) band, then the property types.
                ...promo,
                ...types,
                const RecentSearches(),
                // Two rows of homes, as the big portals' home pages have them:
                // the realtor's Hot Properties, then the newest.
                const _HotRow(),
                // The rows managers fill in the admin (Home page); each only when it has homes.
                _PicksRow(
                    rowKey: const Key('featured-row'), title: 'Featured properties', icon: Icons.workspace_premium_outlined, homes: featuredHomesProvider),
                _PicksRow(rowKey: const Key('recommended-row'), title: 'Recommended', icon: Icons.thumb_up_alt_outlined, homes: recommendedHomesProvider),
                _Newest(purpose: _purpose, onSeeAll: () => _search()),
              ]),
            ),
            // The site footer runs the width of the window.
            SliverToBoxAdapter(child: Padding(padding: EdgeInsets.only(top: b.spacing.xl), child: SiteFooter(width: maxContentWidth + 2 * b.spacing.gutter))),
          ])),
    );
  }
}

/// A band's n-th photo (1-based), as `tenant prepare` bundles it.
String homePhotoAsset(String band, int n) => '${tenantAssetDir()}/home-$band-$n.webp';

/// A band with the realtor's words over a photo, or over the brand colour
/// when the tenant has no photo (or it fails to load). With several photos
/// it shows them in turn, cross-fading every [interval]; visitors who have
/// turned animations off see the first one only.
class _PhotoBand extends StatefulWidget {
  const _PhotoBand({super.key, required this.band, required this.name, required this.minHeight, this.large = false, this.onTap});
  final HomeBand band;

  /// `hero` or `banner`: which bundled photos to use.
  final String name;
  final double minHeight;
  final bool large;
  final VoidCallback? onTap;

  static const interval = Duration(seconds: 7);

  @override
  State<_PhotoBand> createState() => _PhotoBandState();
}

class _PhotoBandState extends State<_PhotoBand> {
  Timer? _timer;
  int _index = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final rotate = widget.band.imageCount > 1 && !MediaQuery.disableAnimationsOf(context);
    if (rotate && _timer == null) {
      _timer = Timer.periodic(_PhotoBand.interval, (_) => _next());
    } else if (!rotate) {
      _timer?.cancel();
      _timer = null;
      _index = 0;
    }
  }

  void _next() {
    final count = widget.band.imageCount;
    final next = (_index + 1) % count;
    // Fetch the next photo first, so the fade never shows a blank. One that
    // fails to load is shown as the brand colour rather than stopping the turn.
    void show() {
      if (mounted) setState(() => _index = next);
    }

    precacheImage(AssetImage(homePhotoAsset(widget.name, next + 1)), context, onError: (_, __) {}).then((_) => show(), onError: (Object _) => show());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final band = widget.band;
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
          onTap: widget.onTap,
          child: Stack(
            children: [
              Positioned.fill(
                child: onPhoto
                    ? AnimatedSwitcher(
                        duration: const Duration(milliseconds: 900),
                        layoutBuilder: (current, previous) => Stack(fit: StackFit.expand, children: [...previous, if (current != null) current]),
                        child: Image.asset(
                          homePhotoAsset(widget.name, _index + 1),
                          key: ValueKey('${widget.name}-$_index'),
                          fit: BoxFit.cover,
                          excludeFromSemantics: true,
                          errorBuilder: (_, __, ___) => plain,
                        ),
                      )
                    : plain,
              ),
              if (onPhoto) Positioned.fill(child: ColoredBox(color: scheme.scrim.withValues(alpha: 0.45))),
              ConstrainedBox(
                constraints: BoxConstraints(minHeight: widget.minHeight, minWidth: double.infinity),
                child: Padding(
                  // The hero leaves room at the bottom for the search card over its edge.
                  padding: EdgeInsets.fromLTRB(b.spacing.xl, b.spacing.xl, b.spacing.xl, widget.large ? b.spacing.xl * 2 : b.spacing.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(band.title, style: (widget.large ? text.headlineMedium : text.titleLarge)?.copyWith(color: ink)),
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
    required this.beds,
    required this.bedsUpFrom,
    required this.price,
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
  final int? beds;
  final int bedsUpFrom;
  final _Price? price;
  final List<String> types;
  final List<_Price> prices;
  final ValueChanged<String?> onType;
  final ValueChanged<int?> onBeds;
  final ValueChanged<_Price?> onPrice;
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
      // Areas are suggested while typing (as on the big portals).
      AreaSuggestField(
        controller: area,
        field: (context, controller, focus) => TextField(
          key: const Key('home-area'),
          controller: controller,
          focusNode: focus,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => onSearch(),
          decoration: const InputDecoration(
            hintText: 'Area or estate, e.g. Kilimani, Ruaka',
            prefixIcon: Icon(Icons.search),
          ),
        ),
      ),
      menu<String>('Property type', type, [for (final t in types) (t, typeName(t))], onType),
      menu<int>('Bedrooms', beds, [for (var n = 1; n <= bedsUpFrom; n++) (n, n == bedsUpFrom ? '$n +' : '$n')], onBeds),
      menu<_Price>(
        period == null ? 'Top price' : 'Top price a $period',
        price,
        [for (final p in prices) (p, p.label)],
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

/// The realtor's Hot Properties (managers choose them in the admin); nothing
/// while loading, on an error or when there are none.
class _HotRow extends ConsumerWidget {
  const _HotRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hits = ref.watch(hotHomesProvider).value ?? const [];
    if (hits.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: context.brand.spacing.xl),
      child: HomeRow(
        key: const Key('hot-row'),
        title: 'Hot properties',
        icon: Icons.local_fire_department,
        listings: hits.take(12).toList(),
        onSeeAll: () => context.push('/hot'),
      ),
    );
  }
}

/// A row of homes a manager picked (Featured, Recommended); nothing while
/// loading, on an error or when there are none.
class _PicksRow extends ConsumerWidget {
  const _PicksRow({required this.rowKey, required this.title, required this.icon, required this.homes});
  final Key rowKey;
  final String title;
  final IconData icon;
  final FutureProvider<List<ListingSummary>> homes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hits = ref.watch(homes).value ?? const [];
    if (hits.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: context.brand.spacing.xl),
      child: HomeRow(key: rowKey, title: title, icon: icon, listings: hits.take(12).toList()),
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
    final found = ref.watch(searchResultsProvider(ListingFilters(purpose: purpose))).value?.hits ?? const [];
    if (found.isEmpty) return const SizedBox.shrink();
    // Homes a manager pinned come first, the rest as they were.
    final hits = [...found.where((l) => l.pinnedNewest), ...found.where((l) => !l.pinnedNewest)];
    return Padding(
      padding: EdgeInsets.only(top: context.brand.spacing.xl),
      child: HomeRow(
          key: const Key('newest-row'),
          title: 'Newest ${purpose.heading}',
          // A sparkle for "new", beside Hot properties' flame.
          icon: Icons.auto_awesome,
          listings: hits.take(12).toList(),
          onSeeAll: onSeeAll),
    );
  }
}

/// One row of homes that slides sideways, as on Bayut's home page: four
/// across on a computer with round arrows at the ends, three on a tablet,
/// and on a phone one and a peek of the next, to swipe.
class HomeRow extends StatefulWidget {
  const HomeRow({super.key, required this.title, required this.listings, this.icon, this.onSeeAll});
  final String title;
  final IconData? icon;
  final List<ListingSummary> listings;
  final VoidCallback? onSeeAll;

  @override
  State<HomeRow> createState() => _HomeRowState();
}

class _HomeRowState extends State<HomeRow> {
  final _row = ScrollController();
  bool _atStart = true, _atEnd = false;

  @override
  void initState() {
    super.initState();
    _row.addListener(_edges);
    WidgetsBinding.instance.addPostFrameCallback((_) => _edges());
  }

  void _edges() {
    if (!_row.hasClients || !mounted) return;
    final p = _row.position;
    final start = p.pixels <= 1, end = p.pixels >= p.maxScrollExtent - 1;
    if (start != _atStart || end != _atEnd) {
      setState(() {
        _atStart = start;
        _atEnd = end;
      });
    }
  }

  @override
  void dispose() {
    _row.dispose();
    super.dispose();
  }

  void _page(int dir, double by) => _row.animateTo((_row.offset + dir * by).clamp(0.0, _row.position.maxScrollExtent),
      duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic);

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        if (widget.icon != null) ...[Icon(widget.icon, color: scheme.primary), SizedBox(width: b.spacing.sm)],
        Expanded(child: Text(widget.title, style: text.titleLarge)),
        if (widget.onSeeAll != null) TextButton(onPressed: widget.onSeeAll, child: const Text('See all')),
      ]),
      SizedBox(height: b.spacing.sm),
      LayoutBuilder(builder: (context, c) {
        final gap = b.spacing.md;
        final phone = c.maxWidth < 600;
        final across = c.maxWidth >= 1000 ? 4 : (c.maxWidth >= 600 ? 3 : 1);
        // Phones: one card and a peek of the next, so it reads as a row to swipe.
        final width = phone ? c.maxWidth * 0.86 : (c.maxWidth - gap * (across - 1)) / across;
        Widget arrow(IconData icon, String tip, int dir, Key key) => Material(
              color: scheme.surface,
              shape: const CircleBorder(),
              elevation: 3,
              child: IconButton(key: key, tooltip: tip, icon: Icon(icon), onPressed: () => _page(dir, (width + gap) * across)),
            );
        return Stack(clipBehavior: Clip.none, children: [
          SingleChildScrollView(
            controller: _row,
            scrollDirection: Axis.horizontal,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final (i, l) in widget.listings.indexed) ...[
                if (i > 0) SizedBox(width: gap),
                SizedBox(width: width, child: ListingCard(listing: l)),
              ],
            ]),
          ),
          if (!phone && !_atStart) Positioned(left: -20, top: 0, bottom: 0, child: Center(child: arrow(Icons.chevron_left, 'Back', -1, const Key('row-back')))),
          if (!phone && !_atEnd && widget.listings.length > across)
            Positioned(right: -20, top: 0, bottom: 0, child: Center(child: arrow(Icons.chevron_right, 'More', 1, const Key('row-more')))),
        ]);
      }),
    ]);
  }
}

/// One top-price choice: up to [max], or [min] and more.
class _Price {
  const _Price({this.min, this.max});
  final int? min, max;

  String get label => max != null ? formatKes(max!, compact: max! >= 1000000) : '${formatKes(min!, compact: min! >= 1000000)} +';

  @override
  bool operator ==(Object other) => other is _Price && other.min == min && other.max == max;
  @override
  int get hashCode => Object.hash(min, max);
}
