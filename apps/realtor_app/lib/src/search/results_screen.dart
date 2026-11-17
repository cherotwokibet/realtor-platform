import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';

import '../account/account_data.dart';
import '../account/account_screen.dart';
import '../ad_slot.dart';
import '../app.dart' show TopNav;
import '../nav.dart';
import '../providers.dart';
import '../phone_nav.dart';
import '../saved/favourites.dart';
import '../site_footer.dart';
import '../sections.dart';
import 'filters_sheet.dart';
import 'purpose.dart';
import 'results_map.dart';

/// Results for a filter URL. Every change of filter is a new URL, so the
/// browser back button, shared links and app deep links all work.
///
/// The search bar stays at the top while the homes scroll under it: the
/// location box, a dropdown each for type, beds and price, and More Filters
/// at the far end.
class ResultsScreen extends ConsumerWidget {
  const ResultsScreen({super.key, required this.filters});
  final ListingFilters filters;

  // A changed filter or sort replaces this page, so Back returns to where
  // the search started, not through every filter tried.
  void _go(BuildContext context, ListingFilters f) => context.replace(f.toUri().toString());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final result = ref.watch(searchResultsProvider(filters));
    final onMap = ref.watch(resultsOnMapProvider);
    void change(ListingFilters f) => _go(context, f);
    final wide = MediaQuery.sizeOf(context).width >= wideLayoutFrom;
    final b = context.brand;
    // The page's width, centred; the scrolling area itself spans the window.
    Widget page(Widget child) => Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: resultsContentWidth), child: child),
        );
    // Wide: one row of 48. Phones: the 44 location box over the 36 pills.
    // (A back arrow, when there is a screen behind, makes the first row 48.)
    final barHeight = wide ? 48 + b.spacing.sm * 2 + 1 : (context.canPop() ? 48 : 44) + 36 + b.spacing.sm * 3 + 1;
    final bar = Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        page(SearchBarRow(filters: filters, onChange: change)),
        const Divider(height: 1),
      ]),
    );
    final tenant = ref.watch(tenantProvider);
    final menu = !wide
        ? const SizedBox.shrink()
        : SizedBox(
            height: TopNav.height,
            child: TopNav(
              sections: visibleSections(enabledSections(tenant.features), signedIn: ref.watch(customerProvider).value != null),
              location: '/${filters.purpose.pathSegment}',
              // The logo and Log in line up with the homes and the column beside them.
              width: resultsContentWidth,
              gutter: 24,
            ),
          );

    return Scaffold(
      // Phones switch list and map with one pill over the results, where a
      // thumb reaches it; wide screens have List | Map over the homes. Both
      // as the big property portals do.
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: wide
          ? null
          : FloatingActionButton.extended(
              key: const Key('map-toggle'),
              tooltip: onMap ? 'List' : 'Map',
              icon: Icon(onMap ? Icons.view_list_outlined : Icons.map_outlined),
              label: Text(onMap ? 'List' : 'Map'),
              onPressed: () => ref.read(resultsOnMapProvider.notifier).set(!onMap),
            ),
      drawer: wide ? null : const AppDrawer(),
      body: SafeArea(
        child: !onMap
            // One page that scrolls, as a web page does. The
            // top menu scrolls away, the search bar stays, and the homes
            // and the column beside them move together.
            // The scrollbar is always shown, at the window's edge.
            ? Scrollbar(
                // Always shown at the window's edge on wide screens.
                thumbVisibility: wide,
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                  child: CustomScrollView(
                    key: const Key('results-page'),
                    primary: true,
                    slivers: [
                      // The top menu scrolls away with the page and is back at the top.
                      if (wide) SliverToBoxAdapter(child: menu) else const PhoneTopBar(),
                      SliverPersistentHeader(pinned: true, delegate: _PinnedBar(height: barHeight, child: bar)),
                      result.when(
                        loading: () => const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator())),
                        error: (e, _) => SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(child: Text('Search is not available right now.', style: text.bodyMedium)),
                        ),
                        data: (r) => SliverToBoxAdapter(child: page(_ResultsList(filters: filters, result: r, onChange: change, scrolls: false))),
                      ),
                      SliverToBoxAdapter(child: SiteFooter(width: wide ? resultsContentWidth : maxContentWidth)),
                    ],
                  ),
                ),
              )
            // The map fills the screen under the bar.
            : Column(children: [
                if (wide) menu,
                bar,
                Expanded(
                  child: page(result.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Search is not available right now.', style: text.bodyMedium)),
                    data: (r) => Column(children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(b.spacing.gutter, b.spacing.md, b.spacing.gutter, 0),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          if (wide) ListHeading(filters: filters, found: r.found, onChange: change),
                          _ActiveFilters(filters: filters, onChange: change),
                        ]),
                      ),
                      SizedBox(height: context.brand.spacing.sm),
                      Expanded(child: ResultsMap(hits: r.hits, filters: filters, onChange: change)),
                    ]),
                  )),
                ),
              ]),
      ),
    );
  }
}

/// Keeps the search bar at the top of a page that scrolls under it.
class _PinnedBar extends SliverPersistentHeaderDelegate {
  const _PinnedBar({required this.height, required this.child});
  final double height;
  final Widget child;

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => SizedBox.expand(child: child);
  @override
  bool shouldRebuild(_PinnedBar old) => old.height != height || old.child != child;
}

const _keep = Object();

