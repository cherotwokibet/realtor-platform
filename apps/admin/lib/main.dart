import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:realtor_ui/realtor_ui.dart';

import 'src/app.dart';
import 'src/providers.dart';

Future<void> main() async {
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  final (tenant, _) = await (loadTenant(), loadTenantFonts()).wait;
  runApp(ProviderScope(
    overrides: [tenantProvider.overrideWithValue(tenant)],
    child: const AdminApp(),
  ));
}
