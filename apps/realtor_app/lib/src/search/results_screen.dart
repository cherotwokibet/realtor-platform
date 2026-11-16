import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';

import '../account/account_screen.dart';
import '../ad_slot.dart';
import '../nav.dart';
import '../providers.dart';
import '../saved/favourites.dart';
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

    return Scaffold(
      // Phones switch list and map with one pill over the results, where a
      // thumb reaches it; wide screens have the button at the end of the
      // search bar. Both as the big property portals do.
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: MediaQuery.sizeOf(context).width >= wideLayoutFrom
          ? null
          : FloatingActionButton.extended(
              key: const Key('map-toggle'),
              tooltip: onMap ? 'List' : 'Map',
              icon: Icon(onMap ? Icons.view_list_outlined : Icons.map_outlined),
              label: Text(onMap ? 'List' : 'Map'),
              onPressed: () => ref.read(resultsOnMapProvider.notifier).set(!onMap),
            ),
      body: SafeArea(
        child: Column(children: [
          SearchBarRow(filters: filters, onChange: change),
          const Divider(height: 1),
          Expanded(
            child: result.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Search is not available right now.', style: text.bodyMedium)),
              data: (r) => onMap
                  ? Column(children: [
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: context.brand.spacing.gutter),
                        child: _ActiveFilters(filters: filters, onChange: change),
                      ),
                      SizedBox(height: context.brand.spacing.sm),
                      Expanded(child: ResultsMap(hits: r.hits, filters: filters, onChange: change)),
                    ])
                  : _ResultsList(filters: filters, result: r, onChange: change),
            ),
          ),
        ]),
      ),
    );
  }
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
  bool? tour,
  List<GeoPoint>? polygon,
  ListingSort? sort,
}) =>
    ListingFilters(
      purpose: f.purpose,
      q: identical(q, _keep) ? f.q : q as String?,
      types: f.types,
      areas: areas ?? f.areas,
      minBeds: identical(minBeds, _keep) ? f.minBeds : minBeds as int?,
      minPriceKES: identical(minPrice, _keep) ? f.minPriceKES : minPrice as int?,
      maxPriceKES: identical(maxPrice, _keep) ? f.maxPriceKES : maxPrice as int?,
      amenities: amenities ?? f.amenities,
      verifiedOnly: verifiedOnly ?? f.verifiedOnly,
      verifiedFirst: verifiedFirst ?? f.verifiedFirst,
      furnished: identical(furnished, _keep) ? f.furnished : furnished as bool?,
      floorPlan: floorPlan ?? f.floorPlan,
      tour: tour ?? f.tour,
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
      amenities: f.amenities,
      verifiedOnly: f.verifiedOnly,
      verifiedFirst: f.verifiedFirst,
      furnished: f.furnished,
      floorPlan: f.floorPlan,
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

  @override
  void didUpdateWidget(SearchBarRow old) {
    super.didUpdateWidget(old);
    if (old.filters != widget.filters) _location.text = locationText(widget.filters);
  }

  @override
  void dispose() {
    _location.dispose();
    super.dispose();
  }

  void _search() {
    final (areas, q) = parseLocation(_location.text, ref.read(areaNamesProvider).value ?? const {});
    FocusScope.of(context).unfocus();
    widget.onChange(_edit(widget.filters, areas: areas, q: q));
  }

  Future<void> _open(BuildContext anchor, FilterSection section) async {
    final next = await showFiltersSheet(context, widget.filters, section: section, anchor: anchor);
    if (next != null && mounted) widget.onChange(next);
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final scheme = Theme.of(context).colorScheme;
    final wide = MediaQuery.sizeOf(context).width >= wideLayoutFrom;
    final f = widget.filters;
    final more = [f.furnished != null, f.amenities.isNotEmpty, f.verifiedFirst, f.verifiedOnly, f.floorPlan, f.tour].where((x) => x).length;
    String priceLabel() => switch ((f.minPriceKES, f.maxPriceKES)) {
          (null, null) => 'Price',
          (final min?, null) => 'From ${formatKes(min, compact: true)}',
          (null, final max?) => 'Up to ${formatKes(max, compact: true)}',
          (final min?, final max?) => '${formatKes(min, compact: true)}–${formatKes(max, compact: true)}',
        };
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(b.radiusSm));
    Widget drop(String label, bool active, FilterSection section, Key key, {IconData icon = Icons.arrow_drop_down}) => Builder(
          builder: (anchor) => OutlinedButton(
            key: key,
            style: OutlinedButton.styleFrom(
              shape: shape,
              minimumSize: const Size(0, 48),
              padding: wide ? null : EdgeInsets.symmetric(horizontal: b.spacing.sm),
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
    final location = SizedBox(
      height: 48,
      child: TextField(
        key: const Key('filter-location'),
        controller: _location,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _search(),
        decoration: InputDecoration(
          hintText: 'Area, estate or location',
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: b.spacing.md),
          prefixIcon: const Icon(Icons.place_outlined),
          suffixIcon: IconButton(tooltip: 'Search', icon: const Icon(Icons.search), onPressed: _search),
        ),
      ),
    );
    final drops = [
      drop(f.types.isEmpty ? (wide ? 'Property type' : 'Type') : f.types.map(typeName).join(', '), f.types.isNotEmpty, FilterSection.type, const Key('filter-type')),
      drop(f.minBeds == null ? (wide ? 'Bedrooms' : 'Beds') : '${f.minBeds}+ beds', f.minBeds != null, FilterSection.beds, const Key('filter-beds')),
      drop(priceLabel(), f.minPriceKES != null || f.maxPriceKES != null, FilterSection.price, const Key('filter-price')),
      drop(more == 0 ? 'More Filters' : 'More Filters ($more)', more > 0, FilterSection.more, const Key('filter-more'), icon: Icons.tune),
    ];
    final gap = SizedBox(width: b.spacing.sm);
    final onMap = ref.watch(resultsOnMapProvider);
    return Material(
      key: const Key('filter-bar'),
      color: scheme.surface,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: b.spacing.gutter, vertical: b.spacing.sm),
        child: wide
            ? Row(children: [
                Expanded(child: location),
                for (final d in drops) ...[gap, d],
                gap,
                Tooltip(
                  message: onMap ? 'List' : 'Map',
                  child: FilledButton.icon(
                    key: const Key('map-toggle'),
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 48), shape: const StadiumBorder()),
                    onPressed: () => ref.read(resultsOnMapProvider.notifier).set(!onMap),
                    iconAlignment: IconAlignment.end,
                    icon: Icon(onMap ? Icons.view_list : Icons.map, size: 20),
                    label: Text(onMap ? 'List' : 'Map'),
                  ),
                ),
              ])
            : Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  if (context.canPop()) const AppBack(),
                  Expanded(child: location),
                ]),
                SizedBox(height: b.spacing.sm),
                // All four fit a phone's width: the first three share what More Filters leaves.
                Row(children: [
                  for (final d in drops.take(3)) ...[Expanded(child: d), gap],
                  drops.last,
                ]),
              ]),
      ),
    );
  }
}

