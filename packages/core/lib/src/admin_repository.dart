import 'agent_profile.dart';
import 'area_guide.dart';
import 'off_plan_project.dart';
import 'listing_draft.dart';
import 'money.dart';
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
    this.hot = false,
    this.recommended = false,
    this.pinnedNewest = false,
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

  /// In the home page's Hot Properties.
  final bool hot;

  /// In the home page's Recommended; pinned first in Newest.
  final bool recommended, pinnedNewest;

  /// Whether it is in [placement] ('hot', 'featured', 'recommended', 'newest') at [now].
  bool inPlacement(String placement, DateTime now) => switch (placement) {
        'hot' => hot,
        'featured' => featuredAt(now),
        'recommended' => recommended,
        'newest' => pinnedNewest,
        _ => false,
      };

  /// A photo here matches another listing's (`photoFlags`, P6-s05). Managers only.
  final bool photoMatch;

  StaffListingRow withStatus(String status, DateTime updatedAt,
          {DateTime? expiresAt, DateTime? Function()? featuredUntil, bool? hot, bool? recommended, bool? pinnedNewest}) =>
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
        hot: hot ?? this.hot,
        recommended: recommended ?? this.recommended,
        pinnedNewest: pinnedNewest ?? this.pinnedNewest,
        photoMatch: photoMatch,
      );
}

/// The home page's rows managers fill, in the order the site shows them.
const homePlacements = <(String, String)>[
  ('hot', 'Hot properties'),
  ('featured', 'Featured'),
  ('recommended', 'Recommended'),
  ('newest', 'Newest to rent (pinned first)'),
];

/// An agent's edit to a live listing, waiting for a manager (listingEdits/{listingId}).
class EditRequestRow {
  const EditRequestRow({
    required this.listingId,
    required this.title,
    required this.agentId,
    required this.agentName,
    required this.status,
    required this.submittedAt,
    required this.proposed,
    this.current,
    this.changed = const [],
    this.submittedBy,
    this.reason,
  });
  final String listingId, title, agentId, agentName;

  /// pending, approved or rejected.
  final String status;
  final DateTime submittedAt;
  final ListingDraft proposed;

  /// The listing as it is now; null when it has gone.
  final ListingDraft? current;
  final List<String> changed;
  final String? submittedBy;

  /// Why a manager rejected it.
  final String? reason;
}

/// What an edit changes, field by field: (field, now, proposed); only the
/// fields that differ, in the form's order.
List<(String, String, String)> editChanges(ListingDraft now, ListingDraft next, {Map<String, String> areaNames = const {}, Map<String, String> agentNames = const {}}) {
  String kes(int? v) => v == null ? '—' : formatKes(v);
  String words(List<String> xs) => xs.isEmpty ? '—' : xs.join(', ');
  final rows = <(String, String, String)>[
    ('Title', now.title, next.title),
    ('For', now.purpose, next.purpose),
    ('Type', now.type, next.type),
    ('Bedrooms', '${now.beds}', '${next.beds}'),
    ('Bathrooms', '${now.baths}', '${next.baths}'),
    ('Price', kes(now.priceKES), kes(next.priceKES)),
    ('Deposit (months)', '${now.depositMonths ?? '—'}', '${next.depositMonths ?? '—'}'),
    ('Service charge', kes(now.serviceChargeKES), kes(next.serviceChargeKES)),
    ('Viewing fee', kes(now.viewingFeeKES), kes(next.viewingFeeKES)),
    ('Other expenses', words([for (final c in now.extraCharges) '${c.name} ${kes(c.amountKES)}']), words([for (final c in next.extraCharges) '${c.name} ${kes(c.amountKES)}'])),
    ('Area', areaNames[now.area] ?? now.area, areaNames[next.area] ?? next.area),
    ('Estate or building', now.estate ?? '—', next.estate ?? '—'),
    ('Map position', '${now.lat.toStringAsFixed(5)}, ${now.lng.toStringAsFixed(5)}', '${next.lat.toStringAsFixed(5)}, ${next.lng.toStringAsFixed(5)}'),
    ('Amenities', words([...now.amenities]..sort()), words([...next.amenities]..sort())),
    ('Description', now.description.trim(), next.description.trim()),
    ('Agent', agentNames[now.agentId] ?? now.agentId ?? '—', agentNames[next.agentId] ?? next.agentId ?? '—'),
  ];
  return [for (final r in rows) if (r.$2 != r.$3) r];
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
      {required this.uid, required this.role, this.email, this.name, this.agentId, this.agentName, this.agentReplyMins, this.phone});
  final String uid;
  final StaffRole role;
  final String? email, name, agentId, agentName;

  /// Their own phone (Account), or their agent profile's.
  final String? phone;

  /// True when [q] (any case) is in their name, email, phone or agent name;
  /// phones also match without spaces or the leading 0 / +254.
  bool matches(String q) {
    final t = q.trim().toLowerCase();
    if (t.isEmpty) return true;
    String digits(String? s) => (s ?? '').replaceAll(RegExp(r'\D'), '').replaceFirst(RegExp(r'^(254|0)'), '');
    final d = digits(t);
    return [name, email, agentName].any((v) => (v ?? '').toLowerCase().contains(t)) || (d.length >= 3 && digits(phone).contains(d));
  }

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

