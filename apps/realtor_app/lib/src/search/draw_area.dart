import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Draw area: the least corners a drawn area takes before it can be searched.
const minDrawCorners = 4;

// Over a city, longitude and latitude can be treated as flat x and y.
double _x(LatLng p) => p.longitude;
double _y(LatLng p) => p.latitude;
double _dist(LatLng a, LatLng b) => math.sqrt(math.pow(_x(a) - _x(b), 2) + math.pow(_y(a) - _y(b), 2));

/// Adds [p] where it lengthens the outline least: between the two corners
/// nearest to it along an edge, so a new corner never makes the edges cross
/// the way joining corners in the order they were tapped can.
List<LatLng> addCorner(List<LatLng> corners, LatLng p) {
  if (corners.length < 3) return untangle([...corners, p]);
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
  return untangle([...corners.sublist(0, best), p, ...corners.sublist(best)]);
}

/// True when two of the outline's edges cross.
bool selfIntersects(List<LatLng> c) {
  final n = c.length;
  if (n < 4) return false;
  double cross(LatLng o, LatLng a, LatLng b) => (_x(a) - _x(o)) * (_y(b) - _y(o)) - (_y(a) - _y(o)) * (_x(b) - _x(o));
  bool crosses(LatLng p1, LatLng p2, LatLng q1, LatLng q2) {
    final d1 = cross(q1, q2, p1), d2 = cross(q1, q2, p2), d3 = cross(p1, p2, q1), d4 = cross(p1, p2, q2);
    return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0));
  }

  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      // Edges that share a corner do not count.
      if (j == i + 1 || (i == 0 && j == n - 1)) continue;
      if (crosses(c[i], c[(i + 1) % n], c[j], c[(j + 1) % n])) return true;
    }
  }
  return false;
}

/// [corners] as they are when the edges do not cross; otherwise put in
/// order around their middle, which never crosses.
List<LatLng> untangle(List<LatLng> corners) {
  if (!selfIntersects(corners)) return corners;
  final cx = corners.map(_x).reduce((a, b) => a + b) / corners.length;
  final cy = corners.map(_y).reduce((a, b) => a + b) / corners.length;
  return [...corners]..sort((a, b) => math.atan2(_y(a) - cy, _x(a) - cx).compareTo(math.atan2(_y(b) - cy, _x(b) - cx)));
}
