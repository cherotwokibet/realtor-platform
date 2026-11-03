import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../account/push.dart';

/// What the app needs from FCM, so the registration logic is testable.
abstract interface class PushClient {
  Future<bool> requestPermission();
  Future<bool> hasPermission();
  Future<String?> token();
  Stream<String> get tokenRefresh;
  Future<void> deleteToken();

  /// Data of the notification that started the app, then of each tapped later.
  Stream<Map<String, Object?>> get tapped;
}

/// FCM registration tokens: firebase_messaging 17 marks them deprecated in
/// favour of installation IDs, but the Admin SDK sends to tokens, and they
/// keep working.
// ignore_for_file: deprecated_member_use
class FcmPushClient implements PushClient {
  FcmPushClient(this._fcm);
  final FirebaseMessaging _fcm;

  static bool _allowed(NotificationSettings s) =>
      s.authorizationStatus == AuthorizationStatus.authorized || s.authorizationStatus == AuthorizationStatus.provisional;

  @override
  Future<bool> requestPermission() async => _allowed(await _fcm.requestPermission());
  @override
  Future<bool> hasPermission() async => _allowed(await _fcm.getNotificationSettings());
  @override
  Future<String?> token() => _fcm.getToken();
  @override
  Stream<String> get tokenRefresh => _fcm.onTokenRefresh;
  @override
  Future<void> deleteToken() => _fcm.deleteToken();
  @override
  Stream<Map<String, Object?>> get tapped async* {
    final first = await _fcm.getInitialMessage();
    if (first != null) yield first.data;
    yield* FirebaseMessaging.onMessageOpenedApp.map((m) => m.data);
  }
}

/// Registers this phone under users/{uid}/devices/{token}, in the shape
/// firestore.rules allow; the sweep reads them and forgets dead tokens.
class DevicePushAlerts implements PushAlerts {
  DevicePushAlerts(this._client, this._db, {required this.platform}) {
    _tapped = _client.tapped.map((d) => appPathFrom(d['path'])).where((p) => p != null).cast<String>().asBroadcastStream();
  }
  final PushClient _client;
  final FirebaseFirestore _db;

  /// 'android' or 'ios'.
  final String platform;
  late final Stream<String> _tapped;
  String? _uid;
  StreamSubscription<String>? _refresh;

  CollectionReference<Map<String, Object?>> _devices(String uid) => _db.collection('users').doc(uid).collection('devices');

  Future<bool> _register(String uid) async {
    final token = await _client.token();
    if (token == null || token.isEmpty) return false;
    await _save(uid, token);
    _uid = uid;
    _refresh ??= _client.tokenRefresh.listen((t) {
      final u = _uid;
      if (u != null) unawaited(_save(u, t));
    });
    return true;
  }

  Future<void> _save(String uid, String token) =>
      _devices(uid).doc(token).set({'token': token, 'platform': platform, 'updatedAt': FieldValue.serverTimestamp()});

  @override
  Future<bool> enable(String uid) async {
    if (!await _client.requestPermission()) return false;
    return _register(uid);
  }

  @override
  Future<void> resume(String uid) async {
    if (await _client.hasPermission()) await _register(uid);
  }

  @override
  Future<void> disable(String uid) async {
    _uid = null;
    if (!await _client.hasPermission()) return;
    final token = await _client.token();
    if (token != null) await _devices(uid).doc(token).delete();
    // A new token next time, so a later account on this phone starts clean.
    await _client.deleteToken();
  }

  @override
  Stream<String> get opened => _tapped;
}
