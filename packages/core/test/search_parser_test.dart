import 'package:realtor_core/realtor_core.dart';
import 'package:test/test.dart';

const areas = {'kilimani': 'Kilimani', 'south-c': 'South C', 'south-b': 'South B', 'ruaka': 'Ruaka', 'westlands': 'Westlands'};

ParsedSearch parse(String t, {Purpose purpose = Purpose.rent, Set<Purpose>? allowed}) =>
    parseSearch(t, purpose: purpose, areas: areas, allowed: allowed ?? const {Purpose.rent, Purpose.sale, Purpose.shortStay});

void main() {
  test('the done-when example: "2br Kilimani under 60k with parking"', () {
    final r = parse('2br Kilimani under 60k with parking');
    final f = r.filters;
    expect(f.purpose, Purpose.rent);
    expect(f.minBeds, 2);
    expect(f.areas, ['kilimani']);
    expect(f.maxPriceKES, 60000);
    expect(f.amenities, ['parking']);
    expect(f.q, isNull);
    expect(r.understood, ['2+ bedrooms', 'up to KES 60,000', 'parking', 'Kilimani']);
    expect(f.toUri().toString(), '/rent/kilimani?beds=2&max=60000&amenities=parking');
  });

  test('Swahili: nyumba ya vyumba viwili Ruaka chini ya elfu 40... and amounts in words', () {
    final f = parse('natafuta nyumba ya vyumba viwili Ruaka chini ya 40 elfu yenye maegesho').filters;
    expect(f.minBeds, 2);
    expect(f.areas, ['ruaka']);
    expect(f.maxPriceKES, 40000);
    expect(f.amenities, ['parking']);
    expect(f.q, isNull);
  });

  test('purpose, ranges and millions', () {
    final f = parse('3 bedroom maisonette for sale in South C between 8m and 12.5m').filters;
    expect(f.purpose, Purpose.sale);
    expect(f.types, ['maisonette']);
    expect(f.areas, ['south-c'], reason: 'South C, not South B');
    expect((f.minPriceKES, f.maxPriceKES), (8000000, 12500000));
    expect(f.minBeds, 3);
  });

  test('a purpose the tenant has switched off is ignored', () {
    final r = parse('airbnb studio westlands', allowed: const {Purpose.rent, Purpose.sale});
    expect(r.filters.purpose, Purpose.rent);
    expect(r.filters.types, ['studio']);
  });

  test('budgets written as numbers, and words it does not know stay as text', () {
    expect(parse('bedsitter ksh 8,000 per month').filters.maxPriceKES, 8000);
    expect(parse('bedsitter 8000').filters.maxPriceKES, 8000);
    final r = parse('apartment near Two Rivers with wifi');
    expect(r.filters.types, ['apartment']);
    expect(r.filters.amenities, ['wifi']);
    expect(r.filters.q, 'two rivers');
  });

  test('verified, gym and a minimum price', () {
    final f = parse('verified 1 bedroom westlands above 50k gym').filters;
    expect(f.verifiedOnly, isTrue);
    expect(f.minPriceKES, 50000);
    expect(f.amenities, ['gym']);
    expect(f.minBeds, 1);
  });

  test('plain text is kept whole', () {
    final f = parse('Kahawa Sukari').filters;
    expect(f.q, 'kahawa sukari');
    expect(f.areas, isEmpty);
  });

  test('bedroom phrases with "up to" or "at least" are bedrooms, never a KES 2 budget (phone test)', () {
    for (final (text, beds) in [('up to 2 bedrooms', 2), ('at least 2 bedrooms', 2), ('min 3 bedrooms', 3), ('within 2 bedrooms ruaka', 2)]) {
      final f = parse(text).filters;
      expect(f.minBeds, beds, reason: text);
      expect((f.minPriceKES, f.maxPriceKES), (null, null), reason: text);
      expect(f.q, isNull, reason: text);
    }
    final f = parse('min 3 bedrooms under 80k').filters;
    expect((f.minBeds, f.minPriceKES, f.maxPriceKES), (3, null, 80000));
  });

  test('tiny amounts are not prices; a cut-off "apart" is apartments; a bare "bedrooms" is dropped', () {
    expect(parse('under 3').filters.maxPriceKES, isNull);
    expect(parse('ksh 2').filters.maxPriceKES, isNull);
    expect(parse('apart').filters.types, ['apartment']);
    expect(parse('bedrooms').filters.q, isNull);
  });
}
