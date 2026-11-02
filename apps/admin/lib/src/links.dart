import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens a link in a new tab (WhatsApp, tel:); the web build overrides it.
abstract interface class LinkOpener {
  void open(Uri uri);
}

/// Outside a browser: remembers what would have opened (tests).
class MemoryLinkOpener implements LinkOpener {
  final opened = <Uri>[];
  @override
  void open(Uri uri) => opened.add(uri);
}

final linkOpenerProvider = Provider<LinkOpener>((ref) => MemoryLinkOpener());

/// Where the share pages live for this admin: on Firebase's own hosts the
/// sibling `<project>-share` site (dev, stage), else the tenant's domain.
String shareHost(String tenantShareDomain, Uri adminBase) {
  final m = RegExp(r'^(.+)-admin\.(web\.app|firebaseapp\.com)$').firstMatch(adminBase.host);
  return m == null ? tenantShareDomain : '${m[1]}-share.${m[2]}';
}

/// The admin's own address; replaced in tests.
final adminBaseProvider = Provider<Uri>((ref) => Uri.base);
