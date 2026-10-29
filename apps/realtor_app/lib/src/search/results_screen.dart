import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';

import '../providers.dart';
import '../account/account_screen.dart';
import '../saved/favourites.dart';
import 'purpose.dart';

/// Results for a filter URL. Every change of filter is a new URL, so the
/// browser back button, shared links and app deep links all work.
class ResultsScreen extends ConsumerWidget {
  const ResultsScreen({super.key, required this.filters});
  final ListingFilters filters;

  void _go(BuildContext context, ListingFilters f) => context.go(f.toUri().toString());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final result = ref.watch(searchResultsProvider(filters));
    final where = filters.areas.length == 1 ? ' in ${areaName(filters.areas.single)}' : '';
    final what = filters.types.length == 1 ? '${typeName(filters.types.single)}s' : 'Homes';

    return Scaffold(
      appBar: AppBar(
        title: Text('$what ${filters.purpose.heading}$where'),
        actions: [
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
        data: (r) => ListView(
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
  const ListingCard({super.key, required this.listing});
  final ListingSummary listing;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final l = listing;
    final beds = l.beds == 0 ? typeName(l.type) : '${l.beds} bed · ${l.baths} bath';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/listing/${l.slug}'),
        child: Padding(
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
        ),
      ),
    );
  }
}