/// An M-Pesa payment (payments/{id}), managers only: a viewing fee, a
/// deposit or a featured-ad fee, with its STK Push outcome.
class PaymentRow {
  const PaymentRow({
    required this.id,
    required this.purpose,
    required this.amountKES,
    required this.phone,
    required this.status,
    required this.createdAt,
    this.listingId,
    this.listingTitle,
    this.viewingId,
    this.receipt,
    this.reason,
  });
  final String id, purpose, phone, status;
  final int amountKES;
  final DateTime createdAt;
  final String? listingId, listingTitle, viewingId, receipt, reason;
}

const paymentStatuses = ['pending', 'paid', 'failed', 'cancelled'];
const paymentPurposes = ['viewing-fee', 'deposit', 'featured-ad'];

/// A Help & feedback message (feedback/{id}), managers only.
class FeedbackRow {
  const FeedbackRow({
    required this.id,
    required this.kind,
    required this.message,
    required this.status,
    required this.createdAt,
    this.name,
    this.phone,
    this.email,
    this.page,
    this.notes = const [],
  });
  final String id, kind, message, status;
  final DateTime createdAt;
  final String? name, phone, email, page;

  /// What staff noted (what was done, the reply sent), oldest first.
  final List<({String text, String? by, DateTime at})> notes;
}

const feedbackKinds = ['question', 'problem', 'feedback', 'complaint'];
const feedbackStatuses = ['new', 'open', 'resolved'];

/// An advert on the site (ads/{id}): words, a photo, where a tap goes,
/// where it shows (home, results, both) and when.
class AdRow {
  const AdRow({
    this.id,
    this.title = '',
    this.text = '',
    this.advertiser = '',
    this.linkUrl,
    this.image,
    this.placement = 'both',
    this.active = true,
    this.startsOn,
    this.endsOn,
    this.updatedAt,
  });

  /// Null for a new ad.
  final String? id;
  final String title, text, advertiser, placement;

  /// https only; null: Enquire now opens the realtor's WhatsApp.
  final String? linkUrl;

  /// A Storage path under ads/(id)/.
  final String? image;
  final bool active;

  /// Days, YYYY-MM-DD; null: no limit.
  final String? startsOn, endsOn;
  final DateTime? updatedAt;

  static const placements = ['home', 'results', 'both'];

  factory AdRow.fromDoc(String id, Map<String, Object?> d) => AdRow(
        id: id,
        title: d['title'] as String? ?? '',
        text: d['text'] as String? ?? '',
        advertiser: d['advertiser'] as String? ?? '',
        linkUrl: d['linkUrl'] as String?,
        image: d['image'] as String?,
        placement: placements.contains(d['placement']) ? d['placement']! as String : 'both',
        active: d['active'] == true,
        startsOn: d['startsOn'] as String?,
        endsOn: d['endsOn'] as String?,
      );

  /// Running on [day] (local): switched on and within its dates.
  bool runningOn(DateTime day) {
    final d = '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    return active && (startsOn == null || startsOn!.compareTo(d) <= 0) && (endsOn == null || endsOn!.compareTo(d) >= 0);
  }

  /// Running, scheduled, ended or paused, as the admin lists it.
  String stateOn(DateTime day) {
    if (!active) return 'paused';
    if (runningOn(day)) return 'running';
    final d = '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    return startsOn != null && startsOn!.compareTo(d) > 0 ? 'scheduled' : 'ended';
  }

