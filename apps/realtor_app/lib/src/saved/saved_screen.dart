import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';

import '../account/account_data.dart';
import '../account/account_screen.dart' show SavedSearchesList;
import '../account/sign_in.dart';
import '../app.dart' show TopNav;
import '../nav.dart';
import '../providers.dart';
import '../search/purpose.dart';
import '../search/results_screen.dart';
import '../sections.dart';
import '../site_footer.dart';
import '../window_scroll.dart';
import 'favourites.dart';

/// `/saved`: the homes saved on this device and the saved searches, under
/// two tabs, Favourites (the default) and Search alerts, each with its
/// count rolling up to the number. On computers the page scrolls as a whole
/// with the window's scrollbar, the homes four across as on the home page;
/// on phones, a bar with back and Saved over the tabs.
class SavedScreen extends ConsumerStatefulWidget {
  const SavedScreen({super.key, this.tab});

  /// `searches` opens on Search alerts; otherwise Favourites.
  final String? tab;

  @override
  ConsumerState<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends ConsumerState<SavedScreen> {
  late bool _searches = widget.tab == 'searches';

  @override
  void didUpdateWidget(SavedScreen old) {
    super.didUpdateWidget(old);
    if (widget.tab != old.tab) _searches = widget.tab == 'searches';
  }

  Future<void> _deleteAll(BuildContext context) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove all saved homes?'),
        content: const Text('They are removed from this list. You can save them again from their pages.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep them')),
          FilledButton(key: const Key('confirm-delete-all'), onPressed: () => Navigator.pop(context, true), child: const Text('Delete All')),
        ],
      ),
    );
    if (sure == true) await ref.read(favouritesProvider.notifier).clear();
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final tenant = ref.watch(tenantProvider);
    final saved = ref.watch(favouritesProvider);
    final wide = MediaQuery.sizeOf(context).width >= wideLayoutFrom;
    final customer = ref.watch(customerProvider).value;
    final signedIn = customer != null;
    final purposes = [
      for (final p in Purpose.values)
        if (tenant.features.isOn(p.feature)) p
    ];
    final count = saved.value?.length ?? 0;
    final alerts = customer == null ? 0 : (ref.watch(savedSearchesProvider(customer.uid)).value?.length ?? 0);

    // A friendly block for an empty or signed-out state: a big icon, a line, one button.
    Widget empty({required IconData icon, required String title, required String line, required String action, required VoidCallback onTap}) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: b.spacing.xl, vertical: b.spacing.xxl),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(color: b.primarySoft, shape: BoxShape.circle),
                  child: Icon(icon, size: 44, color: scheme.primary),
                ),
                SizedBox(height: b.spacing.lg),
                Text(title, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700), textAlign: TextAlign.center),
                SizedBox(height: b.spacing.sm),
                Text(line, style: text.bodyMedium?.copyWith(color: b.textMuted), textAlign: TextAlign.center),
                SizedBox(height: b.spacing.lg),
                FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(220, 48)), onPressed: onTap, child: Text(action)),
              ]),
            ),
          ),
        );

    // What each tab holds, as plain widgets: the page around them scrolls.
    final List<Widget> favourites = !signedIn
        ? [
            empty(
              icon: Icons.lock_outline,
              title: 'Sign in to see the homes you have saved.',
              line: 'Hearts you tap are kept on this device and show here once you sign in, on every device.',
              action: 'Log in / Sign up',
              onTap: () => showSignIn(context),
            )
          ]
        : saved.when(
            loading: () => [const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))],
            error: (e, _) => [Center(child: Text("Couldn't open your saved homes.", style: text.bodyMedium))],
            data: (list) => list.isEmpty
                ? [
                    empty(
                      icon: Icons.favorite_border,
                      title: 'No saved homes yet',
                      line: 'Tap the heart on a home to keep it here, and compare them later.',
                      action: 'Start searching',
                      onTap: () => context.go(purposes.isEmpty ? '/' : '/${purposes.first.pathSegment}'),
                    )
                  ]
                : [
                    Text('${list.length} ${list.length == 1 ? 'home' : 'homes'}, newest first', style: text.labelLarge?.copyWith(color: b.textMuted)),
                    SizedBox(height: b.spacing.md),
                    // As the home page's rows: four across on a computer.
                    ListingGrid(key: const Key('saved-grid'), listings: list, maxAcross: 4),
                    if (wide) ...[
                      SizedBox(height: b.spacing.xl),
                      Center(
                        child: TextButton.icon(
                          key: const Key('saved-delete-all'),
                          onPressed: () => _deleteAll(context),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Delete All'),
                        ),
                      ),
                    ],
                  ],
          );
    final List<Widget> searches = !signedIn
        ? [
            empty(
              icon: Icons.notifications_none,
              title: 'Sign in to see your search alerts.',
              line: 'Save a search from the results and hear as soon as a matching home is listed.',
              action: 'Log in / Sign up',
              onTap: () => showSignIn(context),
            )
          ]
        : [SavedSearchesList(uid: customer.uid)];

    final tabs = _Tabs(
      wide: wide,
      searches: _searches,
      favourites: count,
      alerts: alerts,
      onPick: (s) => setState(() => _searches = s),
    );

    if (wide) {
      // One page that scrolls with the window's own scrollbar, top menu included.
      final side = ((MediaQuery.sizeOf(context).width - WindowScroll.width - maxContentWidth) / 2).clamp(0.0, double.infinity) + 24;
      return Scaffold(
        body: WindowScroll(
          child: CustomScrollView(key: const Key('saved-page'), primary: true, slivers: [
            SliverToBoxAdapter(
              child: SizedBox(
                height: TopNav.height,
                child: TopNav(sections: visibleSections(enabledSections(tenant.features), signedIn: signedIn), location: '/saved'),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side, b.spacing.xl, side, b.spacing.xxl),
              sliver: SliverList.list(children: [
                tabs,
                SizedBox(height: b.spacing.lg),
                ...(_searches ? searches : favourites),
              ]),
            ),
            SliverToBoxAdapter(child: SiteFooter(width: maxContentWidth + 48)),
          ]),
        ),
      );
    }
    return Scaffold(
      // Back to where the visitor was, and the page's name in the middle.
      appBar: AppBar(
        leading: const AppBack(),
        centerTitle: true,
        title: const Text('Saved'),
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Divider(height: 1, color: scheme.outlineVariant)),
      ),
      body: Column(children: [
        // Space under the tabs that stays while the homes scroll, as above them.
        Padding(padding: EdgeInsets.fromLTRB(b.spacing.gutter, b.spacing.lg, b.spacing.gutter, b.spacing.lg), child: tabs),
        Expanded(
          child: ListView(
            key: const Key('saved-list'),
            padding: EdgeInsets.fromLTRB(b.spacing.gutter, 0, b.spacing.gutter, b.spacing.gutter),
            children: _searches ? searches : favourites,
          ),
        ),
      ]),
    );
  }
}

