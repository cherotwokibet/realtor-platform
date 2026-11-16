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
        sort: ListingSort.nearest,
        page: 3,
      ),
    ];
    for (final f in cases) {
      expect(ListingFilters.fromUri(f.toUri()), f, reason: f.toUri().toString());
    }
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

  test('furnishing, floor plan, tour and verified-first round-trip (More Filters)', () {
    const f = ListingFilters(purpose: Purpose.rent, areas: ['kilimani'], furnished: false, floorPlan: true, tour: true, verifiedFirst: true);
    expect(f.toUri().toString(), '/rent/kilimani?vfirst=1&furnished=0&plan=1&tour=1');
    final back = ListingFilters.fromUri(f.toUri())!;
    expect(back, f);
    expect((back.furnished, back.floorPlan, back.tour, back.verifiedFirst), (false, true, true, true));
    expect(ListingFilters.fromUri(Uri.parse('/rent?furnished=1'))!.furnished, isTrue);
    expect(ListingFilters.fromUri(Uri.parse('/rent?furnished=maybe'))!.furnished, isNull);
    // Changing another filter keeps them.
    expect(f.copyWith(minBeds: 2).furnished, isFalse);
  });

  test('a saved home keeps its photos for the card carousel', () {
    const l = ListingSummary(id: 'a', slug: 'a', title: 'A', purpose: Purpose.rent, type: 'apartment', beds: 1, baths: 1, priceKES: 1, area: 'x', lat: 0, lng: 0, photos: ['p1', 'p2'], hasFloorPlan: true);
    final back = ListingSummary.fromJson(l.toJson())!;
    expect(back.photos, ['p1', 'p2']);
    expect((back.hasFloorPlan, back.hasVideo, back.has360), (true, false, false));
  });

  test('Beds & Baths, video and 360° tours, and the Newest order round-trip', () {
    const f = ListingFilters(purpose: Purpose.rent, beds: [1, 2, 8], baths: [6], video: true, tour: true, sort: ListingSort.latest);
    expect(f.toUri().toString(), '/rent?video=1&tour=1&bd=1%2C2%2C8&ba=6&sort=latest');
    expect(ListingFilters.fromUri(f.toUri()), f);
    // Out-of-range or repeated counts are dropped, never thrown on.
    final odd = ListingFilters.fromUri(Uri.parse('/rent?bd=3,0,3,9,x,1&ba=7,2'))!;
    expect(odd.beds, [1, 3]);
    expect(odd.baths, [2]);
    expect(f.copyWith(page: 2).beds, [1, 2, 8], reason: 'kept by other changes');
  });
}
