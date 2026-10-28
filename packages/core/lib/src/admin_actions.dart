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

  /// `setStaffRole`, owners only: give an account that has signed in once a
  /// role (an agent needs [agentId]), or take it away with a null [role].
  Future<void> setStaffRole(StaffUser who, {required String email, required StaffRole? role, String? agentId});
}
