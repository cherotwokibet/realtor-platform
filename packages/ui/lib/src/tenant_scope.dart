import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:realtor_core/realtor_core.dart';

/// Where `tenant prepare <id>` writes a single tenant (web, plain `flutter run`).
const singleTenantAssetDir = 'assets/tenant';

/// The tenant's asset folder. A flavor build (`--flavor realtimeEstates`)
/// reads `assets/flavors/<flavor>/`, written by `tenant flavors`; otherwise
/// the single prepared tenant.
String tenantAssetDir([String? flavor = appFlavor]) =>
    flavor == null || flavor.isEmpty ? singleTenantAssetDir : 'assets/flavors/$flavor';

Future<TenantConfig> loadTenant([AssetBundle? bundle, String? dir]) async {
  final raw = await (bundle ?? rootBundle).loadString('${dir ?? tenantAssetDir()}/tenant.json');
  return TenantConfig.fromJson(jsonDecode(raw) as Map<String, Object?>);
}

/// Makes the tenant available below it: `TenantScope.of(context)`.
/// The app wraps this in a Riverpod provider override; widgets in this
/// package use the scope so they stay framework-free.
class TenantScope extends InheritedWidget {
  const TenantScope({super.key, required this.tenant, required super.child});
  final TenantConfig tenant;

  static TenantConfig of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TenantScope>()!.tenant;

  @override
  bool updateShouldNotify(TenantScope old) => old.tenant.id != tenant.id;
}
