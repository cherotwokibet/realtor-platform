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
    this.hot = false,
    this.recommended = false,
    this.pinnedNewest = false,
    this.amenities = const [],
    this.thumb,
    this.blurhash,
    this.photos = const [],
    this.hasFloorPlan = false,
    this.hasVideo = false,
    this.has360 = false,
    this.videoPoster,
  });

  /// How many photos a card's carousel carries.
  static const maxCardPhotos = 6;

  final String id, slug, title, type, area;
  final Purpose purpose;
  final int beds, baths, priceKES;
  final double lat, lng;
  final bool verified, featured;

  /// A manager put it in the home page's Hot Properties.
  final bool hot;

  /// A manager put it in the home page's Recommended; first in Newest.
  final bool recommended, pinnedNewest;
  final List<String> amenities;
  final String? thumb, blurhash;

  /// The first few photos at card size, for the card's carousel. Empty on
  /// rows saved before cards had one; [thumb] stands in then.
  final List<String> photos;

  /// Has a floor plan; a video; a 360° tour.
  final bool hasFloorPlan, hasVideo, has360;

  /// A frame of the home's video, shown last in the card's carousel.
  final String? videoPoster;

  /// For keeping a copy on the device (saved homes).
  Map<String, Object?> toJson() => {
        'id': id,
        'slug': slug,
        'title': title,
        'purpose': purpose.value,
        'type': type,
        'beds': beds,
        'baths': baths,
        'priceKES': priceKES,
        'area': area,
        'lat': lat,
        'lng': lng,
        'verified': verified,
        if (featured) 'featured': true,
        if (hot) 'hot': true,
        if (recommended) 'recommended': true,
        if (pinnedNewest) 'pinnedNewest': true,
        'amenities': amenities,
        if (thumb != null) 'thumb': thumb,
        if (blurhash != null) 'blurhash': blurhash,
        if (photos.isNotEmpty) 'photos': photos,
        if (hasFloorPlan) 'hasFloorPlan': true,
        if (hasVideo) 'hasVideo': true,
        if (has360) 'has360': true,
        if (videoPoster != null) 'videoPoster': videoPoster,
      };

  /// Null when [j] isn't a saved row (an older or damaged copy).
  static ListingSummary? fromJson(Object? j) {
    if (j is! Map) return null;
    try {
      return ListingSummary(
        id: j['id'] as String,
        slug: j['slug'] as String,
        title: j['title'] as String,
        purpose: Purpose.values.firstWhere((p) => p.value == j['purpose']),
        type: j['type'] as String,
        beds: (j['beds'] as num).toInt(),
        baths: (j['baths'] as num).toInt(),
        priceKES: (j['priceKES'] as num).toInt(),
        area: j['area'] as String,
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        verified: j['verified'] == true,
        featured: j['featured'] == true,
        hot: j['hot'] == true,
        recommended: j['recommended'] == true,
        pinnedNewest: j['pinnedNewest'] == true,
        amenities: [for (final a in (j['amenities'] as List?) ?? const []) '$a'],
        thumb: j['thumb'] as String?,
        blurhash: j['blurhash'] as String?,
        photos: [for (final p in (j['photos'] as List?) ?? const []) '$p'],
        hasFloorPlan: j['hasFloorPlan'] == true,
        hasVideo: j['hasVideo'] == true,
        has360: j['has360'] == true,
        videoPoster: j['videoPoster'] as String?,
      );
    } on Object {
      return null;
    }
  }
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