/// [f] with some parts replaced; pass null to clear one of the nullable parts.
ListingFilters _edit(
  ListingFilters f, {
  Object? q = _keep,
  List<String>? areas,
  Object? minBeds = _keep,
  Object? minPrice = _keep,
  Object? maxPrice = _keep,
  List<String>? amenities,
  bool? verifiedOnly,
  bool? verifiedFirst,
  Object? furnished = _keep,
  bool? floorPlan,
  bool? video,
  bool? tour,
  List<int>? beds,
  List<int>? baths,
  List<String>? types,
  List<GeoPoint>? polygon,
  ListingSort? sort,
}) =>
    ListingFilters(
      purpose: f.purpose,
      q: identical(q, _keep) ? f.q : q as String?,
      types: types ?? f.types,
      areas: areas ?? f.areas,
      minBeds: identical(minBeds, _keep) ? f.minBeds : minBeds as int?,
      minPriceKES: identical(minPrice, _keep) ? f.minPriceKES : minPrice as int?,
      maxPriceKES: identical(maxPrice, _keep) ? f.maxPriceKES : maxPrice as int?,
      amenities: amenities ?? f.amenities,
      verifiedOnly: verifiedOnly ?? f.verifiedOnly,
      verifiedFirst: verifiedFirst ?? f.verifiedFirst,
      furnished: identical(furnished, _keep) ? f.furnished : furnished as bool?,
      floorPlan: floorPlan ?? f.floorPlan,
      video: video ?? f.video,
      tour: tour ?? f.tour,
      beds: beds ?? f.beds,
      baths: baths ?? f.baths,
      near: f.near,
      polygon: polygon ?? f.polygon,
      sort: sort ?? f.sort,
    );

/// The same search for another purpose. Prices and types rarely carry over
/// (a month's rent is not a sale price), so those start again.
ListingFilters _withPurpose(ListingFilters f, Purpose p) => ListingFilters(
      purpose: p,
      q: f.q,
      areas: f.areas,
      minBeds: f.minBeds,
      beds: f.beds,
      baths: f.baths,
      amenities: f.amenities,
      verifiedOnly: f.verifiedOnly,
      verifiedFirst: f.verifiedFirst,
      furnished: f.furnished,
      floorPlan: f.floorPlan,
      video: f.video,
      tour: f.tour,
      near: f.near,
      polygon: f.polygon,
      sort: f.sort,
    );

/// The search bar of a results page. Wide screens: everything in one row.
/// Phones: the location box, then the dropdowns in a row under it. Rent, Buy
/// and BnB are pages of their own (the top menu; pills over the list on
/// phones), so the bar has no purpose control. The dropdowns open under their button on wide
/// screens and as bottom sheets on phones.
class SearchBarRow extends ConsumerStatefulWidget {
  const SearchBarRow({super.key, required this.filters, required this.onChange});
  final ListingFilters filters;
  final ValueChanged<ListingFilters> onChange;

  @override
  ConsumerState<SearchBarRow> createState() => _SearchBarRowState();
}

class _SearchBarRowState extends ConsumerState<SearchBarRow> {
  late final _location = TextEditingController(text: locationText(widget.filters));

  // A changed filter opens a new results page. Its pill row starts where the
  // last one was left, so the pill just used is still in view, then glides
  // back to the start, as the big portals' apps do.
  static double _carriedOffset = 0;
  late final _pills = ScrollController(initialScrollOffset: _carriedOffset);

  @override
  void initState() {
    super.initState();
    if (_carriedOffset > 0) {
      _carriedOffset = 0;
      _glideBack();
    }
  }

