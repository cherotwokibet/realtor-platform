import 'listing_amenities.dart';
import 'listing_draft.dart';
import 'money.dart';

/// Listing copy assistant (P7-s02): a title and description written only
/// from what the agent entered (type, rooms, price, deposit, service charge,
/// estate, area, amenities), for them to edit before saving. No claims the
/// facts do not support, no model and no key. A model-written version can
/// replace it later behind a Secret Manager key; this stays the fallback.
typedef ListingCopy = ({String title, String description});

const _typeWords = {
  'bedsitter': 'bedsitter',
  'single-room': 'single room',
  'studio': 'studio',
  'apartment': 'apartment',
  'maisonette': 'maisonette',
  'townhouse': 'townhouse',
  'bungalow': 'bungalow',
  'villa': 'villa',
  'hostel': 'hostel room',
  'land': 'plot',
  'commercial': 'commercial space',
};

/// Types where "2 bedroom …" is how people say it.
const _withBedrooms = {'apartment', 'maisonette', 'townhouse', 'bungalow', 'villa'};

/// [areaName] is the area's display name (the draft holds its slug).
ListingCopy suggestListingCopy(ListingDraft d, {required String areaName}) {
  final type = _typeWords[d.type] ?? d.type.replaceAll('-', ' ');
  final what = _withBedrooms.contains(d.type) && d.beds > 0 ? '${d.beds} bedroom $type' : type;
  final purpose = switch (d.purpose) { 'sale' => 'for sale', 'short-stay' => 'for short stays', _ => 'to let' };
  final estate = (d.estate ?? '').trim();
  final where = [if (estate.isNotEmpty) estate, if (areaName.trim().isNotEmpty) areaName.trim()].join(', ');
  final title = _cap('$what $purpose${where.isEmpty ? '' : ' in $where'}');

  final rooms = [
    if (d.beds > 0 && d.type != 'land' && d.type != 'commercial') '${d.beds}-bedroom',
    if (d.baths > 0 && d.type != 'land') '${d.baths}-bathroom',
  ].join(', ');
  final opening = '${_article(rooms.isEmpty ? type : rooms)} ${rooms.isEmpty ? type : '$rooms $type'} $purpose${where.isEmpty ? '' : ' in $where'}.';

  final amenities = [for (final a in d.amenities) if (a.trim().isNotEmpty) _amenity(a.trim())];
  final has = amenities.isEmpty ? null : 'It comes with ${_list(amenities)}.';

  final price = d.priceKES <= 0
      ? null
      : switch (d.purpose) {
          'sale' => 'Asking price: ${formatKes(d.priceKES)}.',
          'short-stay' => '${formatKes(d.priceKES)} a night.',
          _ => [
              'Rent is ${formatKes(d.priceKES)} a month',
              if ((d.depositMonths ?? 0) > 0) ', with a deposit of ${d.depositMonths} month${d.depositMonths == 1 ? '' : 's'}',
              if ((d.serviceChargeKES ?? 0) > 0) '${(d.depositMonths ?? 0) > 0 ? ' and' : ','} a service charge of ${formatKes(d.serviceChargeKES!)} a month',
              '.',
            ].join(),
        };
  final next = switch (d.purpose) {
    'sale' => 'Ask about it or book a viewing from this page.',
    'short-stay' => 'Ask about dates from this page.',
    _ => 'Ask about it or book a viewing from this page.',
  };
  return (title: title, description: [opening, if (has != null) has, if (price != null) price, next].join(' '));
}

String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

String _article(String next) => RegExp(r'^[aeiou8]|^11-|^18-', caseSensitive: false).hasMatch(next) ? 'An' : 'A';

/// "Parking" -> "parking", "Borehole" -> "a borehole"; anything else as typed.
String _amenity(String key) {
  // Ticked amenities are stored by key ("swimming-pool"): use their words.
  final a = amenityLabel(key);
  final lower = a.toLowerCase();
  const countable = {'borehole', 'lift', 'gym', 'swimming pool', 'pool', 'garden', 'balcony', 'generator', 'backup generator', 'playground'};
  if (countable.contains(lower)) return '${_article(lower).toLowerCase()} $lower';
  return a == a.toUpperCase() && a.length <= 4 ? a : lower;
}

String _list(List<String> xs) => xs.length == 1 ? xs.single : '${xs.sublist(0, xs.length - 1).join(', ')} and ${xs.last}';
