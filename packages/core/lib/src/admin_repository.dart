import 'staff.dart';

/// Lead pipeline stages, in order (functions/src/model/schema.ts).
const leadStages = ['new', 'contacted', 'viewing', 'offer', 'won', 'lost'];

/// Listing statuses (functions/src/model/schema.ts).
const listingStatuses = ['draft', 'pending', 'live', 'expired', 'let', 'sold'];

/// One page of rows and the cursor for the next, as Firestore pages them
/// (`startAfter`); [next] is null on the last page.
class RowPage<T> {
  const RowPage(this.rows, {this.next});
  final List<T> rows;
  final String? next;
}

class LeadRow {
  const LeadRow({
    required this.id,
    required this.listingId,
    required this.listingTitle,
    required this.agentId,
    required this.agentName,
    required this.channel,
    required this.stage,
    required this.createdAt,
    this.contactName,
    this.contactPhone,
  });
  final String id, listingId, listingTitle, agentId, agentName, channel, stage;
  final DateTime createdAt;
  final String? contactName, contactPhone;

  LeadRow withStage(String stage) => LeadRow(
        id: id,
        listingId: listingId,
        listingTitle: listingTitle,
        agentId: agentId,
        agentName: agentName,
        channel: channel,
        stage: stage,
        createdAt: createdAt,
        contactName: contactName,
        contactPhone: contactPhone,
      );
}

class StaffListingRow {
  const StaffListingRow({
    required this.id,
    required this.slug,
    required this.title,
    required this.area,
    required this.priceKES,
    required this.status,
    required this.agentId,
    required this.agentName,
    required this.updatedAt,
    this.leads = 0,
    this.calls = 0,
    this.whatsapps = 0,
  });
  final String id, slug, title, area, status, agentId, agentName;
  final int priceKES, leads, calls, whatsapps;
  final DateTime updatedAt;

  StaffListingRow withStatus(String status, DateTime updatedAt) => StaffListingRow(
        id: id,
        slug: slug,
        title: title,
        area: area,
        priceKES: priceKES,
        status: status,
        agentId: agentId,
        agentName: agentName,
        updatedAt: updatedAt,
        leads: leads,
        calls: calls,
        whatsapps: whatsapps,
      );
}

class AuditRow {
  const AuditRow({
    required this.id,
    required this.at,
    required this.actorName,
    required this.actorRole,
    required this.action,
    required this.target,
    this.from,
    this.to,
    this.reason,
  });
  final String id, actorName, action, target;
  final StaffRole actorRole;
  final DateTime at;
  final String? from, to, reason;
}

/// What the admin reads. Firestore once the admin has Firebase, demo data
/// until then, fakes in tests. Every call takes the signed-in user and
/// returns only what their role covers: agents get their own leads and
/// listings, and no audit log. Changes go through the Functions (D7).
abstract interface class AdminRepository {
  /// Newest first, optionally one [stage].
  Future<RowPage<LeadRow>> leads(StaffUser who, {String? stage, String? after, int limit = 25});

  /// Most recently updated first, optionally one [status].
  Future<RowPage<StaffListingRow>> listings(StaffUser who, {String? status, String? after, int limit = 25});

  /// Newest first. Throws [StaffAccessException] for agents.
  Future<RowPage<AuditRow>> audit(StaffUser who, {String? after, int limit = 25});
}

/// The rows [who] may see: an agent's own, everyone's for managers.
Iterable<T> scopedTo<T>(StaffUser who, Iterable<T> rows, String Function(T) agentOf) {
  final scope = who.agentScope;
  return scope == null ? rows : rows.where((r) => agentOf(r) == scope);
}

/// The page after the row with id [after] (from the start when null), the
/// way a Firestore `startAfter(...).limit(n)` query pages. An unknown cursor
/// starts again from the top rather than failing.
RowPage<T> pageAfter<T>(List<T> rows, String Function(T) idOf, {String? after, int limit = 25}) {
  if (limit < 1) throw ArgumentError.value(limit, 'limit', 'must be at least 1');
  final start = after == null ? 0 : rows.indexWhere((r) => idOf(r) == after) + 1;
  final page = rows.skip(start).take(limit).toList();
  final more = start + page.length < rows.length;
  return RowPage(page, next: more && page.isNotEmpty ? idOf(page.last) : null);
}