  /// A pause, then the glide to the start: one animation, so nothing is left pending.
  void _glideBack() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pills.hasClients && _pills.offset > 0) {
          _pills.animateTo(0, duration: const Duration(milliseconds: 950), curve: const Interval(0.45, 1, curve: Curves.easeInOutCubic));
        }
      });

  @override
  void didUpdateWidget(SearchBarRow old) {
    super.didUpdateWidget(old);
    if (old.filters != widget.filters) {
      _location.text = locationText(widget.filters);
      // The same bar on the new results: glide back from the pill just used.
      if (_carriedOffset > 0) {
        _carriedOffset = 0;
        _glideBack();
      }
    }
  }

  @override
  void dispose() {
    _location.dispose();
    _pills.dispose();
    super.dispose();
  }

  void _search() {
    final (areas, q) = parseLocation(_location.text, ref.read(areaNamesProvider).value ?? const {});
    FocusScope.of(context).unfocus();
    widget.onChange(_edit(widget.filters, areas: areas, q: q));
  }

  Future<void> _open(BuildContext anchor, FilterSection section) async {
    final next = await showFiltersSheet(context, widget.filters, section: section, anchor: anchor);
    if (next != null && mounted) _apply(next);
  }

  void _apply(ListingFilters next) {
    if (next == widget.filters) return;
    _carriedOffset = _pills.hasClients ? _pills.offset : 0;
    widget.onChange(next);
  }

  /// Every filter of the bar cleared; the place, the order and furnishing stay.
  ListingFilters get _cleared {
    final f = widget.filters;
    return ListingFilters(
      purpose: f.purpose,
      q: f.q,
      areas: f.areas,
      furnished: f.furnished,
      verifiedFirst: f.verifiedFirst,
      near: f.near,
      polygon: f.polygon,
      sort: f.sort,
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final scheme = Theme.of(context).colorScheme;
    final wide = MediaQuery.sizeOf(context).width >= wideLayoutFrom;
    final f = widget.filters;
    final more = [f.amenities.where((a) => a != 'furnished').isNotEmpty, f.floorPlan, f.video, f.tour].where((x) => x).length;
    final roomTypes = {for (final (t, _) in filterRoomTypes) t};
    final rooms = [
      for (final (t, label) in filterRoomTypes)
        if (f.types.contains(t)) label
    ];
    String count(int n, int max) => n == max ? '$n+' : '$n';
    final bedsBaths = [
      if (rooms.isNotEmpty || f.beds.isNotEmpty) '${[...rooms, ...f.beds.map((n) => count(n, maxBedsChoice))].join(', ')} beds',
      if (f.beds.isEmpty && rooms.isEmpty && f.minBeds != null) '${f.minBeds}+ beds',
      if (f.baths.isNotEmpty) '${f.baths.map((n) => count(n, maxBathsChoice)).join(', ')} baths',
    ].join(' · ');
    final otherTypes = f.types.where((t) => !roomTypes.contains(t)).toList();
    // Everything the filters button covers, for its badge.
    final all = [otherTypes.isNotEmpty, bedsBaths.isNotEmpty, f.minPriceKES != null || f.maxPriceKES != null].where((x) => x).length + more;
    String priceLabel() => switch ((f.minPriceKES, f.maxPriceKES)) {
          (null, null) => 'Price',
          (final min?, null) => 'From ${formatKes(min, compact: true)}',
          (null, final max?) => 'Up to ${formatKes(max, compact: true)}',
          (final min?, final max?) => '${formatKes(min, compact: true)}–${formatKes(max, compact: true)}',
        };
    final squared = RoundedRectangleBorder(borderRadius: BorderRadius.circular(b.radiusSm));
    Widget drop(String label, bool active, FilterSection section, Key key, {IconData icon = Icons.arrow_drop_down}) => Builder(
          builder: (anchor) => OutlinedButton(
            key: key,
            style: OutlinedButton.styleFrom(
              minimumSize: wide ? const Size(0, 48) : const Size(0, 36),
              padding: wide ? null : EdgeInsets.only(left: b.spacing.md, right: b.spacing.sm),
              shape: wide ? squared : const StadiumBorder(),
              textStyle: wide ? null : Theme.of(context).textTheme.labelLarge,
              foregroundColor: active ? scheme.primary : scheme.onSurface,
              backgroundColor: active ? b.primarySoft : null,
              side: active ? BorderSide(color: scheme.primary) : null,
            ),
            onPressed: () => _open(anchor, section),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
              SizedBox(width: b.spacing.xs),
              Icon(icon, size: 20),
            ]),
          ),
        );
    // The same height, corners and border as the buttons beside it.
    final edge = OutlineInputBorder(borderRadius: BorderRadius.circular(b.radiusSm), borderSide: BorderSide(color: scheme.outline));
    final location = SizedBox(
      height: 48,
      child: TextField(
        key: const Key('filter-location'),
        controller: _location,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _search(),
        expands: true,
        maxLines: null,
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          hintText: 'Area, estate or location',
          filled: false,
          contentPadding: EdgeInsets.symmetric(horizontal: b.spacing.md),
          border: edge,
          enabledBorder: edge,
          focusedBorder: edge.copyWith(borderSide: BorderSide(color: scheme.primary, width: 2)),
          prefixIcon: Icon(Icons.place_outlined, color: scheme.primary),
          suffixIcon: IconButton(tooltip: 'Search', icon: const Icon(Icons.search), onPressed: _search),
        ),
      ),
    );
    final drops = [
      drop(otherTypes.isEmpty ? 'Property type' : otherTypes.map(typeName).join(', '), otherTypes.isNotEmpty, FilterSection.type, const Key('filter-type')),
      drop(bedsBaths.isEmpty ? 'Beds & Baths' : bedsBaths, bedsBaths.isNotEmpty, FilterSection.bedsBaths, const Key('filter-beds')),
      drop(priceLabel(), f.minPriceKES != null || f.maxPriceKES != null, FilterSection.price, const Key('filter-price')),
      drop(more == 0 ? 'More Filters' : 'More Filters ($more)', more > 0, FilterSection.more, const Key('filter-more'), icon: Icons.tune),
    ];
    final gap = SizedBox(width: b.spacing.sm);
    return Material(
      key: const Key('filter-bar'),
      color: scheme.surface,
      child: Padding(
        // Wide: the same 24 edges as the homes and the column beside them.
        padding: EdgeInsets.symmetric(horizontal: wide ? 24 : b.spacing.gutter, vertical: b.spacing.sm),
        child: wide
            ? Row(children: [
                Expanded(child: location),
                // A long choice ("Studio, 2, 3 beds · 6+ baths") shortens with "…".
                for (final d in drops) ...[gap, ConstrainedBox(constraints: const BoxConstraints(maxWidth: 200), child: d)],
              ])
            // Phones, as on the big portals: the location box, then one
            // row of small pills that scrolls sideways, the filters button
            // first. Each pill opens its sheet; the filters button opens all.
            : Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  if (context.canPop()) const AppBack(),
                  Expanded(child: SizedBox(height: 44, child: location)),
                ]),
                SizedBox(height: b.spacing.sm),
                SizedBox(
                  height: 36,
                  child: SingleChildScrollView(
                    key: const Key('filter-pills'),
                    controller: _pills,
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      Builder(
                        builder: (anchor) => _FiltersButton(active: all > 0, onPressed: () => _open(anchor, FilterSection.all)),
                      ),
                      SizedBox(width: b.spacing.sm),
                      VerticalDivider(width: 1, indent: 6, endIndent: 6, color: b.borderStrong),
                      for (final d in drops) ...[gap, d],
                      if (all > 0) ...[
                        gap,
                        TextButton(
                          key: const Key('filter-reset-all'),
                          style: TextButton.styleFrom(minimumSize: const Size(0, 36), padding: EdgeInsets.symmetric(horizontal: b.spacing.sm)),
                          onPressed: () => _apply(_cleared),
                          child: const Text('Reset All Filters'),
                        ),
                      ],
                    ]),
                  ),
                ),
              ]),
      ),
    );
  }
}

/// The phones' filters button. Once any filter is set it turns tinted with
/// the brand colour, like a chosen pill, with a short pulse, as on the big
/// portals' apps; no number.
class _FiltersButton extends StatelessWidget {
  const _FiltersButton({required this.active, required this.onPressed});
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final scheme = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      // A new key for each state, so the pulse plays when it changes.
      key: ValueKey(active),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      builder: (context, t, child) {
        // Grows a little and settles: 1 -> 1.12 -> 1.
        final scale = active ? 1 + 0.12 * Curves.easeOut.transform(t < 0.5 ? t * 2 : (1 - t) * 2) : 1.0;
        return Transform.scale(scale: scale, child: child);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        decoration: ShapeDecoration(
          color: active ? b.primarySoft : Colors.transparent,
          shape: StadiumBorder(side: BorderSide(color: active ? scheme.primary : b.borderStrong, width: active ? 1.5 : 1)),
        ),
        child: Semantics(
          selected: active,
          child: IconButton(
            key: const Key('filter-all'),
            tooltip: active ? 'Filters (some set)' : 'Filters',
            constraints: const BoxConstraints.tightFor(width: 44, height: 36),
            padding: EdgeInsets.zero,
            style: IconButton.styleFrom(shape: const StadiumBorder()),
            icon: Icon(Icons.tune, size: 18, color: scheme.primary),
            onPressed: onPressed,
          ),
        ),
      ),
    );
  }
}

