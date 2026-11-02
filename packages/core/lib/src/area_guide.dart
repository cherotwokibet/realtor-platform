/// An area guide (P3-s05) as managers edit it in the admin and `saveArea`
/// stores it. Median rent and listing count are the nightly job's, shown
/// here but never sent.
library;

final _areaSlug = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');

class AreaGuide {
  const AreaGuide({
    this.slug,
    this.name = '',
    this.county = '',
    this.lat = 0,
    this.lng = 0,
    this.guide = '',
    this.amenities = const [],
    this.medianRentKES,
    this.listings = 0,
  });

  /// Null for a new area; the Function makes it from the name.
  final String? slug;
  final String name, county, guide;
  final double lat, lng;
  final List<String> amenities;
  final int? medianRentKES;
  final int listings;

  factory AreaGuide.fromDoc(String slug, Map<String, Object?> d) {
    final c = (d['centre'] as Map?) ?? const {};
    final s = (d['stats'] as Map?) ?? const {};
    return AreaGuide(
      slug: slug,
      name: d['name'] as String? ?? slug,
      county: d['county'] as String? ?? '',
      lat: (c['lat'] as num?)?.toDouble() ?? 0,
      lng: (c['lng'] as num?)?.toDouble() ?? 0,
      guide: d['guide'] as String? ?? '',
      amenities: [for (final a in (d['amenities'] as List<Object?>?) ?? const []) '$a'],
      medianRentKES: (s['medianRentKES'] as num?)?.toInt(),
      listings: (s['listings'] as num?)?.toInt() ?? 0,
    );
  }

  /// What is wrong, by field, as `saveArea` would refuse it.
  Map<String, String> problems() => {
        if (name.trim().length < 2 || name.trim().length > 60) 'name': 'Use 2 to 60 characters.',
        if (county.trim().length < 2 || county.trim().length > 40) 'county': 'Enter the county.',
        if (lat < -5 || lat > 5 || lng < 33 || lng > 42) 'location': 'A position in Kenya, e.g. -1.2921, 36.7856.',
        if (guide.length > 5000) 'guide': 'Under 5,000 characters.',
        if (amenities.length > 30 || amenities.any((a) => a.length > 60)) 'amenities': 'Up to 30, each under 60 characters.',
        if (slug != null && !_areaSlug.hasMatch(slug!)) 'slug': 'Not an area id.',
      };

  Map<String, Object?> toCallable() => {
        if (slug != null) 'slug': slug,
        'name': name.trim(),
        'county': county.trim(),
        'lat': lat,
        'lng': lng,
        'guide': guide.trim(),
        'amenities': [for (final a in amenities) if (a.trim().isNotEmpty) a.trim()],
      };
}
