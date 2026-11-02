import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:realtor_core/realtor_core.dart';

/// Region the Cloud Functions are deployed in. Must match `REGION` in
/// functions/src/listing-rules.ts (a test checks this).
const functionsRegion = 'europe-west1';

/// How long a lead's details are kept (D12); quoted on the consent tick.
const leadRetentionMonths = 24;

/// Callable endpoint base for a project, e.g. `https://europe-west1-<project>.cloudfunctions.net`.
Uri functionsBase(String projectId) => Uri.parse('https://$functionsRegion-$projectId.cloudfunctions.net');

/// The two Cloud Functions the share pages call. Pages never write
/// Firestore themselves (D7): the Functions validate and store.
abstract interface class LeadApi {
  /// `createLead` with channel `form` and the consent tick.
  Future<void> createLead({required String listingId, required String phone, String? name, String? message});

  /// `logContactTap`: counts a call or WhatsApp tap, no personal data (D13).
  Future<void> logTap({required String listingId, required String channel});

  /// `logRecommendation` (P7-s04): counts "Similar homes" under [listingId]
  /// being `shown`, or one of them `opened`, on the web. Counts only.
  Future<void> logRecommendation({required String listingId, required String event});

  /// `bookViewing`: [slot] is ISO 8601 with the Nairobi offset.
  Future<void> bookViewing({required String listingId, required String slot, required String name, required String phone, String? message});

  /// `openSlots` (P4-s04): the free times on [day]; null when unknown.
  Future<List<String>?> openTimes({required String listingId, required String day});

  /// `submitReview` (P6-s03): the review link's [token] is the permission.
  Future<void> submitReview({required String token, required int rating, String? comment, String? name});
}

class LeadApiException implements Exception {
  LeadApiException(this.status, this.message);

  /// Callable error status, e.g. INVALID_ARGUMENT, NOT_FOUND, or HTTP_503.
  final String status;
  final String message;

  @override
  String toString() => 'LeadApiException($status: $message)';
}

/// An OIDC ID token for calling [audience] (Cloud Run IAM).
typedef IdTokenSource = Future<String> Function(Uri audience);

/// Calls the Functions over the callable HTTP protocol (POST {"data": ...}).
/// With [idToken] it calls their App Check-free twins instead (D16:
/// `shareCreateLead`, ...), which only the share pages' service account may
/// invoke, signing each request with a token for that URL.
class CallableLeadApi implements LeadApi {
  CallableLeadApi(this.base, {http.Client? client, this.idToken}) : _client = client ?? http.Client();
  final Uri base;
  final IdTokenSource? idToken;
  final http.Client _client;

  Future<Object?> _call(String name, Map<String, Object?> data, {bool twin = true}) async {
    final fn = idToken == null || !twin ? name : 'share${name[0].toUpperCase()}${name.substring(1)}';
    final url = Uri.parse('${base.toString().replaceFirst(RegExp(r'/$'), '')}/$fn');
    final res = await _client
        .post(url,
            headers: {'content-type': 'application/json', if (idToken != null && twin) 'authorization': 'Bearer ${await idToken!(url)}'},
            body: jsonEncode({'data': data}))
        .timeout(const Duration(seconds: 8));
    if (res.statusCode == 200) return (_tryDecode(res.body) as Map?)?['result'];
    final error = switch (_tryDecode(res.body)) {
      {'error': {'status': final String s, 'message': final String m}} => LeadApiException(s, m),
      _ => LeadApiException('HTTP_${res.statusCode}', 'callable $name failed'),
    };
    throw error;
  }

