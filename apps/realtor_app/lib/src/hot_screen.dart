import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_ui/realtor_ui.dart';

import 'nav.dart';
import 'providers.dart';
import 'search/results_screen.dart';

/// `/hot`: every home a manager put in Hot Properties, from the home page's
/// See all; four across on a computer, as the home page's rows.
class HotScreen extends ConsumerWidget {
  const HotScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final hot = ref.watch(hotHomesProvider);
    return Scaffold(
      appBar: AppBar(
        leading: const AppBack(),
        centerTitle: true,
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.local_fire_department, color: scheme.primary),
          SizedBox(width: b.spacing.sm),
          const Text('Hot properties'),
        ]),
      ),
      body: hot.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Hot properties could not be loaded.', style: text.bodyMedium)),
        data: (list) => list.isEmpty
            ? Center(child: Text('No hot properties right now.', style: text.bodyLarge?.copyWith(color: b.textMuted)))
            : ListView(padding: EdgeInsets.all(b.spacing.gutter), children: [
                Text('${list.length} ${list.length == 1 ? 'home' : 'homes'}', style: text.labelLarge?.copyWith(color: b.textMuted)),
                SizedBox(height: b.spacing.md),
                ListingGrid(key: const Key('hot-grid'), listings: list, maxAcross: 4),
              ]),
      ),
    );
  }
}
