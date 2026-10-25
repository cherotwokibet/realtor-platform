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

enum ListingSort { newest, priceAsc, priceDesc, nearest }

const _sortParam = {
  ListingSort.newest: 'newest',
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
  final GeoRadius? near;

  /// Draw-an-area search: 3 to [maxPolygonPoints] corners, implicitly closed.
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
    ListingSort? sort,
    int? page,
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
        near: near,
        polygon: polygon,
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
