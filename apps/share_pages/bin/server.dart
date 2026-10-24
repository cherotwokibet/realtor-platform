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
/// Enquiries and WhatsApp taps go to the project's Cloud Functions
/// (FUNCTIONS_BASE to override, e.g. the Functions emulator).
Future<void> main() async {
  Jaspr.initializeApp();
  final tenant = TenantConfig.fromJson(
    jsonDecode(await File(Platform.environment['TENANT_FILE'] ?? 'tenant.json').readAsString()) as Map<String, Object?>,
  );
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final env = Platform.environment;
  final projectId = env['FIRESTORE_PROJECT'] ?? tenant.firebaseProjects[FirebaseEnv.prod]!;
  final source = FirestoreListingSource(projectId: projectId, emulatorHost: env['FIRESTORE_EMULATOR_HOST']);
  final leads = CallableLeadApi(env['FUNCTIONS_BASE'] != null ? Uri.parse(env['FUNCTIONS_BASE']!) : functionsBase(projectId));
  final server = await io.serve(shareHandler(tenant, source, leads: leads), InternetAddress.anyIPv4, port);
  stdout.writeln('share pages for ${tenant.id} on :${server.port}');
}
