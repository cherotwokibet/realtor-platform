import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter/services.dart' show AssetBundle;
import 'package:http/http.dart' as http;

/// Firebase Hosting serves the linked web app's config here, so neither the
/// admin nor the customer web app needs one in the repo (infra: the Hosting
/// sites in modules/firebase-env).
const hostingConfigPath = '/__/firebase/init.json';

/// The config from Hosting, or null when the app isn't served by Firebase
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

/// On Android and iOS: the settings `tenant firebase-config` wrote beside
/// tenant.json ([dir]/firebase.json, generated and never committed). Null
/// when there is none, or none for [platform]: the app runs on demo data.
Future<FirebaseOptions?> bundledFirebaseOptions(AssetBundle bundle, String dir, TargetPlatform platform) async {
  final String body;
  try {
    body = await bundle.loadString('$dir/firebase.json');
  } on Exception {
    return null;
  } on Error {
    return null; // FlutterError: the asset is not in the bundle
  }
  return parseBundledConfig(body, platform);
}

FirebaseOptions? parseBundledConfig(String body, TargetPlatform platform) {
  final Object? json;
  try {
    json = jsonDecode(body);
  } on FormatException {
    return null;
  }
  if (json is! Map<String, Object?>) return null;
  final app = json[platform == TargetPlatform.iOS ? 'ios' : 'android'];
  final projectId = json['projectId'], sender = json['messagingSenderId'];
  if (app is! Map || projectId is! String || sender is! String || app['appId'] is! String || app['apiKey'] is! String) return null;
  return FirebaseOptions(
    apiKey: app['apiKey'] as String,
    appId: app['appId'] as String,
    projectId: projectId,
    messagingSenderId: sender,
    storageBucket: json['storageBucket'] as String?,
    iosBundleId: app['bundleId'] as String?,
  );
}
