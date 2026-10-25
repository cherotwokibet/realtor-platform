import 'package:realtor_core/realtor_core.dart';
import 'package:test/test.dart';

void main() {
  const square = [GeoPoint(-1.28, 36.80), GeoPoint(-1.28, 36.84), GeoPoint(-1.30, 36.84), GeoPoint(-1.30, 36.80)];

  test('pointInPolygon', () {
    expect(pointInPolygon(const GeoPoint(-1.29, 36.82), square), isTrue);
    expect(pointInPolygon(const GeoPoint(-1.31, 36.82), square), isFalse);
    expect(pointInPolygon(const GeoPoint(-1.29, 36.90), square), isFalse);
    expect(pointInPolygon(const GeoPoint(-1.29, 36.82), square.take(2).toList()), isFalse);
  });

  test('pointInPolygon on a concave shape', () {
    const l = [GeoPoint(0, 0), GeoPoint(0, 2), GeoPoint(1, 2), GeoPoint(1, 1), GeoPoint(2, 1), GeoPoint(2, 0)];
    expect(pointInPolygon(const GeoPoint(0.5, 1.5), l), isTrue);
    expect(pointInPolygon(const GeoPoint(1.5, 1.5), l), isFalse);
  });

  test('distanceKm', () {
    expect(distanceKm(const GeoPoint(-1.2864, 36.8172), const GeoPoint(-1.2864, 36.8172)), 0);
    expect(distanceKm(const GeoPoint(0, 0), const GeoPoint(0, 1)), closeTo(111.2, 0.5));
  });
}
