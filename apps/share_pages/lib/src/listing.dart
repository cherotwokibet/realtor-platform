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

/// Where share pages read listings from: Firestore in production, a fixed
/// list in tests and local runs.
abstract interface class ListingSource {
  Future<ShareListing?> bySlug(String slug);
}

class InMemoryListingSource implements ListingSource {
  InMemoryListingSource(this.listings);
  final List<ShareListing> listings;

  @override
  Future<ShareListing?> bySlug(String slug) async {
    for (final l in listings) {
      if (l.slug == slug) return l;
    }
    return null;
  }
}
