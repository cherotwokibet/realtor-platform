import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';

import '../providers.dart';
import '../account/account_screen.dart';
import '../saved/favourites.dart';
import 'purpose.dart';
import '../nav.dart';
import 'filters_sheet.dart';
import 'results_map.dart';

/// Results for a filter URL. Every change of filter is a new URL, so the
/// browser back button, shared links and app deep links all work.
class ResultsScreen extends ConsumerWidget {
  const ResultsScreen({super.key, required this.filters});
  final ListingFilters filters;

  // A changed filter or sort replaces this page, so Back returns to where
  // the search started, not through every filter tried.
  void _go(BuildContext context, ListingFilters f) => context.replace(f.toUri().toString());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final result = ref.watch(searchResultsProvider(filters));
    final onMap = ref.watch(resultsOnMapProvider);
    final where = filters.areas.length == 1 ? ' in ${areaName(filters.areas.single)}' : '';
    final what = filters.types.length == 1 ? '${typeName(filters.types.single)}s' : 'Homes';
    Future<void> filter(FilterSection section) async {
      final next = await showFiltersSheet(context, filters, section: section);
      if (next != null && context.mounted) _go(context, next.copyWith(page: 1));
    }

    return Scaffold(
      appBar: AppBar(
        leading: const AppBack(),
        title: Text('$what ${filters.purpose.heading}$where'),
        actions: [
          PopupMenuButton<ListingSort>(
            tooltip: 'Sort',
            icon: const Icon(Icons.swap_vert),
            initialValue: filters.sort,
            onSelected: (s) => _go(context, filters.copyWith(sort: s)),
            itemBuilder: (_) => const [
              PopupMenuItem(value: ListingSort.newest, child: Text('Newest')),
              PopupMenuItem(value: ListingSort.priceAsc, child: Text('Price: low to high')),
              PopupMenuItem(value: ListingSort.priceDesc, child: Text('Price: high to low')),
            ],
          ),
        ],
      ),
      // List and map switch with one pill over the results, where a thumb
      // reaches it, as the big property portals do.
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('map-toggle'),
        tooltip: onMap ? 'List' : 'Map',
        icon: Icon(onMap ? Icons.view_list_outlined : Icons.map_outlined),
        label: Text(onMap ? 'List' : 'Map'),
        onPressed: () => ref.read(resultsOnMapProvider.notifier).set(!onMap),
      ),
      body: Column(children: [
        Align(
          alignment: Alignment.centerLeft,
          child: _FilterBar(filters: filters, onPurpose: (p) => _go(context, _withPurpose(filters, p)), onOpen: filter),
        ),
        Expanded(
          child: result.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Search is not available right now.', style: text.bodyMedium)),
            data: (r) => onMap
                ? Column(children: [
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: b.spacing.gutter),
                      child: _ActiveFilters(filters: filters, onChange: (f) => _go(context, f)),
                    ),
                    SizedBox(height: b.spacing.sm),
                    Expanded(child: ResultsMap(hits: r.hits, filters: filters, onChange: (f) => _go(context, f))),
                  ])
                : ListView(
                    // Room at the bottom for the Map pill.
                    padding: EdgeInsets.fromLTRB(b.spacing.gutter, b.spacing.sm, b.spacing.gutter, 96),
                    children: [
                      _ActiveFilters(filters: filters, onChange: (f) => _go(context, f)),
                      SizedBox(height: b.spacing.md),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: b.spacing.md,
                        runSpacing: b.spacing.sm,
                        children: [Text('${r.found} ${r.found == 1 ? 'home' : 'homes'}', style: text.labelLarge), AlertButton(filters: filters)],
                      ),
                      SizedBox(height: b.spacing.md),
                      if (r.hits.isEmpty)
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: b.spacing.xxl),
                          child: Text('Nothing matches yet. Try fewer filters.', style: text.bodyMedium, textAlign: TextAlign.center),
                        ),
                      ListingGrid(listings: r.hits),
                    ],
                  ),
          ),
        ),
      ]),
    );
  }
}

