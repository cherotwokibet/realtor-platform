import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';

import 'demo_admin.dart';
import 'format.dart';
import 'providers.dart';
import 'screens.dart';

/// One admin section: its route and navigation destination.
class _Section {
  const _Section(this.section, this.label, this.icon, this.screen);
  final AdminSection section;
  final String label;
  final IconData icon;
  final Widget Function() screen;
  String get path => '/${section.name}';
}

final _sections = [
  _Section(AdminSection.leads, 'Leads', Icons.inbox_outlined, () => const LeadsScreen()),
  _Section(AdminSection.listings, 'Listings', Icons.home_work_outlined, () => const ListingsScreen()),
  _Section(AdminSection.audit, 'Audit log', Icons.history, () => const AuditScreen()),
];

const signInPath = '/sign-in';

/// Where [path] should go instead for [who], or null to open it: signed-out
/// staff go to sign in, and nobody opens a section their role doesn't cover.
String? adminRedirect(StaffUser? who, String path) {
  if (who == null) return path == signInPath ? null : signInPath;
  final home = '/${AdminSection.leads.name}';
  if (path == signInPath || path == '/') return home;
  for (final s in AdminSection.values) {
    if (path == '/${s.name}' || path.startsWith('/${s.name}/')) return who.canOpen(s) ? null : home;
  }
  return home;
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(staffProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);
  return GoRouter(
    initialLocation: '/${AdminSection.leads.name}',
    refreshListenable: refresh,
    redirect: (context, state) => adminRedirect(ref.read(staffProvider), state.uri.path),
    routes: [
      GoRoute(path: signInPath, builder: (context, state) => const SignInScreen()),
      ShellRoute(
        builder: (context, state, child) => _AdminShell(location: state.uri.path, child: child),
        routes: [for (final s in _sections) GoRoute(path: s.path, builder: (context, state) => s.screen())],
      ),
    ],
  );
});

class AdminApp extends ConsumerWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(tenantProvider);
    return TenantScope(
      tenant: tenant,
      child: MaterialApp.router(
        title: '${tenant.name} admin',
        debugShowCheckedModeBanner: false,
        theme: buildBrandTheme(tenant),
        routerConfig: ref.watch(routerProvider),
      ),
    );
  }
}

/// App bar with the signed-in user, and the sections their role opens: a
/// side rail on desktop, a bottom bar on narrow windows.
class _AdminShell extends ConsumerWidget {
  const _AdminShell({required this.location, required this.child});
  final String location;
  final Widget child;

  static const wideFrom = 840.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final who = ref.watch(staffProvider);
    // Signed out: the router is about to move to sign in; draw nothing until then.
    if (who == null) return const SizedBox.shrink();
    final tenant = ref.watch(tenantProvider);
    final sections = [
      for (final s in _sections)
        if (who.canOpen(s.section)) s
    ];
    final i = sections.indexWhere((s) => location.startsWith(s.path));
    final selected = i < 0 ? 0 : i;
    void go(int i) => context.go(sections[i].path);

    final wide = MediaQuery.sizeOf(context).width >= wideFrom;
    final appBar = AppBar(
      title: Text('${tenant.name} admin'),
      actions: [
        if (wide)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(child: Text('${who.name} · ${label(who.role.name)}')),
          ),
        IconButton(
          tooltip: 'Sign out (${who.name})',
          icon: const Icon(Icons.logout),
          onPressed: () => ref.read(staffProvider.notifier).signOut(),
        ),
      ],
    );

    if (!wide) {
      return Scaffold(
        appBar: appBar,
        body: child,
        bottomNavigationBar: NavigationBar(
          selectedIndex: selected,
          onDestinationSelected: go,
          destinations: [for (final s in sections) NavigationDestination(icon: Icon(s.icon), label: s.label)],
        ),
      );
    }
    return Scaffold(
      appBar: appBar,
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: selected,
            onDestinationSelected: go,
            labelType: NavigationRailLabelType.all,
            destinations: [
              for (final s in sections) NavigationRailDestination(icon: Icon(s.icon), label: Text(s.label))
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Demo accounts until Firebase Auth is connected; then email link or
/// password sign-in, with the role read from the ID token's claims.
class SignInScreen extends ConsumerWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(tenantProvider);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text('${tenant.name} admin', style: t.headlineSmall),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child:
                        Text('Demo accounts over demo data. Pick one to see what that role sees.', style: t.bodyMedium),
                  ),
                  for (final s in demoStaff)
                    ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(s.name),
                      subtitle: Text(label(s.role.name)),
                      onTap: () => ref.read(staffProvider.notifier).signIn(s),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
