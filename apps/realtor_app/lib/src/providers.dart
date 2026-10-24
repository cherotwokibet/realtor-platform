import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_core/realtor_core.dart';

import 'search/demo_search.dart';

/// Overridden in main() with the tenant loaded from assets.
final tenantProvider = Provider<TenantConfig>((ref) => throw UnimplementedError('tenantProvider not overridden'));

/// Demo data until the tenant's Typesense host is configured (P2-s05, D4).
final listingSearchProvider = Provider<ListingSearch>((ref) => DemoListingSearch());

final searchResultsProvider = FutureProvider.family<SearchResult, ListingFilters>(
  (ref, filters) => ref.watch(listingSearchProvider).search(filters),
);
