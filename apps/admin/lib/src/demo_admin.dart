import 'package:realtor_core/realtor_core.dart';

/// Demo accounts for the sign-in screen until Firebase Auth is connected.
const demoStaff = [
  StaffUser(uid: 'demo-owner', name: 'Demo Owner', role: StaffRole.owner),
  StaffUser(uid: 'demo-manager', name: 'Demo Manager', role: StaffRole.manager),
  StaffUser(uid: 'demo-wanjiku', name: 'Wanjiku Mwangi', role: StaffRole.agent, agentId: 'agent-wanjiku'),
  StaffUser(uid: 'demo-otieno', name: 'Brian Otieno', role: StaffRole.agent, agentId: 'agent-otieno'),
];

const _agents = {
  'agent-wanjiku': 'Wanjiku Mwangi',
  'agent-otieno': 'Brian Otieno',
  'agent-achieng': 'Achieng Odhiambo',
};

const _areas = ['kilimani', 'westlands', 'kileleshwa', 'lavington', 'south-b', 'ruaka'];
const _kinds = ['2 bedroom apartment', '1 bedroom apartment', 'Studio', '3 bedroom maisonette', 'Bedsitter'];
const _first = [
  'Amina',
  'Kevin',
  'Faith',
  'Juma',
  'Grace',
  'Peter',
  'Mercy',
  'Hassan',
  'Joy',
  'Dennis',
  'Wairimu',
  'Ochieng'
];
const _channels = ['form', 'viewing', 'form', 'call', 'whatsapp'];

/// Demo data with the same shape and scoping as the Firestore version: an
/// agent only ever gets their own leads and listings, and no audit log.
class DemoAdminRepository implements AdminRepository {
  DemoAdminRepository({DateTime? now}) : _now = now ?? DateTime(2026, 10, 27, 12) {
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
  final _listings = <StaffListingRow>[];
  final _leads = <LeadRow>[];
  final _audit = <AuditRow>[];

  @override
  Future<RowPage<LeadRow>> leads(StaffUser who, {String? stage, String? after, int limit = 25}) async {
    final rows = scopedTo(who, _leads, (r) => r.agentId).where((r) => stage == null || r.stage == stage).toList();
    return pageAfter(rows, (r) => r.id, after: after, limit: limit);
  }

  @override
  Future<RowPage<StaffListingRow>> listings(StaffUser who, {String? status, String? after, int limit = 25}) async {
    final rows = scopedTo(who, _listings, (r) => r.agentId).where((r) => status == null || r.status == status).toList();
    return pageAfter(rows, (r) => r.id, after: after, limit: limit);
  }

  @override
  Future<RowPage<AuditRow>> audit(StaffUser who, {String? after, int limit = 25}) async {
    if (!who.canOpen(AdminSection.audit)) throw StaffAccessException('the audit log is for owners and managers');
    return pageAfter(_audit, (r) => r.id, after: after, limit: limit);
  }
}

String _areaName(String slug) =>
    slug.split('-').map((w) => w.length <= 1 ? w.toUpperCase() : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