  bool showsOn(String where) => placement == 'both' || placement == where;

  /// What is wrong, by field, as `saveAd` would refuse it.
  Map<String, String> problems() => {
        if (title.trim().length < 2 || title.trim().length > 80) 'title': 'Use 2 to 80 characters.',
        if (text.trim().length > 200) 'text': 'Under 200 characters.',
        if (advertiser.trim().length > 80) 'advertiser': 'Under 80 characters.',
        if (linkUrl != null && !(Uri.tryParse(linkUrl!)?.isScheme('https') ?? false)) 'linkUrl': 'A full https:// address, or leave it empty.',
        if (startsOn != null && endsOn != null && startsOn!.compareTo(endsOn!) > 0) 'endsOn': 'It ends before it starts.',
      };

  Map<String, Object?> toCallable() => {
        if (id != null) 'adId': id,
        'title': title.trim(),
        'text': text.trim(),
        'advertiser': advertiser.trim(),
        if (linkUrl != null && linkUrl!.trim().isNotEmpty) 'linkUrl': linkUrl!.trim(),
        if (image != null) 'image': image,
        'placement': placement,
        'active': active,
        if (startsOn != null) 'startsOn': startsOn,
        if (endsOn != null) 'endsOn': endsOn,
      };

  AdRow copyWith({String? id, String? image}) => AdRow(
        id: id ?? this.id,
        title: title,
        text: text,
        advertiser: advertiser,
        linkUrl: linkUrl,
        image: image ?? this.image,
        placement: placement,
        active: active,
        startsOn: startsOn,
        endsOn: endsOn,
        updatedAt: updatedAt,
      );
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
  /// M-Pesa payments, newest first, optionally one [status]. Managers only.
  Future<RowPage<PaymentRow>> payments(StaffUser who, {String? status, String? after, int limit = 25});

  /// Help & feedback messages, newest first, optionally one [status]. Managers only.
  Future<List<FeedbackRow>> feedback(StaffUser who, {String? status});

  /// Every advert, newest first. Managers only.
  Future<List<AdRow>> ads(StaffUser who);

  /// [who]'s own staff record (Account), or null before they have one.
  Future<StaffMember?> me(StaffUser who);

  /// Edits to live listings: managers see those waiting; agents their own, newest first.
  Future<List<EditRequestRow>> editRequests(StaffUser who);

  /// The Dashboard for [who] at [now].
  Future<DashboardData> dashboard(StaffUser who, DateTime now);

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

/// The Dashboard (the admin's home): what needs doing now and how things
/// are going, for one staff member (agents: their own only).
class DashboardData {
  const DashboardData({
    required this.newLeads,
    required this.leadsByDay,
    required this.viewingsToday,
    required this.viewingsWeek,
    required this.liveListings,
    required this.pendingListings,
    required this.upcoming,
    required this.latestLeads,
    this.activity = const [],
  });

  /// Leads still at "new": nobody has replied yet.
  final int newLeads;

  /// Leads per day, the last [dashboardDays] days, oldest first (today last).
  final List<int> leadsByDay;

  /// Open (requested or confirmed) viewings today, and in the next 7 days.
  final int viewingsToday, viewingsWeek;

  final int liveListings;

  /// Waiting for a manager to approve; 0 for agents' own count of theirs.
  final int pendingListings;

  /// The next few open viewings, soonest first.
  final List<ViewingRow> upcoming;

  /// The newest leads still at "new".
  final List<LeadRow> latestLeads;

  /// The latest audit entries (managers and owners only).
  final List<AuditRow> activity;

  int get leadsInPeriod => leadsByDay.fold(0, (a, b) => a + b);
}

/// How many days the Dashboard's leads chart covers.
const dashboardDays = 14;

/// Buckets [times] into [dashboardDays] days ending on [now]'s day (local).
List<int> leadsPerDay(Iterable<DateTime> times, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final out = List.filled(dashboardDays, 0);
  for (final t in times) {
    final l = t.toLocal();
    final back = today.difference(DateTime(l.year, l.month, l.day)).inDays;
    if (back >= 0 && back < dashboardDays) out[dashboardDays - 1 - back]++;
  }
  return out;
}
