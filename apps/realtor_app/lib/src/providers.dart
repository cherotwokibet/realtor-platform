import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_core/realtor_core.dart';

import 'package:url_launcher/url_launcher.dart';

import 'listing/demo_listings.dart';
import 'search/demo_search.dart';

/// Overridden in main() with the tenant loaded from assets.
final tenantProvider = Provider<TenantConfig>((ref) => throw UnimplementedError('tenantProvider not overridden'));

/// Demo data until the tenant's Typesense host is configured (P2-s05, D4).
final listingSearchProvider = Provider<ListingSearch>((ref) => DemoListingSearch());

final searchResultsProvider = FutureProvider.family<SearchResult, ListingFilters>(
  (ref, filters) => ref.watch(listingSearchProvider).search(filters),
);

/// Demo listing details until the app reads Firestore (P4).
final listingRepositoryProvider = Provider<ListingRepository>((ref) => DemoListingRepository());

final listingDetailProvider = FutureProvider.family<ListingDetail?, String>(
  (ref, slug) => ref.watch(listingRepositoryProvider).bySlug(slug),
);

final areaProvider = FutureProvider.family<AreaGuide?, String>((ref, slug) => ref.watch(listingRepositoryProvider).area(slug));

final agentProvider = FutureProvider.family<AgentProfile?, String>((ref, id) => ref.watch(listingRepositoryProvider).agent(id));

/// Area slug -> name, for reading area names out of typed searches. Empty
/// until loaded or when it fails: words then stay free text, which still matches.
final areaNamesProvider = FutureProvider<Map<String, String>>((ref) async {
  try {
    return {
      for (final a in await ref.watch(listingRepositoryProvider).areas())
        if (a.slug != null) a.slug!: a.name
    };
  } on Exception {
    return const {};
  }
});

/// Published off-plan projects, cheapest first (P5-s06).
final projectsProvider = FutureProvider<List<OffPlanProject>>((ref) => ref.watch(listingRepositoryProvider).projects());

final projectProvider = FutureProvider.family<OffPlanProject?, String>((ref, slug) => ref.watch(listingRepositoryProvider).project(slug));

/// The home page's Hot Properties: live homes a manager marked hot, newest first.
final hotHomesProvider = FutureProvider<List<ListingSummary>>((ref) async {
  final live = await ref.watch(listingRepositoryProvider).live(limit: 500);
  return live.where((l) => l.hot).toList();
});

/// Featured homes (managers feature them for some days), for the home page's Featured row.
final featuredHomesProvider = FutureProvider<List<ListingSummary>>((ref) async {
  final live = await ref.watch(listingRepositoryProvider).live(limit: 500);
  return live.where((l) => l.featured).toList();
});

/// The realtor's Recommended picks (managers choose them in the admin).
final recommendedHomesProvider = FutureProvider<List<ListingSummary>>((ref) async {
  final live = await ref.watch(listingRepositoryProvider).live(limit: 500);
  return live.where((l) => l.recommended).toList();
});

/// Live listings in an area (`area`) or by an agent (`agent`), newest first.
final liveListingsProvider = FutureProvider.family<List<ListingSummary>, ({String? area, String? agent})>(
  (ref, q) => ref.watch(listingRepositoryProvider).live(area: q.area, agentId: q.agent),
);

/// Listing reviews: demo ones until the app reads Firestore.
final listingReviewsProvider = Provider<ListingReviews>((ref) => DemoListingReviews());

final reviewsForListingProvider = FutureProvider.family<List<ListingReview>, String>((ref, id) => ref.watch(listingReviewsProvider).forListing(id));

/// Leads stay on the phone until the app calls the Functions (P4).
final leadRepositoryProvider = Provider<LeadRepository>((ref) => DemoLeadRepository());

/// Opens tel: and wa.me links; replaced in tests.
final urlOpenerProvider = Provider<Future<bool> Function(Uri)>(
  (ref) => (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// The time, for the viewing days on offer; replaced in tests.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
