import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:realtor_ui/realtor_ui.dart';

import 'package:realtor_core/realtor_core.dart';

import 'account/account_screen.dart';
import 'home_screen.dart';
import 'listing/listing_screen.dart';
import 'places/place_screens.dart';
import 'providers.dart';
import 'saved/saved_screen.dart';
import 'search/purpose.dart';
import 'search/recent_searches.dart';
import 'search/results_screen.dart';
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
              builder: (context, state) => switch (s.path) {
                '/' => const HomeScreen(),
                '/saved' => const SavedScreen(),
                '/account' => const AccountScreen(),
                _ => PlaceholderScreen(title: s.label),
              },
            ),
          // Search results: /rent, /buy/apartments, /rent/apartments/kilimani?beds=2 ...
          for (final p in Purpose.values)
            if (features.isOn(p.feature))
              GoRoute(
                path: '/${p.pathSegment}',
                redirect: _resultsOrHome,
                builder: _results,
                routes: [
                  GoRoute(path: ':a', redirect: _resultsOrHome, builder: _results),
                  GoRoute(path: ':a/:b', redirect: _resultsOrHome, builder: _results),
                ],
              ),
        ],
      ),
      // Share pages hand visitors to these paths (P3), and App Links open
      // them from shared links: keep them in step with appLinkPaths.
      GoRoute(
        path: '/listing/:slug',
        builder: (context, state) => ListingScreen(slug: state.pathParameters['slug']!),
      ),
      GoRoute(
        path: '/area/:slug',
        builder: (context, state) => AreaScreen(slug: state.pathParameters['slug']!),
      ),
      GoRoute(
        path: '/agent/:id',
        builder: (context, state) => AgentScreen(id: state.pathParameters['id']!),
      ),
    ],
  );
});

String? _resultsOrHome(BuildContext context, GoRouterState state) =>
    ListingFilters.fromUri(state.uri) == null ? '/' : null;

Widget _results(BuildContext context, GoRouterState state) =>
    RecordSearch(filters: ListingFilters.fromUri(state.uri)!, child: ResultsScreen(filters: ListingFilters.fromUri(state.uri)!));

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

/// Navigation built from the tenant's enabled sections: a bottom bar on
/// phones, a side rail with centred content on tablets and desktop web.
class _SectionShell extends StatelessWidget {
  const _SectionShell({required this.sections, required this.location, required this.child});
  final List<AppSection> sections;
  final String location;
  final Widget child;

  /// Material 3 "expanded" window class starts here.
  static const wideFrom = 840.0;
  static const maxContentWidth = 1200.0;

  @override
  Widget build(BuildContext context) {
    final i = sections.indexWhere((s) => s.path == location);
    final selected = i < 0 ? 0 : i;
    void go(int i) => context.go(sections[i].path);

    if (MediaQuery.sizeOf(context).width < wideFrom) {
      return Scaffold(
        body: child,
        bottomNavigationBar: NavigationBar(
          selectedIndex: selected,
          onDestinationSelected: go,
          destinations: [for (final s in sections) NavigationDestination(icon: Icon(s.icon), label: s.label)],
        ),
      );
    }
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: selected,
            onDestinationSelected: go,
            labelType: NavigationRailLabelType.all,
            destinations: [
              for (final s in sections) NavigationRailDestination(icon: Icon(s.icon), label: Text(s.label)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: maxContentWidth), child: child),
            ),
          ),
        ],
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
