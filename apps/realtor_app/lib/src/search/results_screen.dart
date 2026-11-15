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

    return Scaffold(
      appBar: AppBar(
        leading: const AppBack(),
        title: Text('$what ${filters.purpose.heading}$where'),
        actions: [
          IconButton(
            tooltip: onMap ? 'List' : 'Map',
            icon: Icon(onMap ? Icons.view_list_outlined : Icons.map_outlined),
            onPressed: () => ref.read(resultsOnMapProvider.notifier).set(!onMap),
          ),
          PopupMenuButton<ListingSort>(
            tooltip: 'Sort',
            icon: const Icon(Icons.sort),
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
      body: result.when(
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
          padding: EdgeInsets.all(b.spacing.gutter),
          children: [
            Wrap(
              spacing: b.spacing.sm,
              runSpacing: b.spacing.sm,
              children: [
                for (final t in r.facets['type'] ?? const <FacetCount>[])
                  FilterChip(
                    label: Text('${typeName(t.value)} (${t.count})'),
                    selected: filters.types.contains(t.value),
                    onSelected: (on) => _go(
                      context,
                      filters.copyWith(types: on ? [...filters.types, t.value] : (List.of(filters.types)..remove(t.value))),
                    ),
                  ),
              ],
            ),
            _ActiveFilters(filters: filters, onChange: (f) => _go(context, f)),
            SizedBox(height: b.spacing.md),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: b.spacing.md,
              runSpacing: b.spacing.sm,
              children: [Text('${r.found} ${r.found == 1 ? 'home' : 'homes'}', style: text.labelLarge), AlertButton(filters: filters)],
            ),
            SizedBox(height: b.spacing.sm),
            if (r.hits.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: b.spacing.xxl),
                child: Text('Nothing matches yet. Try fewer filters.', style: text.bodyMedium, textAlign: TextAlign.center),
              ),
            for (final l in r.hits) ...[
              ListingCard(listing: l),
              SizedBox(height: b.spacing.md),
            ],
          ],
        ),
      ),
    );
  }
}

/// A home in a list (results, saved), with its save heart.
class ListingCard extends StatelessWidget {
  const ListingCard({super.key, required this.listing, this.onOpen, this.stacked = false});
  final ListingSummary listing;

  /// Called as the card opens its listing (e.g. to count a recommendation).
  final VoidCallback? onOpen;

  /// Photo above the words whatever the width (grids); otherwise a wide
  /// card puts the photo beside them.
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final l = listing;
    final beds = l.beds == 0 ? typeName(l.type) : '${l.beds} bed · ${l.baths} bath';
    final words = Padding(
      padding: EdgeInsets.all(b.spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (l.verified) ...[const VerifiedBadge(), SizedBox(height: b.spacing.sm)],
          Row(children: [Expanded(child: Text(l.title, style: text.titleMedium)), FavouriteButton(listing: l)]),
          SizedBox(height: b.spacing.xs),
          PriceText(l.priceKES, period: l.purpose.period, compact: l.purpose == Purpose.sale),
          SizedBox(height: b.spacing.xs),
          Text('$beds · ${areaName(l.area)}', style: text.bodySmall),
        ],
      ),
    );
    // The first photo, when the listing has one; a quiet tile if it fails to load.
    final photo = l.thumb == null
        ? null
        : Image.network(
            l.thumb!,
            fit: BoxFit.cover,
            semanticLabel: l.title,
            errorBuilder: (_, __, ___) => ColoredBox(color: b.surfaceAlt, child: Icon(Icons.home_work_outlined, color: b.textMuted)),
          );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          onOpen?.call();
          context.push('/listing/${l.slug}');
        },
        child: photo == null
            ? words
            : LayoutBuilder(
                builder: (context, c) => stacked || c.maxWidth < 560
                    ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [AspectRatio(aspectRatio: 16 / 10, child: photo), words])
                    : IntrinsicHeight(
                        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          SizedBox(width: 240, child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 150), child: photo)),
                          Expanded(child: words),
                        ]),
                      ),
              ),
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
        for (final (label, without) in chips)
          InputChip(label: Text(label), onDeleted: () => onChange(without), deleteButtonTooltipMessage: 'Remove $label'),
      ]),
    );
  }
}
