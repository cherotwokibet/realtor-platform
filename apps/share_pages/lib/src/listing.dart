import 'package:realtor_core/realtor_core.dart';

/// What a share page needs about one live listing (read from Firestore).
class ShareListing {
  const ShareListing({
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
    this.estate,
    this.depositMonths,
    this.amenities = const [],
    this.photos = const [],
    this.verified = false,
    this.updatedAt,
  });

  final String id, slug, title, type, area;
  final Purpose purpose;
  final int beds, baths, priceKES;
  final int? depositMonths;
  final double lat, lng;
  final String? estate;
  final List<String> amenities;

  /// Storage paths of the media pipeline's `card` / `full` variants.
  final List<({String card, String full})> photos;
  final bool verified;
  final DateTime? updatedAt;
}

/// An area guide (areas/{slug}).
class ShareArea {
  const ShareArea({
    required this.slug,
    required this.name,
    required this.county,
    required this.lat,
    required this.lng,
    this.guide = '',
    this.medianRentKES,
  });
  final String slug, name, county, guide;
  final double lat, lng;
  final int? medianRentKES;
}

/// One URL in sitemap.xml.
typedef SitemapEntry = ({String path, DateTime? lastModified});

/// Where share pages read from: Firestore in production, fixed lists in
/// tests and local runs.
abstract interface class ListingSource {
  Future<ShareListing?> bySlug(String slug);
  Future<ShareArea?> area(String slug);

  /// Live listings in an area, newest first, at most [limit].
  Future<List<ShareListing>> liveInArea(String slug, {int limit = 24});

  /// Every live listing and every area.
  Future<List<SitemapEntry>> sitemapEntries();
}

class InMemoryListingSource implements ListingSource {
  InMemoryListingSource(this.listings, {this.areas = const []});
  final List<ShareListing> listings;
  final List<ShareArea> areas;

  @override
  Future<ShareListing?> bySlug(String slug) async {
    for (final l in listings) {
      if (l.slug == slug) return l;
    }
    return null;
  }

  @override
  Future<ShareArea?> area(String slug) async {
    for (final a in areas) {
      if (a.slug == slug) return a;
    }
    return null;
  }

  @override
  Future<List<ShareListing>> liveInArea(String slug, {int limit = 24}) async =>
      listings.where((l) => l.area == slug).take(limit).toList();

  @override
  Future<List<SitemapEntry>> sitemapEntries() async => [
        for (final a in areas) (path: '/area/${a.slug}', lastModified: null),
        for (final l in listings) (path: '/listing/${l.slug}', lastModified: l.updatedAt),
      ];
}
