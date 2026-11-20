import 'package:realtor_core/realtor_core.dart';
import 'package:test/test.dart';

void main() {
  test('problems mirror saveArea; stats are read, never sent', () {
    expect(const AreaGuide().problems().keys, ['name', 'county', 'location']);
    final a = AreaGuide.fromDoc('kilimani', {
      'name': 'Kilimani',
      'county': 'Nairobi',
      'centre': {'lat': -1.29, 'lng': 36.78, 'geohash': 'x'},
      'guide': 'Leafy.',
      'amenities': ['Yaya Centre', ' '],
      'stats': {'medianRentKES': 75000, 'listings': 12},
    });
    expect((a.medianRentKES, a.listings), (75000, 12));
    expect(a.problems(), isEmpty);
    expect(a.toCallable(), {
      'slug': 'kilimani',
      'name': 'Kilimani',
      'county': 'Nairobi',
      'lat': -1.29,
      'lng': 36.78,
      'guide': 'Leafy.',
      'amenities': ['Yaya Centre'],
      'boundary': null,
    });
  });
}
