import 'dart:convert';
import 'dart:io';

import 'package:jaspr/server.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:share_pages/share_pages.dart';
import 'package:shelf/shelf_io.dart' as io;

/// Cloud Run entry point. TENANT_FILE points at `tenants/<id>.json` (copied
/// into the image at build time); PORT is set by Cloud Run.
/// The Firestore listing source comes in the next slice; until then this
/// serves an empty source (every listing 404s).
Future<void> main() async {
  Jaspr.initializeApp();
  final tenant = TenantConfig.fromJson(
    jsonDecode(await File(Platform.environment['TENANT_FILE'] ?? 'tenant.json').readAsString()) as Map<String, Object?>,
  );
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final server = await io.serve(shareHandler(tenant, InMemoryListingSource(const [])), InternetAddress.anyIPv4, port);
  stdout.writeln('share pages for ${tenant.id} on :${server.port}');
}
