import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';

import 'format.dart';
import 'listing_editor.dart';
import 'providers.dart';

/// The time the Dashboard counts from; tests pin it.
final dashboardClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// The admin's home: what needs doing now (leads nobody has answered,
/// today's viewings, listings waiting for review) and how things are going
/// (leads per day), for the signed-in person: agents see their own only.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  late Future<DashboardData> _data = _load();

  Future<DashboardData> _load() => ref.read(adminRepositoryProvider).dashboard(ref.read(staffProvider)!, ref.read(dashboardClockProvider)());

  Future<void> _newListing() async {
    final id = await showDialog<String>(context: context, builder: (_) => const ListingEditorDialog());
    if (id != null && mounted) {
      setState(() {
        _data = _load();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final who = ref.watch(staffProvider)!;
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final now = ref.watch(dashboardClockProvider)();
    final greeting = switch (now.hour) { < 12 => 'Good morning', < 17 => 'Good afternoon', _ => 'Good evening' };
    final first = who.name.split(' ').first;

    return RefreshIndicator(
      onRefresh: () async {
        setState(() {
          _data = _load();
        });
        await _data;
      },
      child: ListView(padding: const EdgeInsets.all(24), children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 12,
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$greeting, $first', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                '${longDate(now)} · ${who.isManager ? 'Everything across the team' : 'Your leads, viewings and listings'}',
                style: text.bodyMedium?.copyWith(color: b.textMuted),
              ),
            ]),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                onPressed: () => setState(() {
                  _data = _load();
                }),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Refresh'),
              ),
              FilledButton.icon(
                key: const Key('dashboard-new-listing'),
                onPressed: _newListing,
                icon: const Icon(Icons.add_home_outlined, size: 18),
                label: const Text('New listing'),
              ),
            ]),
          ],
        ),
        const SizedBox(height: 24),
        FutureBuilder<DashboardData>(
          future: _data,
          builder: (context, snap) {
            if (snap.hasError) {
              return _Panel(child: Text("Couldn't load the dashboard: ${snap.error}", style: TextStyle(color: Theme.of(context).colorScheme.error)));
            }
            final d = snap.data;
            if (d == null) return const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()));
            return _Body(data: d, now: now, who: who);
          },
        ),
      ]),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.data, required this.now, required this.who});
  final DashboardData data;
  final DateTime now;
  final StaffUser who;

  @override
  Widget build(BuildContext context) {
    final since = DateTime(now.year, now.month, now.day).subtract(const Duration(days: dashboardDays - 1));
    final tiles = [
      _Stat(
        key: const Key('stat-new-leads'),
        icon: Icons.mark_email_unread_outlined,
        label: 'New leads',
        value: data.newLeads,
        caption: 'Waiting for a first reply',
        onTap: () => context.go('/leads'),
        urgent: data.newLeads > 0,
      ),
      _Stat(
        key: const Key('stat-leads-period'),
        icon: Icons.trending_up,
        label: 'Leads, last $dashboardDays days',
        value: data.leadsInPeriod,
        caption: 'Since ${shortDate(since)}',
        onTap: () => context.go('/leads'),
      ),
      _Stat(
        key: const Key('stat-viewings-today'),
        icon: Icons.event_available_outlined,
        label: 'Viewings today',
        value: data.viewingsToday,
        caption: '${data.viewingsWeek} in the next 7 days',
        onTap: () => context.go('/viewings'),
      ),
      _Stat(
        key: const Key('stat-live-listings'),
        icon: Icons.home_work_outlined,
        label: 'Live listings',
        value: data.liveListings,
        caption:
            data.pendingListings == 0 ? 'Nothing waiting for review' : '${data.pendingListings} waiting for ${who.isManager ? 'your' : 'a manager\'s'} review',
        onTap: () => context.go('/listings'),
        urgent: who.isManager && data.pendingListings > 0,
      ),
    ];
    final upcoming = _Panel(
      title: 'Upcoming viewings',
      action: TextButton(onPressed: () => context.go('/viewings'), child: const Text('All viewings')),
      child: data.upcoming.isEmpty
          ? const _Empty(icon: Icons.event_busy_outlined, line: 'No viewings booked yet.')
          : Column(children: [for (final v in data.upcoming) _ViewingTile(v: v, now: now, showAgent: who.isManager)]),
    );
    final chart = _Panel(
      title: 'Leads per day',
      subtitle: 'Last $dashboardDays days · ${data.leadsInPeriod} in all',
      child: _LeadsChart(byDay: data.leadsByDay, now: now),
    );
    final leads = _Panel(
      title: 'New leads to contact',
      action: TextButton(onPressed: () => context.go('/leads'), child: const Text('All leads')),
      child: data.latestLeads.isEmpty
          ? const _Empty(icon: Icons.done_all, line: 'Every lead has had a reply.')
          : Column(children: [for (final l in data.latestLeads) _LeadTile(l: l, now: now, showAgent: who.isManager)]),
    );
    final activity = who.canOpen(AdminSection.audit)
        ? _Panel(
            title: 'Recent activity',
            action: TextButton(onPressed: () => context.go('/audit'), child: const Text('Audit log')),
            child: data.activity.isEmpty
                ? const _Empty(icon: Icons.history, line: 'Nothing yet.')
                : Column(children: [for (final a in data.activity) _ActivityTile(a: a, now: now)]),
          )
        : null;

    return LayoutBuilder(builder: (context, box) {
      final across = box.maxWidth >= 1100 ? 4 : (box.maxWidth >= 560 ? 2 : 1);
      const gap = 16.0;
      final tileWidth = (box.maxWidth - gap * (across - 1)) / across;
      final two = box.maxWidth >= 900;
      Widget pair(Widget a, Widget? b, {int flexA = 1, int flexB = 1}) => b == null
          ? a
          : two
              ? IntrinsicHeight(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(flex: flexA, child: a),
                    const SizedBox(width: gap),
                    Expanded(flex: flexB, child: b),
                  ]),
                )
              : Column(children: [a, const SizedBox(height: gap), b]);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: gap, runSpacing: gap, children: [for (final t in tiles) SizedBox(width: tileWidth, child: t)]),
        const SizedBox(height: gap),
        pair(chart, upcoming, flexA: 3, flexB: 2),
        const SizedBox(height: gap),
        pair(leads, activity),
      ]);
    });
  }
}

