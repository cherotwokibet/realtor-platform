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

  @override
  Future<void> setStaffRole(StaffUser who, {required String email, required StaffRole? role, String? agentId}) =>
      _run('setStaffRole', {
        'email': email.trim(),
        'role': role?.name,
        if (role == StaffRole.agent) 'agentId': agentId,
      });

  Future<void> _run(String name, Map<String, Object?> data) async {
    try {
      await _call(name, data);
    } on FirebaseException catch (e) {
      // FirebaseFunctionsException is one of these; its code is the callable
      // status. On the web the code can carry a "functions/" prefix and the
      // message an HTTP status, e.g. "... [400]": keep what a person reads.
      final code = e.code.replaceFirst('functions/', '');
      final message = (e.message ?? code).replaceFirst(RegExp(r'\s*\[\d{3}\]$'), '');
      throw AdminActionException(code, message);
    }
  }
}
