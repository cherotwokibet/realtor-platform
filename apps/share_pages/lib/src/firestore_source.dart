import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:realtor_core/realtor_core.dart';

import 'listing.dart';

/// Reads live listings from Firestore over REST (no SDK, small image).
/// On Cloud Run it authenticates with the service account from the
/// metadata server; against the emulator it uses the `owner` token.
class FirestoreListingSource implements ListingSource {
  FirestoreListingSource({required this.projectId, http.Client? client, String? emulatorHost, DateTime Function()? now})
      : _client = client ?? http.Client(),
        _emulatorHost = emulatorHost,
        _now = now ?? DateTime.now;

  final String projectId;
  final http.Client _client;
  final String? _emulatorHost;
  final DateTime Function() _now;
  String? _token;
  DateTime _tokenExpires = DateTime.fromMillisecondsSinceEpoch(0);

  Uri get _base => _emulatorHost != null
      ? Uri.parse('http://$_emulatorHost/v1/projects/$projectId/databases/(default)/documents')
      : Uri.parse('https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents');

  static Map<String, Object?> _eq(String field, String value) =>
      {'fieldFilter': {'field': {'fieldPath': field}, 'op': 'EQUAL', 'value': {'stringValue': value}}};

  Future<List<Map<String, Object?>>> _query(Map<String, Object?> structuredQuery) async {
    final res = await _client.post(
      Uri.parse('$_base:runQuery'),
      headers: {'content-type': 'application/json', 'authorization': 'Bearer ${await _accessToken()}'},
      body: jsonEncode({'structuredQuery': structuredQuery}),
    );
    if (res.statusCode != 200) throw StateError('Firestore query failed: ${res.statusCode} ${res.body}');
    return [
      for (final row in jsonDecode(res.body) as List<Object?>)
        if (_map(row)['document'] != null) _map(_map(row)['document']),
    ];
  }

  Map<String, Object?> _liveWhere(List<Map<String, Object?>> more) => {
        'compositeFilter': {'op': 'AND', 'filters': [_eq('status', 'live'), ...more]},
      };

  @override
  Future<ShareListing?> bySlug(String slug) async {
    final docs = await _query({
      'from': [{'collectionId': 'listings'}],
      'where': _liveWhere([_eq('slug', slug)]),
      'limit': 1,
    });
    return docs.isEmpty ? null : listingFromDocument(docs.single, _now());
  }

  @override
  Future<List<ShareListing>> liveInArea(String slug, {int limit = 24}) async {
    // Equality filters only (no index needed); newest first is done here.
    final docs = await _query({
      'from': [{'collectionId': 'listings'}],
      'where': _liveWhere([_eq('area', slug)]),
      'limit': 200,
    });
    final listings = [for (final d in docs) listingFromDocument(d, _now())]
      ..sort((a, b) => (b.updatedAt ?? DateTime(0)).compareTo(a.updatedAt ?? DateTime(0)));
    return listings.take(limit).toList();
  }

  Future<Map<String, Object?>?> _get(String path) async {
    final res = await _client.get(Uri.parse('$_base/$path'), headers: {'authorization': 'Bearer ${await _accessToken()}'});
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) throw StateError('Firestore get failed: ${res.statusCode}');
    return _map(jsonDecode(res.body));
  }

  @override
  Future<ShareArea?> area(String slug) async {
    final doc = await _get('areas/$slug');
    return doc == null ? null : areaFromDocument(doc);
  }

  @override
  Future<ShareAgent?> agent(String id) async {
    final doc = await _get('agents/${Uri.encodeComponent(id)}');
    if (doc == null) return null;
    final agent = agentFromDocument(doc);
    return _decodeFields(_map(doc['fields']))['active'] == true ? agent : null;
  }

  @override
  Future<List<ShareListing>> liveByAgent(String agentId, {int limit = 24}) async {
    final docs = await _query({
      'from': [{'collectionId': 'listings'}],
      'where': _liveWhere([_eq('agentId', agentId)]),
      'limit': 200,
    });
    final listings = [for (final d in docs) listingFromDocument(d, _now())]
      ..sort((a, b) => (b.updatedAt ?? DateTime(0)).compareTo(a.updatedAt ?? DateTime(0)));
    return listings.take(limit).toList();
  }

  @override
  Future<List<ShareListing>> latestLive({int limit = 12}) async {
    // Uses the (status, updatedAt desc) index in firestore.indexes.json.
    final docs = await _query({
      'from': [{'collectionId': 'listings'}],
      'where': _eq('status', 'live'),
      'orderBy': [{'field': {'fieldPath': 'updatedAt'}, 'direction': 'DESCENDING'}],
      'limit': limit,
    });
    return [for (final d in docs) listingFromDocument(d, _now())];
  }

  @override
  Future<List<ShareArea>> areas() async {
    final docs = await _query({
      'from': [{'collectionId': 'areas'}],
      'limit': 1000,
    });
    return [for (final d in docs) areaFromDocument(d)]..sort((a, b) => a.name.compareTo(b.name));
  }

  @override
  Future<List<SitemapEntry>> sitemapEntries() async {
    final listings = await _query({
      'select': {'fields': [{'fieldPath': 'slug'}, {'fieldPath': 'updatedAt'}]},
      'from': [{'collectionId': 'listings'}],
      'where': _liveWhere([]),
      'limit': 10000,
    });
    final areas = await _query({
      'select': {'fields': [{'fieldPath': '__name__'}]},
      'from': [{'collectionId': 'areas'}],
      'limit': 1000,
    });
    final agents = await _query({
      'select': {'fields': [{'fieldPath': '__name__'}]},
      'from': [{'collectionId': 'agents'}],
      'where': {'fieldFilter': {'field': {'fieldPath': 'active'}, 'op': 'EQUAL', 'value': {'booleanValue': true}}},
      'limit': 1000,
    });
    String id(Map<String, Object?> doc) => (doc['name']! as String).split('/').last;
    return [
      for (final a in areas) (path: '/area/${id(a)}', lastModified: null),
      for (final a in agents) (path: '/agent/${id(a)}', lastModified: null),
      for (final l in listings)
        (path: '/listing/${_decodeFields(_map(l['fields']))['slug']}', lastModified: _decodeFields(_map(l['fields']))['updatedAt'] as DateTime?),
    ];
  }

  Future<String> _accessToken() async {
    if (_emulatorHost != null) return 'owner';
    if (_token != null && _now().isBefore(_tokenExpires)) return _token!;
    final res = await _client.get(
      Uri.parse('http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token'),
      headers: {'Metadata-Flavor': 'Google'},
    );
    if (res.statusCode != 200) throw StateError('no service account token (${res.statusCode})');
    final t = jsonDecode(res.body) as Map<String, Object?>;
    _token = t['access_token']! as String;
    _tokenExpires = _now().add(Duration(seconds: (t['expires_in']! as num).toInt() - 60));
    return _token!;
  }
}

