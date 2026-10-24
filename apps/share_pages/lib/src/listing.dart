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
    this.agentId,
  });

  final String id, slug, title, type, area;
  final String? agentId;
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
    this.amenities = const [],
    this.medianRentKES,
  });
  final String slug, name, county, guide;

  /// Nearby places the realtor lists (malls, hospitals, transport).
  final List<String> amenities;
  final double lat, lng;
  final int? medianRentKES;
}

/// An active agent's public profile (agents/{id}). Phone numbers here are
/// the agent's business lines, which the app shows on every listing.
class ShareAgent {
  const ShareAgent({
    required this.id,
    required this.name,
    required this.earbNo,
    required this.phone,
    required this.whatsapp,
    this.languages = const ['en'],
    this.photo,
    this.rating,
    this.responseMins,
  });
  final String id, name, earbNo, phone, whatsapp;
  final List<String> languages;
  final String? photo;
  final double? rating;
  final int? responseMins;
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

  /// An active agent, else null.
  Future<ShareAgent?> agent(String id);

  /// An agent's live listings, newest first, at most [limit].
  Future<List<ShareListing>> liveByAgent(String agentId, {int limit = 24});

  /// The newest live listings, for the home page.
  Future<List<ShareListing>> latestLive({int limit = 12});

  /// Every area, by name.
  Future<List<ShareArea>> areas();

  /// Every live listing, area and active agent.
  Future<List<SitemapEntry>> sitemapEntries();
}

class InMemoryListingSource implements ListingSource {
  InMemoryListingSource(this.listings, {List<ShareArea> areas = const [], this.agents = const []}) : _areas = areas;
  final List<ShareListing> listings;
  final List<ShareArea> _areas;
  final List<ShareAgent> agents;

  @override
  Future<ShareListing?> bySlug(String slug) async {
    for (final l in listings) {
      if (l.slug == slug) return l;
    }
    return null;
  }

  @override
  Future<ShareArea?> area(String slug) async {
    for (final a in _areas) {
      if (a.slug == slug) return a;
    }
    return null;
  }

  @override
  Future<ShareAgent?> agent(String id) async {
    for (final a in agents) {
      if (a.id == id) return a;
    }
    return null;
  }

  @override
  Future<List<ShareListing>> liveByAgent(String agentId, {int limit = 24}) async =>
      listings.where((l) => l.agentId == agentId).take(limit).toList();

  @override
  Future<List<ShareListing>> latestLive({int limit = 12}) async => listings.take(limit).toList();

  @override
  Future<List<ShareArea>> areas() async => [..._areas]..sort((a, b) => a.name.compareTo(b.name));

  @override
  Future<List<ShareListing>> liveInArea(String slug, {int limit = 24}) async =>
      listings.where((l) => l.area == slug).take(limit).toList();

  @override
  Future<List<SitemapEntry>> sitemapEntries() async => [
        for (final a in _areas) (path: '/area/${a.slug}', lastModified: null),
        for (final a in agents) (path: '/agent/${a.id}', lastModified: null),
        for (final l in listings) (path: '/listing/${l.slug}', lastModified: l.updatedAt),
      ];
}
