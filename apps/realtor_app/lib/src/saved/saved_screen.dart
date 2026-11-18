import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';

import '../account/account_data.dart';
import '../search/results_screen.dart';
import '../providers.dart';
import '../search/purpose.dart';
import 'favourites.dart';

/// `/saved`: the homes saved on this device, newest first. The navigation
/// offers it only to signed-in customers; anyone else reaching it by link is
/// asked to sign in (their saves are kept and appear once they have).
class SavedScreen extends ConsumerWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final saved = ref.watch(favouritesProvider);
    final signedIn = ref.watch(customerProvider).value != null;
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
    return Scaffold(
      appBar: AppBar(title: const Text('Saved homes')),
      body: !signedIn
          ? empty(
              icon: Icons.lock_outline,
              title: 'Sign in to see the homes you have saved.',
              line: 'Hearts you tap are kept on this device and show here once you sign in, on every device.',
              action: 'Log in / Sign up',
              onTap: () => context.go('/account'),
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
                  : Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1100),
                        child: ListView(
                          padding: EdgeInsets.all(b.spacing.gutter),
                          children: [
                            Text('${list.length} ${list.length == 1 ? 'home' : 'homes'}, newest first', style: text.labelLarge?.copyWith(color: b.textMuted)),
                            SizedBox(height: b.spacing.md),
                            ListingGrid(listings: list),
                          ],
                        ),
                      ),
                    ),
            ),
    );
  }
}
