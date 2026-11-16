import 'dart:math' as math;

import 'package:realtor_core/realtor_core.dart';

/// In-memory search over a handful of Nairobi listings, with the same
/// filter, sort and facet behaviour as the Typesense collection. Used until
/// the tenant's search host is configured, and in widget tests.
class DemoListingSearch implements ListingSearch {
  DemoListingSearch([List<ListingSummary>? listings]) : listings = listings ?? demoListings;
  final List<ListingSummary> listings;
  static const perPage = 20;

  @override
  Future<SearchResult> search(ListingFilters f) async {
    final hits = listings.where((l) => _matches(f, l)).toList();
    final near = f.near;
    switch (f.sort) {
      case ListingSort.priceAsc:
        hits.sort((a, b) => a.priceKES.compareTo(b.priceKES));
      case ListingSort.priceDesc:
        hits.sort((a, b) => b.priceKES.compareTo(a.priceKES));
      case ListingSort.nearest when near != null:
        hits.sort((a, b) => _km(near, a).compareTo(_km(near, b)));
      default:
        hits.sort((a, b) => (b.featured ? 1 : 0) - (a.featured ? 1 : 0));
    }
    // Dart's list sort is not stable, so keep the order above within each group.
    if (f.verifiedFirst) hits.setAll(0, [...hits.where((l) => l.verified), ...hits.where((l) => !l.verified)]);
    // Like Typesense facets with the facet's own filter relaxed, so the
    // other options stay visible next to the selected one.
    List<FacetCount> facet(String Function(ListingSummary) key, ListingFilters relaxed) {
      final counts = <String, int>{};
      for (final l in listings.where((l) => _matches(relaxed, l))) {
        counts.update(key(l), (n) => n + 1, ifAbsent: () => 1);
      }
      final sorted = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      return [for (final e in sorted) FacetCount(e.key, e.value)];
    }

    return SearchResult(
      found: hits.length,
      hits: hits.skip((f.page - 1) * perPage).take(perPage).toList(),
      facets: {
        'type': facet((l) => l.type, f.copyWith(types: const [])),
        'area': facet((l) => l.area, f.copyWith(areas: const [])),
      },
    );
  }

  static bool _matches(ListingFilters f, ListingSummary l) {
    final words = (f.q ?? '').toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final text = '${l.title} ${l.area}'.toLowerCase();
    return l.purpose == f.purpose &&
        (f.types.isEmpty || f.types.contains(l.type)) &&
        (f.areas.isEmpty || f.areas.contains(l.area)) &&
        (f.minBeds == null || l.beds >= f.minBeds!) &&
        (f.minPriceKES == null || l.priceKES >= f.minPriceKES!) &&
        (f.maxPriceKES == null || l.priceKES <= f.maxPriceKES!) &&
        // Amenities are typed freely in admin ("Parking"); match any case.
        f.amenities.every((a) => l.amenities.any((x) => x.toLowerCase() == a.toLowerCase())) &&
        (!f.verifiedOnly || l.verified) &&
        (f.furnished == null || f.furnished == l.amenities.any((x) => x.toLowerCase() == 'furnished')) &&
        (!f.floorPlan || l.hasFloorPlan) &&
        (!f.tour || l.hasTour) &&
        (f.near == null || _km(f.near!, l) <= f.near!.km) &&
        (f.polygon.isEmpty || pointInPolygon(GeoPoint(l.lat, l.lng), f.polygon)) &&
        words.every(text.contains);
  }

  static double _km(GeoRadius p, ListingSummary l) {
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(l.lat - p.lat), dLng = rad(l.lng - p.lng);
    final a = math.pow(math.sin(dLat / 2), 2) + math.cos(rad(p.lat)) * math.cos(rad(l.lat)) * math.pow(math.sin(dLng / 2), 2);
    return 2 * 6371 * math.asin(math.sqrt(a));
  }
}

const demoListings = [
  ListingSummary(id: 'demo-1', slug: '2-bedroom-apartment-kilimani', title: '2 bedroom apartment, Kilimani', purpose: Purpose.rent, type: 'apartment', beds: 2, baths: 2, priceKES: 65000, area: 'kilimani', lat: -1.2901, lng: 36.7846, verified: true, featured: true, amenities: ['parking', 'borehole']),
  ListingSummary(id: 'demo-2', slug: 'bedsitter-near-kasarani-stadium', title: 'Bedsitter near Kasarani stadium', purpose: Purpose.rent, type: 'bedsitter', beds: 0, baths: 1, priceKES: 9500, area: 'kasarani', lat: -1.224, lng: 36.899),
  ListingSummary(id: 'demo-3', slug: 'single-room-south-b', title: 'Single room, South B', purpose: Purpose.rent, type: 'single-room', beds: 0, baths: 1, priceKES: 7000, area: 'south-b', lat: -1.309, lng: 36.836),
  ListingSummary(id: 'demo-4', slug: 'studio-with-wi-fi-westlands', title: 'Studio with Wi-Fi, Westlands', purpose: Purpose.shortStay, type: 'studio', beds: 0, baths: 1, priceKES: 4500, area: 'westlands', lat: -1.2666, lng: 36.8088, verified: true, amenities: ['wifi']),
  ListingSummary(id: 'demo-5', slug: '3-bedroom-maisonette-syokimau', title: '3 bedroom maisonette, Syokimau', purpose: Purpose.sale, type: 'maisonette', beds: 3, baths: 3, priceKES: 12500000, area: 'syokimau', lat: -1.356, lng: 36.933, verified: true),
  ListingSummary(id: 'demo-6', slug: '1-bedroom-apartment-ruaka', title: '1 bedroom apartment, Ruaka', purpose: Purpose.rent, type: 'apartment', beds: 1, baths: 1, priceKES: 25000, area: 'ruaka', lat: -1.206, lng: 36.779, verified: true),
  ListingSummary(id: 'demo-7', slug: '4-bedroom-townhouse-lavington', title: '4 bedroom townhouse, Lavington', purpose: Purpose.sale, type: 'townhouse', beds: 4, baths: 4, priceKES: 38000000, area: 'lavington', lat: -1.276, lng: 36.77),
  ListingSummary(id: 'demo-8', slug: '3-bedroom-apartment-kileleshwa', title: '3 bedroom apartment, Kileleshwa', purpose: Purpose.rent, type: 'apartment', beds: 3, baths: 3, priceKES: 110000, area: 'kileleshwa', lat: -1.2825, lng: 36.785, verified: true, amenities: ['parking']),
  ListingSummary(id: 'demo-9', slug: 'student-hostel-bed-kasarani', title: 'Student hostel bed, Kasarani', purpose: Purpose.rent, type: 'hostel', beds: 1, baths: 1, priceKES: 6000, area: 'kasarani', lat: -1.218, lng: 36.894),
];
