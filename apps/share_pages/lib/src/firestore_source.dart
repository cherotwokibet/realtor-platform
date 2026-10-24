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

  @override
  Future<ShareListing?> bySlug(String slug) async {
    final body = jsonEncode({
      'structuredQuery': {
        'from': [
          {'collectionId': 'listings'}
        ],
        'where': {
          'compositeFilter': {
            'op': 'AND',
            'filters': [
              {'fieldFilter': {'field': {'fieldPath': 'slug'}, 'op': 'EQUAL', 'value': {'stringValue': slug}}},
              {'fieldFilter': {'field': {'fieldPath': 'status'}, 'op': 'EQUAL', 'value': {'stringValue': 'live'}}},
            ],
          },
        },
        'limit': 1,
      },
    });
    final res = await _client.post(
      Uri.parse('$_base:runQuery'),
      headers: {'content-type': 'application/json', 'authorization': 'Bearer ${await _accessToken()}'},
      body: body,
    );
    if (res.statusCode != 200) throw StateError('Firestore query failed: ${res.statusCode} ${res.body}');
    for (final row in jsonDecode(res.body) as List<Object?>) {
      final doc = (row! as Map<String, Object?>)['document'] as Map<String, Object?>?;
      if (doc != null) return listingFromDocument(doc, _now());
    }
    return null;
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