/// The homes under the search bar. Wide screens: a list of wide cards with a
/// column beside it for alerts and adverts. Narrower: cards one or two
/// across, with an advert after every few homes.
class _ResultsList extends ConsumerWidget {
  const _ResultsList({required this.filters, required this.result, required this.onChange, this.scrolls = true});
  final ListingFilters filters;

  /// False when the page around it does the scrolling (wide screens).
  final bool scrolls;
  final SearchResult result;
  final ValueChanged<ListingFilters> onChange;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final ads = AdSlot.enabledFor(ref.watch(tenantProvider));
    final r = result;
    final gap = SizedBox(height: b.spacing.md);
    final header = <Widget>[
      ListHeading(filters: filters, found: r.found, onChange: onChange),
      _ActiveFilters(filters: filters, onChange: onChange),
      gap,
    ];
    final empty = Padding(
      padding: EdgeInsets.symmetric(vertical: b.spacing.xxl),
      child: Text('Nothing matches yet. Try fewer filters.', style: text.bodyMedium, textAlign: TextAlign.center),
    );
    // Room at the bottom for the Map pill on phones.
    const bottom = 96.0;

    Widget list(EdgeInsets padding, List<Widget> children) => scrolls
        ? ListView(padding: padding, children: children)
        : Padding(padding: padding, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children));

    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 960) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: list(EdgeInsets.fromLTRB(24, b.spacing.md, 0, bottom), [
              ...header,
              if (r.hits.isEmpty) empty,
              for (final l in r.hits) ...[ListingCard(listing: l, layout: CardLayout.wide), gap],
            ]),
          ),
          // Beside the homes, not among them: alerts, then the advert space.
          SizedBox(
            width: 300 + 25 + 24,
            child: SingleChildScrollView(
              // Scrolls by itself only when the page does not (it never does on wide screens).
              physics: scrolls ? null : const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(25, b.spacing.md, 24, bottom),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(b.spacing.md),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text('Be the first to hear about new homes', style: text.bodyMedium, textAlign: TextAlign.center),
                      SizedBox(height: b.spacing.sm),
                      AlertButton(filters: filters),
                    ]),
                  ),
                ),
                if (ads) ...[gap, const AdSlot(tall: true), gap, const AdSlot(tall: true)],
              ]),
            ),
          ),
        ]);
      }
      final cols = c.maxWidth >= 600 ? 2 : 1;
      final features = ref.watch(tenantProvider).features;
      final purposes = [
        for (final p in Purpose.values)
          if (features.isOn(p.feature)) p
      ];
      // Whole rows between adverts: five homes on a phone, six when two across.
      final chunk = cols == 1 ? AdSlot.every : AdSlot.every + 1;
      return list(
        EdgeInsets.fromLTRB(b.spacing.gutter, b.spacing.md, b.spacing.gutter, bottom),
        [
          // Phones have no top menu, so Rent, Buy and BnB switch here.
          if (purposes.length > 1 && MediaQuery.sizeOf(context).width < wideLayoutFrom) ...[
            SegmentedButton<Purpose>(
              key: const Key('purpose-pills'),
              showSelectedIcon: false,
              segments: [for (final p in purposes) ButtonSegment(value: p, label: Text(p.label))],
              selected: {filters.purpose},
              onSelectionChanged: (s) => onChange(_withPurpose(filters, s.first)),
            ),
            gap,
          ],
          ...header,
          Align(alignment: Alignment.centerLeft, child: AlertButton(filters: filters)),
          gap,
          if (r.hits.isEmpty) empty,
          for (var i = 0; i < r.hits.length; i += chunk) ...[
            ListingGrid(listings: r.hits.sublist(i, i + chunk > r.hits.length ? r.hits.length : i + chunk)),
            gap,
            // After each full group of homes, never straight after a short last one.
            if (ads && i + chunk <= r.hits.length) ...[const AdSlot(), gap],
          ],
        ],
      );
    });
  }
}

/// Over the homes, as on the big portals: the heading and the count, then
/// All / Furnished / Unfurnished, the order, and List | Map on wide screens.
class ListHeading extends ConsumerWidget {
  const ListHeading({super.key, required this.filters, required this.found, required this.onChange});
  final ListingFilters filters;
  final int found;
  final ValueChanged<ListingFilters> onChange;

  /// The orders offered; "verified" is Popular with verified homes first.
  static const orders = [
    ('popular', 'Popular'),
    ('latest', 'Newest'),
    ('low', 'Lowest price'),
    ('high', 'Highest price'),
    ('verified', 'Verified homes first')
  ];

  static String orderOf(ListingFilters f) => f.verifiedFirst
      ? 'verified'
      : switch (f.sort) { ListingSort.latest => 'latest', ListingSort.priceAsc => 'low', ListingSort.priceDesc => 'high', _ => 'popular' };