/// A white card with an optional heading row.
class _Panel extends StatelessWidget {
  const _Panel({this.title, this.subtitle, this.action, required this.child});
  final String? title, subtitle;
  final Widget? action;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(b.radiusMd + 4),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (title != null) ...[
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title!, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  if (subtitle != null) Text(subtitle!, style: text.bodySmall?.copyWith(color: b.textMuted)),
                ]),
              ),
              if (action != null) action!,
            ]),
            const SizedBox(height: 12),
          ],
          child,
        ]),
      ),
    );
  }
}

/// One headline number: what it is, the number, what it means; opens its page.
class _Stat extends StatelessWidget {
  const _Stat({super.key, required this.icon, required this.label, required this.value, required this.caption, required this.onTap, this.urgent = false});
  final IconData icon;
  final String label, caption;
  final int value;
  final VoidCallback onTap;

  /// Something is waiting on someone: the icon takes the accent.
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(b.radiusMd + 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(b.radiusMd + 4),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(b.radiusMd + 4),
            border: Border.all(color: scheme.outlineVariant),
          ),
          padding: const EdgeInsets.all(20),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: text.bodyMedium?.copyWith(color: b.textMuted, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text('$value', style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: scheme.onSurface)),
                const SizedBox(height: 4),
                Text(caption, style: text.bodySmall?.copyWith(color: b.textMuted), maxLines: 2, overflow: TextOverflow.ellipsis),
              ]),
            ),
            DecoratedBox(
              decoration: BoxDecoration(color: urgent ? b.accent : b.primarySoft, shape: BoxShape.circle),
              child: Padding(padding: const EdgeInsets.all(10), child: Icon(icon, size: 22, color: urgent ? b.onAccent : scheme.primary)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.line});
  final IconData icon;
  final String line;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(children: [
        Icon(icon, color: b.textMuted, size: 28),
        const SizedBox(height: 8),
        Text(line, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: b.textMuted)),
      ]),
    );
  }
}

