import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';

import 'account/account_data.dart';
import 'providers.dart';
import 'search/purpose.dart';
import 'sections.dart';

/// One tab of the phone's bottom bar.
class PhoneTab {
  const PhoneTab(this.label, this.icon, this.path, {this.matches = const []});
  final String label, path;
  final IconData icon;

  /// Other paths (and the pages under them) that count as this tab.
  final List<String> matches;

  bool isAt(String location) => [path, ...matches].any((p) => p == '/' ? location == '/' : location == p || location.startsWith('$p/'));
}

/// Home, Search, Saved and Account, as on the big property apps. Search opens
/// the first way to search the tenant offers (usually Rent), where Buy and
/// BnB are one tap away.
List<PhoneTab> phoneTabs(Features f) {
  final purposes = [
    for (final p in Purpose.values)
      if (f.isOn(p.feature)) '/${p.pathSegment}'
  ];
  return [
    const PhoneTab('Home', Icons.home_outlined, '/'),
    if (purposes.isNotEmpty) PhoneTab('Search', Icons.search, purposes.first, matches: purposes.skip(1).toList()),
    const PhoneTab('Saved', Icons.favorite_border, '/saved'),
    const PhoneTab('Account', Icons.person_outline, '/account'),
  ];
}

/// Where a tab goes: Saved asks a signed-out visitor to sign in first.
String phoneTabTarget(PhoneTab tab, {required bool signedIn}) => tab.path == '/saved' && !signedIn ? '/account' : tab.path;

/// The phone's top bar, as a sliver: the menu on the left, the logo in the
/// middle, and Log in on the right (Saved once signed in). It scrolls away
/// with the page and comes back only at the top, so the page gets the room.
class PhoneTopBar extends ConsumerWidget {
  const PhoneTopBar({super.key});

  static const height = 64.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(tenantProvider);
    final b = context.brand;
    final signedIn = ref.watch(customerProvider).value != null;
    return SliverAppBar(
      key: const Key('phone-top-bar'),
      toolbarHeight: height,
      leadingWidth: 64,
      primary: false,
      automaticallyImplyLeading: false,
      leading: Builder(
        builder: (context) => Padding(
          padding: EdgeInsets.only(left: b.spacing.sm),
          // The menu in a soft round, so it reads as a button.
          child: Center(
            child: IconButton.filledTonal(
              constraints: const BoxConstraints.tightFor(width: 48, height: 48),
              tooltip: 'Open navigation menu',
              style: IconButton.styleFrom(backgroundColor: b.surfaceAlt, foregroundColor: Theme.of(context).colorScheme.onSurface),
              icon: const Icon(Icons.menu),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
        ),
      ),
      title: Image.asset(b.logoAsset, height: 48, filterQuality: FilterQuality.medium, semanticLabel: tenant.name),
      centerTitle: true,
      actions: [
        Padding(
          padding: EdgeInsets.only(right: b.spacing.sm),
          // A solid pill in the brand colour, as Property Finder has it.
          child: Builder(builder: (context) {
            final style = FilledButton.styleFrom(
              shape: const StadiumBorder(),
              padding: EdgeInsets.symmetric(horizontal: b.spacing.lg),
              minimumSize: const Size(0, 44),
              textStyle: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            );
            return signedIn
                ? FilledButton.icon(
                    key: const Key('top-saved'),
                    style: style,
                    onPressed: () => context.go('/saved'),
                    icon: const Icon(Icons.favorite_border, size: 20),
                    label: const Text('Saved'),
                  )
                : FilledButton(key: const Key('home-login'), style: style, onPressed: () => context.go('/account'), child: const Text('Log in'));
          }),
        ),
      ],
    );
  }
}

/// The phone menu behind the hamburger: every way in, including the
/// sections that have no bottom tab (Off-plan, Chat) and the site pages.
class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(tenantProvider);
    final b = context.brand;
    final signedIn = ref.watch(customerProvider).value != null;
    final open = ref.read(urlOpenerProvider);
    void go(String path) {
      Navigator.pop(context);
      context.go(path);
    }

    return Drawer(
      key: const Key('app-drawer'),
      child: SafeArea(
        child: ListView(padding: EdgeInsets.symmetric(vertical: b.spacing.md), children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: b.spacing.gutter, vertical: b.spacing.md),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Image.asset(b.logoAsset, height: 48, filterQuality: FilterQuality.medium, semanticLabel: tenant.name),
            ),
          ),
          ListTile(leading: const Icon(Icons.home_outlined), title: const Text('Home'), onTap: () => go('/')),
          for (final p in Purpose.values)
            if (tenant.features.isOn(p.feature))
              ListTile(leading: const Icon(Icons.search), title: Text('Homes ${p.heading}'), onTap: () => go('/${p.pathSegment}')),
          for (final s in enabledSections(tenant.features))
            if (s.path != '/' && s.path != '/account')
              ListTile(
                leading: Icon(s.icon),
                title: Text(s.label),
                onTap: () => go(s.path == '/saved' && !signedIn ? '/account' : s.path),
              ),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(signedIn ? 'Account' : 'Log in / Sign up'),
            onTap: () => go('/account'),
          ),
          const Divider(),
          for (final (slug, name) in const [('about', 'About us'), ('contact', 'Contact'), ('faq', 'FAQs'), ('privacy', 'Privacy'), ('terms', 'Terms')])
            ListTile(
              title: Text(name),
              onTap: () {
                Navigator.pop(context);
                open(Uri.https(tenant.shareDomain, '/$slug'));
              },
            ),
        ]),
      ),
    );
  }
}
