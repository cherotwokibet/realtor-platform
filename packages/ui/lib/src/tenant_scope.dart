import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:realtor_core/realtor_core.dart';

/// Asset written by `melos run app:prepare -- <tenant-id>`.
const tenantAssetPath = 'assets/tenant/tenant.json';

Future<TenantConfig> loadTenant([AssetBundle? bundle]) async {
  final raw = await (bundle ?? rootBundle).loadString(tenantAssetPath);
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
