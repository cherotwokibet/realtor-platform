import 'package:realtor_core/realtor_core.dart';
import 'package:test/test.dart';

void main() {
  test('a rental: title and text only from the facts entered', () {
    const d = ListingDraft(
      purpose: 'rent', type: 'apartment', beds: 2, baths: 2, priceKES: 65000, depositMonths: 2, serviceChargeKES: 3000,
      area: 'kilimani', estate: 'Rose Court', amenities: ['Parking', 'Borehole', 'CCTV'],
    );
    final c = suggestListingCopy(d, areaName: 'Kilimani');
    expect(c.title, '2 bedroom apartment to let in Rose Court, Kilimani');
    expect(c.description,
        'A 2-bedroom, 2-bathroom apartment to let in Rose Court, Kilimani. It comes with parking, a borehole and CCTV. '
        'Rent is ${formatKes(65000)} a month, with a deposit of 2 months and a service charge of ${formatKes(3000)} a month. '
        'Ask about it or book a viewing from this page.');
    expect(d.copyWith(title: c.title, description: c.description).problems().keys, isNot(contains('title')));
  });

  test('sale, short stay, plots and rooms read naturally; nothing is invented', () {
    final sale = suggestListingCopy(const ListingDraft(purpose: 'sale', type: 'maisonette', beds: 3, baths: 3, priceKES: 12500000, area: 'syokimau'), areaName: 'Syokimau');
    expect(sale.title, '3 bedroom maisonette for sale in Syokimau');
    expect(sale.description, contains('Asking price: ${formatKes(12500000)}.'));
    expect(sale.description, isNot(contains('comes with')), reason: 'no amenities entered');

    final stay = suggestListingCopy(const ListingDraft(purpose: 'short-stay', type: 'studio', beds: 0, baths: 1, priceKES: 4500, area: 'westlands'), areaName: 'Westlands');
    expect(stay.title, 'Studio for short stays in Westlands');
    expect(stay.description, startsWith('A 1-bathroom studio for short stays in Westlands.'));
    expect(stay.description, contains('a night'));

    final plot = suggestListingCopy(const ListingDraft(purpose: 'sale', type: 'land', beds: 0, baths: 0, priceKES: 3000000, area: 'kitengela'), areaName: 'Kitengela');
    expect(plot.title, 'Plot for sale in Kitengela');
    expect(plot.description, startsWith('A plot for sale in Kitengela.'));

    final room = suggestListingCopy(const ListingDraft(type: 'bedsitter', beds: 1, baths: 1, priceKES: 9500, area: 'kasarani'), areaName: 'Kasarani');
    expect(room.title, 'Bedsitter to let in Kasarani');
    expect(suggestListingCopy(const ListingDraft(type: 'apartment', beds: 8, baths: 1, priceKES: 1, area: 'x'), areaName: 'X').description, startsWith('An 8-bedroom'));
  });

  test('the description travels to submitListing and is capped', () {
    expect(const ListingDraft(description: '  Quiet street.  ').toCallable()['description'], 'Quiet street.');
    expect(const ListingDraft().toCallable().containsKey('description'), isFalse);
    expect(ListingDraft(description: 'x' * 3001).problems()['description'], 'Under 3,000 characters.');
    expect(ListingDraft.fromDoc('l1', {'description': 'Hi'}).description, 'Hi');
  });
}
