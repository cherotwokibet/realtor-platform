import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:realtor_core/realtor_core.dart';

/// Calls one callable Function by name with [data]; completes with what it returns.
typedef CallFunction = Future<Object?> Function(String name, Map<String, Object?> data);

/// The admin's changes as Functions calls (D7). The signed-in user travels
/// in the ID token, so [StaffUser] is not sent: the Functions read the claims.
class CallableAdminActions implements AdminActions {
  CallableAdminActions(this._call);

  factory CallableAdminActions.firebase(FirebaseFunctions functions) =>
      CallableAdminActions((name, data) async => (await functions.httpsCallable(name).call<Object?>(data)).data);

  final CallFunction _call;

  @override
  Future<void> moveLead(StaffUser who, {required String leadId, required String stage}) => _run('updateLeadStage', {'leadId': leadId, 'stage': stage});

  @override
  Future<void> moderateListing(StaffUser who, {required String listingId, required String action, String? reason}) =>
      _run('moderateListing', {'listingId': listingId, 'action': action, if (reason != null) 'reason': reason});

  @override
  Future<DateTime> confirmListing(StaffUser who, {required String listingId}) async {
    final r = await _run('confirmListing', {'listingId': listingId}) as Map<Object?, Object?>;
    return DateTime.parse(r['expiresAt'] as String);
  }

  @override
  Future<void> updateViewing(StaffUser who, {required String viewingId, required String status}) =>
      _run('updateViewingStatus', {'viewingId': viewingId, 'status': status});

  @override
  Future<String> rescheduleViewing(StaffUser who, {required String viewingId, required String slot}) async {
    final r = await _run('rescheduleViewing', {'viewingId': viewingId, 'slot': slot}) as Map<Object?, Object?>;
    return r['viewingId'] as String;
  }

  @override
  Future<String> addTimeOff(StaffUser who, {String? agentId, required String start, required String end, String? note}) async {
    final r = await _run('addAgentBlock', {
      if (agentId != null) 'agentId': agentId,
      'start': start,
      'end': end,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    }) as Map<Object?, Object?>;
    return r['blockId'] as String;
  }

  @override
  Future<MonthlyReport> monthlyReport(StaffUser who, String month) async =>
      MonthlyReport.fromJson(await _run('monthlyReport', {'month': month}) as Map<Object?, Object?>);

  @override
  Future<({double? rating, int count})> moderateReview(StaffUser who, {required String reviewId, required String action}) async {
    final r = await _run('moderateReview', {'reviewId': reviewId, 'action': action}) as Map<Object?, Object?>;
    return (rating: (r['rating'] as num?)?.toDouble(), count: (r['ratingCount'] as num?)?.toInt() ?? 0);
  }

  @override
  Future<void> savePage(StaffUser who, SitePageRow page) =>
      _run('savePage', {'slug': page.slug, 'title': page.title.trim(), 'body': page.body, 'published': page.published});

  @override
  Future<String> saveArea(StaffUser who, AreaGuide area) async {
    final r = await _run('saveArea', area.toCallable()) as Map<Object?, Object?>;
    return r['slug'] as String;
  }

  @override
  Future<String> saveProject(StaffUser who, OffPlanProject project) async {
    final r = await _run('saveProject', project.toCallable()) as Map<Object?, Object?>;
    return r['slug'] as String;
  }

  @override
  Future<String> saveAgent(StaffUser who, AgentProfile profile) async {
    final r = await _run('saveAgent', profile.toCallable()) as Map<Object?, Object?>;
    return r['agentId'] as String;
  }

  @override
  Future<void> removeTimeOff(StaffUser who, {required String blockId}) => _run('removeAgentBlock', {'blockId': blockId});

  @override
  Future<DateTime?> featureListing(StaffUser who, {required String listingId, required int days}) async {
    final r = await _run('featureListing', {'listingId': listingId, 'days': days}) as Map<Object?, Object?>;
    final until = r['featuredUntil'] as String?;
    return until == null ? null : DateTime.parse(until);
  }