/// The same search for another purpose. Prices and types rarely carry over
/// (a month's rent is not a sale price), so those start again.
ListingFilters _withPurpose(ListingFilters f, Purpose p) => ListingFilters(
      purpose: p,
      q: f.q,
      areas: f.areas,
      minBeds: f.minBeds,
      amenities: f.amenities,
      verifiedOnly: f.verifiedOnly,
      near: f.near,
      polygon: f.polygon,
      sort: f.sort,
    );

/// Search, Filters, the purpose, and a button each for type, beds and price,
/// in one row that scrolls sideways on phones.
class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.filters, required this.onPurpose, required this.onOpen});
  final ListingFilters filters;
  final ValueChanged<Purpose> onPurpose;
  final ValueChanged<FilterSection> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = context.brand;
    final features = ref.watch(tenantProvider).features;
    final purposes = [
      for (final p in Purpose.values)
        if (features.isOn(p.feature)) p
    ];
    final f = filters;
    final count =
        [f.types.isNotEmpty, f.minBeds != null, f.minPriceKES != null || f.maxPriceKES != null, f.amenities.isNotEmpty, f.verifiedOnly].where((x) => x).length;
    String priceLabel() => switch ((f.minPriceKES, f.maxPriceKES)) {
          (null, null) => 'Price',
          (final min?, null) => 'From ${formatKes(min, compact: true)}',
          (null, final max?) => 'Up to ${formatKes(max, compact: true)}',
          (final min?, final max?) => '${formatKes(min, compact: true)}–${formatKes(max, compact: true)}',
        };
    Widget menu(String label, bool active, VoidCallback onTap, {Key? key}) => FilterChip(
          key: key,
          label: Row(mainAxisSize: MainAxisSize.min, children: [Text(label), const Icon(Icons.arrow_drop_down, size: 18)]),
          selected: active,
          showCheckmark: false,
          onSelected: (_) => onTap(),
        );
    return SingleChildScrollView(
      key: const Key('filter-bar'),
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: b.spacing.gutter, vertical: b.spacing.sm),
      child: Row(children: [
        FilledButton.icon(
          key: const Key('filter-search'),
          onPressed: () => onOpen(FilterSection.all),
          icon: const Icon(Icons.search),
          label: const Text('Search'),
        ),
        SizedBox(width: b.spacing.sm),
        OutlinedButton.icon(
          key: const Key('filter-all'),
          onPressed: () => onOpen(FilterSection.all),
          icon: const Icon(Icons.tune),
          label: Text(count == 0 ? 'Filters' : 'Filters ($count)'),
        ),
        SizedBox(width: b.spacing.sm),
        if (purposes.length > 1) ...[
          PopupMenuButton<Purpose>(
            key: const Key('filter-purpose'),
            tooltip: 'Rent, buy or BnB',
            initialValue: f.purpose,
            onSelected: onPurpose,
            itemBuilder: (_) => [for (final p in purposes) PopupMenuItem(value: p, child: Text(p.label))],
            child: Chip(
              label: Row(mainAxisSize: MainAxisSize.min, children: [Text(f.purpose.label), const Icon(Icons.arrow_drop_down, size: 18)]),
            ),
          ),
          SizedBox(width: b.spacing.sm),
        ],
        menu(f.types.isEmpty ? 'Property type' : f.types.map(typeName).join(', '), f.types.isNotEmpty, () => onOpen(FilterSection.type),
            key: const Key('filter-type')),
        SizedBox(width: b.spacing.sm),
        menu(f.minBeds == null ? 'Beds' : '${f.minBeds}+ beds', f.minBeds != null, () => onOpen(FilterSection.beds), key: const Key('filter-beds')),
        SizedBox(width: b.spacing.sm),
        menu(priceLabel(), f.minPriceKES != null || f.maxPriceKES != null, () => onOpen(FilterSection.price), key: const Key('filter-price')),
      ]),
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

/// A home as a card: its photo with the Verified badge and the save heart on
/// it, then the price, beds and baths, the title and the area, and Call and
/// WhatsApp once the realtor's numbers are set. [compact] is the short,
/// photo-beside-words card the map shows over its pins.
class ListingCard extends ConsumerWidget {
  const ListingCard({super.key, required this.listing, this.onOpen, this.compact = false});
  final ListingSummary listing;