/// The homes under the search bar. Wide screens: a list of wide cards with a
/// column beside it for alerts and adverts. Narrower: cards one or two
/// across, with an advert after every few homes.
class _ResultsList extends ConsumerWidget {
  const _ResultsList({required this.filters, required this.result, required this.onChange});
  final ListingFilters filters;
  final SearchResult result;
  final ValueChanged<ListingFilters> onChange;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final ads = AdSlot.enabledFor(ref.watch(tenantProvider));
    final r = result;
    final where = filters.areas.length == 1 ? ' in ${areaName(filters.areas.single)}' : '';
    final what = filters.types.length == 1 ? '${typeName(filters.types.single)}s' : 'Homes';
    const sorts = [(ListingSort.newest, 'Newest'), (ListingSort.priceAsc, 'Price: low to high'), (ListingSort.priceDesc, 'Price: high to low')];
    final sortName = sorts.where((s) => s.$1 == filters.sort).map((s) => s.$2).firstOrNull ?? 'Nearest';
    final gap = SizedBox(height: b.spacing.md);
    final header = <Widget>[
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: b.spacing.md,
        runSpacing: b.spacing.sm,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('$what ${filters.purpose.heading}$where', style: text.titleLarge),
            Text('${r.found} ${r.found == 1 ? 'home' : 'homes'}', style: text.labelLarge),
          ]),
          PopupMenuButton<ListingSort>(
            tooltip: 'Sort',
            initialValue: filters.sort,
            onSelected: (s) => onChange(_edit(filters, sort: s)),
            itemBuilder: (_) => [for (final (value, label) in sorts) PopupMenuItem(value: value, child: Text(label))],
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: b.spacing.sm),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.swap_vert, size: 20),
                SizedBox(width: b.spacing.xs),
                Text(sortName, style: text.labelLarge),
                const Icon(Icons.arrow_drop_down, size: 20),
              ]),
            ),
          ),
        ],
      ),
      _ActiveFilters(filters: filters, onChange: onChange),
      gap,
    ];
    final empty = Padding(
      padding: EdgeInsets.symmetric(vertical: b.spacing.xxl),
      child: Text('Nothing matches yet. Try fewer filters.', style: text.bodyMedium, textAlign: TextAlign.center),
    );
    // Room at the bottom for the Map pill on phones.
    const bottom = 96.0;

    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 960) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(b.spacing.gutter, b.spacing.md, b.spacing.md, bottom),
              children: [
                ...header,
                if (r.hits.isEmpty) empty,
                for (final l in r.hits) ...[ListingCard(listing: l, layout: CardLayout.wide), gap],
              ],
            ),
          ),
          // Beside the homes, not among them: alerts, then the advert space.
          SizedBox(
            width: 320,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(b.spacing.md, b.spacing.md, b.spacing.gutter, bottom),
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
      final purposes = [for (final p in Purpose.values) if (features.isOn(p.feature)) p];
      // Whole rows between adverts: five homes on a phone, six when two across.
      final chunk = cols == 1 ? AdSlot.every : AdSlot.every + 1;
      return ListView(
        padding: EdgeInsets.fromLTRB(b.spacing.gutter, b.spacing.md, b.spacing.gutter, bottom),
        children: [
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
        for (final l in listings)
          SizedBox(width: width, child: ListingCard(listing: l, onOpen: onOpen == null ? null : () => onOpen!(l))),
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
                  child: Stack(fit: StackFit.expand, children: [PhotoCarousel(photos: photos, label: l.title), if (badge != null) badge]),
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
                  PhotoCarousel(photos: photos, label: l.title),
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

/// A card's photos: swipe on a phone, or use the arrows; dots show where you
/// are. Tapping a photo opens the home, like the rest of the card.
class PhotoCarousel extends StatefulWidget {
  const PhotoCarousel({super.key, required this.photos, required this.label});
  final List<String> photos;
  final String label;

  @override
  State<PhotoCarousel> createState() => _PhotoCarouselState();
}

class _PhotoCarouselState extends State<PhotoCarousel> {
  final _pages = PageController();
  int _at = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _move(int by) => _pages.animateToPage(_at + by, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final scheme = Theme.of(context).colorScheme;
    final n = widget.photos.length;
    final placeholder = ColoredBox(
      color: b.surfaceAlt,
      child: Center(child: Icon(Icons.home_work_outlined, size: 40, color: b.textMuted)),
    );
    if (n == 0) return placeholder;
    Widget photo(int i) => Image.network(
          widget.photos[i],
          fit: BoxFit.cover,
          semanticLabel: n == 1 ? widget.label : '${widget.label}, photo ${i + 1} of $n',
          errorBuilder: (_, __, ___) => placeholder,
        );
    if (n == 1) return photo(0);
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
        itemCount: n,
        onPageChanged: (i) => setState(() => _at = i),
        itemBuilder: (_, i) => photo(i),
      ),
      if (_at > 0) Positioned(left: b.spacing.xs, top: 0, bottom: 0, child: Center(child: arrow(Icons.chevron_left, 'Previous photo', -1))),
      if (_at < n - 1) Positioned(right: b.spacing.xs, top: 0, bottom: 0, child: Center(child: arrow(Icons.chevron_right, 'Next photo', 1))),
      Positioned(
        left: 0,
        right: 0,
        bottom: b.spacing.sm,
        child: ExcludeSemantics(
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < n; i++)
              Container(
                width: i == _at ? 8 : 6,
                height: i == _at ? 8 : 6,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(shape: BoxShape.circle, color: scheme.surface.withValues(alpha: i == _at ? 1 : 0.6)),
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
      if (f.minPriceKES != null) ('from ${formatKes(f.minPriceKES!)}', _edit(f, minPrice: null)),
      if (f.maxPriceKES != null) ('up to ${formatKes(f.maxPriceKES!)}', _edit(f, maxPrice: null)),
      if (f.furnished != null) (f.furnished! ? 'furnished' : 'unfurnished', _edit(f, furnished: null)),
      for (final a in f.amenities) (a.replaceAll('-', ' '), _edit(f, amenities: [...f.amenities]..remove(a))),
      if (f.verifiedFirst) ('verified first', _edit(f, verifiedFirst: false)),
      if (f.verifiedOnly) ('verified only', _edit(f, verifiedOnly: false)),
      if (f.floorPlan) ('floor plan', _edit(f, floorPlan: false)),
      if (f.tour) ('video or tour', _edit(f, tour: false)),
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
