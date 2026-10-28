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

/// `moderateListing` action → the status it sets.
const moderationTargets = {'approve': 'live', 'reject': 'draft', 'expire': 'expired', 'let': 'let', 'sold': 'sold'};

/// The stages a lead at [stage] can move to.
List<String> nextLeadStages(String stage) => leadStageMoves[stage] ?? const [];

/// What [who] may do to a listing from its status menu: managers moderate,
/// and the listing's agent (or a manager) confirms a live or expired one.
List<String> listingActionsFor(StaffUser who, {required String status, required String agentId, bool featured = false}) => [
      if (who.isManager) ...moderationsFor(status),
      if ((status == 'live' || status == 'expired') && (who.isManager || who.agentId == agentId)) 'confirm',
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

  /// `featureListing` (P5-s02), managers: a live listing ranks first in
  /// search for [days]; 0 stops it. Completes with the new end, or null.
  Future<DateTime?> featureListing(StaffUser who, {required String listingId, required int days});

  /// `importListings` (P5-s02), managers: each row (see [ListingCsv]) becomes
  /// a pending listing; at most [importChunk] rows per call.
  Future<ImportOutcome> importListings(StaffUser who, List<Map<String, Object?>> rows);

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
  const DataRequestResult({required this.kind, required this.leads, required this.viewings, this.exportJson});

  final DataRequestKind kind;
  final int leads, viewings;

  /// The person's records as indented JSON, for an export; null for a delete.
  final String? exportJson;

  bool get foundNothing => leads == 0 && viewings == 0;
}