/// Leads per day as thin bars, one hue, the day under each; hovering a bar
/// says the day and the count. One series, so no legend: the title names it.
class _LeadsChart extends StatelessWidget {
  const _LeadsChart({required this.byDay, required this.now});
  final List<int> byDay;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final top = byDay.fold(0, (a, c) => c > a ? c : a);
    final today = DateTime(now.year, now.month, now.day);
    const plot = 160.0;
    return SizedBox(
      height: plot + 28,
      child: Stack(children: [
        // The one gridline: the highest day, labelled; the baseline under the bars.
        if (top > 0)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Row(children: [
              Expanded(child: Divider(height: 1, color: scheme.outlineVariant)),
              const SizedBox(width: 6),
              Text('$top', style: text.labelSmall?.copyWith(color: b.textMuted)),
            ]),
          ),
        Positioned(left: 0, right: 0, top: plot, child: Divider(height: 1, color: scheme.outline)),
        Positioned.fill(
          right: 24,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (final (i, n) in byDay.indexed)
              Expanded(
                child: () {
                  final day = today.subtract(Duration(days: byDay.length - 1 - i));
                  final h = top == 0 ? 0.0 : (plot - 4) * n / top;
                  return Tooltip(
                    message: '${shortDate(day)}: $n ${n == 1 ? 'lead' : 'leads'}',
                    child: Semantics(
                      label: '${shortDate(day)}, $n leads',
                      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                        Container(
                          // Thin bars, never wider than 24, with surface between them.
                          constraints: const BoxConstraints(maxWidth: 24),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          height: n == 0 ? 2 : h.clamp(4.0, plot),
                          decoration: BoxDecoration(
                            color: n == 0 ? scheme.outlineVariant : scheme.primary,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                          ),
                        ),
                        SizedBox(
                          height: 28,
                          child: Center(
                            child: Text(
                              '${day.day}',
                              style: text.labelSmall?.copyWith(
                                color: i == byDay.length - 1 ? scheme.onSurface : b.textMuted,
                                fontWeight: i == byDay.length - 1 ? FontWeight.w700 : FontWeight.w400,
                              ),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  );
                }(),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _ViewingTile extends StatelessWidget {
  const _ViewingTile({required this.v, required this.now, required this.showAgent});
  final ViewingRow v;
  final DateTime now;
  final bool showAgent;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final l = v.slot.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(l.year, l.month, l.day);
    final when = day == today ? 'Today' : (day == today.add(const Duration(days: 1)) ? 'Tomorrow' : shortDate(l));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Container(
          width: 64,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(color: b.primarySoft, borderRadius: BorderRadius.circular(b.radiusSm)),
          child: Column(children: [
            Text(when, style: text.labelSmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(timeOfDay(l), style: text.labelLarge?.copyWith(color: scheme.primary, fontWeight: FontWeight.w800)),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(v.listingTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            Text(
              [v.clientName ?? 'Client', if (showAgent) v.agentName, label(v.status)].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(color: b.textMuted),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _LeadTile extends StatelessWidget {
  const _LeadTile({required this.l, required this.now, required this.showAgent});
  final LeadRow l;
  final DateTime now;
  final bool showAgent;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final name = l.contactName ?? l.contactPhone ?? 'Someone';
    final initials = name.trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0].toUpperCase()).join();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        CircleAvatar(
            radius: 18,
            backgroundColor: b.primarySoft,
            child: Text(initials, style: text.labelLarge?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700))),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            Text(
              [l.listingTitle, label(l.channel), if (showAgent) l.agentName].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(color: b.textMuted),
            ),
          ]),
        ),
        const SizedBox(width: 8),
        Text(ago(l.createdAt, now), style: text.labelSmall?.copyWith(color: b.textMuted)),
      ]),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.a, required this.now});
  final AuditRow a;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final change = [a.from, a.to].whereType<String>().map(label).join(' → ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 2), child: Icon(Icons.circle, size: 8, color: b.textMuted)),
        const SizedBox(width: 12),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: a.actorName, style: const TextStyle(fontWeight: FontWeight.w600)),
              TextSpan(text: ' · ${label(a.action)} · ${a.target}${change.isEmpty ? '' : ' ($change)'}'),
            ]),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: text.bodySmall,
          ),
        ),
        const SizedBox(width: 8),
        Text(ago(a.at, now), style: text.labelSmall?.copyWith(color: b.textMuted)),
      ]),
    );
  }
}
