import 'agent_profile.dart';
import 'area_guide.dart';
import 'off_plan_project.dart';
import 'listing_draft.dart';
import 'staff.dart';
import 'viewing_week.dart';

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

/// A viewing as staff see it (viewings/{id}, P5-s05).
class ViewingRow {
  const ViewingRow({
    required this.id,
    required this.listingId,
    required this.listingTitle,
    required this.agentId,
    required this.agentName,
    required this.slot,
    required this.status,
    this.clientName,
    this.clientPhone,
    this.reviewToken,
  });
  final String id, listingId, listingTitle, agentId, agentName, status;
  final DateTime slot;
  final String? clientName, clientPhone;

  /// The one-time review link's token once the viewing is done (P6-s03).
  final String? reviewToken;

  ViewingRow withStatus(String status, {String? reviewToken}) => ViewingRow(
        id: id,
        listingId: listingId,
        listingTitle: listingTitle,
        agentId: agentId,
        agentName: agentName,
        slot: slot,
        status: status,
        clientName: clientName,
        clientPhone: clientPhone,
        reviewToken: reviewToken ?? this.reviewToken,
      );
}

const viewingStatuses = ['requested', 'confirmed', 'done', 'no-show', 'cancelled'];

/// The history filters of the Viewings page; null there means open.
///
/// Open viewings are shown from this many days back.
const openViewingsDays = 14;

const viewingHistory = ['done', 'no-show', 'cancelled'];

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
    this.expiresAt,
    this.featuredUntil,
    this.photoMatch = false,
  });
  final String id, slug, title, area, status, agentId, agentName;
  final int priceKES, leads, calls, whatsapps;
  final DateTime updatedAt;

  /// When the Verified badge runs out unless the agent confirms again (P6-s02); null when never verified.
  final DateTime? expiresAt;

  /// Ranks first in search until then (P5-s02); null when not featured.
  final DateTime? featuredUntil;

  bool featuredAt(DateTime now) => featuredUntil != null && featuredUntil!.isAfter(now);

  /// A photo here matches another listing's (`photoFlags`, P6-s05). Managers only.
  final bool photoMatch;

  StaffListingRow withStatus(String status, DateTime updatedAt, {DateTime? expiresAt, DateTime? Function()? featuredUntil}) =>
      StaffListingRow(
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
        expiresAt: expiresAt ?? this.expiresAt,
        featuredUntil: featuredUntil == null ? this.featuredUntil : featuredUntil(),
        photoMatch: photoMatch,
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

  /// Null for a trusted script (the first-owner bootstrap).
  final StaffRole? actorRole;
  final DateTime at;
  final String? from, to, reason;
}

/// One person on the team (staff/{uid}, the mirror of their role claims).
class StaffMember {
  const StaffMember(
      {required this.uid, required this.role, this.email, this.name, this.agentId, this.agentName, this.agentReplyMins});
  final String uid;
  final StaffRole role;
  final String? email, name, agentId, agentName;

  /// The agent's typical first reply to a lead, in minutes (P5-s03); null until there are enough replies.
  final int? agentReplyMins;
}

/// An agent record staff accounts can act as.
/// Time an agent blocked out (P5-s05): no viewing can be booked in it.
/// A client's review of an agent (P6-s03), as managers moderate it.
class ReviewRow {
  const ReviewRow({
    required this.id,
    required this.agentId,
    required this.agentName,
    required this.rating,
    required this.status,
    required this.createdAt,
    this.comment,
    this.name,
  });
  final String id, agentId, agentName, status;
  final int rating;
  final DateTime createdAt;
  final String? comment, name;
}

/// A site page (P5-s07): about, privacy, terms, faq, contact.
class SitePageRow {
  const SitePageRow({required this.slug, this.title = '', this.body = '', this.published = false, this.updatedAt});
  final String slug, title, body;
  final bool published;
  final DateTime? updatedAt;
}

/// The pages the share site can show, in footer order.
const sitePageSlugs = ['about', 'privacy', 'terms', 'faq', 'contact'];

/// Review statuses: new ones wait as pending until a manager acts.
const reviewStatuses = ['pending', 'approved', 'hidden'];

class AgentBlock {
  const AgentBlock({required this.id, required this.agentId, required this.agentName, required this.start, required this.end, this.note});
  final String id, agentId, agentName;
  final DateTime start, end;

  /// For the team only; clients never see it.
  final String? note;
}

class AgentOption {
  const AgentOption(this.id, this.name);
  final String id, name;
}

/// What the admin reads. Firestore once the admin has Firebase, demo data
/// until then, fakes in tests. Every call takes the signed-in user and
/// returns only what their role covers: agents get their own leads and
/// listings, and no audit log. Changes go through the Functions (D7).
abstract interface class AdminRepository {
  /// Newest first, optionally one [stage].
  Future<RowPage<LeadRow>> leads(StaffUser who, {String? stage, String? after, int limit = 25});

  /// [status] null: open ones (requested or confirmed) with a slot from
  /// [from], earliest first, so past ones still to close come first;
  /// otherwise that status, latest first.
  Future<RowPage<ViewingRow>> viewings(StaffUser who, {String? status, required DateTime from, String? after, int limit = 25});

  /// Most recently updated first, optionally one [status].
  Future<RowPage<StaffListingRow>> listings(StaffUser who, {String? status, String? after, int limit = 25});

  /// Newest first. Throws [StaffAccessException] for agents.
  Future<RowPage<AuditRow>> audit(StaffUser who, {String? after, int limit = 25});

  /// The team, by email. Throws [StaffAccessException] for agents.
  Future<List<StaffMember>> team(StaffUser who);

  /// Agent records, by name, to pick from when giving someone the agent role.
  Future<List<AgentOption>> agents(StaffUser who);

  /// One listing as the editor shows it; null when missing or not [who]'s.
  Future<ListingDraft?> listingDraft(StaffUser who, String listingId);

  /// The tenant's areas, by name, for the listing form.
  Future<List<AreaOption>> areas();

  /// Every site page, saved or not, in [sitePageSlugs] order. Managers only.
  Future<List<SitePageRow>> sitePages(StaffUser who);

  /// Reviews with [status], newest first. Throws [StaffAccessException] for agents.
  Future<List<ReviewRow>> reviews(StaffUser who, {String status = 'pending'});

  /// Every area's guide, by name (the guides are public).
  Future<List<AreaGuide>> areaGuides();

  /// Off-plan projects (P5-s06), drafts too, by name. Managers only.
  Future<List<OffPlanProject>> projects(StaffUser who);

  /// Every agent's profile, by name. Throws [StaffAccessException] for agents.
  Future<List<AgentProfile>> agentProfiles(StaffUser who);

  /// Time off not yet over at [now], soonest first: an agent's own, or
  /// everyone's for managers.
  Future<List<AgentBlock>> timeOff(StaffUser who, DateTime now);

  /// Viewings in [calendarViewingStatuses] with a slot in [from, to),
  /// earliest first: an agent's own, or everyone's for managers.
  Future<List<ViewingRow>> viewingsBetween(StaffUser who, DateTime from, DateTime to);
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
