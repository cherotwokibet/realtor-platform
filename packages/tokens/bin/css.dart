// dart run realtor_tokens:css <tenant-id>  -> prints the tenant's CSS variables.
// CI diffs this against tools/tenant-cli output so Dart and TS never drift.
import 'dart:convert';
import 'dart:io';

import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_tokens/realtor_tokens.dart';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: dart run realtor_tokens:css <tenant-id>');
    exit(64);
  }
  final root = _findRepoRoot();
  final json = jsonDecode(File('$root/tenants/${args.first}.json').readAsStringSync());
  stdout.write(Tokens(TenantConfig.fromJson(json as Map<String, Object?>)).toCss());
}

String _findRepoRoot() {
  var dir = Directory.current;
  while (!File('${dir.path}/tenants/schema/tenant.schema.json').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) throw StateError('run inside the realtor-platform repo');
    dir = parent;
  }
  return dir.path;
}