  static ListingFilters withOrder(ListingFilters f, String order) => _edit(
        f,
        verifiedFirst: order == 'verified',
        sort: switch (order) { 'latest' => ListingSort.latest, 'low' => ListingSort.priceAsc, 'high' => ListingSort.priceDesc, _ => ListingSort.newest },
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final f = filters;
    final wide = MediaQuery.sizeOf(context).width >= wideLayoutFrom;
    final onMap = ref.watch(resultsOnMapProvider);
    final where = f.areas.length == 1 ? ' in ${areaName(f.areas.single)}' : '';
    final what = f.types.length == 1 ? '${typeName(f.types.single)}s' : 'Homes';
    final order = orderOf(f);
    // Furnished is stored as a feature in older links; the choice reads both.
    final furnished = f.furnished ?? (f.amenities.contains('furnished') ? true : null);
    void furnish(bool? value) => onChange(_edit(f, furnished: value, amenities: [...f.amenities]..remove('furnished')));

    // The order. Phones: plain coloured words with the sort mark on the
    // heading's line. Wide: a bordered dropdown beside List | Map.
    final sort = SortMenu(value: order, bordered: wide, onChanged: (o) => onChange(withOrder(f, o)));
    final view = GroupedChoice<bool>(
      key: const Key('map-toggle'),
      value: onMap,
      options: const [(false, 'List', Icons.view_list_outlined), (true, 'Map', Icons.map_outlined)],
      onChanged: (v) => ref.read(resultsOnMapProvider.notifier).set(v),
    );
    // Wide: three separate buttons, the chosen one tinted. Phones: one group.
    Widget chip(String label, bool? value) {
      final on = furnished == value;
      return OutlinedButton(
        key: Key('furnished-${value ?? 'all'}'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(b.radiusSm)),
          backgroundColor: on ? b.primarySoft : null,
          foregroundColor: on ? scheme.primary : scheme.onSurface,
          side: BorderSide(color: on ? scheme.primary : b.borderStrong),
        ),
        onPressed: () => furnish(value),
        child: Text(label),
      );
    }

    final furnishing = GroupedChoice<bool?>(
      key: const Key('furnishing'),
      value: furnished,
      expand: true,
      options: const [(null, 'All', null), (true, 'Furnished', null), (false, 'Unfurnished', null)],
      keyOf: (v) => Key('furnished-${v ?? 'all'}'),
      onChanged: furnish,
    );
    // The heading with the order on its line, then furnishing (and List |
    // Map on wide screens), as on the big portals.
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(child: Text('$what ${f.purpose.heading}$where', style: text.titleLarge)),
        if (!wide) sort,
      ]),
      Text('$found ${found == 1 ? 'home' : 'homes'}', style: text.labelLarge?.copyWith(color: b.textMuted)),
      SizedBox(height: b.spacing.md),
      wide
          // Both ends of the row when they fit; the order under furnishing when not.
          ? Wrap(
              key: const Key('list-heading'),
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: b.spacing.sm,
              children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  chip('All', null),
                  SizedBox(width: b.spacing.sm),
                  chip('Furnished', true),
                  SizedBox(width: b.spacing.sm),
                  chip('Unfurnished', false),
                ]),
                Row(mainAxisSize: MainAxisSize.min, children: [sort, SizedBox(width: b.spacing.sm), view]),
              ],
            )
          : KeyedSubtree(key: const Key('list-heading'), child: furnishing),
    ]);
  }
}

/// The order of the homes, as the portals draw it: a button with the sort
/// mark (and on wide screens a border and an arrow that turns while open);
/// the menu drops down under it, its words centred, the chosen one tinted.
class SortMenu extends StatefulWidget {
  const SortMenu({super.key, required this.value, required this.onChanged, this.bordered = true});
  final String value;
  final ValueChanged<String> onChanged;
  final bool bordered;

  @override
  State<SortMenu> createState() => _SortMenuState();
}

