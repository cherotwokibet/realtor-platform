import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:realtor_core/realtor_core.dart';

/// Calls one callable Function by name with [data].
typedef CallFunction = Future<void> Function(String name, Map<String, Object?> data);

/// The admin's changes as Functions calls (D7). The signed-in user travels
/// in the ID token, so [StaffUser] is not sent: the Functions read the claims.
class CallableAdminActions implements AdminActions {
  CallableAdminActions(this._call);

  factory CallableAdminActions.firebase(FirebaseFunctions functions) =>
      CallableAdminActions((name, data) => functions.httpsCallable(name).call<Object?>(data));

  final CallFunction _call;

  @override
  Future<void> moveLead(StaffUser who, {required String leadId, required String stage}) =>
      _run('updateLeadStage', {'leadId': leadId, 'stage': stage});

  @override
  Future<void> moderateListing(StaffUser who, {required String listingId, required String action, String? reason}) =>
      _run('moderateListing', {'listingId': listingId, 'action': action, if (reason != null) 'reason': reason});

  Future<void> _run(String name, Map<String, Object?> data) async {
    try {
      await _call(name, data);
    } on FirebaseException catch (e) {
      // FirebaseFunctionsException is one of these; its code is the callable status.
      throw AdminActionException(e.code, e.message ?? e.code);
    }
  }
}
