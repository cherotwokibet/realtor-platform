import 'dart:convert';

import 'package:realtor_core/realtor_core.dart';

/// Demo accounts for the sign-in screen until Firebase Auth is connected.
const demoStaff = [
  StaffUser(uid: 'demo-owner', name: 'Demo Owner', role: StaffRole.owner),
  StaffUser(uid: 'demo-manager', name: 'Demo Manager', role: StaffRole.manager),
  StaffUser(uid: 'demo-wanjiku', name: 'Wanjiku Mwangi', role: StaffRole.agent, agentId: 'agent-wanjiku'),
  StaffUser(uid: 'demo-otieno', name: 'Brian Otieno', role: StaffRole.agent, agentId: 'agent-otieno'),
];

/// Demo sign-in accounts by email: the staff above, plus one person who has
/// signed in but has no role yet, for trying out the Team page.
final _demoAccounts = {
  for (final u in demoStaff) '${u.uid.replaceFirst('demo-', '')}@example.com': u,
  'new.agent@example.com': const StaffUser(uid: 'demo-new', name: 'New Agent', role: StaffRole.agent),
};

const _agents = {
  'agent-wanjiku': 'Wanjiku Mwangi',
  'agent-otieno': 'Brian Otieno',
  'agent-achieng': 'Achieng Odhiambo',
};

/// Typical first replies in minutes (Achieng has too few leads yet).
const _demoReplies = {'agent-wanjiku': 25, 'agent-otieno': 140};

const _areas = ['kilimani', 'westlands', 'kileleshwa', 'lavington', 'south-b', 'ruaka'];

/// Area centres for the editor's first map pin.
const _areaCentres = {
  'kilimani': (-1.2921, 36.7856),
  'westlands': (-1.2676, 36.8108),
  'kileleshwa': (-1.2833, 36.7833),
  'lavington': (-1.2799, 36.7680),
  'south-b': (-1.3110, 36.8360),
  'ruaka': (-1.2050, 36.7770),
};
const _kinds = ['2 bedroom apartment', '1 bedroom apartment', 'Studio', '3 bedroom maisonette', 'Bedsitter'];
const _first = ['Amina', 'Kevin', 'Faith', 'Juma', 'Grace', 'Peter', 'Mercy', 'Hassan', 'Joy', 'Dennis', 'Wairimu', 'Ochieng'];
const _channels = ['form', 'viewing', 'form', 'call', 'whatsapp'];

/// Demo data with the same shape and scoping as the Firestore version: an
/// agent only ever gets their own leads and listings, and no audit log.
/// Actions check what the Functions check and write the audit log, in memory.
class DemoAdminRepository implements AdminRepository, AdminActions {
  DemoAdminRepository({DateTime? now, DateTime Function()? clock})
      : _now = now ?? DateTime(2026, 10, 27, 12),
        _clock = clock ?? DateTime.now {
    final agentIds = _agents.keys.toList();
    for (var i = 0; i < 18; i++) {
      final agentId = agentIds[i % agentIds.length];
      final area = _areas[i % _areas.length];
      final kind = _kinds[i % _kinds.length];
      _listings.add(StaffListingRow(
        id: 'listing-${(i + 1).toString().padLeft(3, '0')}',
        slug: '${kind.toLowerCase().replaceAll(' ', '-')}-$area-${i + 1}',
        title: '$kind, ${_areaName(area)}',
        area: area,
        priceKES: 25000 + (i * 7 % 10) * 7500,
        status: listingStatuses[(i * 5 + 2) % listingStatuses.length],
        agentId: agentId,
        agentName: _agents[agentId]!,
        updatedAt: _now.subtract(Duration(hours: 5 * i + 1)),
        leads: (i * 3) % 7,
        calls: (i * 5) % 11,
        whatsapps: (i * 7) % 13,
        // Live ones were verified some days ago; expired ones ran out.
        expiresAt: switch (listingStatuses[(i * 5 + 2) % listingStatuses.length]) {
          'live' => _now.add(Duration(days: 30 - i)),
          'expired' => _now.subtract(Duration(days: i + 1)),
          _ => null,
        },
        // One demo listing reuses another's photo, so the flag shows.
        photoMatch: i == 4,
        // Counted from today, not from the demo's fixed date: the screens ask
        // "featured now?" against the real clock, so a fixed end date expires.
        featuredUntil: i == 0 ? (now ?? _clock()).add(const Duration(days: 12)) : null,
      ));
    }
    // Home page rows: two Recommended and one pinned first in Newest, among the live ones.
    final live = [
      for (final (i, l) in _listings.indexed)
        if (l.status == 'live') i
    ];
    for (final i in live.take(2)) {
      _listings[i] = _listings[i].withStatus('live', _listings[i].updatedAt, recommended: true);
    }
    if (live.length > 2) _listings[live[2]] = _listings[live[2]].withStatus('live', _listings[live[2]].updatedAt, pinnedNewest: true);
    // Viewings: some past (done, no-show, cancelled, one still confirmed to close), most this week.
    for (var i = 0; i < 14; i++) {
      final listing = _listings[(i * 5) % _listings.length];
      // Around the real today, so "Open" always has something to show.
      final today = _clock();
      // The first four are in the past (4 to 1 days ago); the rest from tomorrow on.
      final day = DateTime(today.year, today.month, today.day + (i < 4 ? i - 4 : i - 3));
      final slot = day.add(Duration(hours: 9 + (i % 7), minutes: i.isEven ? 0 : 30));
      final status = switch (i) {
        0 => 'done',
        1 => 'no-show',
        2 => 'cancelled',
        3 => 'confirmed', // yesterday: waiting to be marked done or no-show
        _ => i.isEven ? 'requested' : 'confirmed',
      };
      _viewings.add(ViewingRow(
        id: '${listing.agentId}_${slot.millisecondsSinceEpoch}',
        listingId: listing.id,
        listingTitle: listing.title,
        agentId: listing.agentId,
        agentName: listing.agentName,
        slot: slot,
        status: status,
        clientName: '${_first[(i + 3) % _first.length]} ${String.fromCharCode(75 + i % 10)}.',
        clientPhone: '+2547000003${i.toString().padLeft(2, '0')}',
      ));
    }
    for (var i = 0; i < 40; i++) {
      final listing = _listings[(i * 7) % _listings.length];
      _leads.add(LeadRow(
        id: 'lead-${(i + 1).toString().padLeft(3, '0')}',
        listingId: listing.id,
        listingTitle: listing.title,
        agentId: listing.agentId,
        agentName: listing.agentName,
        channel: _channels[i % _channels.length],
        stage: leadStages[(i * 3) % leadStages.length],
        createdAt: _now.subtract(Duration(hours: 3 * i + 2)),
        contactName: '${_first[i % _first.length]} ${String.fromCharCode(65 + i % 26)}.',
        contactPhone: '+2547000002${(i % 100).toString().padLeft(2, '0')}',
      ));
    }
    for (var i = 0; i < 30; i++) {
      final manager = i % 3 != 0;
      final listing = _listings[i % _listings.length];
      final lead = _leads[i % _leads.length];
      _audit.add(AuditRow(
        id: 'audit-${(i + 1).toString().padLeft(3, '0')}',
        at: _now.subtract(Duration(hours: 2 * i + 1)),
        actorName: manager ? 'Demo Manager' : lead.agentName,
        actorRole: manager ? StaffRole.manager : StaffRole.agent,
        action: manager ? (i % 4 == 1 ? 'listing.reject' : 'listing.approve') : 'lead.stage',
        target: manager ? listing.title : lead.listingTitle,
        from: manager ? 'pending' : 'new',
        to: manager ? (i % 4 == 1 ? 'draft' : 'live') : 'contacted',
        reason: manager && i % 4 == 1 ? 'Photos missing' : null,
      ));
    }
  }