class _SortMenuState extends State<SortMenu> {
  final _menu = MenuController();
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final label = ListHeading.orders.firstWhere((o) => o.$1 == widget.value).$2;
    const width = 180.0;
    // The portals' sort mark: three lines, shorter each time, with an arrow down.
    Widget mark(Color color, double size) => Padding(padding: const EdgeInsets.only(right: 6), child: SortIcon(size: size, color: color));
    final button = widget.bordered
        ? AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 44,
            constraints: const BoxConstraints(minWidth: width),
            padding: EdgeInsets.symmetric(horizontal: b.spacing.md),
            decoration: BoxDecoration(
              border: Border.all(color: _open ? scheme.onSurface : b.borderStrong, width: _open ? 1.5 : 1),
              borderRadius: BorderRadius.circular(b.radiusSm),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              mark(scheme.onSurface, 18),
              Text(label, style: text.labelLarge),
              SizedBox(width: b.spacing.md),
              AnimatedRotation(turns: _open ? 0.5 : 0, duration: const Duration(milliseconds: 150), child: const Icon(Icons.arrow_drop_down, size: 22)),
            ]),
          )
        : Padding(
            padding: EdgeInsets.all(b.spacing.xs),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              mark(scheme.primary, 20),
              Text(label, style: text.titleSmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600)),
            ]),
          );
    return MenuAnchor(
      controller: _menu,
      onOpen: () => setState(() => _open = true),
      onClose: () => setState(() => _open = false),
      alignmentOffset: const Offset(0, 4),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(scheme.surface),
        elevation: const WidgetStatePropertyAll(4),
        padding: WidgetStatePropertyAll(EdgeInsets.all(b.spacing.sm)),
        minimumSize: const WidgetStatePropertyAll(Size(width, 0)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(b.radiusSm))),
      ),
      menuChildren: [
        for (final (value, name) in ListHeading.orders)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: SizedBox(
              width: width - b.spacing.sm * 2,
              child: Material(
                color: value == widget.value ? b.primarySoft : Colors.transparent,
                borderRadius: BorderRadius.circular(b.radiusSm),
                child: InkWell(
                  borderRadius: BorderRadius.circular(b.radiusSm),
                  onTap: () {
                    _menu.close();
                    if (value != widget.value) widget.onChanged(value);
                  },
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: b.spacing.sm),
                    child: Text(
                      name,
                      textAlign: TextAlign.center,
                      style: text.bodyMedium?.copyWith(
                        color: value == widget.value ? scheme.primary : b.textMuted,
                        fontWeight: value == widget.value ? FontWeight.w700 : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
      builder: (context, menu, _) => Semantics(
        button: true,
        label: 'Order: $label',
        child: InkWell(
          key: const Key('sort'),
          borderRadius: BorderRadius.circular(b.radiusSm),
          onTap: () => menu.isOpen ? menu.close() : menu.open(),
          child: button,
        ),
      ),
    );
  }
}

/// Three lines lined up on the right, each shorter than the one above, with
/// an arrow down beside them: the mark the big portals put on their order.
class SortIcon extends StatelessWidget {
  const SortIcon({super.key, this.size = 20, this.color});
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: CustomPaint(size: Size(size * 1.15, size), painter: _SortMark(color ?? IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface)),
      );
}

class _SortMark extends CustomPainter {
  const _SortMark(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height, w = size.width;
    final pen = Paint()
      ..color = color
      ..strokeWidth = h * 0.12
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final right = w * 0.6;
    for (final (i, length) in [0.55, 0.42, 0.28].indexed) {
      final y = h * (0.22 + i * 0.28);
      canvas.drawLine(Offset(right - w * length, y), Offset(right, y), pen);
    }
    final x = w * 0.86;
    canvas.drawLine(Offset(x, h * 0.16), Offset(x, h * 0.86), pen);
    canvas.drawPath(
      Path()
        ..moveTo(x - w * 0.14, h * 0.68)
        ..lineTo(x, h * 0.86)
        ..lineTo(x + w * 0.14, h * 0.68),
      pen,
    );
  }

  @override
  bool shouldRepaint(_SortMark old) => old.color != color;
}

/// Options in one bordered group, the chosen one filled softly, as the
/// portals draw All / Furnished / Unfurnished and List / Map.
class GroupedChoice<T> extends StatelessWidget {
  const GroupedChoice({super.key, required this.value, required this.options, required this.onChanged, this.expand = false, this.keyOf});
  final T value;
  final List<(T, String, IconData?)> options;
  final ValueChanged<T> onChanged;

  /// Share the width equally instead of hugging the words.
  final bool expand;
  final Key Function(T)? keyOf;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    Widget option(T v, String label, IconData? icon) {
      final on = v == value;
      final ink = on ? scheme.primary : b.textMuted;
      return Semantics(
        selected: on,
        button: true,
        child: Material(
          key: keyOf?.call(v),
          color: on ? b.primarySoft : Colors.transparent,
          borderRadius: BorderRadius.circular(b.radiusSm),
          child: InkWell(
            borderRadius: BorderRadius.circular(b.radiusSm),
            onTap: () => onChanged(v),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: b.spacing.md, vertical: b.spacing.sm),
              child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                if (icon != null) ...[Icon(icon, size: 18, color: ink), SizedBox(width: b.spacing.xs)],
                Flexible(
                  child: Text(label,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: text.labelLarge?.copyWith(color: ink, fontWeight: on ? FontWeight.w600 : null)),
                ),
              ]),
            ),
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(border: Border.all(color: b.borderStrong), borderRadius: BorderRadius.circular(b.radiusSm)),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min, children: [
          for (final (v, label, icon) in options) expand ? Expanded(child: option(v, label, icon)) : option(v, label, icon),
        ]),
      ),
    );
  }
}

/// Homes as cards: one column on phones, two or three side by side wider.
class ListingGrid extends StatelessWidget {
  const ListingGrid({super.key, required this.listings, this.onOpen});
  final List<ListingSummary> listings;
  final void Function(ListingSummary)? onOpen;

  @override
  Widget build(BuildContext context) {
    final gap = context.brand.spacing.md;
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 960 ? 3 : (c.maxWidth >= 600 ? 2 : 1);
      final width = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(spacing: gap, runSpacing: gap, children: [
        for (final l in listings) SizedBox(width: width, child: ListingCard(listing: l, onOpen: onOpen == null ? null : () => onOpen!(l))),
      ]);
    });
  }
}

/// How a [ListingCard] is laid out.
enum CardLayout {
  /// Photos on top, words under them (phones, grids).
  stacked,

  /// Photos on the left, words beside them (the results list on wide screens).
  wide,

  /// A short card with one photo, shown by the map over its pins.
  compact,
}

/// A home as a card: its photos to flick through, the price, beds and
/// baths, the title and the area, the save heart in the top right corner,
/// and Call, WhatsApp and Email.
class ListingCard extends ConsumerWidget {
  const ListingCard({super.key, required this.listing, this.onOpen, this.layout = CardLayout.stacked});
  final ListingSummary listing;

  /// Called as the card opens its listing (e.g. to count a recommendation).
  final VoidCallback? onOpen;
  final CardLayout layout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final l = listing;
    void open() {
      onOpen?.call();
      context.push('/listing/${l.slug}');
    }

