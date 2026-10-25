import 'package:realtor_core/realtor_core.dart';
import 'package:test/test.dart';

void main() {
  ListingFilters? parse(String url) => ListingFilters.fromUri(Uri.parse(url));

  test('the tracker example round-trips', () {
    final f = parse('/rent/apartments/kilimani?beds=2&max=60000')!;
    expect(f.purpose, Purpose.rent);
    expect(f.types, ['apartment']);
    expect(f.areas, ['kilimani']);
    expect(f.minBeds, 2);
    expect(f.maxPriceKES, 60000);
    expect(f.toUri().toString(), '/rent/apartments/kilimani?beds=2&max=60000');
  });

  test('every combination is a URL and comes back unchanged', () {
    final cases = [
      const ListingFilters(purpose: Purpose.sale),
      const ListingFilters(purpose: Purpose.rent, areas: ['ruaka']),
      const ListingFilters(purpose: Purpose.rent, types: ['bedsitter', 'single-room'], areas: ['kasarani', 'roysambu']),
      const ListingFilters(
        purpose: Purpose.shortStay,
        q: 'pool',
        minBeds: 1,
        minPriceKES: 3000,
        maxPriceKES: 9000,
        amenities: ['wifi', 'parking'],
        verifiedOnly: true,
        near: GeoRadius(-1.2676, 36.8108, 2),
        polygon: [GeoPoint(-1.28, 36.8), GeoPoint(-1.28, 36.84), GeoPoint(-1.3, 36.82)],
        sort: ListingSort.nearest,
        page: 3,
      ),
    ];
    for (final f in cases) {
      expect(ListingFilters.fromUri(f.toUri()), f, reason: f.toUri().toString());
    }
  });

  test('polygon: junk corners are dropped, fewer than 3 means no polygon', () {
    expect(parse('/rent?poly=-1.28,36.8~-1.28,36.84')!.polygon, isEmpty);
    expect(parse('/rent?poly=-1.28,36.8~x,y~-1.28,36.84~-1.3,36.82')!.polygon.length, 3);
    expect(parse('/rent?poly=99,0~-1.28,36.84~-1.3,36.82')!.polygon, isEmpty);
    final tooMany = List.generate(21, (i) => '-1.${i + 1},36.8').join('~');
    expect(parse('/rent?poly=$tooMany')!.polygon, isEmpty);
  });

  test('area-only path is told apart from a type path', () {
    expect(parse('/buy/kilimani')!.areas, ['kilimani']);
    expect(parse('/buy/kilimani')!.types, isEmpty);
    expect(parse('/buy/land')!.types, ['land']);
  });

  test('not a results URL', () {
    expect(parse('/'), isNull);
    expect(parse('/listing/2-bedroom-apartment-kilimani'), isNull);
    expect(parse('/rent/apartments/kilimani/extra'), isNull);
    expect(parse('/rent/Kilimani'), isNull);
  });

  test('bad parameters are dropped, not thrown', () {
    final f = parse('/rent?beds=-1&max=lots&near=999,0,5&sort=cheapest&page=0&types=castle,studio')!;
    expect(f.minBeds, isNull);
    expect(f.maxPriceKES, isNull);
    expect(f.near, isNull);
    expect(f.sort, ListingSort.newest);
    expect(f.page, 1);
    expect(f.types, ['studio']);
    expect(parse('/rent?sort=nearest')!.sort, ListingSort.newest, reason: 'nearest needs a point');
  });

  test('changing a filter goes back to page 1', () {
    final f = parse('/rent?page=4')!;
    expect(f.page, 4);
    expect(f.copyWith(minBeds: 2).page, 1);
  });
}
