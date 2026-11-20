import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';

import 'providers.dart';
import 'account.dart';
import 'area_guides.dart';
import 'dashboard.dart';
import 'edit_requests.dart';
import 'home_page.dart';
import 'reports.dart';
import 'screens.dart';
import 'session.dart';

/// One admin section: its route, its place in the sidebar and its screen.
class _Section {
  const _Section(this.section, this.label, this.icon, this.group, this.screen);
  final AdminSection section;
  final String label, group;
  final IconData icon;
  final Widget Function() screen;
  String get path => '/${section.name}';
}

/// In sidebar order, under their group headings.
final _sections = [
  _Section(AdminSection.dashboard, 'Dashboard', Icons.space_dashboard_outlined, '', () => const DashboardScreen()),
  _Section(AdminSection.leads, 'Leads', Icons.inbox_outlined, 'Sales', () => const LeadsScreen()),
  _Section(AdminSection.viewings, 'Viewings', Icons.event_outlined, 'Sales', () => const ViewingsScreen()),
  _Section(AdminSection.listings, 'Listings', Icons.home_work_outlined, 'Properties', () => const ListingsScreen()),
  _Section(AdminSection.edits, 'Edit requests', Icons.rule_outlined, 'Properties', () => const EditRequestsScreen()),
  _Section(AdminSection.homePage, 'Home page', Icons.web_outlined, 'Properties', () => const HomePlacementsScreen()),
  _Section(AdminSection.areas, 'Areas', Icons.map_outlined, 'Properties', () => const AreasScreen()),
  _Section(AdminSection.team, 'Users', Icons.group_outlined, 'People', () => const TeamScreen()),
  _Section(AdminSection.reports, 'Reports', Icons.insights_outlined, 'Insights', () => const ReportsScreen()),
  _Section(AdminSection.audit, 'Audit log', Icons.history, 'Insights', () => const AuditScreen()),
  _Section(AdminSection.privacy, 'Privacy', Icons.privacy_tip_outlined, 'Settings', () => const PrivacyScreen()),
  _Section(AdminSection.account, 'Account', Icons.manage_accounts_outlined, 'Settings', () => const AccountScreen()),
];

/// Where staff land: the Dashboard.
final homePath = '/${AdminSection.dashboard.name}';

const signInPath = '/sign-in';

