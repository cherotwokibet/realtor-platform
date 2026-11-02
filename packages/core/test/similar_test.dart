import 'package:realtor_core/realtor_core.dart';
import 'package:test/test.dart';

SimilarKey home(String id, {Purpose purpose = Purpose.rent, String area = 'kilimani', String type = 'apartment', int beds = 2, int price = 60000}) =>
    (id: id, purpose: purpose, area: area, type: type, beds: beds, priceKES: price);

List<String> ids(SimilarKey of, List<SimilarKey> pool, {int count = 3}) =>
    [for (final h in similarListings(of, pool, (h) => h, count: count)) h.id];

void main() {
  final me = home('me');

  test('same area, type and beds near the price rank first; ties by the closer price', () {
    expect(
      ids(me, [
        home('other-area', area: 'westlands'), // type, beds, price: 2+1+2
        home('far', price: 85000), // within half only: 3+2+1+1
        home('close', price: 62000), // 3+2+1+2
        home('closer', price: 61000), // 3+2+1+2, nearer
        home('bedsitter', type: 'bedsitter', beds: 0, price: 15000), // too cheap
      ], count: 4),
      ['closer', 'close', 'far', 'other-area'],
    );
  });

  test('never itself, another purpose, a repeat, or a home sharing neither area nor type', () {
    expect(
      ids(me, [
        me,
        home('sale', purpose: Purpose.sale),
        home('ok'),
        home('ok'),
        home('nothing-shared', area: 'ruaka', type: 'maisonette'),
        home('twice-the-price', price: 120000),
      ]),
      ['ok'],
    );
  });

  test('at most count, and nothing when nothing is close', () {
    expect(ids(me, [for (var i = 0; i < 6; i++) home('h$i', price: 60000 + i)]).length, 3);
    expect(ids(me, [home('x', area: 'ruaka', type: 'hostel')]), isEmpty);
  });
}