  @override
  Future<bool> setHotListing(StaffUser who, {required String listingId, required bool hot}) async {
    final r = await _run('setHotListing', {'listingId': listingId, 'hot': hot}) as Map<Object?, Object?>;
    return r['hot'] == true;
  }

  @override
  Future<bool> setPlacement(StaffUser who, {required String listingId, required String placement, required bool on}) async {
    final r = await _run('setPlacement', {'listingId': listingId, 'placement': placement, 'on': on}) as Map<Object?, Object?>;
    return r['on'] == true;
  }

  @override
  Future<void> moderateEdit(StaffUser who, {required String listingId, required bool approve, String? reason}) =>
      _run('moderateEdit', {'listingId': listingId, 'action': approve ? 'approve' : 'reject', if (reason != null) 'reason': reason});

  @override
  Future<String> submitListing(StaffUser who, ListingDraft draft) async {
    final r = await _run('submitListing', draft.toCallable()) as Map<Object?, Object?>;
    return r['listingId'] as String;
  }

  @override
  Future<ImportOutcome> importListings(StaffUser who, List<Map<String, Object?>> rows) async {
    final r = await _run('importListings', {'rows': rows}) as Map<Object?, Object?>;
    return ImportOutcome(
      created: [for (final c in r['created'] as List) ((c as Map)['row'] as num).toInt()],
      failed: [
        for (final f in r['failed'] as List) (row: ((f as Map)['row'] as num).toInt(), error: f['error'] as String),
      ],
    );
  }

  @override
  Future<void> setStaffRole(StaffUser who, {required String email, required StaffRole? role, String? agentId}) => _run('setStaffRole', {
        'email': email.trim(),
        'role': role?.name,
        if (role == StaffRole.agent) 'agentId': agentId,
      });

  @override
  Future<void> saveMyProfile(StaffUser who, {required String name, String? phone}) => _run('saveStaffProfile', {'name': name.trim(), 'phone': phone});

  @override
  Future<void> updateFeedback(StaffUser who, {required String feedbackId, String? status, String? note}) =>
      _run('updateFeedback', {'feedbackId': feedbackId, if (status != null) 'status': status, if (note != null && note.trim().isNotEmpty) 'note': note.trim()});

  @override
  Future<String> saveAd(StaffUser who, AdRow ad) async => ((await _run('saveAd', ad.toCallable())) as Map<Object?, Object?>)['adId'] as String;

  @override
  Future<void> deleteAd(StaffUser who, String adId) => _run('deleteAd', {'adId': adId});

  @override
  Future<DataRequestResult> dataRequest(StaffUser who, {required DataRequestKind kind, String? phone, String? email}) async {
    final r = await _run('dataRequest', {
      'kind': kind.name,
      if (phone != null) 'phone': phone,
      if (email != null) 'email': email.trim(),
    }) as Map<Object?, Object?>;
    if (kind == DataRequestKind.export) {
      final data = r['data'] as Map<Object?, Object?>;
      return DataRequestResult(
        kind: kind,
        leads: (data['leads'] as List).length,
        viewings: (data['viewings'] as List).length,
        reviews: (data['reviews'] as List?)?.length ?? 0,
        feedback: (data['feedback'] as List?)?.length ?? 0,
        exportJson: const JsonEncoder.withIndent('  ').convert(data),
      );
    }
    final deleted = r['deleted'] as Map<Object?, Object?>;
    return DataRequestResult(
      kind: kind,
      leads: deleted['leads'] as int,
      viewings: deleted['viewings'] as int,
      reviews: (deleted['reviews'] as num?)?.toInt() ?? 0,
      feedback: (deleted['feedback'] as num?)?.toInt() ?? 0,
    );
  }

  Future<Object?> _run(String name, Map<String, Object?> data) async {
    try {
      return await _call(name, data);
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
