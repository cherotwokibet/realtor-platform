import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';

import '../account/account_data.dart';
import '../search/results_screen.dart';
import '../providers.dart';
import '../account/account_screen.dart' show SavedSearchesList;
import '../account/sign_in.dart';
import '../nav.dart';
import '../search/purpose.dart';
import 'favourites.dart';

/// `/saved`: the homes saved on this device, newest first. The navigation
/// offers it only to signed-in customers; anyone else reaching it by link is
/// asked to sign in (their saves are kept and appear once they have).
class SavedScreen extends ConsumerStatefulWidget {
  const SavedScreen({super.key, this.tab});

  /// `searches` opens on Saved searches; otherwise Favourites, as on Bayut.
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

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final saved = ref.watch(favouritesProvider);
    final wide = MediaQuery.sizeOf(context).width >= wideLayoutFrom;
    final customer = ref.watch(customerProvider).value;
    final signedIn = customer != null;
    final purposes = [
      for (final p in Purpose.values)
        if (ref.watch(tenantProvider).features.isOn(p.feature)) p
    ];
    // A friendly page for an empty or signed-out state: a big icon, a line, one button.
    Widget empty({required IconData icon, required String title, required String line, required String action, required VoidCallback onTap}) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: EdgeInsets.all(b.spacing.xl),
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
    final Widget favourites = !signedIn
        ? empty(
            icon: Icons.lock_outline,
            title: 'Sign in to see the homes you have saved.',
            line: 'Hearts you tap are kept on this device and show here once you sign in, on every device.',
            action: 'Log in / Sign up',
            onTap: () => showSignIn(context),
          )
        : saved.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text("Couldn't open your saved homes.", style: text.bodyMedium)),
            data: (list) => list.isEmpty
                ? empty(
                    icon: Icons.favorite_border,
                    title: 'No saved homes yet',
                    line: 'Tap the heart on a home to keep it here, and compare them later.',
                    action: 'Start searching',
                    onTap: () => context.go(purposes.isEmpty ? '/' : '/${purposes.first.pathSegment}'),
                  )
                : wide
                    // Computers, as on Property Finder: one wide card a row, then Delete All.
                    ? ListView(
                        key: const Key('saved-list'),
                        padding: EdgeInsets.fromLTRB(0, b.spacing.lg, 0, b.spacing.xxl),
                        children: [
                          for (final l in list) ...[ListingCard(listing: l, layout: CardLayout.wide), SizedBox(height: b.spacing.lg)],
                          Center(
                            child: TextButton.icon(
                              key: const Key('saved-delete-all'),
                              onPressed: () => _deleteAll(context),
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Delete All'),
                            ),
                          ),
                        ],
                      )
                    : ListView(
                        key: const Key('saved-list'),
                        padding: EdgeInsets.fromLTRB(b.spacing.gutter, 0, b.spacing.gutter, b.spacing.gutter),
                        children: [
                          Text('${list.length} ${list.length == 1 ? 'home' : 'homes'}, newest first', style: text.labelLarge?.copyWith(color: b.textMuted)),
                          SizedBox(height: b.spacing.md),
                          ListingGrid(listings: list),
                        ],
                      ),
          );
    // Favourites | Searches, two boxes across the top, as on Bayut.
    Widget tab(String label, bool on, VoidCallback onTap, Key key) => Expanded(
          child: Material(
            color: on ? b.primarySoft : scheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(b.radiusSm),
              side: BorderSide(color: on ? b.primarySoft : scheme.outlineVariant),
            ),
            child: InkWell(
              key: key,
              borderRadius: BorderRadius.circular(b.radiusSm),
              onTap: onTap,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: b.spacing.md),
                child: Text(label,
                    textAlign: TextAlign.center,
                    style: text.titleSmall?.copyWith(color: on ? scheme.primary : b.textMuted, fontWeight: on ? FontWeight.w700 : FontWeight.w500)),
              ),
            ),
          ),
        );
    final searches = !signedIn
        ? empty(
            icon: Icons.notifications_none,
            title: 'Sign in to see your saved searches.',
            line: 'Save a search from the results and hear as soon as a matching home is listed.',
            action: 'Log in / Sign up',
            onTap: () => showSignIn(context),
          )
        : ListView(
            padding: wide ? EdgeInsets.only(top: b.spacing.lg) : EdgeInsets.fromLTRB(b.spacing.gutter, 0, b.spacing.gutter, b.spacing.gutter),
            children: [SavedSearchesList(uid: customer.uid)],
          );
    final count = saved.value?.length ?? 0;
    final alerts = customer == null ? 0 : (ref.watch(savedSearchesProvider(customer.uid)).value?.length ?? 0);
    if (wide) {
      // Computers, as on Property Finder: the page's name, then underlined tabs with their counts.
      Widget line(String label, bool on, VoidCallback onTap, Key key) => Expanded(
            child: InkWell(
              key: key,
              onTap: onTap,
              child: Container(
                padding: EdgeInsets.symmetric(vertical: b.spacing.md),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: on ? scheme.primary : Colors.transparent, width: 3))),
                child: Text(label,
                    textAlign: TextAlign.center,
                    style: text.titleSmall?.copyWith(color: on ? scheme.primary : b.textMuted, fontWeight: on ? FontWeight.w700 : FontWeight.w400)),
              ),
            ),
          );
      return Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1030),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: b.spacing.lg),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SizedBox(height: b.spacing.xl),
                Text('Saved', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
                SizedBox(height: b.spacing.sm),
                DecoratedBox(
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: scheme.outlineVariant))),
                  child: Row(children: [
                    line('Saved properties ($count)', !_searches, () => setState(() => _searches = false), const Key('saved-tab-favourites')),
                    line('Search alerts ($alerts)', _searches, () => setState(() => _searches = true), const Key('saved-tab-searches')),
                  ]),
                ),
                Expanded(child: _searches ? searches : favourites),
              ]),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      // Back, and the page's name in the middle; no logo, as on Bayut.
      appBar: AppBar(
        leading: const AppBack(),
        centerTitle: true,
        title: const Text('Saved'),
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Divider(height: 1, color: scheme.outlineVariant)),
      ),
      body: Column(children: [
        Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              // Space under the tabs that stays while the homes scroll, as above them.
              padding: EdgeInsets.fromLTRB(b.spacing.gutter, b.spacing.lg, b.spacing.gutter, b.spacing.lg),
              child: Row(children: [
                tab('Favourites', !_searches, () => setState(() => _searches = false), const Key('saved-tab-favourites')),
                SizedBox(width: b.spacing.md),
                tab('Searches', _searches, () => setState(() => _searches = true), const Key('saved-tab-searches')),
              ]),
            ),
          ),
        ),
        Expanded(child: _searches ? searches : favourites),
      ]),
    );
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
}