    Widget fact(IconData icon, String value) => Padding(
          padding: EdgeInsets.only(right: b.spacing.md),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18, color: b.textMuted),
            SizedBox(width: b.spacing.xs),
            Text(value, style: text.bodyMedium),
          ]),
        );
    final facts = Wrap(crossAxisAlignment: WrapCrossAlignment.center, runSpacing: b.spacing.xs, children: [
      if (l.beds > 0) fact(Icons.bed_outlined, '${l.beds}') else fact(Icons.bed_outlined, typeName(l.type)),
      if (l.baths > 0) fact(Icons.bathtub_outlined, '${l.baths}'),
      if (l.beds > 0) fact(Icons.home_outlined, typeName(l.type)),
    ]);
    final where = Row(children: [
      Icon(Icons.place_outlined, size: 16, color: b.textMuted),
      SizedBox(width: b.spacing.xs),
      Expanded(child: Text(areaName(l.area), style: text.bodySmall, overflow: TextOverflow.ellipsis)),
    ]);
    final price = PriceText(
      l.priceKES,
      period: l.purpose.period,
      compact: l.purpose == Purpose.sale,
      style: text.titleLarge?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700),
    );
    final title = Text(l.title, style: text.titleSmall, maxLines: layout == CardLayout.compact ? 1 : 2, overflow: TextOverflow.ellipsis);
    final photos = l.photos.isNotEmpty ? l.photos : [if (l.thumb != null) l.thumb!];
    final badge = l.verified ? Positioned(left: b.spacing.sm, top: b.spacing.sm, child: const VerifiedBadge()) : null;

    switch (layout) {
      case CardLayout.compact:
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: open,
            child: SizedBox(
              height: 120,
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SizedBox(width: 130, child: PhotoCarousel(photos: photos.take(1).toList(), label: l.title)),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.all(b.spacing.md),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                      price,
                      SizedBox(height: b.spacing.xs),
                      title,
                      SizedBox(height: b.spacing.xs),
                      where,
                    ]),
                  ),
                ),
                FavouriteButton(listing: l),
              ]),
            ),
          ),
        );
      case CardLayout.wide:
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: open,
            // A fixed height: a row of photos that page sideways cannot size itself to the words.
            child: SizedBox(
              height: 244,
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SizedBox(
                  width: 320,
                  child: Stack(
                      fit: StackFit.expand, children: [PhotoCarousel(photos: photos, label: l.title, videoPoster: l.videoPoster), if (badge != null) badge]),
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(b.spacing.lg, b.spacing.sm, b.spacing.sm, b.spacing.md),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [Expanded(child: price), FavouriteButton(listing: l)]),
                      facts,
                      SizedBox(height: b.spacing.sm),
                      title,
                      SizedBox(height: b.spacing.xs),
                      where,
                      const Spacer(),
                      SizedBox(height: b.spacing.md),
                      ContactButtons(listing: l),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        );
      case CardLayout.stacked:
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: open,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AspectRatio(
                aspectRatio: 16 / 10,
                child: Stack(fit: StackFit.expand, children: [
                  PhotoCarousel(photos: photos, label: l.title, videoPoster: l.videoPoster),
                  if (badge != null) badge,
                  Positioned(
                    right: b.spacing.xs,
                    top: b.spacing.xs,
                    child: Material(color: scheme.surface, shape: const CircleBorder(), child: FavouriteButton(listing: l)),
                  ),
                ]),
              ),
              Padding(
                padding: EdgeInsets.all(b.spacing.md),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  price,
                  SizedBox(height: b.spacing.sm),
                  facts,
                  SizedBox(height: b.spacing.sm),
                  title,
                  SizedBox(height: b.spacing.xs),
                  where,
                  SizedBox(height: b.spacing.md),
                  ContactButtons(listing: l, expand: true),
                ]),
              ),
            ]),
          ),
        );
    }
  }
}

/// A card's photos, and its video last: swipe on a phone or use the
/// arrows; dots show where you are. It has no end: after the last comes the
/// first again. Tapping opens the home, like the rest of the card.
class PhotoCarousel extends StatefulWidget {
  const PhotoCarousel({super.key, required this.photos, required this.label, this.videoPoster});
  final List<String> photos;
  final String label;

  /// A frame of the home's video, shown last with a play mark.
  final String? videoPoster;

  @override
  State<PhotoCarousel> createState() => _PhotoCarouselState();
}

class _PhotoCarouselState extends State<PhotoCarousel> {
  // Far from page 0 in both directions, so swiping back from the first
  // photo reaches the last, and on from the last reaches the first.
  static const _loops = 10000;
  late final _pages = PageController(initialPage: _count * _loops);
  late int _page = _count * _loops;

  int get _count => widget.photos.length + (widget.videoPoster == null ? 0 : 1);

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _move(int by) => _pages.animateToPage(_page + by, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final scheme = Theme.of(context).colorScheme;
    final n = _count;
    final placeholder = ColoredBox(
      color: b.surfaceAlt,
      child: Center(child: Icon(Icons.home_work_outlined, size: 40, color: b.textMuted)),
    );
    if (n == 0) return placeholder;
    final photos = widget.photos.length;
    Widget slide(int i) {
      if (i < photos) {
        return Image.network(
          widget.photos[i],
          fit: BoxFit.cover,
          semanticLabel: n == 1 ? widget.label : '${widget.label}, photo ${i + 1} of $n',
          errorBuilder: (_, __, ___) => placeholder,
        );
      }
      return Stack(fit: StackFit.expand, children: [
        Image.network(widget.videoPoster!, fit: BoxFit.cover, semanticLabel: '${widget.label}, video', errorBuilder: (_, __, ___) => placeholder),
        Center(
          child: DecoratedBox(
            decoration: BoxDecoration(color: scheme.scrim.withValues(alpha: 0.55), shape: BoxShape.circle),
            child: Padding(padding: EdgeInsets.all(b.spacing.sm), child: Icon(Icons.play_arrow, size: 36, color: scheme.surface)),
          ),
        ),
      ]);
    }

    if (n == 1) return slide(0);
    final at = _page % n;
    Widget arrow(IconData icon, String tip, int by) => Material(
          color: scheme.surface.withValues(alpha: 0.9),
          shape: const CircleBorder(),
          child: IconButton(
            tooltip: tip,
            visualDensity: VisualDensity.compact,
            iconSize: 20,
            icon: Icon(icon),
            onPressed: () => _move(by),
          ),
        );
    return Stack(fit: StackFit.expand, children: [
      PageView.builder(
        key: const Key('photo-carousel'),
        controller: _pages,
        onPageChanged: (i) => setState(() => _page = i),
        itemBuilder: (_, i) => slide(i % n),
      ),
      Positioned(left: b.spacing.xs, top: 0, bottom: 0, child: Center(child: arrow(Icons.chevron_left, 'Previous photo', -1))),
      Positioned(right: b.spacing.xs, top: 0, bottom: 0, child: Center(child: arrow(Icons.chevron_right, 'Next photo', 1))),
      Positioned(
        left: 0,
        right: 0,
        bottom: b.spacing.sm,
        child: ExcludeSemantics(
          child: Row(key: Key('photo-dots-$at'), mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < n; i++)
              i == photos
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: Icon(Icons.play_arrow, size: i == at ? 12 : 10, color: scheme.surface.withValues(alpha: i == at ? 1 : 0.6)),
                    )
                  : Container(
                      width: i == at ? 8 : 6,
                      height: i == at ? 8 : 6,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(shape: BoxShape.circle, color: scheme.surface.withValues(alpha: i == at ? 1 : 0.6)),
                    ),
          ]),
        ),
      ),
    ]);
  }
}