/// Favourites | Search alerts, each with its count rolling up to the
/// number: underlined across the page on computers, two boxes on phones.
class _Tabs extends StatelessWidget {
  const _Tabs({required this.wide, required this.searches, required this.favourites, required this.alerts, required this.onPick});
  final bool wide, searches;
  final int favourites, alerts;
  final ValueChanged<bool> onPick;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    Widget tab(String label, int n, bool on, bool value, Key key) {
      final style = text.titleSmall?.copyWith(color: on ? scheme.primary : b.textMuted, fontWeight: on ? FontWeight.w700 : FontWeight.w500);
      final words = Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
        Flexible(child: Text(label, style: style, maxLines: 1, overflow: TextOverflow.ellipsis)),
        SizedBox(width: b.spacing.sm),
        // The count in a soft pill, rolling up to the number.
        DecoratedBox(
          decoration: BoxDecoration(color: on ? b.primarySoft : b.surfaceAlt, borderRadius: BorderRadius.circular(999)),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: b.spacing.sm, vertical: 2),
            child: TweenAnimationBuilder<double>(
              key: Key('$key-count'),
              tween: Tween(begin: 0, end: n.toDouble()),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => Text('${v.round()}', style: style?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
            ),
          ),
        ),
      ]);
      if (wide) {
        return Expanded(
          child: InkWell(
            key: key,
            onTap: () => onPick(value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: EdgeInsets.symmetric(vertical: b.spacing.md),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: on ? scheme.primary : Colors.transparent, width: 3))),
              child: words,
            ),
          ),
        );
      }
      return Expanded(
        child: Material(
          color: on ? b.primarySoft : scheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(b.radiusSm),
            side: BorderSide(color: on ? b.primarySoft : scheme.outlineVariant),
          ),
          child: InkWell(
            key: key,
            borderRadius: BorderRadius.circular(b.radiusSm),
            onTap: () => onPick(value),
            child: Padding(padding: EdgeInsets.symmetric(vertical: b.spacing.md), child: words),
          ),
        ),
      );
    }

    final row = Row(children: [
      tab('Favourites', favourites, !searches, false, const Key('saved-tab-favourites')),
      if (!wide) SizedBox(width: b.spacing.md),
      tab('Search alerts', alerts, searches, true, const Key('saved-tab-searches')),
    ]);
    return wide ? DecoratedBox(decoration: BoxDecoration(border: Border(bottom: BorderSide(color: scheme.outlineVariant))), child: row) : row;
  }
}
