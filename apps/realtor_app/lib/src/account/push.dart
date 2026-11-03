import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Push alerts on the phone (P4-s03): the 5-minute sweep sends one
/// notification per person to each phone registered here, and a tap opens
/// the home (or Account when there are several). The in-app inbox works
/// without them; web push waits for a VAPID key.
abstract interface class PushAlerts {
  /// Asks the phone for permission (Android 13+, iOS) and registers it for
  /// [uid]. False when refused or not supported here.
  Future<bool> enable(String uid);

  /// Registers again when permission was already given: a new token after
  /// a reinstall, or another account signed in on this phone.
  Future<void> resume(String uid);

  /// Stops pushes to this phone for [uid], before signing out.
  Future<void> disable(String uid);

  /// App paths opened by tapping a notification.
  Stream<String> get opened;
}

/// Web and the demo build: no push.
class NoPushAlerts implements PushAlerts {
  const NoPushAlerts();
  @override
  Future<bool> enable(String uid) async => false;
  @override
  Future<void> resume(String uid) async {}
  @override
  Future<void> disable(String uid) async {}
  @override
  Stream<String> get opened => const Stream.empty();
}

/// Only paths inside the app; anything else in a message is ignored.
String? appPathFrom(Object? path) {
  if (path is! String || !path.startsWith('/') || path.startsWith('//') || path.length > 300) return null;
  return path;
}

final pushAlertsProvider = Provider<PushAlerts>((ref) => const NoPushAlerts());
