import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'tenant_scope.dart';

/// Manifest written by `tenant prepare` / `tenant flavors` next to tenant.json.
const tenantFontsManifest = 'fonts.json';

/// One bundled font file.
class TenantFontFile {
  const TenantFontFile({required this.family, required this.weight, required this.asset});

  factory TenantFontFile.fromJson(Map<String, Object?> json) => TenantFontFile(
        family: json['family']! as String,
        weight: json['weight']! as int,
        asset: json['asset']! as String,
      );

  final String family;
  final int weight;
  final String asset;
}

/// Reads the manifest. An app prepared before fonts were bundled has none,
/// so a missing manifest gives an empty list (platform font fallback).
Future<List<TenantFontFile>> readTenantFonts([AssetBundle? bundle, String? dir]) async {
  final String raw;
  try {
    raw = await (bundle ?? rootBundle).loadString('${dir ?? tenantAssetDir()}/$tenantFontsManifest');
  } on FlutterError {
    return const [];
  }
  return [
    for (final e in jsonDecode(raw) as List<Object?>) TenantFontFile.fromJson(e! as Map<String, Object?>),
  ];
}

/// Registers the tenant's display and body families with the engine, so the
/// theme's `fontFamily` names resolve. Call once before `runApp`.
/// Returns the registered family names.
Future<Set<String>> loadTenantFonts([AssetBundle? bundle, String? dir]) async {
  final b = bundle ?? rootBundle;
  final byFamily = <String, List<TenantFontFile>>{};
  for (final f in await readTenantFonts(b, dir)) {
    byFamily.putIfAbsent(f.family, () => []).add(f);
  }
  final loaders = <Future<void>>[];
  for (final MapEntry(key: family, value: files) in byFamily.entries) {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(b.load(f.asset));
    }
    loaders.add(loader.load());
  }
  await Future.wait(loaders);
  return byFamily.keys.toSet();
}
