import 'listing_filters.dart';

/// One row in a results list (what the Typesense search document carries).
class ListingSummary {
  const ListingSummary({
    required this.id,
    required this.slug,
    required this.title,
    required this.purpose,
    required this.type,
    required this.beds,
    required this.baths,
    required this.priceKES,
    required this.area,
    required this.lat,
    required this.lng,
    this.verified = false,
    this.featured = false,
    this.amenities = const [],
    this.thumb,
    this.blurhash,
  });

  final String id, slug, title, type, area;
  final Purpose purpose;
  final int beds, baths, priceKES;
  final double lat, lng;
  final bool verified, featured;
  final List<String> amenities;
  final String? thumb, blurhash;
}

class FacetCount {
  const FacetCount(this.value, this.count);
  final String value;
  final int count;
}

class SearchResult {
  const SearchResult({required this.found, required this.hits, this.facets = const {}});
  final int found;
  final List<ListingSummary> hits;

  /// Field name (type, area, beds, ...) -> counts, most common first.
  final Map<String, List<FacetCount>> facets;
}

/// Where results come from: Typesense in production, demo data until the
/// tenant's search host is configured, fakes in tests.
abstract interface class ListingSearch {
  Future<SearchResult> search(ListingFilters filters);
}