  static Object? _tryDecode(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> createLead({required String listingId, required String phone, String? name, String? message}) => _call('createLead', {
        'listingId': listingId,
        'channel': 'form',
        'contact': {'phone': phone, 'name': ?name},
        'message': ?message,
        'consent': true,
      });

  /// Read-only and public, so it needs no twin.
  @override
  Future<List<String>?> openTimes({required String listingId, required String day}) async {
    try {
      final r = await _call('openSlots', {'listingId': listingId, 'day': day}, twin: false) as Map?;
      return [for (final t in (r?['times'] as List?) ?? const []) '$t'];
    } on Object {
      return null;
    }
  }

  @override
  Future<void> submitReview({required String token, required int rating, String? comment, String? name}) =>
      _call('submitReview', {'token': token, 'rating': rating, 'comment': ?comment, 'name': ?name});

  @override
  Future<void> logTap({required String listingId, required String channel}) =>
      _call('logContactTap', {'listingId': listingId, 'channel': channel});

  @override
  Future<void> logRecommendation({required String listingId, required String event}) =>
      _call('logRecommendation', {'listingId': listingId, 'event': event, 'surface': 'web'});

  @override
  Future<void> bookViewing({required String listingId, required String slot, required String name, required String phone, String? message}) =>
      _call('bookViewing', {
        'listingId': listingId,
        'slot': slot,
        'client': {'name': name, 'phone': phone},
        'message': ?message,
        'consent': true,
      });
}

/// What a visitor typed into the enquiry form, checked before any call.
class Enquiry {
  Enquiry._(this.phone, this.name, this.message);
  final String phone;
  final String? name, message;

  /// Field name -> problem, for re-showing the form.
  static ({Enquiry? enquiry, Map<String, String> errors}) parse(Map<String, String> form) {
    final errors = <String, String>{};
    final phone = normaliseKenyanPhone(form['phone'] ?? '');
    final name = (form['name'] ?? '').trim();
    final message = (form['message'] ?? '').trim();
    if (phone == null) errors['phone'] = 'Enter a Kenyan mobile number, like 0712 345 678.';
    if (name.length > 80) errors['name'] = 'Keep your name under 80 characters.';
    if (message.length > 2000) errors['message'] = 'Keep the message under 2,000 characters.';
    if (form['consent'] != 'yes') errors['consent'] = 'Tick the box so we may contact you.';
    return (
      enquiry: errors.isEmpty ? Enquiry._(phone!, name.isEmpty ? null : name, message.isEmpty ? null : message) : null,
      errors: errors,
    );
  }
}

/// What a visitor typed into the viewing form, checked before any call.
class ViewingRequest {
  ViewingRequest._(this.slot, this.name, this.phone, this.message);

  /// e.g. `2026-10-27T10:30:00+03:00`.
  final String slot;
  final String name, phone;
  final String? message;

  static ({ViewingRequest? request, Map<String, String> errors}) parse(Map<String, String> form) {
    final errors = <String, String>{};
    final day = form['day'] ?? '';
    final time = form['time'] ?? '';
    final name = (form['name'] ?? '').trim();
    final phone = normaliseKenyanPhone(form['phone'] ?? '');
    final message = (form['message'] ?? '').trim();
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day) || !viewingTimes.contains(time)) errors['slot'] = 'Pick a day and a time.';
    if (name.isEmpty || name.length > 80) errors['name'] = 'Enter your name so the agent knows who to expect.';
    if (phone == null) errors['phone'] = 'Enter a Kenyan mobile number, like 0712 345 678.';
    if (message.length > 2000) errors['message'] = 'Keep the message under 2,000 characters.';
    if (form['consent'] != 'yes') errors['consent'] = 'Tick the box so we may contact you.';
    return (
      request: errors.isEmpty ? ViewingRequest._(viewingSlot(day, time), name, phone!, message.isEmpty ? null : message) : null,
      errors: errors,
    );
  }
}

/// ID tokens from the Cloud Run metadata server for the service's own
/// account, kept for 50 minutes (they last an hour).
class MetadataIdTokens {
  MetadataIdTokens({http.Client? client, DateTime Function()? now}) : _client = client ?? http.Client(), _now = now ?? DateTime.now;
  final http.Client _client;
  final DateTime Function() _now;
  final _cache = <Uri, ({String token, DateTime until})>{};

  Future<String> call(Uri audience) async {
    final hit = _cache[audience];
    if (hit != null && _now().isBefore(hit.until)) return hit.token;
    final res = await _client
        .get(
          Uri.http('metadata.google.internal', '/computeMetadata/v1/instance/service-accounts/default/identity', {'audience': '$audience'}),
          headers: {'Metadata-Flavor': 'Google'},
        )
        .timeout(const Duration(seconds: 3));
    if (res.statusCode != 200) throw LeadApiException('HTTP_${res.statusCode}', 'no identity token');
    _cache[audience] = (token: res.body.trim(), until: _now().add(const Duration(minutes: 50)));
    return res.body.trim();
  }
}
