import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:realtor_ui/realtor_ui.dart';

import 'home_screen.dart';
import 'providers.dart';
import 'sections.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final features = ref.watch(tenantProvider).features;
  final sections = enabledSections(features);
  return GoRouter(
    redirect: (context, state) => redirectForDisabled(features, state.uri.path),
    routes: [
      ShellRoute(
        builder: (context, state, child) => _SectionShell(sections: sections, location: state.uri.path, child: child),
        routes: [
          for (final s in sections)
            GoRoute(
              path: s.path,
              builder: (context, state) => s.path == '/' ? const HomeScreen() : PlaceholderScreen(title: s.label),
            ),
        ],
      ),
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

/// Bottom navigation built from the tenant's enabled sections.
class _SectionShell extends StatelessWidget {
  const _SectionShell({required this.sections, required this.location, required this.child});
  final List<AppSection> sections;
  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final i = sections.indexWhere((s) => s.path == location);
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: i < 0 ? 0 : i,
        onDestinationSelected: (i) => context.go(sections[i].path),
        destinations: [for (final s in sections) NavigationDestination(icon: Icon(s.icon), label: s.label)],
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
