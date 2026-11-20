/// Areas' outlines (geofences) and map positions: whether a pin is inside an
/// area, drawing an outline whose edges never cross, and reading a position
/// pasted from a map. The Functions run the same checks (model/geo.ts).
library;

import 'dart:math' as math;

import 'geo.dart';

/// True when [p] is inside the closed outline [poly] (ray casting).
bool insideOutline(GeoPoint p, List<GeoPoint> poly) {
  var inside = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final a = poly[i], b = poly[j];
    if ((a.lat > p.lat) != (b.lat > p.lat) && p.lng < (b.lng - a.lng) * (p.lat - a.lat) / (b.lat - a.lat) + a.lng) inside = !inside;
  }
  return inside;
}

double _dist(GeoPoint a, GeoPoint b) => math.sqrt(math.pow(a.lng - b.lng, 2) + math.pow(a.lat - b.lat, 2));

/// True when two of the outline's edges cross.
bool outlineCrosses(List<GeoPoint> c) {
  final n = c.length;
  if (n < 4) return false;
  double cross(GeoPoint o, GeoPoint a, GeoPoint b) => (a.lng - o.lng) * (b.lat - o.lat) - (a.lat - o.lat) * (b.lng - o.lng);
  bool crosses(GeoPoint p1, GeoPoint p2, GeoPoint q1, GeoPoint q2) {
    final d1 = cross(q1, q2, p1), d2 = cross(q1, q2, p2), d3 = cross(p1, p2, q1), d4 = cross(p1, p2, q2);
    return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0));
  }

  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      if (j == i + 1 || (i == 0 && j == n - 1)) continue;
      if (crosses(c[i], c[(i + 1) % n], c[j], c[(j + 1) % n])) return true;
    }
  }
  return false;
}

/// [corners] as they are when the edges do not cross; otherwise in order
/// around their middle, which never crosses.
List<GeoPoint> untangleOutline(List<GeoPoint> corners) {
  if (!outlineCrosses(corners)) return corners;
  final cx = corners.map((p) => p.lng).reduce((a, b) => a + b) / corners.length;
  final cy = corners.map((p) => p.lat).reduce((a, b) => a + b) / corners.length;
  return [...corners]..sort((a, b) => math.atan2(a.lat - cy, a.lng - cx).compareTo(math.atan2(b.lat - cy, b.lng - cx)));
}

/// Adds [p] where it lengthens the outline least (between its two nearest
/// corners), so a new corner never makes the edges cross.
List<GeoPoint> addOutlineCorner(List<GeoPoint> corners, GeoPoint p) {
  if (corners.length < 3) return untangleOutline([...corners, p]);
  var best = 0;
  var cost = double.infinity;
  for (var i = 0; i < corners.length; i++) {
    final a = corners[i], b = corners[(i + 1) % corners.length];
    final c = _dist(a, p) + _dist(p, b) - _dist(a, b);
    if (c < cost) {
      cost = c;
      best = i + 1;
    }
  }
  return untangleOutline([...corners.sublist(0, best), p, ...corners.sublist(best)]);
}

/// The middle of an outline's corners: a sensible centre for an area.
GeoPoint outlineMiddle(List<GeoPoint> c) =>
    GeoPoint(c.map((p) => p.lat).reduce((a, b) => a + b) / c.length, c.map((p) => p.lng).reduce((a, b) => a + b) / c.length);

final _pair = RegExp(r'(-?\d{1,2}(?:\.\d+)?)\s*[, ]\s*(-?\d{1,3}(?:\.\d+)?)');

/// A position from what someone pasted: "-1.2921, 36.7856", or a Google Maps
/// link with the place (`!3d…!4d…`, `@lat,lng`, `?q=lat,lng`, `ll=`). Null
/// when there is none (a short maps.app.goo.gl link has to be opened first).
GeoPoint? parseMapPosition(String input) {
  final s = Uri.decodeFull(input.trim());
  GeoPoint? ok(String? a, String? b) {
    final lat = double.tryParse(a ?? ''), lng = double.tryParse(b ?? '');
    if (lat == null || lng == null || lat.abs() > 90 || lng.abs() > 180 || (lat == 0 && lng == 0)) return null;
    return GeoPoint(lat, lng);
  }

  // The marked place beats the map's centre.
  final pin = RegExp(r'!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)').firstMatch(s);
  if (pin != null) return ok(pin[1], pin[2]);
  for (final re in [RegExp(r'[?&](?:q|query|ll|destination|center)=(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)'), RegExp(r'@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)')]) {
    final m = re.firstMatch(s);
    if (m != null) return ok(m[1], m[2]);
  }
  if (s.contains('://')) return null;
  final m = _pair.firstMatch(s);
  return m == null ? null : ok(m[1], m[2]);
}

/// The areas whose outline holds [p] (usually one).
List<T> areasHolding<T>(GeoPoint p, Iterable<T> areas, List<GeoPoint> Function(T) outline) =>
    [for (final a in areas) if (outline(a).length >= 3 && insideOutline(p, outline(a))) a];
