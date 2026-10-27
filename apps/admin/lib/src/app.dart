import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';

import 'format.dart';
import 'providers.dart';
import 'screens.dart';
import 'session.dart';

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

/// Where [path] should go instead in [session], or null to open it: anyone
/// not signed in as staff goes to sign in, and nobody opens a section their
/// role doesn't cover. While starting, stay put (keeps deep links).
String? adminRedirect(Session session, String path) {
  if (session is Starting) return null;
  if (session is! SignedIn) return path == signInPath ? null : signInPath;
  final who = session.user;
  final home = '/${AdminSection.leads.name}';
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
    initialLocation: '/${AdminSection.leads.name}',
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
    // Starting, or signed out with the router about to move to sign in.
    if (who == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
          onPressed: () => ref.read(adminAuthProvider).signOut(),
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

/// Sign in: demo accounts on demo data; otherwise an emailed one-time link,
/// with the role read from the ID token's claims.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  String? _sentTo, _error;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    final auth = ref.read(adminAuthProvider);
    final remembered = auth.rememberedEmail;
    if (remembered != null) _email.text = remembered;
    // Opened from the link in the same browser: finish without asking.
    if (auth.openedFromLink && remembered != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _run(() => auth.completeSignIn(remembered)));
    }
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, {String? sentTo}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) setState(() => _sentTo = sentTo);
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
    final t = Theme.of(context).textTheme;
    final email = _email.text.trim();

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
            subtitle: Text(label(s.role.name)),
            onTap: () => auth.signInAs(s),
          ),
      ];
    } else if (_sentTo != null) {
      body = [_pad(Text('We sent a sign-in link to $_sentTo. Open it in this browser to continue.'))];
    } else {
      final finishing = auth.openedFromLink;
      body = [
        _pad(Text(finishing
            ? 'Confirm the email the sign-in link was sent to.'
            : 'We will email you a one-time sign-in link.')),
        _pad(TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(labelText: 'Work email'),
          onChanged: (_) => setState(() {}),
        )),
        _pad(FilledButton(
          onPressed: !email.contains('@')
              ? null
              : finishing
                  ? () => _run(() => auth.completeSignIn(email))
                  : () => _run(() => auth.sendSignInLink(email), sentTo: email),
          child: Text(finishing ? 'Sign in' : 'Email me a link'),
        )),
      ];
    }

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
                  _pad(Text('${tenant.name} admin', style: t.headlineSmall)),
                  if (_error != null) _pad(Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
                  ...body,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pad(Widget child) => Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: child);
}