  /// Called as the card opens its listing (e.g. to count a recommendation).
  final VoidCallback? onOpen;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final tenant = ref.watch(tenantProvider);
    final l = listing;
    void open() {
      onOpen?.call();
      context.push('/listing/${l.slug}');
    }

    final placeholder = ColoredBox(
      color: b.surfaceAlt,
      child: Center(child: Icon(Icons.home_work_outlined, size: 40, color: b.textMuted)),
    );
    final photo = l.thumb == null ? placeholder : Image.network(l.thumb!, fit: BoxFit.cover, semanticLabel: l.title, errorBuilder: (_, __, ___) => placeholder);
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
    final title = Text(l.title, style: text.titleSmall, maxLines: compact ? 1 : 2, overflow: TextOverflow.ellipsis);

    if (compact) {
      return Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: open,
          child: SizedBox(
            height: 120,
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(width: 130, child: photo),
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
    }

    final open0 = ref.read(urlOpenerProvider);
    final whatsapp = tenant.whatsappLink('Hello ${tenant.name}, I am interested in ${l.title}: https://${tenant.shareDomain}/listing/${l.slug}');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: open,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AspectRatio(
            aspectRatio: 16 / 10,
            child: Stack(fit: StackFit.expand, children: [
              photo,
              if (l.verified) Positioned(left: b.spacing.sm, top: b.spacing.sm, child: const VerifiedBadge()),
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
              if (tenant.hasContactNumbers) ...[
                SizedBox(height: b.spacing.md),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => open0(Uri(scheme: 'tel', path: tenant.phone)),
                      icon: const Icon(Icons.call_outlined),
                      label: const Text('Call'),
                    ),
                  ),
                  SizedBox(width: b.spacing.sm),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: whatsapp == null ? null : () => open0(whatsapp),
                      icon: const Icon(Icons.chat_outlined),
                      label: const Text('WhatsApp'),
                    ),
                  ),
                ]),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

/// What the search is filtering by, beyond the type chips above: each one a
/// chip whose x removes it, so a typed search shows what was understood
/// (P7-s01) and can be adjusted.
class _ActiveFilters extends StatelessWidget {
  const _ActiveFilters({required this.filters, required this.onChange});
  final ListingFilters filters;
  final ValueChanged<ListingFilters> onChange;

  ListingFilters _with({
    List<String>? areas,
    bool clearBeds = false,
    bool clearMin = false,
    bool clearMax = false,
    List<String>? amenities,
    bool? verifiedOnly,
    bool clearQ = false,
    bool clearPolygon = false,
  }) {
    final f = filters;
    return ListingFilters(
      purpose: f.purpose,
      q: clearQ ? null : f.q,
      types: f.types,
      areas: areas ?? f.areas,
      minBeds: clearBeds ? null : f.minBeds,
      minPriceKES: clearMin ? null : f.minPriceKES,
      maxPriceKES: clearMax ? null : f.maxPriceKES,
      amenities: amenities ?? f.amenities,
      verifiedOnly: verifiedOnly ?? f.verifiedOnly,
      near: f.near,
      polygon: clearPolygon ? const [] : f.polygon,
      sort: f.sort,
    );
  }

  @override
  Widget build(BuildContext context) {
    final f = filters;
    final chips = <(String, ListingFilters)>[
      for (final a in f.areas) (areaName(a), _with(areas: [...f.areas]..remove(a))),
      if (f.minBeds != null) ('${f.minBeds}+ bed', _with(clearBeds: true)),
      if (f.minPriceKES != null) ('from ${formatKes(f.minPriceKES!)}', _with(clearMin: true)),
      if (f.maxPriceKES != null) ('up to ${formatKes(f.maxPriceKES!)}', _with(clearMax: true)),
      for (final a in f.amenities) (a.replaceAll('-', ' '), _with(amenities: [...f.amenities]..remove(a))),
      if (f.verifiedOnly) ('verified only', _with(verifiedOnly: false)),
      if (f.q != null) ('"${f.q}"', _with(clearQ: true)),
      if (f.polygon.isNotEmpty) ('Drawn area', _with(clearPolygon: true)),
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
