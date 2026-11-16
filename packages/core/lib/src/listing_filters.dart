/// The search filter model shared by the app, deep links and the share
/// pages. Same fields as `ListingFilters` in functions/src/search/schema.ts;
/// every combination is a URL (/rent/apartments/kilimani?beds=2&max=60000).
library;

import 'geo.dart';

enum Purpose {
  rent('rent', 'rent'),
  sale('sale', 'buy'),
  shortStay('short-stay', 'short-stay');

  const Purpose(this.value, this.pathSegment);

  /// Stored value (listings.purpose).
  final String value;

  /// First URL segment.
  final String pathSegment;

  static Purpose? fromPath(String segment) {
    for (final p in values) {
      if (p.pathSegment == segment) return p;
    }
    return null;
  }
}

/// [newest] is the default ("Popular" in the app): featured homes first,
/// then the newest. [latest] is strictly newest first.
enum ListingSort { newest, latest, priceAsc, priceDesc, nearest }

/// Highest bedroom and bathroom choices; they mean "this many or more".
const maxBedsChoice = 8, maxBathsChoice = 6;

const _sortParam = {
  ListingSort.newest: 'newest',
  ListingSort.latest: 'latest',
  ListingSort.priceAsc: 'price-asc',
  ListingSort.priceDesc: 'price-desc',
  ListingSort.nearest: 'nearest',
};

/// listings.type -> its URL segment (plural reads better in a link).
const listingTypeSlugs = {
  'bedsitter': 'bedsitters',
  'single-room': 'single-rooms',
  'studio': 'studios',
  'apartment': 'apartments',
  'maisonette': 'maisonettes',
  'townhouse': 'townhouses',
  'bungalow': 'bungalows',
  'villa': 'villas',
  'hostel': 'hostels',
  'land': 'land',
  'commercial': 'commercial',
};

final _typeFromSlug = {for (final e in listingTypeSlugs.entries) e.value: e.key};
final _slug = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');

/// Most corners a drawn area may have (keeps links short).
const maxPolygonPoints = 20;

class GeoRadius {
  const GeoRadius(this.lat, this.lng, this.km);
  final double lat, lng, km;

  @override
  bool operator ==(Object other) => other is GeoRadius && other.lat == lat && other.lng == lng && other.km == km;
  @override
  int get hashCode => Object.hash(lat, lng, km);
}

class ListingFilters {
  const ListingFilters({
    required this.purpose,
    this.q,
    this.types = const [],
    this.areas = const [],
    this.minBeds,
    this.minPriceKES,
    this.maxPriceKES,
    this.amenities = const [],
    this.verifiedOnly = false,
    this.verifiedFirst = false,
    this.furnished,
    this.floorPlan = false,
    this.video = false,
    this.tour = false,
    this.beds = const [],
    this.baths = const [],
    this.near,
    this.polygon = const [],
    this.sort = ListingSort.newest,
    this.page = 1,
  });

  final Purpose purpose;
  final String? q;
  final List<String> types, areas, amenities;
  final int? minBeds, minPriceKES, maxPriceKES;
  final bool verifiedOnly;

  /// Verified homes sort above the rest, whatever the sort.
  final bool verifiedFirst;

  /// true: furnished only; false: unfurnished only; null: either.
  final bool? furnished;

  /// Only homes with a floor plan, a video tour, a 360° tour.
  final bool floorPlan, video, tour;

  /// Exact bedroom and bathroom counts, any of them (Beds & Baths). The
  /// highest choice ([maxBedsChoice], [maxBathsChoice]) means that many or
  /// more. Empty: any. [minBeds] is the older "2+" form, still read from links.
  final List<int> beds, baths;
  final GeoRadius? near;

  /// Draw-an-area search (P3-s04): 3 to [maxPolygonPoints] corners, implicitly closed.
  final List<GeoPoint> polygon;
  final ListingSort sort;
  final int page;

  ListingFilters copyWith({
    Purpose? purpose,
    String? q,
    List<String>? types,
    List<String>? areas,
    int? minBeds,
    int? minPriceKES,
    int? maxPriceKES,
    List<String>? amenities,
    bool? verifiedOnly,
    List<GeoPoint>? polygon,
    ListingSort? sort,
    int? page,
    List<int>? beds,
    List<int>? baths,
  }) =>
      ListingFilters(
        purpose: purpose ?? this.purpose,
        q: q ?? this.q,
        types: types ?? this.types,
        areas: areas ?? this.areas,
        minBeds: minBeds ?? this.minBeds,
        minPriceKES: minPriceKES ?? this.minPriceKES,
        maxPriceKES: maxPriceKES ?? this.maxPriceKES,
        amenities: amenities ?? this.amenities,
        verifiedOnly: verifiedOnly ?? this.verifiedOnly,
        verifiedFirst: verifiedFirst,
        furnished: furnished,
        floorPlan: floorPlan,
        video: video,
        tour: tour,
        beds: beds ?? this.beds,
        baths: baths ?? this.baths,
        near: near,
        polygon: polygon ?? this.polygon,
        sort: sort ?? this.sort,
        // Any change of filter starts again at page 1.
        page: page ?? 1,
      );

