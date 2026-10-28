import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:realtor_core/realtor_core.dart';

typedef _Doc = QueryDocumentSnapshot<Map<String, Object?>>;

/// The admin's tables from Firestore. Each query is scoped to the role the
/// way firestore.rules requires (agents: `agentId ==` their own), newest
/// first, paged with startAfterDocument; firestore.indexes.json has the
/// composite indexes these need.
class FirestoreAdminRepository implements AdminRepository {
  FirestoreAdminRepository(this._db);

  final FirebaseFirestore _db;
  Map<String, String>? _agentNames;

  @override
  Future<RowPage<LeadRow>> leads(StaffUser who, {String? stage, String? after, int limit = 25}) async {
    Query<Map<String, Object?>> q = _db.collection('leads');
    if (who.agentScope != null) q = q.where('agentId', isEqualTo: who.agentScope);
    if (stage != null) q = q.where('stage', isEqualTo: stage);
    return _page('leads', q.orderBy('createdAt', descending: true), after, limit, (docs) async {
      final names = await _agents();
      final titles = await _listingTitles({for (final d in docs) _str(d, 'listingId')});
      return [
        for (final d in docs)
          LeadRow(
            id: d.id,
            listingId: _str(d, 'listingId'),
            listingTitle: titles[_str(d, 'listingId')] ?? _str(d, 'listingId'),
            agentId: _str(d, 'agentId'),
            agentName: names[_str(d, 'agentId')] ?? _str(d, 'agentId'),
            channel: _str(d, 'channel'),
            stage: _str(d, 'stage'),
            createdAt: _date(d.data()['createdAt']),
            contactName: _map(d, 'contact')['name'] as String?,
            contactPhone: _map(d, 'contact')['phone'] as String?,
          ),
      ];
    });
  }

  @override
  Future<RowPage<StaffListingRow>> listings(StaffUser who, {String? status, String? after, int limit = 25}) async {
    Query<Map<String, Object?>> q = _db.collection('listings');
    if (who.agentScope != null) q = q.where('agentId', isEqualTo: who.agentScope);
    if (status != null) q = q.where('status', isEqualTo: status);
    return _page('listings', q.orderBy('updatedAt', descending: true), after, limit, (docs) async {
      final names = await _agents();
      final flagged = who.isManager ? await _photoFlagged([for (final d in docs) d.id]) : const <String>{};
      return [
        for (final d in docs)
          StaffListingRow(
            id: d.id,
            slug: _str(d, 'slug'),
            title: _str(d, 'title'),
            area: _str(d, 'area'),
            priceKES: (d.data()['priceKES'] as num?)?.toInt() ?? 0,
            status: _str(d, 'status'),
            agentId: _str(d, 'agentId'),
            agentName: names[_str(d, 'agentId')] ?? _str(d, 'agentId'),
            updatedAt: _date(d.data()['updatedAt']),
            leads: (_map(d, 'stats')['leads'] as num?)?.toInt() ?? 0,
            calls: (_map(d, 'stats')['calls'] as num?)?.toInt() ?? 0,
            whatsapps: (_map(d, 'stats')['whatsapps'] as num?)?.toInt() ?? 0,
            photoMatch: flagged.contains(d.id),
          ),
      ];
    });
  }

  /// Which of [ids] have a photo flagged as matching another listing.
  Future<Set<String>> _photoFlagged(List<String> ids) async {
    final out = <String>{};
    for (var i = 0; i < ids.length; i += 30) {
      final chunk = ids.sublist(i, i + 30 > ids.length ? ids.length : i + 30);
      final snap = await _db.collection('photoFlags').where('listingId', whereIn: chunk).get();
      for (final d in snap.docs) {
        out.add(d.data()['listingId'] as String? ?? '');
      }
    }
    return out;
  }

  @override
  Future<RowPage<AuditRow>> audit(StaffUser who, {String? after, int limit = 25}) async {
    if (!who.canOpen(AdminSection.audit)) throw StaffAccessException('the audit log is for owners and managers');
    final q = _db.collection('audit').orderBy('at', descending: true);
    return _page('audit', q, after, limit, (docs) async {
      return [
        for (final d in docs)
          () {
            final actor = _map(d, 'actor');
            final target = _map(d, 'target');
            final role = StaffRole.values.where((r) => r.name == actor['role']).firstOrNull;
            return AuditRow(
              id: d.id,
              at: _date(d.data()['at']),
              actorName: actor['name'] as String? ?? (role?.name ?? 'Script'),
              actorRole: role,
              action: _str(d, 'action'),
              // Older entries have no label: show where they point instead.
              target: target['label'] as String? ?? '${target['collection'] ?? ''}/${target['id'] ?? ''}',
              from: d.data()['from'] as String?,
              to: d.data()['to'] as String?,
              reason: d.data()['reason'] as String?,
            );
          }(),
      ];
    });
  }

  @override
  Future<List<StaffMember>> team(StaffUser who) async {
    if (!who.canOpen(AdminSection.team)) throw StaffAccessException('the team is for owners and managers');
    final names = await _agents();
    final docs = (await _db.collection('staff').orderBy('email').get()).docs;
    return [
      for (final d in docs)
        if (StaffRole.values.where((r) => r.name == d.data()['role']).firstOrNull case final role?)
          StaffMember(
            uid: d.id,
            role: role,
            email: d.data()['email'] as String?,
            name: d.data()['name'] as String?,
            agentId: d.data()['agentId'] as String?,
            agentName: names[d.data()['agentId']],
          ),
    ];
  }

  @override
  Future<List<AgentOption>> agents(StaffUser who) async => [
        for (final e in (await _agents()).entries) AgentOption(e.key, e.value)
      ]..sort((a, b) => a.name.compareTo(b.name));

  /// One page of [q] after the document [after], plus the next cursor.
  Future<RowPage<T>> _page<T>(
    String collection,
    Query<Map<String, Object?>> q,
    String? after,
    int limit,
    Future<List<T>> Function(List<_Doc>) rows,
  ) async {
    if (limit < 1) throw ArgumentError.value(limit, 'limit', 'must be at least 1');
    if (after != null) {
      final cursor = await _db.collection(collection).doc(after).get();
      if (cursor.exists) q = q.startAfterDocument(cursor);
    }
    final docs = (await q.limit(limit + 1).get()).docs;
    final page = docs.take(limit).toList();
    return RowPage(await rows(page), next: docs.length > limit ? page.last.id : null);
  }

  /// Agent names, read once (a small collection staff may read).
  Future<Map<String, String>> _agents() async => _agentNames ??= {
        for (final d in (await _db.collection('agents').get()).docs) d.id: (d.data()['name'] as String?) ?? d.id,
      };

  /// Titles of the listings a page of leads points at. One read each: an
  /// agent may not read every listing (a colleague's draft), and a refused
  /// read just shows the id.
  Future<Map<String, String>> _listingTitles(Set<String> ids) async {
    final out = <String, String>{};
    await Future.wait([
      for (final id in ids.where((i) => i.isNotEmpty))
        _db.collection('listings').doc(id).get().then((d) {
          final t = d.data()?['title'];
          if (t is String) out[id] = t;
        }, onError: (Object _) {}),
    ]);
    return out;
  }
}

String _str(_Doc d, String k) => d.data()[k] as String? ?? '';
Map<String, Object?> _map(_Doc d, String k) => (d.data()[k] as Map?)?.cast<String, Object?>() ?? const {};
DateTime _date(Object? v) => v is Timestamp ? v.toDate() : (v is DateTime ? v : DateTime.fromMillisecondsSinceEpoch(0));
