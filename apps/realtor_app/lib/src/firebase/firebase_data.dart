import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:realtor_core/realtor_core.dart';

import '../search/demo_search.dart';

/// Public URL of a media-pipeline variant in the project's media bucket
/// (`<project>-media`, made by Terraform).
String mediaUrl(String bucket, String path) =>
    'https://firebasestorage.googleapis.com/v0/b/$bucket/o/${Uri.encodeComponent(path)}?alt=media';

DateTime? _time(Object? v) => v is Timestamp ? v.toDate() : v is DateTime ? v : null;

/// A `listings/{id}` document as a results row. Verified while the 30-day
/// check holds (P6-s02); featured until `featuredUntil` (P5-s02).
ListingSummary summaryFromDoc(String id, Map<String, Object?> d, {required String bucket, required DateTime now}) {
  final geo = (d['geo'] as Map?) ?? const {};
  final photos = [
    for (final m in (d['media'] as List<Object?>?) ?? const [])
      if (m is Map && m['kind'] == 'photo') m,
  ];
  final expires = _time(d['expiresAt']), featured = _time(d['featuredUntil']);
  final thumb = photos.isEmpty ? null : (photos.first['variants'] as Map?)?['thumb'] as String?;
  return ListingSummary(
    id: id,
    slug: d['slug'] as String? ?? id,
    title: d['title'] as String? ?? '',
    purpose: Purpose.values.firstWhere((p) => p.value == d['purpose'], orElse: () => Purpose.rent),
    type: d['type'] as String? ?? '',
    beds: (d['beds'] as num?)?.toInt() ?? 0,
    baths: (d['baths'] as num?)?.toInt() ?? 0,
    priceKES: (d['priceKES'] as num?)?.toInt() ?? 0,
    area: d['area'] as String? ?? '',
    lat: (geo['lat'] as num?)?.toDouble() ?? 0,
    lng: (geo['lng'] as num?)?.toDouble() ?? 0,
    verified: d['verifiedAt'] != null && expires != null && expires.isAfter(now),
    featured: featured != null && featured.isAfter(now),
    amenities: [for (final a in (d['amenities'] as List<Object?>?) ?? const []) '$a'],
    thumb: thumb == null ? null : mediaUrl(bucket, thumb),
    blurhash: photos.isEmpty ? null : photos.first['blurhash'] as String?,
  );
}

/// Live listings from Firestore, filtered, sorted and faceted in memory the
/// way the Typesense collection does it. Enough for one realtor's few
/// hundred homes until the search host is set up (P2-s05, D4). Each purpose
/// is read once per [maxAge].
class FirestoreListingSearch implements ListingSearch {
  FirestoreListingSearch(this._db, {required this.bucket, DateTime Function()? clock, this.maxAge = const Duration(minutes: 5)})
      : _clock = clock ?? DateTime.now;
  final FirebaseFirestore _db;
  final String bucket;
  final Duration maxAge;
  final DateTime Function() _clock;
  final _cache = <Purpose, ({DateTime at, List<ListingSummary> rows})>{};

  Future<List<ListingSummary>> _live(Purpose purpose) async {
    final now = _clock(), hit = _cache[purpose];
    if (hit != null && now.difference(hit.at) < maxAge) return hit.rows;
    final snap = await _db
        .collection('listings')
        .where('status', isEqualTo: 'live')
        .where('purpose', isEqualTo: purpose.value)
        .limit(2000)
        .get();
    final rows = [for (final d in snap.docs) summaryFromDoc(d.id, d.data(), bucket: bucket, now: now)];
    _cache[purpose] = (at: now, rows: rows);
    return rows;
  }

  @override
  Future<SearchResult> search(ListingFilters filters) async => DemoListingSearch(await _live(filters.purpose)).search(filters);
}

/// Live listing details by slug, with the agent while they are active.
class FirestoreListingRepository implements ListingRepository {
  FirestoreListingRepository(this._db, {required this.bucket, DateTime Function()? clock}) : _clock = clock ?? DateTime.now;
  final FirebaseFirestore _db;
  final String bucket;
  final DateTime Function() _clock;

  @override
  Future<ListingDetail?> bySlug(String slug) async {
    final snap = await _db.collection('listings').where('status', isEqualTo: 'live').where('slug', isEqualTo: slug).limit(1).get();
    if (snap.docs.isEmpty) return null;
    final doc = snap.docs.single, d = doc.data();
    final agentId = d['agentId'] as String?;
    final agentDoc = agentId == null ? null : await _db.collection('agents').doc(agentId).get().then<DocumentSnapshot<Map<String, Object?>>?>((s) => s, onError: (Object _) => null);
    final a = agentDoc?.data();
    return ListingDetail(
      summary: summaryFromDoc(doc.id, d, bucket: bucket, now: _clock()),
      estate: d['estate'] as String?,
      depositMonths: (d['depositMonths'] as num?)?.toInt(),
      photos: [
        for (final m in (d['media'] as List<Object?>?) ?? const [])
          if (m is Map && m['kind'] == 'photo')
            if ((m['variants'] as Map?)?['card'] case final String card) mediaUrl(bucket, card),
      ],
      agent: a == null || a['active'] != true
          ? null
          : ListingAgent(id: agentId!, name: a['name'] as String? ?? '', phone: a['phone'] as String? ?? '', whatsapp: a['whatsapp'] as String? ?? ''),
    );
  }

