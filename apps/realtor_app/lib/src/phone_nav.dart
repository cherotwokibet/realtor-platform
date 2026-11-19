import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';

import 'account/account_data.dart';
import 'account/account_screen.dart' show initialsOf;
import 'account/push.dart';
import 'nav.dart';
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
          // Log in: a solid pill in the brand colour, as Property Finder has it.
          // Saved: just the word and its heart in the brand colour, so it does
          // not shout over the page (the heart is the sign people know for it).
          child: Builder(builder: (context) {
            final style = FilledButton.styleFrom(
              shape: const StadiumBorder(),
              padding: EdgeInsets.symmetric(horizontal: b.spacing.lg),
              minimumSize: const Size(0, 44),
              textStyle: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            );
            return signedIn
                ? TextButton.icon(
                    key: const Key('top-saved'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      padding: EdgeInsets.symmetric(horizontal: b.spacing.sm),
                      textStyle: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
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

    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final customer = ref.watch(customerProvider).value;
    final email = customer?.email;
    final name = ref.watch(profileProvider).value?.name?.trim();
    Widget item(String label, IconData icon, VoidCallback onTap, {Key? key}) => InkWell(
          key: key,
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: b.spacing.lg, vertical: b.spacing.md),
            child: Row(children: [
              Icon(icon, size: 22, color: b.textMuted),
              SizedBox(width: b.spacing.lg),
              Expanded(child: Text(label, style: text.bodyLarge)),
            ]),
          ),
        );
    IconData purposeIcon(Purpose p) =>
        switch (p) { Purpose.rent => Icons.key_outlined, Purpose.sale => Icons.sell_outlined, Purpose.shortStay => Icons.bed_outlined };
    final badges = [
      if (tenant.googlePlayUrl case final String url) StoreBadge.googlePlay(onTap: () => open(Uri.parse(url))),
      if (tenant.appStoreUrl case final String url) StoreBadge.appStore(onTap: () => open(Uri.parse(url))),
    ];

    // As on the big portals' apps: a close button, the account first, then
    // plain rows with their icons; the page behind is dimmed.
    return Drawer(
      key: const Key('app-drawer'),
      width: (MediaQuery.sizeOf(context).width * 0.86).clamp(0, 360),
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(tooltip: 'Close menu', icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: b.spacing.lg),
            child: signedIn
                ? InkWell(
                    key: const Key('drawer-account'),
                    onTap: () => go('/account'),
                    child: Row(children: [
                      // Initials in a round, as on Bayut.
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: scheme.primary,
                        child: Text(initialsOf(name == null || name.isEmpty ? email ?? '?' : name),
                            style: text.titleMedium?.copyWith(color: scheme.onPrimary, fontWeight: FontWeight.w700)),
                      ),
                      SizedBox(width: b.spacing.md),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(name == null || name.isEmpty ? email ?? 'Signed in' : name, style: text.titleSmall, overflow: TextOverflow.ellipsis),
                          if (name != null && name.isNotEmpty && email != null)
                            Text(email, style: text.bodySmall?.copyWith(color: b.textMuted), overflow: TextOverflow.ellipsis),
                        ]),
                      ),
                    ]),
                  )
                : OutlinedButton(
                    key: const Key('drawer-login'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: () => go('/account'),
                    child: const Text('Sign up or Log in'),
                  ),
          ),
          SizedBox(height: b.spacing.sm),
          Expanded(
            child: ListView(padding: EdgeInsets.only(bottom: b.spacing.lg), children: [
              item('Home', Icons.home_outlined, () => go('/')),
              for (final p in Purpose.values)
                if (tenant.features.isOn(p.feature)) item('Homes ${p.heading}', purposeIcon(p), () => go('/${p.pathSegment}')),
              for (final s in enabledSections(tenant.features))
                if (s.path != '/' && s.path != '/account')
                  item(s.label, s.path == '/saved' ? Icons.favorite_border : s.icon, () => go(s.path == '/saved' && !signedIn ? '/account' : s.path)),
              signedIn
                  ? item('Account', Icons.person_outline, () => go('/account'))
                  : item('Saved searches and alerts', Icons.notifications_none, () => go('/account')),
              if (badges.isNotEmpty) ...[
                const Divider(height: 32),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: b.spacing.lg),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Download the ${tenant.name} app', style: text.titleSmall),
                    SizedBox(height: b.spacing.md),
                    Wrap(spacing: b.spacing.sm, runSpacing: b.spacing.sm, children: badges),
                  ]),
                ),
              ],
            ]),
          ),
          // Log out at the foot, only for someone signed in.
          if (customer != null) ...[
            const Divider(height: 1),
            item('Log out', Icons.logout, () async {
              Navigator.pop(context);
              try {
                await ref.read(pushAlertsProvider).disable(customer.uid);
              } on Object {
                // Signing out still works; the sweep forgets dead tokens.
              }
              await ref.read(customerAccountProvider).signOut();
            }, key: const Key('drawer-logout')),
          ],
        ]),
      ),
    );
  }
}

