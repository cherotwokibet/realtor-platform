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

  /// `bookViewing`: [slot] is ISO 8601 with the Nairobi offset.
  Future<void> bookViewing({required String listingId, required String slot, required String name, required String phone, String? message});
}

class LeadApiException implements Exception {
  LeadApiException(this.status, this.message);

  /// Callable error status, e.g. INVALID_ARGUMENT, NOT_FOUND, or HTTP_503.
  final String status;
  final String message;

  @override
  String toString() => 'LeadApiException($status: $message)';
}

/// Calls the Functions over the callable HTTP protocol (POST {"data": ...}).
class CallableLeadApi implements LeadApi {
  CallableLeadApi(this.base, {http.Client? client}) : _client = client ?? http.Client();
  final Uri base;
  final http.Client _client;

  Future<void> _call(String name, Map<String, Object?> data) async {
    final res = await _client
        .post(Uri.parse('${base.toString().replaceFirst(RegExp(r'/$'), '')}/$name'),
            headers: {'content-type': 'application/json'}, body: jsonEncode({'data': data}))
        .timeout(const Duration(seconds: 8));
    if (res.statusCode == 200) return;
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
        'contact': {'phone': phone, if (name != null) 'name': name},
        if (message != null) 'message': message,
        'consent': true,
      });

  @override
  Future<void> logTap({required String listingId, required String channel}) =>
      _call('logContactTap', {'listingId': listingId, 'channel': channel});

  @override
  Future<void> bookViewing({required String listingId, required String slot, required String name, required String phone, String? message}) =>
      _call('bookViewing', {
        'listingId': listingId,
        'slot': slot,
        'client': {'name': name, 'phone': phone},
        if (message != null) 'message': message,
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

/// Viewing slots offered on the form. They mirror `VIEWING_RULES` in
/// functions/src/api/viewings.ts, which has the final say: half-hour starts
/// 08:00-17:30 Nairobi time (UTC+3 all year), Monday to Saturday.
final viewingTimes = [
  for (var m = 8 * 60; m <= 17 * 60 + 30; m += 30) '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}',
];

/// The next [count] viewing days (no Sundays), from today in Nairobi:
/// value `2026-10-27`, label `Tue 27 Oct`.
List<({String value, String label})> viewingDays(DateTime now, {int count = 12}) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final nairobi = now.toUtc().add(const Duration(hours: 3));
  var d = DateTime.utc(nairobi.year, nairobi.month, nairobi.day);
  final out = <({String value, String label})>[];
  while (out.length < count) {
    if (d.weekday != DateTime.sunday) {
      final value = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      out.add((value: value, label: '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]}'));
    }
    d = d.add(const Duration(days: 1));
  }
  return out;
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
      request: errors.isEmpty ? ViewingRequest._('${day}T$time:00+03:00', name, phone!, message.isEmpty ? null : message) : null,
      errors: errors,
    );
  }
}
