import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:realtor_ui/realtor_ui.dart';

import 'home_screen.dart';
import 'providers.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
      // Share pages hand visitors to these paths (P3): keep them stable.
      GoRoute(
        path: '/listing/:slug',
        builder: (context, state) => PlaceholderScreen(title: 'Listing ${state.pathParameters['slug']}'),
      ),
      GoRoute(
        path: '/area/:slug',
        builder: (context, state) => PlaceholderScreen(title: 'Area ${state.pathParameters['slug']}'),
      ),
    ],
  );
});

class RealtorApp extends ConsumerWidget {
  const RealtorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(tenantProvider);
    return TenantScope(
      tenant: tenant,
      child: MaterialApp.router(
        title: tenant.name,
        debugShowCheckedModeBanner: false,
        theme: buildBrandTheme(tenant),
        routerConfig: ref.watch(routerProvider),
      ),
    );
  }
}

class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.title});
  final String title;

  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: Text(title)), body: const Center(child: Text('Coming in Phase 4')));
}
