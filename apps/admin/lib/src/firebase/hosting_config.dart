import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;

/// Firebase Hosting serves the linked web app's config here, so the admin
/// needs none in the repo (infra: google_firebase_hosting_site.admin).
const hostingConfigPath = '/__/firebase/init.json';

/// The config from Hosting, or null when the admin isn't served by Firebase
/// Hosting (`flutter run`, tests, any other server): then it runs on demo data.
Future<FirebaseOptions?> hostingFirebaseOptions(Uri origin, {http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final r = await c.get(Uri(scheme: origin.scheme, host: origin.host, port: origin.port, path: hostingConfigPath));
    if (r.statusCode != 200) return null;
    return parseHostingConfig(r.body);
  } on Exception {
    return null;
  } finally {
    if (client == null) c.close();
  }
}

/// Null unless [body] is a Hosting init.json with the fields Firebase needs.
FirebaseOptions? parseHostingConfig(String body) {
  final Object? json;
  try {
    json = jsonDecode(body);
  } on FormatException {
    return null;
  }
  if (json is! Map<String, Object?>) return null;
  final map = json;
  String? s(String k) => map[k] is String && (map[k] as String).isNotEmpty ? map[k] as String : null;
  final apiKey = s('apiKey'), appId = s('appId'), projectId = s('projectId'), sender = s('messagingSenderId');
  if (apiKey == null || appId == null || projectId == null || sender == null) return null;
  return FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    projectId: projectId,
    messagingSenderId: sender,
    authDomain: s('authDomain'),
    storageBucket: s('storageBucket'),
  );
}