  final DateTime _now;
  final DateTime Function() _clock;
  final _listings = <StaffListingRow>[];
  final _leads = <LeadRow>[];
  final _viewings = <ViewingRow>[];
  final _audit = <AuditRow>[];

  /// uid -> member; starts with the demo staff (the no-role account is not staff).
  late final _team = {
    for (final e in _demoAccounts.entries)
      if (e.value.uid != 'demo-new')
        e.value.uid: StaffMember(
          uid: e.value.uid,
          email: e.key,
          name: e.value.name,
          role: e.value.role,
          agentId: e.value.agentId,
          agentName: _agents[e.value.agentId],
          agentReplyMins: _demoReplies[e.value.agentId],
          phone: _demoPhones[e.value.uid],
        ),
  };

  static const _demoPhones = {
    'demo-owner': '+254700000101',
    'demo-manager': '+254700000102',
    'demo-wanjiku': '+254711222333',
    'demo-otieno': '+254722444555',
  };

  @override
  Future<StaffMember?> me(StaffUser who) async => _team[who.uid];

  @override
  Future<DashboardData> dashboard(StaffUser who, DateTime now) async {
    bool mine(String agentId) => who.agentScope == null || agentId == who.agentScope;
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1)), week = today.add(const Duration(days: 7));
    final leads = _leads.where((l) => mine(l.agentId)).toList();
    final open = [
      for (final v in _viewings)
        if (mine(v.agentId) && (v.status == 'requested' || v.status == 'confirmed') && !v.slot.isBefore(today)) v
    ]..sort((a, b) => a.slot.compareTo(b.slot));
    final listings = _listings.where((l) => mine(l.agentId));
    final fresh = leads.where((l) => l.stage == 'new').toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return DashboardData(
      newLeads: fresh.length,
      // The demo's leads are dated from its fixed day: shift them onto today.
      leadsByDay: leadsPerDay([for (final l in leads) l.createdAt.add(today.difference(DateTime(_now.year, _now.month, _now.day)))], now),
      viewingsToday: open.where((v) => v.slot.isBefore(tomorrow)).length,
      viewingsWeek: open.where((v) => v.slot.isBefore(week)).length,
      liveListings: listings.where((l) => l.status == 'live').length,
      pendingListings: listings.where((l) => l.status == 'pending').length,
      upcoming: open.take(5).toList(),
      latestLeads: fresh.take(5).toList(),
      activity: who.canOpen(AdminSection.audit) ? (_audit.toList()..sort((a, b) => b.at.compareTo(a.at))).take(6).toList() : const [],
    );
  }

  @override
  Future<void> saveMyProfile(StaffUser who, {required String name, String? phone}) async {
    final m = _team[who.uid];
    if (m == null) throw AdminActionException('failed-precondition', 'no staff record for this account yet');
    if (name.trim().length < 2) throw AdminActionException('invalid-argument', 'a name of at least 2 letters');
    if (phone != null && !RegExp(r'^\+254[17]\d{8}$').hasMatch(phone)) throw AdminActionException('invalid-argument', 'a Kenyan mobile, e.g. +254712345678');
    _team[who.uid] = StaffMember(
        uid: m.uid,
        role: m.role,
        email: m.email,
        name: name.trim(),
        agentId: m.agentId,
        agentName: m.agentName,
        agentReplyMins: m.agentReplyMins,
        phone: phone);
  }

  @override
  Future<RowPage<LeadRow>> leads(StaffUser who, {String? stage, String? after, int limit = 25}) async {
    final rows = scopedTo(who, _leads, (r) => r.agentId).where((r) => stage == null || r.stage == stage).toList();
    return pageAfter(rows, (r) => r.id, after: after, limit: limit);
  }

  @override
  Future<RowPage<ViewingRow>> viewings(StaffUser who, {String? status, required DateTime from, String? after, int limit = 25}) async {
    final rows = scopedTo(who, _viewings, (v) => v.agentId)
        .where((v) => status == null ? (v.status == 'requested' || v.status == 'confirmed') && !v.slot.isBefore(from) : v.status == status)
        .toList()
      ..sort((a, b) => status == null ? a.slot.compareTo(b.slot) : b.slot.compareTo(a.slot));
    return pageAfter(rows, (v) => v.id, after: after, limit: limit);
  }

  @override
  Future<void> updateViewing(StaffUser who, {required String viewingId, required String status}) async {
    final i = _viewings.indexWhere((v) => v.id == viewingId);
    if (i < 0) throw AdminActionException('not-found', 'no such viewing');
    final v = _viewings[i];
    if (!who.isManager && v.agentId != who.agentId) throw AdminActionException('permission-denied', 'not your viewing');
    if (!nextViewingStatuses(v.status, v.slot, _clock()).contains(status)) {
      throw AdminActionException('failed-precondition', 'a ${v.status} viewing cannot become $status now');
    }
    _viewings[i] = v.withStatus(status, reviewToken: status == 'done' ? 'demo-review-${v.id}'.replaceAll(RegExp('[^A-Za-z0-9_-]'), '-') : null);
    _log(who, 'viewing.status', 'Viewing of ${v.listingTitle}', v.status, status);
  }

  @override
  Future<String> rescheduleViewing(StaffUser who, {required String viewingId, required String slot}) async {
    final i = _viewings.indexWhere((v) => v.id == viewingId);
    if (i < 0) throw AdminActionException('not-found', 'no such viewing');
    final v = _viewings[i];
    if (!who.isManager && v.agentId != who.agentId) throw AdminActionException('permission-denied', 'not your viewing');
    if (v.status != 'requested' && v.status != 'confirmed') throw AdminActionException('failed-precondition', 'a ${v.status} viewing cannot be moved');
    final at = DateTime.parse(slot);
    if (!at.isAfter(_clock().add(const Duration(hours: 2)))) throw AdminActionException('invalid-argument', 'slot: book at least 2 hours ahead');
    final id = '${v.agentId}_${at.millisecondsSinceEpoch}';
    final slotEnd = at.add(const Duration(minutes: 30));
    if (_blocks.any((b) => b.agentId == v.agentId && b.start.isBefore(slotEnd) && b.end.isAfter(at))) {
      throw AdminActionException('already-exists', 'the agent is not available then, pick another time');
    }
    if (_viewings.any((o) => o.id == id && (o.status == 'requested' || o.status == 'confirmed'))) {
      throw AdminActionException('already-exists', 'the agent has another viewing then');
    }
    _viewings[i] = v.withStatus('cancelled');
    _viewings.add(ViewingRow(
      id: id,
      listingId: v.listingId,
      listingTitle: v.listingTitle,
      agentId: v.agentId,
      agentName: v.agentName,
      slot: at.toLocal(),
      status: 'confirmed',
      clientName: v.clientName,
      clientPhone: v.clientPhone,
    ));
    _log(who, 'viewing.reschedule', 'Viewing of ${v.listingTitle}', null, null);
    return id;
  }

  @override
  Future<RowPage<StaffListingRow>> listings(StaffUser who, {String? status, String? after, int limit = 25}) async {
    final rows = scopedTo(who, _listings, (r) => r.agentId)
        .where((r) => status == null || r.status == status)
        .map((r) => who.isManager || !r.photoMatch ? r : _unflagged(r))
        .toList();
    return pageAfter(rows, (r) => r.id, after: after, limit: limit);
  }

  @override
  Future<RowPage<AuditRow>> audit(StaffUser who, {String? after, int limit = 25}) async {
    if (!who.canOpen(AdminSection.audit)) throw StaffAccessException('the audit log is for owners and managers');
    return pageAfter(_audit, (r) => r.id, after: after, limit: limit);
  }

  @override
  Future<void> moveLead(StaffUser who, {required String leadId, required String stage}) async {
    final i = _leads.indexWhere((l) => l.id == leadId);
    if (i < 0) throw AdminActionException('not-found', 'no such lead');
    final lead = _leads[i];
    if (!who.isManager && lead.agentId != who.agentId) throw AdminActionException('permission-denied', 'not your lead');
    if (!nextLeadStages(lead.stage).contains(stage)) {
      throw AdminActionException('failed-precondition', 'a lead cannot go from ${lead.stage} to $stage');
    }
    _leads[i] = lead.withStage(stage);
    _log(who, 'lead.stage', lead.listingTitle, lead.stage, stage);
  }

  @override
  Future<void> moderateListing(StaffUser who, {required String listingId, required String action, String? reason}) async {
    if (!who.isManager) throw AdminActionException('permission-denied', 'owner or manager only');
    final to = moderationTargets[action];
    if (to == null) throw AdminActionException('invalid-argument', 'unknown action $action');
    if (action == 'reject' && (reason == null || reason.trim().isEmpty)) {
      throw AdminActionException('invalid-argument', 'a rejection needs a reason');
    }
    final i = _listings.indexWhere((l) => l.id == listingId);
    if (i < 0) throw AdminActionException('not-found', 'no such listing');
    final listing = _listings[i];
    if (!(listingStatusMoves[listing.status] ?? const []).contains(to)) {
      throw AdminActionException('failed-precondition', 'a ${listing.status} listing cannot be set to $to');
    }
    final at = _clock();
    _listings[i] = listing.withStatus(to, at);
    _log(who, 'listing.$action', listing.title, listing.status, to, reason: reason?.trim(), at: at);
  }

  @override
  Future<DateTime> confirmListing(StaffUser who, {required String listingId}) async {
    final i = _listings.indexWhere((l) => l.id == listingId);
    if (i < 0) throw AdminActionException('not-found', 'no such listing');
    final listing = _listings[i];
    if (!who.isManager && listing.agentId != who.agentId) throw AdminActionException('permission-denied', 'not your listing');
    if (listing.status != 'live' && listing.status != 'expired') {
      throw AdminActionException('failed-precondition', 'a ${listing.status} listing cannot be confirmed');
    }
    final at = _clock();
    final expiresAt = at.add(const Duration(days: 30));
    _listings[i] = listing.withStatus('live', at, expiresAt: expiresAt);
    _log(who, 'listing.confirm', listing.title, listing.status, 'live', at: at);
    return expiresAt;
  }

  @override
  Future<DateTime?> featureListing(StaffUser who, {required String listingId, required int days}) async {
    if (!who.isManager) throw AdminActionException('permission-denied', 'owner or manager only');
    if (days < 0 || days > 90) throw AdminActionException('invalid-argument', 'days: 0 to 90');
    final i = _listings.indexWhere((l) => l.id == listingId);
    if (i < 0) throw AdminActionException('not-found', 'no such listing');
    final listing = _listings[i];
    if (days > 0 && listing.status != 'live') throw AdminActionException('failed-precondition', 'only a live listing can be featured');
    final at = _clock();
    final until = days == 0 ? null : at.add(Duration(days: days));
    _listings[i] = listing.withStatus(listing.status, at, featuredUntil: () => until);
    _log(who, 'listing.feature', listing.title, listing.featuredAt(at) ? 'featured' : 'none', until == null ? 'none' : '$days days', at: at);
    return until;
  }

  @override
  Future<bool> setHotListing(StaffUser who, {required String listingId, required bool hot}) async {
    if (!who.isManager) throw AdminActionException('permission-denied', 'owner or manager only');
    final i = _listings.indexWhere((l) => l.id == listingId);
    if (i < 0) throw AdminActionException('not-found', 'no such listing');
    final listing = _listings[i];
    if (hot && listing.status != 'live') throw AdminActionException('failed-precondition', 'only a live listing can be a hot property');
    final at = _clock();
    _listings[i] = listing.withStatus(listing.status, at, hot: hot);
    _log(who, 'listing.hot', listing.title, listing.hot ? 'hot' : 'none', hot ? 'hot' : 'none', at: at);
    return hot;
  }

  @override
  Future<bool> setPlacement(StaffUser who, {required String listingId, required String placement, required bool on}) async {
    if (placement == 'hot') return setHotListing(who, listingId: listingId, hot: on);
    if (!who.isManager) throw AdminActionException('permission-denied', 'owner or manager only');
    if (placement != 'recommended' && placement != 'newest') throw AdminActionException('invalid-argument', 'no row "$placement"');
    final i = _listings.indexWhere((l) => l.id == listingId);
    if (i < 0) throw AdminActionException('not-found', 'no such listing');
    final listing = _listings[i];
    if (on && listing.status != 'live') throw AdminActionException('failed-precondition', 'only a live listing can be placed on the home page');
    final at = _clock();
    _listings[i] =
        placement == 'recommended' ? listing.withStatus(listing.status, at, recommended: on) : listing.withStatus(listing.status, at, pinnedNewest: on);
    _log(who, placement == 'recommended' ? 'listing.recommend' : 'listing.pin-newest', listing.title, listing.inPlacement(placement, at) ? placement : 'none',
        on ? placement : 'none',
        at: at);
    return on;
  }

  /// Agents' edits to live listings, by listing id.
  final _edits = <String, EditRequestRow>{};

  @override
  Future<List<EditRequestRow>> editRequests(StaffUser who) async => [
        for (final e in _edits.values)
          if (who.agentScope == null ? e.status == 'pending' : e.agentId == who.agentScope) e
      ]..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));

  @override
  Future<void> moderateEdit(StaffUser who, {required String listingId, required bool approve, String? reason}) async {
    if (!who.isManager) throw AdminActionException('permission-denied', 'owner or manager only');
    final e = _edits[listingId];
    if (e == null || e.status != 'pending') throw AdminActionException('not-found', 'no edit waiting for this listing');
    if (!approve && (reason ?? '').trim().isEmpty) throw AdminActionException('invalid-argument', 'a rejection needs a reason');
    final at = _clock();
    final i = _listings.indexWhere((l) => l.id == listingId);
    if (approve && i >= 0) {
      final l = _listings[i];
      _listings[i] = StaffListingRow(
        id: l.id,
        slug: l.slug,
        title: e.proposed.title.trim(),
        area: e.proposed.area,
        priceKES: e.proposed.priceKES,
        status: l.status,
        agentId: l.agentId,
        agentName: l.agentName,
        updatedAt: at,
        leads: l.leads,
        calls: l.calls,
        whatsapps: l.whatsapps,
        expiresAt: l.expiresAt,
        featuredUntil: l.featuredUntil,
        hot: l.hot,
        recommended: l.recommended,
        pinnedNewest: l.pinnedNewest,
        photoMatch: l.photoMatch,
      );
      _drafts[listingId] = e.proposed;
    }
    _edits[listingId] = EditRequestRow(
      listingId: e.listingId,
      title: e.title,
      agentId: e.agentId,
      agentName: e.agentName,
      status: approve ? 'approved' : 'rejected',
      submittedAt: e.submittedAt,
      proposed: e.proposed,
      current: e.current,
      changed: e.changed,
      submittedBy: e.submittedBy,
      reason: approve ? null : reason!.trim(),
    );
    _log(who, approve ? 'listing.edit-approve' : 'listing.edit-reject', e.title, 'pending edit', approve ? 'applied' : 'rejected', at: at);
  }

  @override
  Future<ImportOutcome> importListings(StaffUser who, List<Map<String, Object?>> rows) async {
    if (!who.isManager) throw AdminActionException('permission-denied', 'owner or manager only');
    final created = <int>[];
    final failed = <({int row, String error})>[];
    for (final (i, r) in rows.indexed) {
      final agentId = r['agentId'] as String?;
      if (agentId == null || !_agents.containsKey(agentId)) {
        failed.add((row: i + 1, error: 'agentId: no agent "${agentId ?? ''}"'));
        continue;
      }
      final at = _clock();
      final area = r['area'] as String? ?? '';
      _listings.insert(
        0,
        StaffListingRow(
          id: 'listing-import-${_listings.length + 1}',
          slug: '${r['title']}'.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-'),
          title: '${r['title']}',
          area: area,
          priceKES: (r['priceKES'] as num?)?.toInt() ?? 0,
          status: 'pending',
          agentId: agentId,
          agentName: _agents[agentId]!,
          updatedAt: at,
        ),
      );
      _log(who, 'listing.submit', '${r['title']}', 'none', 'pending', at: at);
      created.add(i + 1);
    }
    return ImportOutcome(created: created, failed: failed);
  }

  final _blocks = <AgentBlock>[];

  /// Profiles for the demo agents, made up from their names.
  late final _profiles = {
    for (final (i, e) in _agents.entries.indexed)
      e.key: AgentProfile(
        id: e.key,
        name: e.value,
        earbNo: 'EARB/DEMO/${(i + 1).toString().padLeft(4, '0')}',
        phone: '+2547000001${i.toString().padLeft(2, '0')}',
        whatsapp: '+2547000001${i.toString().padLeft(2, '0')}',
        languages: const ['en', 'sw'],
        responseMins: _demoReplies[e.key],
      ),
  };

  @override
  Future<MonthlyReport> monthlyReport(StaffUser who, String month) async {
    if (!who.isManager) throw AdminActionException('permission-denied', 'owner or manager only');
    bool inMonth(DateTime t) {
      final n = t.toUtc().add(const Duration(hours: 3));
      return '${n.year}-${n.month.toString().padLeft(2, '0')}' == month;
    }

    final leads = _leads.where((l) => inMonth(l.createdAt)).toList();
    final viewings = _viewings.where((v) => inMonth(v.slot)).toList();
    Map<String, int> tally(Iterable<String> keys) => {for (final k in keys.toSet()) k: keys.where((x) => x == k).length};
    final agents = [
      for (final p in _profiles.values)
        (
          agentId: p.id!,
          name: p.name,
          leads: leads.where((l) => l.agentId == p.id).length,
          won: leads.where((l) => l.agentId == p.id && l.stage == 'won').length,
          viewingsDone: viewings.where((v) => v.agentId == p.id && v.status == 'done').length,
          noShows: viewings.where((v) => v.agentId == p.id && v.status == 'no-show').length,
          replyMins: p.responseMins,
        ),
    ].where((a) => a.leads + a.viewingsDone + a.noShows > 0).toList()
      ..sort((a, b) => b.won != a.won ? b.won - a.won : b.leads - a.leads);
    final top = [..._listings]..sort((a, b) => b.leads - a.leads);
    return MonthlyReport(
      month: month,
      leads: leads.length,
      leadsByChannel: tally(leads.map((l) => l.channel)),
      leadsByStage: tally(leads.map((l) => l.stage)),
      viewings: viewings.length,
      viewingsByStatus: tally(viewings.map((v) => v.status)),
      agents: agents,
      topListings: [
        for (final l in top.take(10))
          if (l.leads > 0) (listingId: l.id, title: l.title, agentId: l.agentId, leads: l.leads, calls: l.calls, whatsapps: l.whatsapps),
      ],
      // A sample month of similar-homes counts (the Function adds up real days).
      similarShown: 120,
      similarOpened: 14,
    );
  }

  @override
  Future<List<AgentProfile>> agentProfiles(StaffUser who) async {
    if (!who.isManager) throw StaffAccessException('agent profiles are for owners and managers');
    return _profiles.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  @override
  Future<String> saveAgent(StaffUser who, AgentProfile profile) async {
    if (!who.isManager) throw AdminActionException('permission-denied', 'owner or manager only');
    final problems = profile.problems();
    if (problems.isNotEmpty) throw AdminActionException('invalid-argument', problems.entries.map((e) => '${e.key}: ${e.value}').join('; '));
    final slug = profile.name.trim().toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-');
    final id = profile.id ?? (_profiles.containsKey('agent-$slug') ? 'agent-$slug-${_profiles.length + 1}' : 'agent-$slug');
    if (profile.id != null && !_profiles.containsKey(id)) throw AdminActionException('not-found', 'no agent "$id"');
    final before = _profiles[id];
    final input = profile.toCallable();
    _profiles[id] = AgentProfile(
      id: id,
      name: input['name']! as String,
      earbNo: input['earbNo']! as String,
      phone: input['phone']! as String,
      whatsapp: input['whatsapp']! as String,
      languages: profile.languages,
      active: profile.active,
      photo: before?.photo,
      rating: before?.rating,
      responseMins: before?.responseMins,
    );
    _log(who, 'agent.save', profile.name.trim(), before == null ? 'none' : (before.active ? 'active' : 'inactive'), profile.active ? 'active' : 'inactive');
    return id;
  }

  @override
  Future<List<ViewingRow>> viewingsBetween(StaffUser who, DateTime from, DateTime to) async => scopedTo(who, _viewings, (v) => v.agentId)
      .where((v) => calendarViewingStatuses.contains(v.status) && !v.slot.isBefore(from) && v.slot.isBefore(to))
      .toList()
    ..sort((a, b) => a.slot.compareTo(b.slot));

  @override
  Future<List<AgentBlock>> timeOff(StaffUser who, DateTime now) async =>
      scopedTo(who, _blocks, (b) => b.agentId).where((b) => b.end.isAfter(now)).toList()..sort((a, b) => a.start.compareTo(b.start));

  @override
  Future<String> addTimeOff(StaffUser who, {String? agentId, required String start, required String end, String? note}) async {
    final agent = who.isManager ? agentId : who.agentId;
    if (agent == null || !_agents.containsKey(agent)) throw AdminActionException('invalid-argument', 'agentId: pick an agent');
    final s = DateTime.parse(start).toLocal(), e = DateTime.parse(end).toLocal();
    if (!e.isAfter(s)) throw AdminActionException('invalid-argument', 'end: must be after the start');
    if (!e.isAfter(_clock())) throw AdminActionException('invalid-argument', 'end: that time has passed');
    if (e.difference(s) > const Duration(days: 31)) throw AdminActionException('invalid-argument', 'end: at most 31 days at a time');
    final id = 'block-${_blocks.length + 1}';
    _blocks.add(AgentBlock(id: id, agentId: agent, agentName: _agents[agent]!, start: s, end: e, note: note));
    _log(who, 'agent.block', _agents[agent]!, null, null);
    return id;
  }

  @override
  Future<void> removeTimeOff(StaffUser who, {required String blockId}) async {
    final i = _blocks.indexWhere((b) => b.id == blockId);
    if (i < 0) throw AdminActionException('not-found', 'no such block');
    if (!who.isManager && _blocks[i].agentId != who.agentId) throw AdminActionException('permission-denied', 'not your time off');
    _log(who, 'agent.unblock', _blocks.removeAt(i).agentName, null, null);
  }

  /// Drafts saved in the editor; seeded listings get one made up on first open.
  final _drafts = <String, ListingDraft>{};

  /// Guides for the demo areas, editable in the demo.
  late final _guides = {
    for (final e in _areaCentres.entries)
      e.key: AreaGuide(
        slug: e.key,
        name: _areaName(e.key),
        county: 'Nairobi',
        lat: e.value.$1,
        lng: e.value.$2,
        guide: 'A demo guide for ${_areaName(e.key)}.',
        listings: _listings.where((l) => l.area == e.key && l.status == 'live').length,
        // Kilimani has an outline drawn, to show the geofence; the others not yet.
        boundary: e.key == 'kilimani' ? _kilimaniOutline : const [],
      ),
  };

  static const _kilimaniOutline = [GeoPoint(-1.2800, 36.7720), GeoPoint(-1.2800, 36.8000), GeoPoint(-1.3050, 36.8000), GeoPoint(-1.3050, 36.7720)];

  @override
  Future<List<AreaOption>> areas() async => [
        for (final g in _guides.values) (slug: g.slug!, name: g.name, lat: g.lat, lng: g.lng, boundary: g.boundary),
      ]..sort((a, b) => a.name.compareTo(b.name));

  final _pages = <String, SitePageRow>{
    'about': const SitePageRow(slug: 'about', title: 'About us', body: 'A demo page.', published: true),
  };

  @override
  Future<List<SitePageRow>> sitePages(StaffUser who) async {
    if (!who.isManager) throw StaffAccessException('site pages are for owners and managers');
    return [for (final s in sitePageSlugs) _pages[s] ?? SitePageRow(slug: s)];
  }

  @override
  Future<void> savePage(StaffUser who, SitePageRow page) async {
    if (!who.isManager) throw AdminActionException('permission-denied', 'owner or manager only');
    if (page.title.trim().length < 2) throw AdminActionException('invalid-argument', 'title: at least 2 characters');
    final before = _pages[page.slug];
    _pages[page.slug] = SitePageRow(slug: page.slug, title: page.title.trim(), body: page.body, published: page.published, updatedAt: _clock());
    _log(who, 'page.save', page.title.trim(), before == null ? 'none' : (before.published ? 'published' : 'draft'), page.published ? 'published' : 'draft');
  }

  /// Two demo reviews waiting for a manager, and one shown.
  late final _reviews = <ReviewRow>[
    ReviewRow(
        id: 'review-1',
        agentId: 'agent-wanjiku',
        agentName: 'Wanjiku Mwangi',
        rating: 5,
        status: 'pending',
        createdAt: _now.subtract(const Duration(hours: 3)),
        comment: 'Showed us three flats in one afternoon.',
        name: 'Akinyi'),
    ReviewRow(
        id: 'review-2',
        agentId: 'agent-otieno',
        agentName: 'Brian Otieno',
        rating: 2,
        status: 'pending',
        createdAt: _now.subtract(const Duration(hours: 9)),
        comment: 'Came 40 minutes late.'),
    ReviewRow(
        id: 'review-3',
        agentId: 'agent-wanjiku',
        agentName: 'Wanjiku Mwangi',
        rating: 4,
        status: 'approved',
        createdAt: _now.subtract(const Duration(days: 4)),
        name: 'Juma'),
  ];

  @override
  Future<List<ReviewRow>> reviews(StaffUser who, {String status = 'pending'}) async {
    if (!who.isManager) throw StaffAccessException('reviews are for owners and managers');
    return _reviews.where((r) => r.status == status).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<({double? rating, int count})> moderateReview(StaffUser who, {required String reviewId, required String action}) async {
    if (!who.isManager) throw AdminActionException('permission-denied', 'owner or manager only');
    final i = _reviews.indexWhere((r) => r.id == reviewId);
    if (i < 0) throw AdminActionException('not-found', 'no such review');
    final r = _reviews[i];
    final status = action == 'approve' ? 'approved' : 'hidden';
    _reviews[i] = ReviewRow(
        id: r.id, agentId: r.agentId, agentName: r.agentName, rating: r.rating, status: status, createdAt: r.createdAt, comment: r.comment, name: r.name);
    final ratings = [
      for (final x in _reviews)
        if (x.agentId == r.agentId && x.status == 'approved') x.rating
    ];
    final rating = ratings.isEmpty ? null : (ratings.reduce((a, b) => a + b) / ratings.length * 10).round() / 10;
    _log(who, 'review.moderate', 'Review of ${r.agentName}, ${r.rating} stars', r.status, status);
    return (rating: rating, count: ratings.length);
  }

  @override
  Future<List<AreaGuide>> areaGuides() async => _guides.values.toList()..sort((a, b) => a.name.compareTo(b.name));

  late final _projects = <String, OffPlanProject>{
    'sample-gardens': OffPlanProject(
      slug: 'sample-gardens',
      name: 'Sample Gardens',
      developer: 'Demo Developers Ltd',
      area: _guides.keys.first,
      summary: 'A demo project.',
      completion: '2028-06',
      units: const [OffPlanUnit(type: 'apartment', beds: 2, sizeSqm: 84, fromKES: 7200000, available: 40)],
      paymentPlan: const [(stage: 'Deposit on booking', percent: 10), (stage: 'On handover', percent: 90)],
      published: true,
      fromKES: 7200000,
      updatedAt: _now,
    ),
  };

  @override
  Future<List<OffPlanProject>> projects(StaffUser who) async {
    if (!who.isManager) throw StaffAccessException('projects are for owners and managers');
    return _projects.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  @override
  Future<String> saveProject(StaffUser who, OffPlanProject project) async {
    if (!who.isManager) throw AdminActionException('permission-denied', 'owner or manager only');
    final problems = project.problems();
    if (problems.isNotEmpty) throw AdminActionException('invalid-argument', problems.entries.map((e) => '${e.key}: ${e.value}').join('; '));
    final slug = project.slug ?? project.name.trim().toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
    if (project.slug == null && _projects.containsKey(slug)) throw AdminActionException('already-exists', 'there is already a project "$slug"');
    if (project.slug != null && !_projects.containsKey(slug)) throw AdminActionException('not-found', 'no project "$slug"');
    if (!_guides.containsKey(project.area)) throw AdminActionException('invalid-argument', 'area: no area "${project.area}"');
    final before = _projects[slug];
    _projects[slug] = OffPlanProject.fromDoc(
        slug,
        {
          ...project.toCallable(),
          'fromKES': project.units.map((u) => u.fromKES).reduce((a, b) => a < b ? a : b),
        },
        updatedAt: _clock());
    _log(who, 'project.save', project.name.trim(), before == null ? 'none' : (before.published ? 'published' : 'draft'),
        project.published ? 'published' : 'draft');
    return slug;
  }

  @override
  Future<String> saveArea(StaffUser who, AreaGuide area) async {
    if (!who.isManager) throw AdminActionException('permission-denied', 'owner or manager only');
    final problems = area.problems();
    if (problems.isNotEmpty) throw AdminActionException('invalid-argument', problems.entries.map((e) => '${e.key}: ${e.value}').join('; '));
    final slug = area.slug ?? area.name.trim().toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
    if (area.slug == null && _guides.containsKey(slug)) throw AdminActionException('already-exists', 'there is already an area "$slug"');
    if (area.slug != null && !_guides.containsKey(slug)) throw AdminActionException('not-found', 'no area "$slug"');
    final before = _guides[slug];
    final input = area.toCallable();
    _guides[slug] = AreaGuide(
      slug: slug,
      name: input['name']! as String,
      county: input['county']! as String,
      lat: area.lat,
      lng: area.lng,
      guide: input['guide']! as String,
      amenities: [for (final a in input['amenities']! as List) '$a'],
      medianRentKES: before?.medianRentKES,
      listings: before?.listings ?? 0,
      boundary: area.boundary.length < 3 ? const [] : area.boundary,
    );
    _log(who, 'area.save', area.name.trim(), before == null ? 'none' : 'saved', 'saved');
    return slug;
  }

  @override
  Future<ListingDraft?> listingDraft(StaffUser who, String listingId) async {
    final row = _listings.where((l) => l.id == listingId).firstOrNull;
    if (row == null || (!who.isManager && row.agentId != who.agentId)) return null;
    final c = _areaCentres[row.area] ?? (-1.2921, 36.8219);
    return _drafts[listingId] ??
        ListingDraft(
          listingId: row.id,
          title: row.title,
          type: row.title.contains('Studio')
              ? 'studio'
              : row.title.contains('Bedsitter')
                  ? 'bedsitter'
                  : 'apartment',
          beds: int.tryParse(row.title.split(' ').first) ?? 0,
          priceKES: row.priceKES,
          lat: c.$1,
          lng: c.$2,
          area: row.area,
          agentId: row.agentId,
        );
  }

  @override
  Future<String> submitListing(StaffUser who, ListingDraft draft) async {
    final agentId = who.isManager ? draft.agentId : who.agentId;
    if (agentId == null || !_agents.containsKey(agentId)) throw AdminActionException('invalid-argument', 'agentId: pick an agent');
    final problems = draft.problems();
    if (problems.isNotEmpty) throw AdminActionException('invalid-argument', problems.entries.map((e) => '${e.key}: ${e.value}').join('; '));
    // Geofence, as the Function checks it.
    final outline = _guides[draft.area]?.boundary ?? const [];
    if (outline.length >= 3 && !insideOutline(GeoPoint(draft.lat, draft.lng), outline)) {
      throw AdminActionException('invalid-argument', 'location: the pin is outside ${_guides[draft.area]!.name}. Move it, or pick the area it is in');
    }
    final at = _clock();
    final i = draft.listingId == null ? -1 : _listings.indexWhere((l) => l.id == draft.listingId);
    if (draft.listingId != null && i < 0) throw AdminActionException('not-found', 'no such listing');
    if (i >= 0 && !who.isManager && _listings[i].agentId != who.agentId) throw AdminActionException('permission-denied', 'not your listing');
    final id = i >= 0 ? _listings[i].id : 'listing-new-${_listings.length + 1}';
    final before = i >= 0 ? _listings[i] : null;
    // A live listing stays live: a manager's edit applies now; an agent's waits for a manager.
    if (before != null && before.status == 'live') {
      final now = await listingDraft(who, id);
      final next = ListingDraft.fromDoc(id, {...draft.toCallable(), 'agentId': agentId});
      if (!who.isManager) {
        _edits[id] = EditRequestRow(
          listingId: id,
          title: before.title,
          agentId: agentId,
          agentName: _agents[agentId]!,
          status: 'pending',
          submittedAt: at,
          proposed: next,
          current: now,
          submittedBy: who.name,
        );
        _log(who, 'listing.edit-request', before.title, 'live', 'pending edit', at: at);
        return id;
      }
      _listings[i] = StaffListingRow(
        id: id,
        slug: before.slug,
        title: draft.title.trim(),
        area: draft.area,
        priceKES: draft.priceKES,
        status: 'live',
        agentId: agentId,
        agentName: _agents[agentId]!,
        updatedAt: at,
        leads: before.leads,
        calls: before.calls,
        whatsapps: before.whatsapps,
        expiresAt: before.expiresAt,
        featuredUntil: before.featuredUntil,
        hot: before.hot,
        recommended: before.recommended,
        pinnedNewest: before.pinnedNewest,
        photoMatch: before.photoMatch,
      );
      _drafts[id] = next;
      _log(who, 'listing.edit', before.title, 'live', 'live', at: at);
      return id;
    }
    final row = StaffListingRow(
      id: id,
      slug: before?.slug ?? draft.title.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-'),
      title: draft.title.trim(),
      area: draft.area,
      priceKES: draft.priceKES,
      status: 'pending',
      agentId: agentId,
      agentName: _agents[agentId]!,
      updatedAt: at,
      leads: before?.leads ?? 0,
      calls: before?.calls ?? 0,
      whatsapps: before?.whatsapps ?? 0,
    );
    i >= 0 ? _listings.removeAt(i) : null;
    _listings.insert(0, row);
    _drafts[id] = ListingDraft.fromDoc(id, {...draft.toCallable(), 'agentId': agentId});
    _log(who, 'listing.submit', row.title, before?.status ?? 'none', 'pending', at: at);
    return id;
  }

  /// How many times the team was read (tests check screens don't refetch needlessly).
  var teamCalls = 0;

  @override
  Future<List<StaffMember>> team(StaffUser who) async {
    teamCalls++;
    if (!who.canOpen(AdminSection.team)) throw StaffAccessException('the team is for owners and managers');
    return _team.values.toList()..sort((a, b) => (a.email ?? '').compareTo(b.email ?? ''));
  }

  @override
  Future<List<AgentOption>> agents(StaffUser who) async =>
      [for (final p in _profiles.values) AgentOption(p.id!, p.name)]..sort((a, b) => a.name.compareTo(b.name));

  @override
  Future<void> setStaffRole(StaffUser who, {required String email, required StaffRole? role, String? agentId}) async {
    if (!who.canManageStaff) throw AdminActionException('permission-denied', 'owner only');
    final account = _demoAccounts[email.trim().toLowerCase()];
    if (account == null) {
      throw AdminActionException('not-found', 'no account with that email: ask them to sign in to the admin once first');
    }
    if (account.uid == who.uid && role != StaffRole.owner) {
      throw AdminActionException('failed-precondition', 'an owner cannot remove their own owner role');
    }
    if (role == StaffRole.agent && !_agents.containsKey(agentId)) {
      throw AdminActionException('invalid-argument', 'an agent needs a known agent record');
    }
    final before = _team[account.uid]?.role.name;
    if (role == null) {
      _team.remove(account.uid);
    } else {
      final id = role == StaffRole.agent ? agentId : null;
      _team[account.uid] = StaffMember(
          uid: account.uid,
          email: email.trim().toLowerCase(),
          name: account.name,
          role: role,
          agentId: id,
          agentName: _agents[id],
          phone: _team[account.uid]?.phone ?? _demoPhones[account.uid]);
    }
    _log(who, 'staff.role', email.trim().toLowerCase(), before ?? 'none', role?.name ?? 'none');
  }

  @override
  Future<DataRequestResult> dataRequest(StaffUser who, {required DataRequestKind kind, String? phone, String? email}) async {
    if (!who.canOpen(AdminSection.privacy)) throw AdminActionException('permission-denied', 'owner or manager only');
    if (phone == null && (email == null || email.trim().isEmpty)) {
      throw AdminActionException('invalid-argument', 'a phone or an email');
    }
    // Demo leads keep a phone only, and demo viewings are not modelled.
    final found = phone == null ? <LeadRow>[] : _leads.where((l) => l.contactPhone == phone).toList();
    final counts = '${found.length} leads, 0 viewings';
    if (kind == DataRequestKind.delete) _leads.removeWhere(found.contains);
    _log(who, 'privacy.${kind.name}', counts, null, null);
    return DataRequestResult(
      kind: kind,
      leads: found.length,
      viewings: 0,
      exportJson: kind == DataRequestKind.export
          ? const JsonEncoder.withIndent('  ').convert({
              'leads': [
                for (final l in found)
                  {
                    'id': l.id,
                    'listingId': l.listingId,
                    'channel': l.channel,
                    'stage': l.stage,
                    'contact': {'name': l.contactName, 'phone': l.contactPhone},
                    'createdAt': l.createdAt.toIso8601String(),
                  }
              ],
              'viewings': [],
            })
          : null,
    );
  }

  void _log(StaffUser who, String action, String target, String? from, String? to, {String? reason, DateTime? at}) => _audit.insert(
        0,
        AuditRow(
          id: 'audit-local-${_audit.length + 1}',
          at: at ?? _clock(),
          actorName: who.name,
          actorRole: who.role,
          action: action,
          target: target,
          from: from,
          to: to,
          reason: reason,
        ),
      );
}

/// Agents never see photo flags (the Firestore repository only reads them for managers).
StaffListingRow _unflagged(StaffListingRow r) => StaffListingRow(
      id: r.id,
      slug: r.slug,
      title: r.title,
      area: r.area,
      priceKES: r.priceKES,
      status: r.status,
      agentId: r.agentId,
      agentName: r.agentName,
      updatedAt: r.updatedAt,
      leads: r.leads,
      calls: r.calls,
      whatsapps: r.whatsapps,
      expiresAt: r.expiresAt,
      featuredUntil: r.featuredUntil,
    );

String _areaName(String slug) => slug.split('-').map((w) => w.length <= 1 ? w.toUpperCase() : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
