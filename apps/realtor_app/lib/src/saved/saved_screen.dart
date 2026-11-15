import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:realtor_ui/realtor_ui.dart';

import '../account/account_data.dart';
import '../search/results_screen.dart';
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
    final saved = ref.watch(favouritesProvider);
    final signedIn = ref.watch(customerProvider).value != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Saved homes')),
      body: !signedIn
          ? Padding(
              padding: EdgeInsets.all(b.spacing.xl),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Sign in to see the homes you have saved.', style: text.bodyMedium, textAlign: TextAlign.center),
                SizedBox(height: b.spacing.md),
                FilledButton(onPressed: () => context.go('/account'), child: const Text('Log in / Sign up')),
              ]),
            )
          : saved.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text("Couldn't open your saved homes.", style: text.bodyMedium)),
        data: (list) => list.isEmpty
            ? Padding(
                padding: EdgeInsets.all(b.spacing.xl),
                child: Text(
                  'Tap the heart on a home to keep it here. Saved homes stay on this phone; nothing is sent anywhere.',
                  style: text.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              )
            : ListView(
                padding: EdgeInsets.all(b.spacing.gutter),
                children: [
                  for (final l in list) ...[ListingCard(listing: l), SizedBox(height: b.spacing.md)],
                ],
              ),
      ),
    );
  }
}
