/// Small geometry helpers for map search: no map SDK needed, so the same
/// code filters demo data, validates URLs and draws on any map widget.
library;

import 'dart:math' as math;

class GeoPoint {
  const GeoPoint(this.lat, this.lng);
  final double lat, lng;

  @override
  bool operator ==(Object other) => other is GeoPoint && other.lat == lat && other.lng == lng;
  @override
  int get hashCode => Object.hash(lat, lng);
  @override
  String toString() => '$lat,$lng';
}

/// Great-circle distance in km (haversine).
double distanceKm(GeoPoint a, GeoPoint b) {
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(b.lat - a.lat), dLng = rad(b.lng - a.lng);
  final h = math.pow(math.sin(dLat / 2), 2) + math.cos(rad(a.lat)) * math.cos(rad(b.lat)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * 6371 * math.asin(math.sqrt(h));
}

/// Ray casting. The polygon is implicitly closed; city-sized areas only, so
/// treating lat/lng as planar is accurate enough.
bool pointInPolygon(GeoPoint p, List<GeoPoint> polygon) {
  if (polygon.length < 3) return false;
  var inside = false;
  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final a = polygon[i], b = polygon[j];
    if ((a.lat > p.lat) != (b.lat > p.lat) && p.lng < (b.lng - a.lng) * (p.lat - a.lat) / (b.lat - a.lat) + a.lng) {
      inside = !inside;
    }
  }
  return inside;
}
