import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';

import '../nav.dart';
import '../providers.dart';
import '../search/purpose.dart';
import '../search/recent_searches.dart';
import 'activity.dart';

/// `/account/activity`, as Bayut's Your Activity: Recent Searches, Viewed
/// and Contacted, each newest first and grouped by day where it has dates.
/// Kept on this device only.
class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

enum _Tab { searches, viewed, contacted }

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  _Tab _tab = _Tab.searches;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final now = ref.read(clockProvider)();

    Widget chip(_Tab t, String label) => ChoiceChip(
          key: Key('activity-${t.name}'),
          label: Text(label),
          selected: _tab == t,
          showCheckmark: false,
          onSelected: (_) => setState(() => _tab = t),
        );
    Widget card({required IconData icon, required String title, String? place, List<String> tags = const [], required VoidCallback onTap}) => Padding(
          padding: EdgeInsets.only(bottom: b.spacing.md),
          child: Material(
            color: scheme.surface,
            elevation: 1,
            shadowColor: scheme.scrim.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(b.radiusMd),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: EdgeInsets.all(b.spacing.md),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(icon, color: scheme.primary, size: 20),
                        SizedBox(width: b.spacing.sm),
                        Expanded(child: Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
                      ]),
                      if (place != null) ...[
                        SizedBox(height: b.spacing.xs),
                        Row(children: [
                          Icon(Icons.place, color: b.textMuted, size: 18),
                          SizedBox(width: b.spacing.sm),
                          Expanded(child: Text(place, style: text.bodyMedium)),
                        ]),
                      ],
                      if (tags.isNotEmpty) ...[
                        SizedBox(height: b.spacing.sm),
                        Wrap(spacing: b.spacing.xs, runSpacing: b.spacing.xs, children: [
                          for (final t in tags)
                            DecoratedBox(
                              decoration: BoxDecoration(color: b.primarySoft, borderRadius: BorderRadius.circular(b.radiusSm)),
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: b.spacing.sm, vertical: 2),
                                child: Text(t, style: text.labelSmall?.copyWith(color: scheme.primary)),
                              ),
                            ),
                        ]),
                      ],
                    ]),
                  ),
                  const Icon(Icons.chevron_right),
                ]),
              ),
            ),
          ),
        );
    Widget empty(String line) => Padding(
          padding: EdgeInsets.symmetric(vertical: b.spacing.xxl),
          child: Column(children: [
            Icon(Icons.history, size: 40, color: b.textMuted),
            SizedBox(height: b.spacing.sm),
            Text(line, style: text.bodyMedium?.copyWith(color: b.textMuted), textAlign: TextAlign.center),
          ]),
        );
    Widget day(String label) => Padding(
          padding: EdgeInsets.only(top: b.spacing.sm, bottom: b.spacing.sm),
          child: Text(label, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        );
    List<Widget> homes(List<ActivityEntry> entries, String emptyLine) {
      if (entries.isEmpty) return [empty(emptyLine)];
      final out = <Widget>[];
      String? last;
      for (final e in entries) {
        final heading = activityDay(e.at, now);
        if (heading != last) out.add(day(heading));
        last = heading;
        final h = e.home;
        out.add(card(
          icon: Icons.apartment,
          title: h.title,
          place: areaName(h.area),
          tags: [
            formatKes(h.priceKES, compact: true) + (h.purpose.period == null ? '' : ' / ${h.purpose.period}'),
            if (h.beds > 0) '${h.beds} bed',
            if (h.baths > 0) '${h.baths} bath',
            if (e.channel != null) switch (e.channel) { 'call' => 'Called', 'whatsapp' => 'WhatsApp', _ => 'Emailed' },
          ],
          onTap: () => context.push('/listing/${h.slug}'),
        ));
      }
      return out;
    }

    final List<Widget> body = switch (_tab) {
      _Tab.searches => () {
          final recent = ref.watch(recentSearchesProvider).value ?? const [];
          if (recent.isEmpty) return [empty('Your searches will show here.')];
          return [
            for (final f in recent)
              card(
                icon: Icons.search,
                title: f.types.isEmpty ? 'Homes ${f.purpose.heading}' : '${f.types.map(typeName).join(', ')} ${f.purpose.heading}',
                place: f.areas.isEmpty ? 'Anywhere' : f.areas.map(areaName).join(', '),
                tags: [
                  if (f.minBeds != null) '${f.minBeds}+ bed',
                  for (final n in f.beds) '$n bed',
                  if (f.maxPriceKES != null) 'Up to ${formatKes(f.maxPriceKES!, compact: true)}',
                  if (f.q != null) '"${f.q}"',
                ],
                onTap: () => context.push(f.toUri().toString()),
              ),
          ];
        }(),
      _Tab.viewed => homes(ref.watch(activityProvider(ActivityKind.viewed)).value ?? const [], 'Homes you open will show here.'),
      _Tab.contacted =>
        homes(ref.watch(activityProvider(ActivityKind.contacted)).value ?? const [], 'Homes whose agent you call, WhatsApp or email will show here.'),
    };

    return Scaffold(
      backgroundColor: b.surfaceAlt,
      appBar: AppBar(leading: const AppBack(), centerTitle: true, title: const Text('Your Activity')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: EdgeInsets.all(b.spacing.gutter), children: [
            Wrap(spacing: b.spacing.sm, children: [
              chip(_Tab.searches, 'Recent Searches'),
              chip(_Tab.viewed, 'Viewed'),
              chip(_Tab.contacted, 'Contacted'),
            ]),
            SizedBox(height: b.spacing.md),
            ...body,
          ]),
        ),
      ),
    );
  }
}
