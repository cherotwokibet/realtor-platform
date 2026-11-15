import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:realtor_ui/realtor_ui.dart';

import 'package:realtor_core/realtor_core.dart';

import 'account/account_data.dart';
import 'account/account_screen.dart';
import 'account/push.dart';
import 'home_screen.dart';
import 'listing/listing_screen.dart';
import 'nav.dart';
import 'places/off_plan_screens.dart';
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
                '/account' => AccountScreen(emailLink: state.uri.queryParameters['emailLink']),
                '/off-plan' => const OffPlanScreen(),
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
      // An emailed sign-in link that opened the app (P4-s03): Account finishes it.
      GoRoute(
        path: '/__/auth/links',
        redirect: (context, state) => Uri(path: '/account', queryParameters: {'emailLink': state.uri.toString()}).toString(),
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
      // Only when offPlan is on: redirectForDisabled sends /off-plan/... home otherwise.
      GoRoute(
        path: '/off-plan/:slug',
        builder: (context, state) => ProjectScreen(slug: state.pathParameters['slug']!),
      ),
      GoRoute(
        path: '/agent/:id',
        builder: (context, state) => AgentScreen(id: state.pathParameters['id']!),
      ),
    ],
  );
});

String? _resultsOrHome(BuildContext context, GoRouterState state) => ListingFilters.fromUri(state.uri) == null ? '/' : null;

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
        builder: (context, child) => _PushRouting(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}

/// A tapped push alert opens its home (or Account); a signed-in phone that
/// already allowed notifications registers again on start (P4-s03).
class _PushRouting extends ConsumerStatefulWidget {
  const _PushRouting({required this.child});
  final Widget child;

  @override
  ConsumerState<_PushRouting> createState() => _PushRoutingState();
}

class _PushRoutingState extends ConsumerState<_PushRouting> {
  StreamSubscription<String>? _taps;

  @override
  void initState() {
    super.initState();
    _taps = ref.read(pushAlertsProvider).opened.listen((path) => ref.read(routerProvider).push(path), onError: (Object _) {});
    ref.listenManual(customerProvider, (previous, next) {
      final uid = next.value?.uid;
      if (uid != null && uid != previous?.value?.uid) ref.read(pushAlertsProvider).resume(uid).ignore();
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _taps?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Navigation built from the tenant's enabled sections: a bottom bar on
/// phones, a top bar with centred content on tablets and desktop web.
class _SectionShell extends StatelessWidget {
  const _SectionShell({required this.sections, required this.location, required this.child});
  final List<AppSection> sections;
  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final i = sections.indexWhere((s) => s.path == location);
    final selected = i < 0 ? 0 : i;
    void go(int i) {
      // A note about one screen should not follow you to another tab.
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      context.go(sections[i].path);
    }

    // Phone back on another tab (Saved, Account, …) goes to Search; only
    // Search itself leaves the app. Screens pushed above a tab pop as usual.
    Widget backToSearch(Widget page) => PopScope(
          canPop: location == '/' || i < 0,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) go(0);
          },
          child: page,
        );

    if (MediaQuery.sizeOf(context).width < wideLayoutFrom) {
      return backToSearch(Scaffold(
        body: child,
        bottomNavigationBar: NavigationBar(
          selectedIndex: selected,
          onDestinationSelected: go,
          destinations: [for (final s in sections) NavigationDestination(icon: Icon(s.icon), label: s.label)],
        ),
      ));
    }
    return backToSearch(Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(TopNav.height),
        child: TopNav(sections: sections, location: location),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: maxContentWidth), child: child),
      ),
    ));
  }
}

/// Wide screens (desktop web, tablets): the logo, Home, one link for each
/// way to search the tenant offers (Rent, Buy, BnB), the other sections,
/// and the account on the right.
class TopNav extends ConsumerWidget {
  const TopNav({super.key, required this.sections, required this.location});
  final List<AppSection> sections;
  final String location;

  static const height = 80.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(tenantProvider);
    final b = context.brand;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final signedIn = ref.watch(customerProvider).value != null;
    void go(String path) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      context.go(path);
    }

    Widget link(String label, String path, {required bool here}) => Padding(
          padding: EdgeInsets.symmetric(horizontal: b.spacing.xs),
          child: TextButton(
            onPressed: () => go(path),
            child: Text(
              label,
              style: text.titleSmall?.copyWith(
                color: here ? scheme.primary : scheme.onSurface,
                decoration: here ? TextDecoration.underline : null,
                decorationColor: scheme.primary,
                decorationThickness: 2,
              ),
            ),
          ),
        );
    bool under(String path) => location == path || location.startsWith('$path/');
    return Material(
      key: const Key('top-nav'),
      color: scheme.surface,
      shape: Border(bottom: BorderSide(color: Theme.of(context).dividerTheme.color ?? scheme.outlineVariant)),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxContentWidth),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: b.spacing.gutter),
            child: Row(children: [
              InkWell(
                onTap: () => go('/'),
                child: Image.asset(b.logoAsset, height: 60, filterQuality: FilterQuality.medium, semanticLabel: tenant.name),
              ),
              SizedBox(width: b.spacing.lg),
              link('Home', '/', here: location == '/'),
              for (final p in Purpose.values)
                if (tenant.features.isOn(p.feature)) link(p.label, '/${p.pathSegment}', here: under('/${p.pathSegment}')),
              for (final s in sections)
                if (s.path != '/' && s.path != '/account') link(s.label, s.path, here: under(s.path)),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () => go('/account'),
                icon: const Icon(Icons.person_outline),
                label: Text(signedIn ? 'Account' : 'Log in / Sign up'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A section whose screen is still being built (in-app chat): says so in
/// plain words and offers WhatsApp, which already reaches the realtor.
class PlaceholderScreen extends ConsumerWidget {
  const PlaceholderScreen({super.key, required this.title});
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(tenantProvider);
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final wa = tenant.whatsappLink('Hello ${tenant.name}, I have a question.');
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(b.spacing.gutter),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('$title is coming soon.', style: text.titleMedium, textAlign: TextAlign.center),
            SizedBox(height: b.spacing.sm),
            Text(
              wa == null ? 'Meanwhile, ask about any home from its page.' : 'Meanwhile, ${tenant.name} answers on WhatsApp.',
              style: text.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (wa != null) ...[
              SizedBox(height: b.spacing.lg),
              FilledButton.icon(onPressed: () => ref.read(urlOpenerProvider)(wa), icon: const Icon(Icons.chat), label: const Text('Message on WhatsApp')),
            ],
          ]),
        ),
      ),
    );
  }
}
