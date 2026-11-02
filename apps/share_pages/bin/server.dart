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
/// FONTS_DIR is the folder of bundled fonts (/app/fonts in the image),
/// BRAND_DIR the tenant's logo SVGs (/app/brand).
/// Enquiries and WhatsApp taps go to the project's Cloud Functions
/// (FUNCTIONS_BASE to override, e.g. the Functions emulator).
/// NOINDEX=1 (set by Terraform outside prod) keeps search engines away.
Future<void> main() async {
  Jaspr.initializeApp();
  final tenant = TenantConfig.fromJson(
    jsonDecode(await File(Platform.environment['TENANT_FILE'] ?? 'tenant.json').readAsString()) as Map<String, Object?>,
  );
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final env = Platform.environment;
  final projectId = env['FIRESTORE_PROJECT'] ?? tenant.firebaseProjects[FirebaseEnv.prod]!;
  mediaProject = projectId;
  final source = FirestoreListingSource(projectId: projectId, emulatorHost: env['FIRESTORE_EMULATOR_HOST']);
  // On Cloud Run (K_SERVICE set) the pages call the Functions' twins with
  // the service account's ID token (D16); locally, the plain callables.
  final local = env['FUNCTIONS_BASE'] != null;
  final leads = CallableLeadApi(
    local ? Uri.parse(env['FUNCTIONS_BASE']!) : functionsBase(projectId),
    idToken: !local && env['K_SERVICE'] != null ? MetadataIdTokens().call : null,
  );
  final handler = shareHandler(tenant, source, leads: leads, fontsDir: env['FONTS_DIR'], brandDir: env['BRAND_DIR'], indexable: env['NOINDEX'] != '1');
  final server = await io.serve(handler, InternetAddress.anyIPv4, port);
  stdout.writeln('share pages for ${tenant.id} on :${server.port}');
}
