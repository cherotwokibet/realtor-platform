import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_ui/realtor_ui.dart';

import 'src/app.dart';
import 'src/providers.dart';

Future<void> main() async {
  // Clean URLs on the web (/listing/<slug>, not /#/listing/<slug>); a no-op elsewhere.
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  final (tenant, _) = await (loadTenant(), loadTenantFonts()).wait;
  runApp(ProviderScope(
    overrides: [tenantProvider.overrideWithValue(tenant)],
    child: const RealtorApp(),
  ));
}