/// A store badge, drawn (no image to load): dark, rounded, the store's
/// mark and its two lines light on it, as the stores' own badges are laid out.
class StoreBadge extends StatelessWidget {
  const StoreBadge._({super.key, required this.top, required this.name, required this.mark, required this.onTap});

  factory StoreBadge.googlePlay({Key? key, required VoidCallback onTap}) => StoreBadge._(
      key: key ?? const Key('badge-google-play'),
      top: 'GET IT ON',
      name: 'Google Play',
      mark: const Icon(Icons.play_arrow_rounded, size: 30),
      onTap: onTap);

  factory StoreBadge.appStore({Key? key, required VoidCallback onTap}) => StoreBadge._(
      key: key ?? const Key('badge-app-store'),
      top: 'Download on the',
      name: 'App Store',
      mark: const Icon(Icons.apple, size: 26),
      onTap: onTap);

  final String top, name;
  final Widget mark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Dark as the stores' badges, from the theme: the text colour behind, the page colour on it.
    final scheme = Theme.of(context).colorScheme;
    final ink = scheme.surface;
    return Semantics(
      button: true,
      label: '$top $name',
      child: Material(
        color: scheme.onSurface,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 14, 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox.square(dimension: 26, child: Center(child: IconTheme(data: IconThemeData(color: ink), child: mark))),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(top, style: TextStyle(color: ink, fontSize: 9, letterSpacing: 0.4, height: 1.1)),
                Text(name, style: TextStyle(color: ink, fontSize: 17, fontWeight: FontWeight.w600, height: 1.15)),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Phones: a top bar that scrolls away with the page and comes back only at
/// the top, as on Bayut's listing page: back on the left, the logo in the
/// middle, [actions] on the right, all in the brand colour on white.
class ScrollAwayBar extends ConsumerWidget {
  const ScrollAwayBar({super.key, this.actions = const []});
  final List<Widget> actions;

  static const height = 56.0;

  /// [body] under the bar; the bar scrolls with it.
  static Widget wrap({required Widget body, List<Widget> actions = const []}) => NestedScrollView(
        headerSliverBuilder: (context, _) => [ScrollAwayBar(actions: actions)],
        body: body,
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(tenantProvider);
    final b = context.brand;
    final scheme = Theme.of(context).colorScheme;
    return SliverAppBar(
      key: const Key('scroll-away-bar'),
      toolbarHeight: height,
      automaticallyImplyLeading: false,
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      iconTheme: IconThemeData(color: scheme.primary),
      actionsIconTheme: IconThemeData(color: scheme.primary),
      leading: IconButton(
        key: const Key('bar-back'),
        tooltip: 'Back',
        color: scheme.primary,
        icon: const Icon(Icons.chevron_left, size: 32),
        onPressed: () => context.canPop() ? context.pop() : context.go('/'),
      ),
      centerTitle: true,
      title: GestureDetector(
        onTap: () => context.go('/'),
        child: Image.asset(b.logoAsset, height: 40, filterQuality: FilterQuality.medium, semanticLabel: tenant.name),
      ),
      actions: [...actions, SizedBox(width: b.spacing.xs)],
    );
  }
}

/// Whether a page should use [ScrollAwayBar] (phones) rather than an app bar.
bool usesScrollAwayBar(BuildContext context) => MediaQuery.sizeOf(context).width < wideLayoutFrom;
