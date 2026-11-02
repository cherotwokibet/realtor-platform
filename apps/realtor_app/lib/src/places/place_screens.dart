import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';

import '../providers.dart';
import '../search/results_screen.dart';

/// Shared layout: a heading block, then the live homes.
class _PlaceScaffold extends ConsumerWidget {
  const _PlaceScaffold({required this.title, required this.header, required this.homes, required this.emptyHomes});
  final String title, emptyHomes;
  final List<Widget> header;
  final ({String? area, String? agent}) homes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final listings = ref.watch(liveListingsProvider(homes));
    return Scaffold(
      appBar: AppBar(title: Text(title, overflow: TextOverflow.ellipsis)),
      body: ListView(padding: EdgeInsets.all(b.spacing.gutter), children: [
        ...header,
        SizedBox(height: b.spacing.lg),
        Text('Homes', style: text.titleMedium),
        SizedBox(height: b.spacing.sm),
        ...listings.when(
          loading: () => [const Center(child: CircularProgressIndicator())],
          error: (_, __) => [Text("Couldn't load the homes. Please try again.", style: text.bodyMedium)],
          data: (rows) => rows.isEmpty
              ? [Text(emptyHomes, style: text.bodyMedium)]
              : [
                  for (final l in rows) ...[ListingCard(listing: l), SizedBox(height: b.spacing.md)],
                ],
        ),
      ]),
    );
  }
}

Widget _missing(BuildContext context, String what) =>
    Scaffold(appBar: AppBar(), body: Center(child: Text('This $what is not here any more.', style: Theme.of(context).textTheme.bodyLarge)));

/// `/area/<slug>`: the guide, typical rent, what is nearby and live homes.
class AreaScreen extends ConsumerWidget {
  const AreaScreen({super.key, required this.slug});
  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    return ref.watch(areaProvider(slug)).when(
          loading: () => Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator())),
          error: (_, __) => _missing(context, 'area'),
          data: (a) => a == null
              ? _missing(context, 'area')
              : _PlaceScaffold(
                  title: a.name,
                  homes: (area: slug, agent: null),
                  emptyHomes: 'No homes listed in ${a.name} right now.',
                  header: [
                    Text('Homes in ${a.name}', style: text.headlineSmall),
                    Text(a.county, style: text.bodySmall?.copyWith(color: b.textMuted)),
                    if (a.medianRentKES != null) ...[
                      SizedBox(height: b.spacing.sm),
                      Text('Typical rent: ${formatKes(a.medianRentKES!)} a month', style: text.titleSmall),
                    ],
                    if (a.guide.isNotEmpty) ...[SizedBox(height: b.spacing.md), Text(a.guide, style: text.bodyMedium)],
                    if (a.amenities.isNotEmpty) ...[
                      SizedBox(height: b.spacing.md),
                      Text('Nearby', style: text.titleSmall),
                      SizedBox(height: b.spacing.xs),
                      Wrap(spacing: b.spacing.sm, runSpacing: b.spacing.sm, children: [for (final x in a.amenities) Chip(label: Text(x))]),
                    ],
                  ],
                ),
        );
  }
}

/// `/agent/<id>`: an active agent's profile, contacts and live homes.
class AgentScreen extends ConsumerWidget {
  const AgentScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    return ref.watch(agentProvider(id)).when(
          loading: () => Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator())),
          error: (_, __) => _missing(context, 'agent'),
          data: (a) {
            if (a == null) return _missing(context, 'agent');
            final open = ref.read(urlOpenerProvider);
            final speaks = [for (final l in a.languages) agentLanguages[l] ?? l].join(' and ');
            return _PlaceScaffold(
              title: a.name,
              homes: (area: null, agent: id),
              emptyHomes: '${a.name} has no homes listed right now.',
              header: [
                Text(a.name, style: text.headlineSmall),
                SizedBox(height: b.spacing.xs),
                Text(
                  [
                    'EARB reg. ${a.earbNo}',
                    'Speaks $speaks',
                    if (a.responseMins != null) 'Usually replies within ${a.responseMins} min',
                    if (a.rating != null) 'Rated ${a.rating!.toStringAsFixed(1)} of 5',
                  ]
                      .join(' · '),
                  style: text.bodySmall?.copyWith(color: b.textMuted),
                ),
                SizedBox(height: b.spacing.md),
                Wrap(spacing: b.spacing.sm, runSpacing: b.spacing.sm, children: [
                  FilledButton.icon(
                    onPressed: () => open(Uri.https('wa.me', '/${a.whatsapp.replaceAll('+', '')}')),
                    icon: const Icon(Icons.chat_outlined),
                    label: const Text('WhatsApp'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => open(Uri(scheme: 'tel', path: a.phone)),
                    icon: const Icon(Icons.call_outlined),
                    label: const Text('Call'),
                  ),
                ]),
              ],
            );
          },
        );
  }
}