/// Firestore REST document (areas/{slug}) -> ShareArea.
ShareArea areaFromDocument(Map<String, Object?> doc) {
  final f = _decodeFields(_map(doc['fields']));
  final centre = _map(f['centre']);
  final stats = f['stats'] == null ? const <String, Object?>{} : _map(f['stats']);
  return ShareArea(
    slug: (doc['name']! as String).split('/').last,
    name: f['name']! as String,
    county: f['county']! as String,
    guide: (f['guide'] as String?) ?? '',
    lat: (centre['lat']! as num).toDouble(),
    lng: (centre['lng']! as num).toDouble(),
    medianRentKES: stats['medianRentKES'] as int?,
  );
}

/// Firestore REST document (agents/{id}) -> ShareAgent. Whether it is
/// active is checked by the caller.
ShareAgent agentFromDocument(Map<String, Object?> doc) {
  final f = _decodeFields(_map(doc['fields']));
  return ShareAgent(
    id: (doc['name']! as String).split('/').last,
    name: f['name']! as String,
    earbNo: f['earbNo']! as String,
    phone: f['phone']! as String,
    whatsapp: f['whatsapp']! as String,
    languages: [for (final l in (f['languages'] as List<Object?>?) ?? const ['en']) l! as String],
    photo: f['photo'] as String?,
    rating: (f['rating'] as num?)?.toDouble(),
    responseMins: f['responseMins'] as int?,
  );
}

/// Firestore REST document -> ShareListing. Pure, so it is unit-tested.
ShareListing listingFromDocument(Map<String, Object?> doc, DateTime now) {
  final f = _decodeFields(_map(doc['fields']));
  final purpose = Purpose.values.firstWhere((p) => p.value == f['purpose']);
  DateTime? time(Object? v) => v is DateTime ? v : null;
  final verifiedAt = time(f['verifiedAt']);
  final expiresAt = time(f['expiresAt']);
  final geo = _map(f['geo']);
  return ShareListing(
    id: (doc['name']! as String).split('/').last,
    slug: f['slug']! as String,
    title: f['title']! as String,
    purpose: purpose,
    type: f['type']! as String,
    beds: f['beds']! as int,
    baths: f['baths']! as int,
    priceKES: f['priceKES']! as int,
    depositMonths: f['depositMonths'] as int?,
    area: f['area']! as String,
    estate: f['estate'] as String?,
    lat: (geo['lat']! as num).toDouble(),
    lng: (geo['lng']! as num).toDouble(),
    amenities: [for (final a in (f['amenities'] as List<Object?>?) ?? const []) a! as String],
    photos: [
      for (final m in (f['media'] as List<Object?>?) ?? const [])
        if (_map(m)['kind'] == 'photo') (card: _map(_map(m)['variants'])['card']! as String, full: _map(_map(m)['variants'])['full']! as String),
    ],
    verified: verifiedAt != null && expiresAt != null && expiresAt.isAfter(now),
    updatedAt: time(f['updatedAt']),
    agentId: f['agentId'] as String?,
  );
}

Map<String, Object?> _map(Object? o) => (o! as Map).cast<String, Object?>();

Map<String, Object?> _decodeFields(Map<String, Object?> fields) =>
    {for (final e in fields.entries) e.key: _decodeValue(_map(e.value))};

Object? _decodeValue(Map<String, Object?> v) {
  final MapEntry(:key, :value) = v.entries.single;
  return switch (key) {
    'stringValue' => value,
    'integerValue' => int.parse(value! as String),
    'doubleValue' => (value! as num).toDouble(),
    'booleanValue' => value,
    'nullValue' => null,
    'timestampValue' => DateTime.parse(value! as String),
    'mapValue' => _decodeFields(_map(value)['fields'] == null ? const {} : _map(_map(value)['fields'])),
    'arrayValue' => [for (final x in (_map(value)['values'] as List<Object?>?) ?? const []) _decodeValue(_map(x))],
    _ => throw FormatException('unsupported Firestore value $key'),
  };
}
