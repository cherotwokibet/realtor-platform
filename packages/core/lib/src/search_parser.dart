import 'listing_filters.dart';

/// Conversational search (P7-s01): turns what someone types, in English or
/// Swahili, into [ListingFilters], and says what it understood so they can
/// adjust it. Rules, no model: "2br Kilimani under 60k with parking" becomes
/// rent · 2+ bedrooms · Kilimani · up to KES 60,000 · parking. Words it does
/// not know stay as free text, so nothing typed is lost.
typedef ParsedSearch = ({ListingFilters filters, List<String> understood});

/// [areas]: area slug -> display name, matched by either. [purpose] is used
/// unless the text names another one that [allowed] contains.
ParsedSearch parseSearch(
  String text, {
  required Purpose purpose,
  Map<String, String> areas = const {},
  Set<Purpose> allowed = const {Purpose.rent, Purpose.sale, Purpose.shortStay},
}) {
  var s = ' ${text.toLowerCase().replaceAll(RegExp(r"(?<!\d),|,(?!\d{3}\b)|[;!?()]"), ' ').replaceAll(RegExp(r'\s+'), ' ').trim()} ';
  final understood = <String>[];
  String take(RegExp re, [String Function(Match)? onMatch]) {
    final m = re.firstMatch(s);
    if (m == null) return '';
    final out = onMatch?.call(m) ?? '';
    s = s.replaceRange(m.start, m.end, ' ');
    return out.isEmpty ? ' ' : out;
  }

  // Purpose.
  var p = purpose;
  for (final (want, re) in [
    (Purpose.shortStay, RegExp(r' (short[ -]?stay|airbnb|per night|a night|nightly|kwa usiku|holiday) ')),
    (Purpose.sale, RegExp(r' (for sale|to buy|buy|buying|kununua|inauzwa|ya kuuza) ')),
    (Purpose.rent, RegExp(r' (for rent|to rent|to let|rent|rental|kukodisha|ya kukodi|kodi) ')),
  ]) {
    if (re.hasMatch(s)) {
      take(re);
      if (allowed.contains(want)) p = want;
      break;
    }
  }

  // Price. Amounts: 60k, 60,000, 1.5m, 1.5 million, ksh 60000, 60 elfu.
  const amount = r'(?:ksh\.?|kes|sh\.?)?\s*(\d+(?:[.,]\d+)?)\s*(k|elfu|m|mn|million|milioni)?\b';
  int? kes(Match m, int g) {
    final n = double.tryParse(m.group(g)!.replaceAll(',', m.group(g)!.contains(RegExp(r',\d{3}$')) ? '' : '.'));
    if (n == null) return null;
    final unit = m.group(g + 1);
    final v = switch (unit) { 'k' || 'elfu' => n * 1000, 'm' || 'mn' || 'million' || 'milioni' => n * 1000000, _ => n };
    return v.round();
  }

  int? minP, maxP;
  take(RegExp(' (?:between|kati ya) $amount (?:and|-|to|na) $amount '), (m) {
    minP = kes(m, 1);
    maxP = kes(m, 3);
    return '';
  });
  if (maxP == null) {
    take(RegExp(' (?:under|below|less than|max|maximum|up to|upto|not more than|within|chini ya|isiyozidi|hadi) $amount '), (m) {
      maxP = kes(m, 1);
      return '';
    });
  }
  if (minP == null) {
    take(RegExp(' (?:over|above|more than|from|at least|min|minimum|zaidi ya|kuanzia) $amount '), (m) {
      minP = kes(m, 1);
      return '';
    });
  }
  // A bare "60k" or "ksh 60,000" is a budget: up to that.
  if (maxP == null && minP == null) {
    take(RegExp(r' (?:(?:ksh\.?|kes|sh\.?)\s*(\d+(?:[.,]\d+)?)\s*(k|m|mn|million)?|(\d+(?:\.\d+)?)\s*(k|m|mn|million)) '), (m) {
      final n = double.parse((m.group(1) ?? m.group(3))!.replaceAll(',', ''));
      final unit = m.group(2) ?? m.group(4);
      maxP = (n * switch (unit) { 'k' => 1000, 'm' || 'mn' || 'million' => 1000000, _ => 1 }).round();
      return '';
    });
  }
  // A plain big number (60000, 60,000) is a budget too.
  if (maxP == null && minP == null) {
    take(RegExp(r' (\d{1,3}(?:,\d{3})+|\d{4,}) '), (m) {
      maxP = int.parse(m.group(1)!.replaceAll(',', ''));
      return '';
    });
  }
  // "per month", "a month", "kwa mwezi" add nothing but should not stay as text.
  take(RegExp(r' (?:per|a|kwa|each) (?:month|mwezi|night|usiku) '));
  if (minP != null) understood.add('from KES ${_money(minP!)}');
  if (maxP != null) understood.add('up to KES ${_money(maxP!)}');

  // Bedrooms.
  const numbers = {
    'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6,
    'moja': 1, 'kimoja': 1, 'mbili': 2, 'viwili': 2, 'tatu': 3, 'vitatu': 3, 'nne': 4, 'vinne': 4, 'tano': 5, 'vitano': 5,
  };
  final numWord = '(\\d|${numbers.keys.join('|')})';
  int? beds;
  int n(String w) => int.tryParse(w) ?? numbers[w]!;
  take(RegExp(' $numWord ?(?:br|bdr|bd|b/r|bed|beds|bedroom|bedrooms|bedroomed|bedroomed|-bedroom|bed-roomed) '), (m) {
    beds = n(m.group(1)!);
    return '';
  });
  if (beds == null) {
    take(RegExp(' (?:vyumba|chumba) (?:vya kulala )?$numWord '), (m) {
      beds = n(m.group(1)!);
      return '';
    });
  }

  // Property types.
  const typeWords = {
    'bedsitter': r'bed-?sitters?|bedsits?|bedsitta',
    'single-room': r'single rooms?|single|chumba kimoja',
    'studio': r'studios?',
    'apartment': r'apartments?|flats?|apartmenti',
    'maisonette': r'maisonettes?|maisonnettes?',
    'townhouse': r'town ?houses?',
    'bungalow': r'bungalows?',
    'villa': r'villas?',
    'hostel': r'hostels?',
    'land': r'land|plots?|shamba|kiwanja|viwanja',
    'commercial': r'commercial|offices?|shops?|ofisi|duka',
  };
  final types = <String>[];
  for (final e in typeWords.entries) {
    if (take(RegExp(' (?:${e.value}) ')).isNotEmpty) types.add(e.key);
  }
  if (beds != null && !(beds == 1 && types.any((t) => t == 'bedsitter' || t == 'single-room' || t == 'studio'))) {
    understood.insert(0, '$beds+ bedroom${beds == 1 ? '' : 's'}');
  }
  for (final t in types) {
    understood.add(t.replaceAll('-', ' '));
  }

  // Amenities, as listings store them in the seed and admin hints.
  const amenityWords = {
    'parking': r'parking|packing|car park|maegesho',
    'wifi': r'wi-?fi|internet',
    'borehole': r'borehole|kisima',
    'security': r'security|guards?|ulinzi',
    'gym': r'gym',
    'swimming-pool': r'swimming pool|pool',
    'lift': r'lifts?|elevator',
    'furnished': r'furnished',
    'garden': r'garden|bustani',
    'balcony': r'balcony|balconies',
  };
  final amenities = <String>[];
  for (final e in amenityWords.entries) {
    if (take(RegExp(' (?:${e.value}) ')).isNotEmpty) amenities.add(e.key);
  }
  understood.addAll(amenities.map((a) => a.replaceAll('-', ' ')));

  final verified = take(RegExp(' (?:verified|imethibitishwa) ')).isNotEmpty;
  if (verified) understood.add('verified only');

  // Areas, longest names first ("south c" before "south").
  final found = <String>[];
  final byName = <String, String>{
    for (final e in areas.entries) ...{e.value.toLowerCase(): e.key, e.key.replaceAll('-', ' '): e.key, e.key: e.key},
  };
  for (final name in byName.keys.toList()..sort((a, b) => b.length.compareTo(a.length))) {
    if (take(RegExp(' ${RegExp.escape(name)} ')).isNotEmpty && !found.contains(byName[name])) found.add(byName[name]!);
  }
  for (final a in found) {
    understood.add(areas[a] ?? a);
  }

  // What is left: drop filler words, keep the rest as free text.
  const filler = {
    'a', 'an', 'the', 'in', 'at', 'on', 'with', 'and', 'or', 'for', 'of', 'to', 'near', 'around', 'i', 'im', "i'm", 'me', 'my',
    'want', 'need', 'looking', 'find', 'show', 'please', 'any', 'some', 'house', 'houses', 'home', 'homes', 'place', 'property',
    'na', 'ya', 'wa', 'za', 'kwa', 'katika', 'huko', 'nataka', 'natafuta', 'tafuta', 'nyumba', 'karibu', 'yenye', 'iliyo',
    'kes', 'ksh', 'shillings', 'bob', 'month', 'monthly', 'pm', 'p.m', '-', '+',
  };
  final rest = s.split(' ').where((w) => w.isNotEmpty && !filler.contains(w)).join(' ');

  return (
    filters: ListingFilters(
      purpose: p,
      q: rest.isEmpty ? null : rest,
      types: types,
      areas: found,
      minBeds: beds,
      minPriceKES: minP,
      maxPriceKES: maxP,
      amenities: amenities,
      verifiedOnly: verified,
    ),
    understood: [if (p != purpose) _purposeLabel(p), ...understood],
  );
}

String _purposeLabel(Purpose p) => switch (p) { Purpose.rent => 'to rent', Purpose.sale => 'to buy', Purpose.shortStay => 'short stay' };

String _money(int v) => v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
