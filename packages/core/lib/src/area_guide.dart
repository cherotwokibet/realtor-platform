/// An area guide (P3-s05) as managers edit it in the admin and `saveArea`
/// stores it. Median rent and listing count are the nightly job's, shown
/// here but never sent.
library;

import 'geo.dart';
import 'geofence.dart';

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
    this.boundary = const [],
  });

  /// Null for a new area; the Function makes it from the name.
  final String? slug;
  final String name, county, guide;
  final double lat, lng;
  final List<String> amenities;
  final int? medianRentKES;
  final int listings;

  /// The area's outline (its geofence): where listings in it must be
  /// pinned. Empty: none drawn yet, any pin goes.
  final List<GeoPoint> boundary;

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
      boundary: [
        for (final p in (d['boundary'] as List<Object?>?) ?? const [])
          if (p case {'lat': final num lat, 'lng': final num lng}) GeoPoint(lat.toDouble(), lng.toDouble()),
      ],
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
        if (boundary.isNotEmpty && boundary.length < 3) 'boundary': 'Place at least 3 corners, or clear the outline.',
        if (boundary.length > 60) 'boundary': 'At most 60 corners.',
        if (boundary.length >= 3 && outlineCrosses(boundary)) 'boundary': 'The outline crosses itself.',
        if (boundary.length >= 3 && !outlineCrosses(boundary) && !insideOutline(GeoPoint(lat, lng), boundary))
          'boundary': 'The centre must be inside the outline.',
      };

  AreaGuide copyWith({List<GeoPoint>? boundary, double? lat, double? lng}) => AreaGuide(
        slug: slug,
        name: name,
        county: county,
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
        guide: guide,
        amenities: amenities,
        medianRentKES: medianRentKES,
        listings: listings,
        boundary: boundary ?? this.boundary,
      );

  Map<String, Object?> toCallable() => {
        if (slug != null) 'slug': slug,
        'name': name.trim(),
        'county': county.trim(),
        'lat': lat,
        'lng': lng,
        'guide': guide.trim(),
        'amenities': [for (final a in amenities) if (a.trim().isNotEmpty) a.trim()],
        'boundary': boundary.length < 3 ? null : [for (final p in boundary) {'lat': p.lat, 'lng': p.lng}],
      };
}
