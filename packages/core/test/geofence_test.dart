import 'package:realtor_core/realtor_core.dart';
import 'package:test/test.dart';

void main() {
  const box = [GeoPoint(-1.28, 36.77), GeoPoint(-1.28, 36.80), GeoPoint(-1.305, 36.80), GeoPoint(-1.305, 36.77)];

  test('inside and outside an outline', () {
    expect(insideOutline(const GeoPoint(-1.2921, 36.7856), box), isTrue, reason: 'Kilimani');
    expect(insideOutline(const GeoPoint(-1.2676, 36.8108), box), isFalse, reason: 'Westlands');
  });

  test('corners tapped in a crossing order still make an outline that does not cross', () {
    var c = <GeoPoint>[];
    for (final p in [box[0], box[2], box[1], box[3]]) {
      c = addOutlineCorner(c, p);
    }
    expect(outlineCrosses(c), isFalse);
    expect(outlineCrosses([box[0], box[2], box[1], box[3]]), isTrue);
    expect(outlineCrosses(untangleOutline([box[0], box[2], box[1], box[3]])), isFalse);
    expect(insideOutline(outlineMiddle(box), box), isTrue);
  });

  test('a position from coordinates or a Google Maps link', () {
    expect(parseMapPosition('-1.2921, 36.7856'), const GeoPoint(-1.2921, 36.7856));
    expect(parseMapPosition('-1.2921 36.7856'), const GeoPoint(-1.2921, 36.7856));
    expect(parseMapPosition('https://www.google.com/maps/@-1.2921,36.7856,15z'), const GeoPoint(-1.2921, 36.7856));
    expect(parseMapPosition('https://maps.google.com/?q=-1.2921,36.7856'), const GeoPoint(-1.2921, 36.7856));
    // The marked place, not the map's centre.
    expect(parseMapPosition('https://www.google.com/maps/place/Yaya/@-1.29,36.78,17z/data=!3m1!4b1!4m6!3m5!1s0x0:0x0!8m2!3d-1.2925!4d36.7871'),
        const GeoPoint(-1.2925, 36.7871));
    expect(parseMapPosition('https://maps.app.goo.gl/abc123'), isNull);
    expect(parseMapPosition('Kilimani'), isNull);
    expect(parseMapPosition('0, 0'), isNull);
    expect(parseMapPosition('95, 36'), isNull);
  });

  test('which areas hold a pin', () {
    final areas = [('kilimani', box), ('westlands', const <GeoPoint>[])];
    expect(areasHolding(const GeoPoint(-1.2921, 36.7856), areas, (a) => a.$2).map((a) => a.$1), ['kilimani']);
    expect(areasHolding(const GeoPoint(-1.2676, 36.8108), areas, (a) => a.$2), isEmpty);
  });

  test('an area outline: the centre inside, edges not crossing; round trip', () {
    const a = AreaGuide(slug: 'kilimani', name: 'Kilimani', county: 'Nairobi', lat: -1.2921, lng: 36.7856, boundary: box);
    expect(a.problems(), isEmpty);
    expect(a.copyWith(lat: -1.2676, lng: 36.8108).problems()['boundary'], 'The centre must be inside the outline.');
    expect(a.copyWith(boundary: [box[0], box[2], box[1], box[3]]).problems()['boundary'], 'The outline crosses itself.');
    expect(a.copyWith(boundary: box.sublist(0, 2)).problems()['boundary'], isNotNull);
    expect(a.copyWith(boundary: const []).problems(), isEmpty);
    expect(a.copyWith(boundary: const []).toCallable()['boundary'], isNull);
    final back = AreaGuide.fromDoc('kilimani', {...a.toCallable(), 'centre': {'lat': a.lat, 'lng': a.lng}});
    expect(back.boundary, box);
  });

  test('extra charges ride with a listing draft', () {
    const d = ListingDraft(extraCharges: [ExtraCharge(name: 'Water', amountKES: 500, per: 'month')]);
    expect(d.toCallable()['extraCharges'], [
      {'name': 'Water', 'amountKES': 500, 'per': 'month'}
    ]);
    expect(ListingDraft.fromDoc('x', d.toCallable()).extraCharges, d.extraCharges);
    expect(const ListingDraft(extraCharges: [ExtraCharge(name: 'W', amountKES: 0)]).problems()['extraCharges'], isNotNull);
    expect(amenityLabel('swimming-pool'), 'Swimming pool');
    expect(amenityLabel('Rooftop'), 'Rooftop');
  });
}
