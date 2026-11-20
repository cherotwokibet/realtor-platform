import 'admin_repository.dart' show AdRow, SitePageRow;
import 'agent_profile.dart';
import 'area_guide.dart';
import 'off_plan_project.dart';
import 'listing_draft.dart';
import 'monthly_report.dart';
import 'staff.dart';

/// Lead stage moves, listing status moves and moderation actions. A copy of
/// functions/src/model/transitions.json, which the Functions enforce; the
/// admin only uses it to offer the moves that can succeed. A test checks the
/// two match.
const leadStageMoves = {
  'new': ['contacted', 'lost'],
  'contacted': ['viewing', 'offer', 'lost'],
  'viewing': ['offer', 'won', 'lost'],
  'offer': ['won', 'lost'],
  'won': <String>[],
  'lost': ['contacted'],
};

const listingStatusMoves = {
  'draft': ['pending'],
  'pending': ['live', 'draft'],
  'live': ['expired', 'let', 'sold', 'draft'],
  'expired': ['pending', 'live'],
  'let': ['live'],
  'sold': <String>[],
};

const viewingStatusMoves = {
  'requested': ['confirmed', 'cancelled'],
  'confirmed': ['done', 'no-show', 'cancelled'],
  'done': <String>[],
  'no-show': <String>[],
  'cancelled': <String>[],
};

/// The moves a viewing at [status] can take at [now]: done and no-show
/// only once its time has passed (the Functions refuse them earlier).
List<String> nextViewingStatuses(String status, DateTime slot, DateTime now) => [
      for (final s in viewingStatusMoves[status] ?? const <String>[])
        if ((s != 'done' && s != 'no-show') || !slot.isAfter(now)) s
    ];

/// `moderateListing` action → the status it sets.
const moderationTargets = {'approve': 'live', 'reject': 'draft', 'expire': 'expired', 'let': 'let', 'sold': 'sold'};

/// The stages a lead at [stage] can move to.
List<String> nextLeadStages(String stage) => leadStageMoves[stage] ?? const [];

/// What [who] may do to a listing from its status menu: managers moderate,
/// and the listing's agent (or a manager) confirms a live or expired one.
List<String> listingActionsFor(StaffUser who, {required String status, required String agentId, bool featured = false, bool hot = false}) => [
      if (who.isManager) ...moderationsFor(status),
      if ((status == 'live' || status == 'expired') && (who.isManager || who.agentId == agentId)) 'confirm',
      if (who.isManager && status == 'live') hot ? 'unhot' : 'hot',
      if (who.isManager && status == 'live') featured ? 'unfeature' : 'feature',
    ];

/// How long "Feature" features a listing, in days.
const featureDays = 30;

/// Rows per `importListings` call (the Function's limit).
const importChunk = 100;

/// What an import did, by row of the batch sent (1-based).
class ImportOutcome {
  const ImportOutcome({required this.created, required this.failed});
  final List<int> created;
  final List<({int row, String error})> failed;
}

/// The moderation actions a listing at [status] can take, in table order.
List<String> moderationsFor(String status) {
  final moves = listingStatusMoves[status] ?? const [];
  return [
    for (final e in moderationTargets.entries)
      if (moves.contains(e.value)) e.key
  ];
}

/// A change the Functions refused or could not make.
class AdminActionException implements Exception {
  AdminActionException(this.code, this.message);

  /// Callable status, e.g. `permission-denied`, `failed-precondition`.
  final String code;
  final String message;

  @override
  String toString() => 'AdminActionException($code: $message)';
}

/// The staff changes the admin asks the Functions to make (D7): they check
/// the role, apply the change and write the audit log in one transaction.
abstract interface class AdminActions {
  /// `updateLeadStage`. Agents move their own leads; managers move any.
  Future<void> moveLead(StaffUser who, {required String leadId, required String stage});

  /// `moderateListing`: approve, reject (needs [reason]), expire, let or sold. Managers only.
  Future<void> moderateListing(StaffUser who, {required String listingId, required String action, String? reason});

  /// `confirmListing` (P6-s02): the listing's agent, or a manager, confirms a
  /// live or expired listing is still available. It goes live, verified for
  /// another 30 days; completes with the new expiry.
  Future<DateTime> confirmListing(StaffUser who, {required String listingId});

  /// `updateViewingStatus` (P5-s05): the viewing's agent, or a manager.
  Future<void> updateViewing(StaffUser who, {required String viewingId, required String status});

  /// `rescheduleViewing` (P5-s05): moves an open viewing to [slot] (as
  /// [viewingSlot] makes it), confirmed; the old one is cancelled.
  /// Completes with the new viewing's id.
  Future<String> rescheduleViewing(StaffUser who, {required String viewingId, required String slot});

