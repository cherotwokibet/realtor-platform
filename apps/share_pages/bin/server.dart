import 'dart:convert';
import 'dart:io';

import 'package:jaspr/server.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:share_pages/share_pages.dart';
import 'package:shelf/shelf_io.dart' as io;

/// Cloud Run entry point. TENANT_FILE points at `tenants/<id>.json` (copied
/// into the image at build time); PORT is set by Cloud Run.
/// Listings come from the tenant's prod Firestore (FIRESTORE_PROJECT to
/// override, FIRESTORE_EMULATOR_HOST for local runs against the emulator).
Future<void> main() async {
  Jaspr.initializeApp();
  final tenant = TenantConfig.fromJson(
    jsonDecode(await File(Platform.environment['TENANT_FILE'] ?? 'tenant.json').readAsString()) as Map<String, Object?>,
  );
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final env = Platform.environment;
  final source = FirestoreListingSource(
    projectId: env['FIRESTORE_PROJECT'] ?? tenant.firebaseProjects[FirebaseEnv.prod]!,
    emulatorHost: env['FIRESTORE_EMULATOR_HOST'],
  );
  final server = await io.serve(shareHandler(tenant, source), InternetAddress.anyIPv4, port);
  stdout.writeln('share pages for ${tenant.id} on :${server.port}');
}