/// Call, WhatsApp and Email for a home, in that order; on phone cards just
/// Call and WhatsApp, side by side. Call and WhatsApp show once the
/// realtor's numbers are set; until then Email stands in.
class ContactButtons extends ConsumerWidget {
  const ContactButtons({super.key, required this.listing, this.expand = false});
  final ListingSummary listing;

  /// Fill the width (cards on phones) instead of hugging the labels.
  final bool expand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = context.brand;
    final tenant = ref.watch(tenantProvider);
    final open = ref.read(urlOpenerProvider);
    final l = listing;
    final link = 'https://${tenant.shareDomain}/listing/${l.slug}';
    final ask = 'Hello ${tenant.name}, I am interested in ${l.title}: $link';
    final whatsapp = tenant.hasContactNumbers ? tenant.whatsappLink(ask) : null;
    void tap(String channel, Uri to) {
      ref.read(leadRepositoryProvider).logTap(listingId: l.id, channel: channel).ignore();
      open(to);
    }

    final scheme = Theme.of(context).colorScheme;
    // Solid buttons, each its own colour, so the three are told apart at a
    // glance: the brand colour to call, green for WhatsApp, a soft tint for email.
    ButtonStyle solid(Color fill, Color ink) => FilledButton.styleFrom(
          backgroundColor: fill,
          foregroundColor: ink,
          elevation: 0,
          minimumSize: const Size(0, 44),
          padding: EdgeInsets.symmetric(horizontal: expand ? b.spacing.sm : b.spacing.md),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(b.radiusSm)),
        );
    final onGreen = ThemeData.estimateBrightnessForColor(b.success) == Brightness.dark ? scheme.surface : scheme.onSurface;
    final buttons = <Widget>[
      if (tenant.hasContactNumbers)
        FilledButton.icon(
          style: solid(scheme.primary, scheme.onPrimary),
          onPressed: () => tap('call', Uri(scheme: 'tel', path: tenant.phone)),
          icon: const Icon(Icons.call, size: 18),
          label: const Text('Call'),
        ),
      if (whatsapp != null)
        FilledButton.icon(
          style: solid(b.success, onGreen),
          onPressed: () => tap('whatsapp', whatsapp),
          icon: const WhatsAppIcon(size: 20),
          label: const Text('WhatsApp', maxLines: 1, softWrap: false),
        ),
      // Phones show Call and WhatsApp only; Email stays while there are no numbers to show.
      if (!expand || !tenant.hasContactNumbers)
        FilledButton.icon(
          style: solid(b.primarySoft, scheme.primary),
          onPressed: () => open(Uri(scheme: 'mailto', path: tenant.email, queryParameters: {'subject': l.title, 'body': ask})),
          icon: const Icon(Icons.mail_outline, size: 18),
          label: const Text('Email'),
        ),
    ];
    return Row(children: [
      for (final (i, button) in buttons.indexed) ...[
        if (i > 0) SizedBox(width: b.spacing.sm),
        if (expand) Expanded(child: button) else button,
      ],
    ]);
  }
}

/// What the search is filtering by, as chips that each remove one filter.
class _ActiveFilters extends StatelessWidget {
  const _ActiveFilters({required this.filters, required this.onChange});
  final ListingFilters filters;
  final ValueChanged<ListingFilters> onChange;

  @override
  Widget build(BuildContext context) {
    final f = filters;
    final chips = <(String, ListingFilters)>[
      for (final a in f.areas) (areaName(a), _edit(f, areas: [...f.areas]..remove(a))),
      if (f.minBeds != null) ('${f.minBeds}+ bed', _edit(f, minBeds: null)),
      for (final n in f.beds) ('${n == maxBedsChoice ? '$n+' : n} bed', _edit(f, beds: [...f.beds]..remove(n))),
      for (final n in f.baths) ('${n == maxBathsChoice ? '$n+' : n} bath', _edit(f, baths: [...f.baths]..remove(n))),
      if (f.minPriceKES != null) ('from ${formatKes(f.minPriceKES!)}', _edit(f, minPrice: null)),
      if (f.maxPriceKES != null) ('up to ${formatKes(f.maxPriceKES!)}', _edit(f, maxPrice: null)),
      for (final a in f.amenities)
        if (a != 'furnished') (a.replaceAll('-', ' '), _edit(f, amenities: [...f.amenities]..remove(a))),
      if (f.verifiedOnly) ('verified only', _edit(f, verifiedOnly: false)),
      if (f.floorPlan) ('floor plan', _edit(f, floorPlan: false)),
      if (f.video) ('video tour', _edit(f, video: false)),
      if (f.tour) ('360° tour', _edit(f, tour: false)),
      if (f.q != null) ('"${f.q}"', _edit(f, q: null)),
      if (f.polygon.isNotEmpty) ('Drawn area', _edit(f, polygon: const [])),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    final b = context.brand;
    return Padding(
      padding: EdgeInsets.only(top: b.spacing.sm),
      child: Wrap(spacing: b.spacing.sm, runSpacing: b.spacing.sm, children: [
        for (final (label, without) in chips) InputChip(label: Text(label), onDeleted: () => onChange(without), deleteButtonTooltipMessage: 'Remove $label'),
      ]),
    );
  }
}