  /// `addAgentBlock` (P5-s05): blocks out [start] to [end] (ISO 8601 with
  /// offset) so no viewing is booked then. Managers name the agent; an agent
  /// always blocks for themself. Completes with the block's id.
  Future<String> addTimeOff(StaffUser who, {String? agentId, required String start, required String end, String? note});

  /// `monthlyReport` (P5-s08), managers: [month] is `YYYY-MM`.
  Future<MonthlyReport> monthlyReport(StaffUser who, String month);

  /// `moderateReview` (P6-s03), managers: `approve` shows a review, `hide`
  /// takes it down. Completes with the agent's new rating (null with none).
  Future<({double? rating, int count})> moderateReview(StaffUser who, {required String reviewId, required String action});

  /// `savePage` (P5-s07), managers: a site page's title, text and whether
  /// the share site shows it.
  Future<void> savePage(StaffUser who, SitePageRow page);

  /// `saveArea` (P3-s05), managers: adds or edits an area guide. Completes
  /// with its slug.
  Future<String> saveArea(StaffUser who, AreaGuide area);

  /// `saveProject` (P5-s06), managers: adds or edits an off-plan project.
  /// Completes with its slug.
  Future<String> saveProject(StaffUser who, OffPlanProject project);

  /// `saveAgent` (P5-s04), managers: adds or edits an agent's profile.
  /// Completes with the agent's id.
  Future<String> saveAgent(StaffUser who, AgentProfile profile);

  /// `removeAgentBlock`: the agent's own, or any for managers.
  Future<void> removeTimeOff(StaffUser who, {required String blockId});

  /// `featureListing` (P5-s02), managers: a live listing ranks first in
  /// search for [days]; 0 stops it. Completes with the new end, or null.
  Future<DateTime?> featureListing(StaffUser who, {required String listingId, required int days});

  /// `setHotListing`, managers: puts a live listing in the home page's Hot
  /// Properties, or takes it out. Completes with the new state.
  Future<bool> setHotListing(StaffUser who, {required String listingId, required bool hot});

  /// `setPlacement`, managers: a live listing in or out of a home page row
  /// ('hot', 'recommended', or 'newest' to pin it first). Featured is [featureListing].
  Future<bool> setPlacement(StaffUser who, {required String listingId, required String placement, required bool on});

  /// `moderateEdit`, managers: apply an agent's waiting edit, or reject it with [reason].
  Future<void> moderateEdit(StaffUser who, {required String listingId, required bool approve, String? reason});

  /// `submitListing` (P5-s02): creates or edits a listing and sends it for
  /// review (pending). Agents submit their own; managers for any agent.
  /// Completes with the listing id.
  Future<String> submitListing(StaffUser who, ListingDraft draft);

  /// `importListings` (P5-s02), managers: each row (see [ListingCsv]) becomes
  /// a pending listing; at most [importChunk] rows per call.
  Future<ImportOutcome> importListings(StaffUser who, List<Map<String, Object?>> rows);

  /// `saveStaffProfile`: any staff member's own name and phone (Account).
  Future<void> saveMyProfile(StaffUser who, {required String name, String? phone});

  /// `updateFeedback`, managers: a message's status (new, open, resolved) and/or a note.
  Future<void> updateFeedback(StaffUser who, {required String feedbackId, String? status, String? note});

  /// `saveAd`, managers: creates ([AdRow.id] null) or replaces an advert; returns its id.
  Future<String> saveAd(StaffUser who, AdRow ad);

  /// `deleteAd`, managers.
  Future<void> deleteAd(StaffUser who, String adId);

  /// `setStaffRole`, owners only: give an account that has signed in once a
  /// role (an agent needs [agentId]), or take it away with a null [role].
  Future<void> setStaffRole(StaffUser who, {required String email, required StaffRole? role, String? agentId});

  /// `dataRequest`, owners and managers (DPA 2019): everything held about
  /// one person, found by an E.164 [phone] or an [email], exported or deleted.
  Future<DataRequestResult> dataRequest(StaffUser who, {required DataRequestKind kind, String? phone, String? email});
}

enum DataRequestKind { export, delete }

/// What a data request found (export) or removed (delete).
class DataRequestResult {
  const DataRequestResult({required this.kind, required this.leads, required this.viewings, this.reviews = 0, this.feedback = 0, this.exportJson});

  final DataRequestKind kind;

  /// Reviews left after the person's viewings (P6-s03).
  final int leads, viewings, reviews;

  /// Messages they sent through Help & feedback.
  final int feedback;

  /// The person's records as indented JSON, for an export; null for a delete.
  final String? exportJson;

  bool get foundNothing => leads == 0 && viewings == 0 && feedback == 0;
}