/// Where [path] should go instead in [session], or null to open it: anyone
/// not signed in as staff goes to sign in, and nobody opens a section their
/// role doesn't cover. While starting, stay put (keeps deep links).
String? adminRedirect(Session session, String path) {
  if (session is Starting) return null;
  if (session is! SignedIn) return path == signInPath ? null : signInPath;
  final who = session.user;
  final home = homePath;
  if (path == signInPath || path == '/') return home;
  for (final s in AdminSection.values) {
    if (path == '/${s.name}' || path.startsWith('/${s.name}/')) return who.canOpen(s) ? null : home;
  }
  return home;
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(sessionProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);
  return GoRouter(
    initialLocation: homePath,
    refreshListenable: refresh,
    redirect: (context, state) => adminRedirect(ref.read(sessionProvider), state.uri.path),
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

/// The admin's frame: a sidebar of the sections the role opens, grouped,
/// with the signed-in person at its foot (desktop); on narrow windows a top
/// bar whose menu opens the same sidebar.
class _AdminShell extends ConsumerWidget {
  const _AdminShell({required this.location, required this.child});
  final String location;
  final Widget child;

  static const wideFrom = 1000.0, sidebarWidth = 256.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final who = ref.watch(staffProvider);
    // Starting, or signed out with the router about to move to sign in.
    if (who == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final sections = [
      for (final s in _sections)
        if (who.canOpen(s.section)) s
    ];
    final current = sections.where((s) => location.startsWith(s.path)).firstOrNull ?? sections.first;
    final wide = MediaQuery.sizeOf(context).width >= wideFrom;
    final b = context.brand;

    if (!wide) {
      return Scaffold(
        backgroundColor: b.surfaceAlt,
        appBar: AppBar(
          title: Text(current.label),
          actions: [
            IconButton(
              tooltip: 'Sign out (${who.name})',
              icon: const Icon(Icons.logout),
              onPressed: () => ref.read(adminAuthProvider).signOut(),
            ),
          ],
        ),
        drawer: Drawer(
          width: sidebarWidth + 24,
          child: _Sidebar(sections: sections, current: current, who: who, inDrawer: true),
        ),
        body: child,
      );
    }
    return Scaffold(
      backgroundColor: b.surfaceAlt,
      body: Row(children: [
        SizedBox(width: sidebarWidth, child: _Sidebar(sections: sections, current: current, who: who)),
        VerticalDivider(width: 1, color: Theme.of(context).colorScheme.outlineVariant),
        Expanded(child: child),
      ]),
    );
  }
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar({required this.sections, required this.current, required this.who, this.inDrawer = false});
  final List<_Section> sections;
  final _Section current;
  final StaffUser who;
  final bool inDrawer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = context.brand;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final tenant = ref.watch(tenantProvider);
    void go(_Section s) {
      if (inDrawer) Navigator.pop(context);
      context.go(s.path);
    }

    Widget item(_Section s) {
      final on = s == current;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
        child: Material(
          color: on ? b.primarySoft : Colors.transparent,
          borderRadius: BorderRadius.circular(b.radiusMd),
          child: InkWell(
            key: Key('nav-${s.section.name}'),
            borderRadius: BorderRadius.circular(b.radiusMd),
            onTap: () => go(s),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                Icon(s.icon, size: 20, color: on ? scheme.primary : b.textMuted),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(s.label,
                      style: text.bodyMedium?.copyWith(color: on ? scheme.primary : scheme.onSurface, fontWeight: on ? FontWeight.w700 : FontWeight.w500)),
                ),
              ]),
            ),
          ),
        ),
      );
    }

    final groups = <String, List<_Section>>{};
    for (final s in sections.where((s) => s.section != AdminSection.account)) {
      (groups[s.group] ??= []).add(s);
    }
    final initials = who.name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();
    return Material(
      color: scheme.surface,
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
            child: Row(children: [
              Flexible(
                child: Image.asset(b.logoAsset,
                    height: 36,
                    fit: BoxFit.contain,
                    alignment: Alignment.centerLeft,
                    semanticLabel: tenant.name,
                    errorBuilder: (_, __, ___) => Text(tenant.name, style: text.titleMedium)),
              ),
              const SizedBox(width: 8),
              DecoratedBox(
                decoration: BoxDecoration(color: b.primarySoft, borderRadius: BorderRadius.circular(b.radiusSm)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  child: Text('Admin', style: text.labelSmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.only(bottom: 12), children: [
              for (final e in groups.entries) ...[
                if (e.key.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 16, 6),
                    child: Text(e.key.toUpperCase(), style: text.labelSmall?.copyWith(color: b.textMuted, letterSpacing: 0.8, fontWeight: FontWeight.w700)),
                  ),
                for (final s in e.value) item(s),
              ],
            ]),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          // The signed-in person: opens Account; signs out beside it.
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                child: InkWell(
                  key: const Key('nav-account'),
                  borderRadius: BorderRadius.circular(b.radiusMd),
                  onTap: () => go(sections.firstWhere((s) => s.section == AdminSection.account)),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Row(children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: current.section == AdminSection.account ? scheme.primary : b.primarySoft,
                        foregroundColor: current.section == AdminSection.account ? scheme.onPrimary : scheme.primary,
                        child: Text(initials,
                            style: text.labelLarge
                                ?.copyWith(fontWeight: FontWeight.w700, color: current.section == AdminSection.account ? scheme.onPrimary : scheme.primary)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(who.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                          Text(roleLabel(who.role), style: text.bodySmall?.copyWith(color: b.textMuted)),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
              if (!inDrawer)
                IconButton(
                  tooltip: 'Sign out (${who.name})',
                  icon: const Icon(Icons.logout),
                  onPressed: () => ref.read(adminAuthProvider).signOut(),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Sign in: demo accounts on demo data; otherwise email + password or
/// Google, with the role read from the ID token's claims.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  var _creating = false, _busy = false;
  String? _error, _notice;

  /// Firebase's own minimum is 6; staff accounts see personal data, so 8.
  static const minPassword = 8;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, {String? notice}) async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
      if (mounted && notice != null) setState(() => _notice = notice);
    } on SignInException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(tenantProvider);
    final session = ref.watch(sessionProvider);
    final auth = ref.watch(adminAuthProvider);
    final theme = Theme.of(context);
    final t = theme.textTheme;
    final email = _email.text.trim();
    final password = _password.text;
    final emailOk = email.contains('@') && email.contains('.');

    final List<Widget> body;
    if (session is Starting || _busy) {
      body = [const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))];
    } else if (session is NotStaff) {
      body = [
        _pad(Text('You are signed in as ${session.email ?? 'this account'}, but it has no staff role yet. '
            'Ask the owner to add you, then check again.')),
        _pad(Wrap(spacing: 8, children: [
          FilledButton(onPressed: () => _run(auth.refresh), child: const Text('Check again')),
          TextButton(onPressed: () => _run(auth.signOut), child: const Text('Sign out')),
        ])),
      ];
    } else if (auth.demoAccounts.isNotEmpty) {
      body = [
        _pad(Text('Demo accounts over demo data. Pick one to see what that role sees.', style: t.bodyMedium)),
        for (final s in auth.demoAccounts)
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(s.name),
            subtitle: Text(roleLabel(s.role)),
            onTap: () => auth.signInAs(s),
          ),
      ];
    } else {
      final canSubmit = emailOk && password.length >= (_creating ? minPassword : 1);
      body = [
        _pad(AutofillGroup(
          child: Column(children: [
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'Work email'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _password,
              obscureText: true,
              autofillHints: [_creating ? AutofillHints.newPassword : AutofillHints.password],
              decoration: InputDecoration(
                labelText: 'Password',
                helperText: _creating ? 'At least $minPassword characters' : null,
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (canSubmit) _submit(auth, email, password);
              },
            ),
          ]),
        )),
        _pad(FilledButton(
          onPressed: canSubmit ? () => _submit(auth, email, password) : null,
          child: Text(_creating ? 'Create account' : 'Sign in'),
        )),
        _pad(Wrap(
          alignment: WrapAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: () => setState(() {
                _creating = !_creating;
                _error = null;
              }),
              child: Text(_creating ? 'I have an account' : 'New here? Create an account'),
            ),
            if (!_creating)
              TextButton(
                onPressed: emailOk
                    ? () => _run(() => auth.sendPasswordReset(email), notice: 'If $email has an account, a link to set a new password is on its way.')
                    : null,
                child: const Text('Forgot password?'),
              ),
          ],
        )),
        const Divider(height: 24),
        _pad(OutlinedButton.icon(
          onPressed: () => _run(auth.signInWithGoogle),
          icon: const Icon(Icons.account_circle_outlined),
          label: const Text('Continue with Google'),
        )),
      ];
    }

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
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
                    _pad(Text('${tenant.name} admin', style: t.headlineSmall)),
                    if (_error != null) _pad(Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
                    if (_notice != null) _pad(Text(_notice!)),
                    ...body,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _submit(AdminAuth auth, String email, String password) => _run(
        () => _creating ? auth.createAccount(email, password) : auth.signInWithPassword(email, password),
      );

  Widget _pad(Widget child) => Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: child);
}