  /// One type and one area go in the path (good for SEO); the rest in the query.
  Uri toUri() {
    final segments = <String>[purpose.pathSegment];
    final typeInPath = types.length == 1 ? listingTypeSlugs[types.single] : null;
    if (typeInPath != null) segments.add(typeInPath);
    final areaInPath = areas.length == 1 ? areas.single : null;
    if (areaInPath != null) segments.add(areaInPath);
    final query = <String, String>{
      if (q != null && q!.trim().isNotEmpty) 'q': q!.trim(),
      if (typeInPath == null && types.isNotEmpty) 'types': types.join(','),
      if (areaInPath == null && areas.isNotEmpty) 'areas': areas.join(','),
      if (minBeds != null) 'beds': '$minBeds',
      if (minPriceKES != null) 'min': '$minPriceKES',
      if (maxPriceKES != null) 'max': '$maxPriceKES',
      if (amenities.isNotEmpty) 'amenities': amenities.join(','),
      if (verifiedOnly) 'verified': '1',
      if (verifiedFirst) 'vfirst': '1',
      if (furnished != null) 'furnished': furnished! ? '1' : '0',
      if (floorPlan) 'plan': '1',
      if (video) 'video': '1',
      if (tour) 'tour': '1',
      if (beds.isNotEmpty) 'bd': beds.join(','),
      if (baths.isNotEmpty) 'ba': baths.join(','),
      if (near != null) 'near': '${near!.lat},${near!.lng},${near!.km}',
      if (polygon.isNotEmpty) 'poly': polygon.map((p) => '${p.lat},${p.lng}').join('~'),
      if (sort != ListingSort.newest) 'sort': _sortParam[sort]!,
      if (page > 1) 'page': '$page',
    };
    return Uri(path: '/${segments.join('/')}', queryParameters: query.isEmpty ? null : query);
  }

  /// Parses a results URL. Returns null if the path is not a results path.
  /// Unknown or malformed parameters are dropped, never thrown on: links get shared.
  static ListingFilters? fromUri(Uri uri) {
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segs.isEmpty || segs.length > 3) return null;
    final purpose = Purpose.fromPath(segs.first);
    if (purpose == null) return null;
    final types = <String>[];
    final areas = <String>[];
    for (final s in segs.skip(1)) {
      final t = _typeFromSlug[s];
      if (t != null && types.isEmpty && areas.isEmpty) {
        types.add(t);
      } else if (_slug.hasMatch(s) && areas.isEmpty) {
        areas.add(s);
      } else {
        return null;
      }
    }
    final p = uri.queryParameters;
    List<String> csv(String k, bool Function(String) ok) =>
        (p[k] ?? '').split(',').map((s) => s.trim()).where((s) => s.isNotEmpty && ok(s)).toList();
    int? nat(String k) {
      final v = int.tryParse(p[k] ?? '');
      return v != null && v >= 0 ? v : null;
    }

    // Distinct counts in order, 1 up to [max]; anything else is dropped.
    List<int> counts(String k, int max) {
      final xs = {for (final s in (p[k] ?? '').split(',')) if (int.tryParse(s.trim()) case final v? when v >= 1 && v <= max) v}.toList()..sort();
      return xs;
    }

    GeoRadius? near;
    final n = (p['near'] ?? '').split(',').map(double.tryParse).toList();
    if (n.length == 3 && n.every((x) => x != null) && n[0]!.abs() <= 90 && n[1]!.abs() <= 180 && n[2]! > 0 && n[2]! <= 100) {
      near = GeoRadius(n[0]!, n[1]!, n[2]!);
    }
    final polygon = <GeoPoint>[];
    for (final pair in (p['poly'] ?? '').split('~')) {
      final c = pair.split(',').map(double.tryParse).toList();
      if (c.length == 2 && c[0] != null && c[1] != null && c[0]!.abs() <= 90 && c[1]!.abs() <= 180) polygon.add(GeoPoint(c[0]!, c[1]!));
    }
    final sort = _sortParam.entries.where((e) => e.value == p['sort']).map((e) => e.key).firstOrNull ?? ListingSort.newest;
    final q = p['q']?.trim();
    return ListingFilters(
      purpose: purpose,
      q: q == null || q.isEmpty ? null : q,
      types: types.isNotEmpty ? types : csv('types', listingTypeSlugs.containsKey),
      areas: areas.isNotEmpty ? areas : csv('areas', _slug.hasMatch),
      minBeds: nat('beds'),
      minPriceKES: nat('min'),
      maxPriceKES: nat('max'),
      amenities: csv('amenities', _slug.hasMatch),
      verifiedOnly: p['verified'] == '1',
      verifiedFirst: p['vfirst'] == '1',
      furnished: switch (p['furnished']) { '1' => true, '0' => false, _ => null },
      floorPlan: p['plan'] == '1',
      video: p['video'] == '1',
      tour: p['tour'] == '1',
      beds: counts('bd', maxBedsChoice),
      baths: counts('ba', maxBathsChoice),
      near: near,
      polygon: polygon.length >= 3 && polygon.length <= maxPolygonPoints ? polygon : const [],
      sort: sort == ListingSort.nearest && near == null ? ListingSort.newest : sort,
      page: (nat('page') ?? 1).clamp(1, 500),
    );
  }

  @override
  bool operator ==(Object other) => other is ListingFilters && other.toUri() == toUri();
  @override
  int get hashCode => toUri().hashCode;
}