  @override
  Future<AreaGuide?> area(String slug) async {
    final d = await _db.collection('areas').doc(slug).get();
    return d.exists ? AreaGuide.fromDoc(d.id, d.data()!) : null;
  }

  @override
  Future<AgentProfile?> agent(String id) async {
    try {
      final d = await _db.collection('agents').doc(id).get();
      final data = d.data();
      return data == null || data['active'] != true ? null : AgentProfile.fromDoc(d.id, data);
    } on FirebaseException {
      return null; // the rules hide inactive agents from the public
    }
  }

  @override
  Future<List<ListingSummary>> live({String? area, String? agentId, int limit = 30}) async {
    Query<Map<String, Object?>> q = _db.collection('listings').where('status', isEqualTo: 'live');
    if (area != null) q = q.where('area', isEqualTo: area);
    if (agentId != null) q = q.where('agentId', isEqualTo: agentId);
    final snap = await q.limit(200).get();
    final now = _clock();
    final rows = [for (final d in snap.docs) (summaryFromDoc(d.id, d.data(), bucket: bucket, now: now), _time(d.data()['updatedAt']))]
      ..sort((a, b) => (b.$2 ?? DateTime(0)).compareTo(a.$2 ?? DateTime(0)));
    return [for (final r in rows.take(limit)) r.$1];
  }

  // The rules let the public read published projects only, so every read
  // asks for published ones.
  @override
  Future<List<OffPlanProject>> projects() async {
    final snap = await _db.collection('projects').where('published', isEqualTo: true).limit(200).get();
    return [for (final d in snap.docs) OffPlanProject.fromDoc(d.id, d.data())]..sort((a, b) => a.fromKES.compareTo(b.fromKES));
  }

  @override
  Future<OffPlanProject?> project(String slug) async {
    try {
      final d = await _db.collection('projects').doc(slug).get();
      final data = d.data();
      return data == null || data['published'] != true ? null : OffPlanProject.fromDoc(d.id, data);
    } on FirebaseException {
      return null; // a draft: the rules hide it from the public
    }
  }
}

/// Calls one callable Function by name with [data]; completes with its answer.
typedef CallFunction = Future<Object?> Function(String name, Map<String, Object?> data);

/// The lead Functions (D7): createLead, logContactTap, bookViewing, logRecommendation.
class CallableLeadRepository implements LeadRepository {
  CallableLeadRepository(this._call);

  factory CallableLeadRepository.firebase(FirebaseFunctions functions) =>
      CallableLeadRepository((name, data) async => (await functions.httpsCallable(name).call<Object?>(data)).data);

  final CallFunction _call;

  Future<void> _run(String name, Map<String, Object?> data) async {
    try {
      await _call(name, data);
    } on FirebaseException catch (e) {
      final code = e.code.replaceFirst('functions/', '');
      throw LeadException(code, (e.message ?? code).replaceFirst(RegExp(r'\s*\[\d{3}\]$'), ''));
    }
  }

  @override
  Future<void> enquire({required String listingId, required String phone, String? name, String? message}) => _run('createLead', {
        'listingId': listingId,
        'channel': 'form',
        'contact': {'phone': phone, if (name != null && name.isNotEmpty) 'name': name},
        if (message != null && message.isNotEmpty) 'message': message,
        'consent': true,
      });

  @override
  Future<List<String>?> openTimes({required String listingId, required String day}) async {
    try {
      final r = await _call('openSlots', {'listingId': listingId, 'day': day}) as Map<Object?, Object?>;
      return [for (final t in r['times']! as List) '$t'];
    } on Object {
      return null; // the booking itself still checks
    }
  }

  @override
  Future<void> logTap({required String listingId, required String channel}) =>
      _run('logContactTap', {'listingId': listingId, 'channel': channel});

  @override
  Future<void> logRecommendation({required String listingId, required String event}) =>
      _run('logRecommendation', {'listingId': listingId, 'event': event, 'surface': 'app'});

  @override
  Future<void> bookViewing({required String listingId, required String slot, required String name, required String phone}) =>
      _run('bookViewing', {
        'listingId': listingId,
        'slot': slot,
        'client': {'name': name, 'phone': phone},
        'consent': true,
      });
}
