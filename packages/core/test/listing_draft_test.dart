import 'package:realtor_core/realtor_core.dart';
import 'package:test/test.dart';

void main() {
  const ok = ListingDraft(title: '2 bedroom apartment, Kilimani', priceKES: 65000, lat: -1.29, lng: 36.78, area: 'kilimani', beds: 2);

  test('a complete draft has no problems; each limit matches submitListing', () {
    expect(ok.problems(), isEmpty);
    expect(ok.copyWith(title: 'Flat').problems().keys, ['title']);
    expect(ok.copyWith(priceKES: 0).problems().keys, ['priceKES']);
    expect(ok.copyWith(area: 'Kilimani').problems().keys, ['area']);
    expect(ok.copyWith(lat: 0, lng: 0).problems().keys, ['location']);
    expect(ok.copyWith(type: 'castle').problems().keys, ['type']);
    expect(ok.copyWith(depositMonths: () => 13).problems().keys, ['depositMonths']);
    expect(ok.copyWith(estate: () => 'x' * 81).problems().keys, ['estate']);
  });

  test('the callable input leaves out media and empty optionals, and trims', () {
    final input = ok.copyWith(title: '  2 bedroom apartment, Kilimani ', amenities: [' Lift ', ''], estate: () => ' ').toCallable();
    expect(input, {
      'title': '2 bedroom apartment, Kilimani',
      'purpose': 'rent',
      'type': 'apartment',
      'beds': 2,
      'baths': 1,
      'priceKES': 65000,
      'lat': -1.29,
      'lng': 36.78,
      'area': 'kilimani',
      'amenities': ['Lift'],
    });
  });

  test('reads a listing document, geo as stored by submitListing', () {
    final d = ListingDraft.fromDoc('l1', {
      'title': 'Studio, Ruaka',
      'purpose': 'rent',
      'type': 'studio',
      'beds': 0,
      'baths': 1,
      'priceKES': 18000,
      'serviceChargeKES': 1500,
      'geo': {'lat': -1.205, 'lng': 36.777, 'geohash': 'kzf'},
      'area': 'ruaka',
      'agentId': 'agent-1',
      'media': [{'kind': 'photo'}],
    });
    expect((d.listingId, d.type, d.serviceChargeKES, d.lat, d.agentId), ('l1', 'studio', 1500, -1.205, 'agent-1'));
    expect(d.toCallable()['listingId'], 'l1');
    expect(d.problems(), isEmpty);
  });
}
