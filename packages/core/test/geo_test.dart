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

  test('distanceKm and rounding', () {
    expect(distanceKm(const GeoPoint(-1.2864, 36.8172), const GeoPoint(-1.2864, 36.8172)), 0);
    expect(distanceKm(const GeoPoint(0, 0), const GeoPoint(0, 1)), closeTo(111.2, 0.5));
    expect(roundedPoint(-1.286412345, 36.817298765), const GeoPoint(-1.2864, 36.8173));
  });

  test('a drawn area round-trips through the URL; junk is dropped, never thrown', () {
    const tri = [GeoPoint(-1.28, 36.8), GeoPoint(-1.28, 36.84), GeoPoint(-1.3, 36.82)];
    final f = const ListingFilters(purpose: Purpose.rent, polygon: tri);
    expect(f.toUri().toString(), '/rent?poly=-1.28%2C36.8~-1.28%2C36.84~-1.3%2C36.82');
    expect(ListingFilters.fromUri(f.toUri())!.polygon, tri);
    ListingFilters? parse(String s) => ListingFilters.fromUri(Uri.parse(s));
    expect(parse('/rent?poly=-1.28,36.8~-1.28,36.84')!.polygon, isEmpty);
    expect(parse('/rent?poly=-1.28,36.8~x,y~-1.28,36.84~-1.3,36.82')!.polygon.length, 3);
    expect(parse('/rent?poly=99,0~-1.28,36.84~-1.3,36.82')!.polygon, isEmpty);
    expect(parse('/rent?poly=${List.generate(21, (i) => '-1.${i + 1},36.8').join('~')}')!.polygon, isEmpty);
    expect(f.copyWith(minBeds: 2).polygon, tri, reason: 'other filter changes keep the area');
    expect(f.copyWith(polygon: const []).polygon, isEmpty);
  });
}
