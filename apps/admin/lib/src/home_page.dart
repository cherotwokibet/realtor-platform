import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';

import 'format.dart';
import 'providers.dart';

/// How long a listing stays Featured when added from here.
const homeFeatureDays = 14;

/// The home page's rows, as managers fill them: Hot properties, Featured
/// (for some days), Recommended, and Newest to rent with chosen homes pinned
/// first. Only live listings can be placed; the site shows each row only
/// when it has homes.
class HomePlacementsScreen extends ConsumerStatefulWidget {
  const HomePlacementsScreen({super.key});

  @override
  ConsumerState<HomePlacementsScreen> createState() => _HomePlacementsScreenState();
}

class _HomePlacementsScreenState extends ConsumerState<HomePlacementsScreen> {
  late Future<List<StaffListingRow>> _live = _load();
  final _busy = <String>{};

  Future<List<StaffListingRow>> _load() async => (await ref.read(adminRepositoryProvider).listings(ref.read(staffProvider)!, status: 'live', limit: 500)).rows;

  Future<void> _set(StaffListingRow l, String placement, bool on) async {
    final who = ref.read(staffProvider)!, actions = ref.read(adminActionsProvider);
    final messenger = ScaffoldMessenger.of(context);
    final key = '${l.id}/$placement';
    setState(() => _busy.add(key));
    try {
      if (placement == 'featured') {
        await actions.featureListing(who, listingId: l.id, days: on ? homeFeatureDays : 0);
      } else {
        await actions.setPlacement(who, listingId: l.id, placement: placement, on: on);
      }
      final name = homePlacements.firstWhere((p) => p.$1 == placement).$2;
      messenger.showSnackBar(SnackBar(content: Text(on ? '${l.title}: added to $name' : '${l.title}: taken out of $name')));
      if (mounted) {
        setState(() {
          _live = _load();
        });
      }
    } on AdminActionException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text("Couldn't save: ${e.message}")));
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  Future<void> _add(String placement, List<StaffListingRow> live) async {
    final now = DateTime.now();
    final picked = await showDialog<StaffListingRow>(
      context: context,
      builder: (_) => _PickListing(options: [
        for (final l in live)
          if (!l.inPlacement(placement, now)) l
      ]),
    );
    if (picked != null) await _set(picked, placement, true);
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final t = Theme.of(context).textTheme;
    return FutureBuilder<List<StaffListingRow>>(
      future: _live,
      builder: (context, snap) {
        final live = snap.data;
        final now = DateTime.now();
        return ListView(padding: const EdgeInsets.all(24), children: [
          Text('Home page', style: t.headlineSmall),
          const SizedBox(height: 4),
          Text('Choose the homes in each row of the site\'s home page. Only live listings can be placed; an empty row is not shown.',
              style: t.bodyMedium?.copyWith(color: b.textMuted)),
          const SizedBox(height: 16),
          if (snap.hasError) Text("Couldn't load the listings: ${snap.error}", style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (live == null && !snap.hasError) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          if (live != null)
            LayoutBuilder(builder: (context, box) {
              final across = box.maxWidth >= 1000 ? 2 : 1;
              final w = (box.maxWidth - 16 * (across - 1)) / across;
              return Wrap(spacing: 16, runSpacing: 16, children: [
                for (final (key, name) in homePlacements)
                  SizedBox(
                    width: w,
                    child: _RowCard(
                      key: Key('placement-$key'),
                      name: name,
                      showUntil: key == 'featured',
                      icon: switch (key) {
                        'hot' => Icons.local_fire_department_outlined,
                        'featured' => Icons.workspace_premium_outlined,
                        'recommended' => Icons.thumb_up_alt_outlined,
                        _ => Icons.push_pin_outlined,
                      },
                      note: switch (key) {
                        'featured' => 'Ranks first in search too; for $homeFeatureDays days from when it is added.',
                        'newest' => 'Pinned homes come first in Newest to rent; the rest follow, newest first.',
                        _ => null,
                      },
                      homes: [
                        for (final l in live)
                          if (l.inPlacement(key, now)) l
                      ],
                      now: now,
                      busy: (l) => _busy.contains('${l.id}/$key'),
                      onAdd: () => _add(key, live),
                      onRemove: (l) => _set(l, key, false),
                    ),
                  ),
              ]);
            }),
        ]);
      },
    );
  }
}

class _RowCard extends StatelessWidget {
  const _RowCard({
    super.key,
    required this.name,
    required this.icon,
    required this.homes,
    required this.now,
    required this.busy,
    required this.onAdd,
    required this.onRemove,
    this.note,
    this.showUntil = false,
  });
  final String name;

  /// Featured: say until when.
  final bool showUntil;
  final IconData icon;
  final String? note;
  final List<StaffListingRow> homes;
  final DateTime now;
  final bool Function(StaffListingRow) busy;
  final VoidCallback onAdd;
  final ValueChanged<StaffListingRow> onRemove;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(b.radiusMd + 4),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(icon, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(child: Text('$name · ${homes.length}', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
          FilledButton.tonalIcon(onPressed: onAdd, icon: const Icon(Icons.add, size: 18), label: const Text('Add')),
        ]),
        if (note != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(note!, style: t.bodySmall?.copyWith(color: b.textMuted))),
        const SizedBox(height: 8),
        if (homes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text('None yet: the row is hidden on the site.', style: t.bodyMedium?.copyWith(color: b.textMuted)),
          ),
        for (final l in homes)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text([
              label(l.area),
              formatKes(l.priceKES),
              l.agentName,
              if (showUntil && l.featuredUntil != null && l.featuredAt(now)) 'until ${shortDate(l.featuredUntil!)}',
            ].join(' · ')),
            trailing: busy(l)
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : IconButton(tooltip: 'Take out of $name', icon: const Icon(Icons.close), onPressed: () => onRemove(l)),
          ),
      ]),
    );
  }
}

/// A live listing to add, found by its title, area or agent.
class _PickListing extends StatefulWidget {
  const _PickListing({required this.options});
  final List<StaffListingRow> options;

  @override
  State<_PickListing> createState() => _PickListingState();
}

class _PickListingState extends State<_PickListing> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.text.trim().toLowerCase();
    final shown = [
      for (final l in widget.options)
        if (q.isEmpty || l.title.toLowerCase().contains(q) || l.area.contains(q) || l.agentName.toLowerCase().contains(q)) l
    ];
    return AlertDialog(
      title: const Text('Add a live listing'),
      content: SizedBox(
        width: 520,
        height: 420,
        child: Column(children: [
          TextField(
            key: const Key('pick-listing-search'),
            controller: _q,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Title, area or agent', border: OutlineInputBorder(), isDense: true),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: shown.isEmpty
                ? const Center(child: Text('No live listing matches.'))
                : ListView(children: [
                    for (final l in shown)
                      ListTile(
                        title: Text(l.title),
                        subtitle: Text('${label(l.area)} · ${formatKes(l.priceKES)} · ${l.agentName}'),
                        onTap: () => Navigator.pop(context, l),
                      ),
                  ]),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
    );
  }
}
