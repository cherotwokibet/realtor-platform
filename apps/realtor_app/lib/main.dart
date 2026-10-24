import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_ui/realtor_ui.dart';

import 'src/app.dart';
import 'src/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final tenant = await loadTenant();
  runApp(ProviderScope(
    overrides: [tenantProvider.overrideWithValue(tenant)],
    child: const RealtorApp(),
  ));
}
