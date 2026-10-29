import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_core/realtor_core.dart';

import 'agent_profiles.dart';
import 'area_guides.dart';
import 'format.dart';
import 'links.dart';
import 'listing_editor.dart';
import 'reviews_dialog.dart';
import 'paged_table.dart';
import 'providers.dart';

/// A new lead should get its first reply within this many minutes (P5-s03).
const leadReplyTargetMins = 60;

/// Heading, optional filters and a table, in a scrollable page.
class _TablePage extends StatelessWidget {
  const _TablePage({required this.title, this.subtitle, this.filters, this.action, required this.table});
  final String title;
  final String? subtitle;
  final Widget? filters;

  /// A button beside the title (e.g. Import CSV).
  final Widget? action;
  final Widget table;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [Expanded(child: Text(title, style: t.headlineSmall)), if (action != null) action!]),
        if (subtitle != null)
          Padding(padding: const EdgeInsets.only(top: 4), child: Text(subtitle!, style: t.bodyMedium)),
        if (filters != null) Padding(padding: const EdgeInsets.only(top: 12), child: filters),
        const SizedBox(height: 12),
        Card(clipBehavior: Clip.antiAlias, child: table),
      ],
    );
  }
}

/// Runs a change through the Functions and says how it went.
Future<bool> _act(BuildContext context, Future<void> Function() change, String done) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await change();
    messenger.showSnackBar(SnackBar(content: Text(done)));
    return true;
  } on AdminActionException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text("Couldn't save: ${e.message}")));
    return false;
  }
}

/// The value as text, with a menu of [options] when there are any.
class _MenuCell extends StatelessWidget {
  const _MenuCell(
      {required this.text,
      required this.tooltip,
      required this.options,
      required this.labelOf,
      required this.onSelected,
      this.saving = false});
  final String text, tooltip;
  final List<String> options;
  final String Function(String) labelOf;
  final ValueChanged<String> onSelected;

  /// A change is on its way to the Functions: show it, and offer nothing
  /// else until it lands (a second pick would race the first).
  final bool saving;

  @override
  Widget build(BuildContext context) {
    if (saving) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Text(text),
        const SizedBox(width: 8),
        const SizedBox.square(
          dimension: 14,
          child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: 'Saving'),
        ),
      ]);
    }
    if (options.isEmpty) return Text(text);
    return PopupMenuButton<String>(
      tooltip: tooltip,
      onSelected: onSelected,
      itemBuilder: (context) => [for (final o in options) PopupMenuItem(value: o, child: Text(labelOf(o)))],
      child: Row(mainAxisSize: MainAxisSize.min, children: [Text(text), const Icon(Icons.arrow_drop_down)]),
    );
  }
}

/// How a moderation action reads for a listing at [status].
String moderationLabel(String action, String status) => switch ((action, status)) {
      ('approve', 'pending') => 'Approve',
      ('approve', _) => 'Relist',
      ('reject', 'pending') => 'Reject…',
      ('reject', _) => 'Unpublish…',
      ('expire', _) => 'Mark expired',
      ('let', _) => 'Mark let',
      ('sold', _) => 'Mark sold',
      ('confirm', _) => 'Confirm still available',
      ('feature', _) => 'Feature for $featureDays days',
      ('unfeature', _) => 'Stop featuring',
      _ => label(action),
    };

/// Asks why a listing is being rejected; null when cancelled.
Future<String?> _askReason(BuildContext context, String title) =>
    showDialog<String>(context: context, builder: (context) => _ReasonDialog(title: title));

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.title});
  final String title;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  // Owned here, so it lives as long as the dialog, closing animation included.
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          controller: _text,
          autofocus: true,
          maxLength: 500,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Reason (the agent sees this)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ListenableBuilder(
            listenable: _text,
            builder: (context, _) => FilledButton(
              onPressed: _text.text.trim().isEmpty ? null : () => Navigator.pop(context, _text.text.trim()),
              child: const Text('Save'),
            ),
          ),
        ],
      );
}

class LeadsScreen extends ConsumerStatefulWidget {
  const LeadsScreen({super.key});
  @override
  ConsumerState<LeadsScreen> createState() => _LeadsScreenState();
}

class _LeadsScreenState extends ConsumerState<LeadsScreen> {
  String? _stage;
  var _reload = 0;

  /// Lead id -> stage being saved, and stages saved but not yet reloaded.
  final _saving = <String, String>{}, _saved = <String, String>{};

  Future<void> _move(StaffUser who, LeadRow r, String to) async {
    if (_saving.containsKey(r.id)) return;
    setState(() => _saving[r.id] = to);
    final ok = await _act(
      context,
      () => ref.read(adminActionsProvider).moveLead(who, leadId: r.id, stage: to),
      '${r.contactName ?? 'Lead'} moved to ${label(to)}',
    );
    if (!mounted) return;
    setState(() {
      _saving.remove(r.id);
      if (ok) {
        _saved[r.id] = to;
        _reload++;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final who = ref.watch(staffProvider)!;
    final repo = ref.watch(adminRepositoryProvider);
    return _TablePage(
      title: 'Leads',
      subtitle: who.isManager ? 'Every agent\'s leads, newest first.' : 'Your leads, newest first.',
      filters: FilterChips(
          values: leadStages, selected: _stage, labelOf: label, onSelected: (s) => setState(() => _stage = s)),
      table: PagedTable<LeadRow>(
        key: ValueKey(('leads', who.uid, _stage)),
        empty: 'No leads at this stage.',
        reload: _reload,
        onLoaded: () {
          if (_saved.isNotEmpty && mounted) setState(_saved.clear);
        },
        load: (after) => repo.leads(who, stage: _stage, after: after, limit: pageSize),
        columns: [
          TableColumn('Received', (r) {
            final received = Text(shortDateTime(r.createdAt));
            if (r.stage != 'new') return received;
            // SLA (P5-s03): a new lead waiting over an hour shows red.
            final waiting = DateTime.now().difference(r.createdAt).inMinutes;
            return Row(mainAxisSize: MainAxisSize.min, children: [
              received,
              const SizedBox(width: 8),
              Text(
                'waiting ${minutesLabel(waiting < 0 ? 0 : waiting)}',
                style: TextStyle(
                  color: waiting > leadReplyTargetMins ? Theme.of(context).colorScheme.error : null,
                  fontWeight: waiting > leadReplyTargetMins ? FontWeight.w600 : null,
                ),
              ),
            ]);
          }),
          TableColumn('Name', (r) => Text(r.contactName ?? '—')),
          TableColumn('Phone', (r) => Text(r.contactPhone ?? '—')),
          TableColumn('Listing', (r) => Text(r.listingTitle)),
          TableColumn('Channel', (r) => Text(label(r.channel))),
          TableColumn(
            'Stage',
            (r) {
              final stage = _saving[r.id] ?? _saved[r.id] ?? r.stage;
              return _MenuCell(
                text: label(stage),
                tooltip: 'Move ${r.contactName ?? 'lead'} on',
                options: nextLeadStages(stage),
                labelOf: label,
                saving: _saving.containsKey(r.id),
                onSelected: (to) => _move(who, r, to),
              );
            },
          ),
          if (who.isManager) TableColumn('Agent', (r) => Text(r.agentName)),
        ],
      ),
    );
  }
}

/// Viewings (P5-s05): upcoming ones soonest first, or the history by
/// status. The agent (or a manager) confirms, cancels, and after the time
/// marks each done or a no-show.
class ViewingsScreen extends ConsumerStatefulWidget {
  const ViewingsScreen({super.key});
  @override
  ConsumerState<ViewingsScreen> createState() => _ViewingsScreenState();
}

class _ViewingsScreenState extends ConsumerState<ViewingsScreen> {
  String? _status;
  var _reload = 0;
  final _saving = <String, String>{}, _saved = <String, String>{};

  Future<void> _move(StaffUser who, ViewingRow v, String to) async {
    if (_saving.containsKey(v.id)) return;
    setState(() => _saving[v.id] = to);
    final ok = await _act(
      context,
      () => ref.read(adminActionsProvider).updateViewing(who, viewingId: v.id, status: to),
      'Viewing ${shortDateTime(v.slot)}: ${label(to)}',
    );
    if (!mounted) return;
    setState(() {
      _saving.remove(v.id);
      if (ok) {
        _saved[v.id] = to;
        _reload++;
      }
    });
  }

  /// Sends the client their one-time review link on WhatsApp (P6-s03).
  void _askReview(ViewingRow v) {
    final tenant = ref.read(tenantProvider);
    final link = 'https://${shareHost(tenant.shareDomain, ref.read(adminBaseProvider))}/review/${v.reviewToken}';
    final text = 'Hi${v.clientName == null ? '' : ' ${v.clientName!.split(' ').first}'}, thank you for viewing '
        '${v.listingTitle} with ${tenant.name}. How did it go? It takes a minute: $link';
    ref.read(linkOpenerProvider).open(Uri.https('wa.me', '/${v.clientPhone!.replaceAll('+', '')}', {'text': text}));
  }

  Future<void> _reschedule(StaffUser who, ViewingRow v) async {
    final slot = await showDialog<String>(context: context, builder: (_) => _RescheduleDialog(from: v.slot));
    if (slot == null || !mounted) return;
    setState(() => _saving[v.id] = 'cancelled');
    final ok = await _act(
      context,
      () => ref.read(adminActionsProvider).rescheduleViewing(who, viewingId: v.id, slot: slot),
      'Viewing moved to ${shortDateTime(DateTime.parse(slot).toLocal())}, confirmed',
    );
    if (!mounted) return;
    setState(() {
      _saving.remove(v.id);
      if (ok) _reload++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final who = ref.watch(staffProvider)!;
    final repo = ref.watch(adminRepositoryProvider);
    return _TablePage(
      title: 'Viewings',
      action: OutlinedButton.icon(
        onPressed: () => showDialog<void>(context: context, builder: (_) => const _TimeOffDialog()),
        icon: const Icon(Icons.event_busy_outlined),
        label: const Text('Time off…'),
      ),
      subtitle: _status == null
          ? 'Viewings to confirm or close, earliest first: past ones still need marking done or no-show.'
          : 'Latest first.',
      filters: FilterChips(
        values: viewingHistory,
        selected: _status,
        allLabel: 'Open',
        labelOf: label,
        onSelected: (s) => setState(() => _status = s),
      ),
      table: PagedTable<ViewingRow>(
        key: ValueKey(('viewings', who.uid, _status)),
        empty: _status == null ? 'No open viewings.' : 'None.',
        reload: _reload,
        onLoaded: () {
          if (_saved.isNotEmpty && mounted) setState(_saved.clear);
        },
        load: (after) {
          final now = DateTime.now();
          final from = DateTime(now.year, now.month, now.day - openViewingsDays);
          return repo.viewings(who, status: _status, from: from, after: after, limit: pageSize);
        },
        columns: [
          TableColumn('When', (v) => Text(shortDateTime(v.slot))),
          TableColumn('Listing', (v) => Text(v.listingTitle)),
          TableColumn('Client', (v) => Text(v.clientName ?? '—')),
          TableColumn('Phone', (v) => Text(v.clientPhone ?? '—')),
          TableColumn('Status', (v) {
            final status = _saving[v.id] ?? _saved[v.id] ?? v.status;
            return _MenuCell(
              text: label(status),
              tooltip: 'Update the viewing ${shortDateTime(v.slot)}',
              options: [
                ...nextViewingStatuses(status, v.slot, DateTime.now()),
                if (status == 'requested' || status == 'confirmed') 'reschedule',
                if (status == 'done' && v.reviewToken != null && v.clientPhone != null) 'review',
              ],
              labelOf: (s) => switch (s) {
                'reschedule' => 'Reschedule…',
                'review' => 'Ask for a review…',
                'confirmed' => 'Confirm',
                'done' => 'Mark done',
                'no-show' => 'Mark no-show',
                'cancelled' => 'Cancel viewing',
                _ => label(s),
              },
              saving: _saving.containsKey(v.id),
              onSelected: (s) => switch (s) {
                'reschedule' => _reschedule(who, v),
                'review' => _askReview(v),
                _ => _move(who, v, s),
              },
            );
          }),
          if (who.isManager) TableColumn('Agent', (v) => Text(v.agentName)),
        ],
      ),
    );
  }
}

class ListingsScreen extends ConsumerStatefulWidget {
  const ListingsScreen({super.key});
  @override
  ConsumerState<ListingsScreen> createState() => _ListingsScreenState();
}

class _ListingsScreenState extends ConsumerState<ListingsScreen> {
  String? _status;
  var _reload = 0;

  /// Listing id -> status being saved, and statuses saved but not yet reloaded.
  final _saving = <String, String>{}, _saved = <String, String>{};

  Future<void> _moderate(StaffUser who, StaffListingRow r, String action) async {
    String? reason;
    if (action == 'reject') {
      reason = await _askReason(context, '${moderationLabel(action, r.status).replaceAll('…', '')} "${r.title}"');
      if (reason == null || !mounted) return;
    }
    if (_saving.containsKey(r.id)) return;
    final to = switch (action) {
      'confirm' => 'live',
      'feature' || 'unfeature' => r.status,
      _ => moderationTargets[action]!,
    };
    setState(() => _saving[r.id] = to);
    final actions = ref.read(adminActionsProvider);
    final ok = await _act(
      context,
      () => switch (action) {
        'confirm' => actions.confirmListing(who, listingId: r.id),
        'feature' => actions.featureListing(who, listingId: r.id, days: featureDays),
        'unfeature' => actions.featureListing(who, listingId: r.id, days: 0),
        _ => actions.moderateListing(who, listingId: r.id, action: action, reason: reason),
      },
      switch (action) {
        'confirm' => '${r.title}: confirmed, verified for 30 days',
        'feature' => '${r.title}: featured for $featureDays days',
        'unfeature' => '${r.title}: no longer featured',
        _ => '${r.title}: ${label(to)}',
      },
    );
    if (!mounted) return;
    setState(() {
      _saving.remove(r.id);
      if (ok) {
        _saved[r.id] = to;
        _reload++;
      }
    });
  }

  /// Opens the editor; a save sends the listing to Pending.
  Future<void> _edit(String? listingId) async {
    final messenger = ScaffoldMessenger.of(context);
    final saved = await showDialog<String>(context: context, builder: (_) => ListingEditorDialog(listingId: listingId));
    if (saved == null || !mounted) return;
    messenger.showSnackBar(const SnackBar(content: Text('Saved. The listing waits in Pending for approval.')));
    setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    final who = ref.watch(staffProvider)!;
    final repo = ref.watch(adminRepositoryProvider);
    return _TablePage(
      title: 'Listings',
      action: Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(
          onPressed: () => _edit(null),
          icon: const Icon(Icons.add),
          label: const Text('New listing'),
        ),
        if (who.isManager)
          OutlinedButton.icon(
            onPressed: () => showDialog<void>(context: context, builder: (_) => const AreaGuidesDialog()),
            icon: const Icon(Icons.map_outlined),
            label: const Text('Areas…'),
          ),
        if (who.isManager)
          OutlinedButton.icon(
            onPressed: () async {
              final imported = await showDialog<int>(context: context, builder: (_) => const _ImportDialog());
              if ((imported ?? 0) > 0 && mounted) setState(() => _reload++);
            },
            icon: const Icon(Icons.upload_file),
            label: const Text('Import CSV…'),
          ),
      ]),
      subtitle:
          who.isManager ? 'Every listing, most recently updated first.' : 'Your listings, most recently updated first.',
      filters: FilterChips(
        values: listingStatuses,
        selected: _status,
        labelOf: label,
        onSelected: (s) => setState(() => _status = s),
      ),
      table: PagedTable<StaffListingRow>(
        key: ValueKey(('listings', who.uid, _status)),
        empty: 'No listings with this status.',
        reload: _reload,
        onLoaded: () {
          if (_saved.isNotEmpty && mounted) setState(_saved.clear);
        },
        load: (after) => repo.listings(who, status: _status, after: after, limit: pageSize),
        columns: [
          TableColumn(
            'Title',
            (r) {
              final featured = r.featuredAt(DateTime.now());
              final title = Tooltip(
                message: 'Edit ${r.title}',
                child: InkWell(onTap: () => _edit(r.id), child: Text(r.title, style: const TextStyle(decoration: TextDecoration.underline))),
              );
              if (!r.photoMatch && !featured) return title;
              return Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(child: title),
                if (featured) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'Featured until ${shortDateTime(r.featuredUntil!)}',
                    child: Icon(Icons.star, size: 18, color: Theme.of(context).colorScheme.primary),
                  ),
                ],
                if (r.photoMatch) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'A photo here matches another listing. Check it is theirs to use.',
                    child: Icon(Icons.flag_outlined, size: 18, color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ]);
            },
          ),
          TableColumn('Area', (r) => Text(label(r.area))),
          TableColumn('Price', (r) => Text(formatKes(r.priceKES)), numeric: true),
          TableColumn(
            'Status',
            (r) {
              final status = _saving[r.id] ?? _saved[r.id] ?? r.status;
              return _MenuCell(
                text: label(status),
                tooltip: 'Change ${r.title}',
                // Managers moderate; agents confirm their own. The Functions refuse anything else.
                options: listingActionsFor(who, status: status, agentId: r.agentId, featured: r.featuredAt(DateTime.now())),
                labelOf: (a) => moderationLabel(a, status),
                saving: _saving.containsKey(r.id),
                onSelected: (a) => _moderate(who, r, a),
              );
            },
          ),
          TableColumn('Leads', (r) => Text('${r.leads}'), numeric: true),
          TableColumn('Calls', (r) => Text('${r.calls}'), numeric: true),
          TableColumn('WhatsApp', (r) => Text('${r.whatsapps}'), numeric: true),
          if (who.isManager) TableColumn('Agent', (r) => Text(r.agentName)),
          TableColumn('Verified until', (r) {
            final e = r.expiresAt;
            if (e == null || (r.status != 'live' && r.status != 'expired')) return const Text('—');
            final lapsed = e.isBefore(DateTime.now());
            return Text(shortDateTime(e), style: lapsed ? TextStyle(color: Theme.of(context).colorScheme.error) : null);
          }),
          TableColumn('Updated', (r) => Text(shortDateTime(r.updatedAt))),
        ],
      ),
    );
  }
}

class AuditScreen extends ConsumerWidget {
  const AuditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final who = ref.watch(staffProvider)!;
    final repo = ref.watch(adminRepositoryProvider);
    return _TablePage(
      title: 'Audit log',
      subtitle: 'Every staff action, written by the server with the change itself.',
      table: PagedTable<AuditRow>(
        key: ValueKey(('audit', who.uid)),
        load: (after) => repo.audit(who, after: after, limit: pageSize),
        columns: [
          TableColumn('When', (r) => Text(shortDateTime(r.at))),
          TableColumn('Who', (r) => Text('${r.actorName} (${label(r.actorRole?.name ?? 'script')})')),
          TableColumn('Action', (r) => Text(label(r.action))),
          TableColumn('On', (r) => Text(r.target)),
          TableColumn('Change', (r) => Text([r.from, r.to].whereType<String>().map(label).join(' → '))),
          TableColumn('Reason', (r) => Text(r.reason ?? '')),
        ],
      ),
    );
  }
}

/// Staff and their roles. Owners and managers see it; only owners change it
/// (setStaffRole), and nobody can lock themselves out of the owner role.
class TeamScreen extends ConsumerStatefulWidget {
  const TeamScreen({super.key});
  @override
  ConsumerState<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends ConsumerState<TeamScreen> {
  final _saving = <String>{};

  /// Loaded once, and again after a change: not on every build, or any
  /// rebuild (a token refresh, say) would start the query over and the
  /// list would never appear.
  late Future<List<StaffMember>> _team = _load();

  Future<List<StaffMember>> _load() => ref.read(adminRepositoryProvider).team(ref.read(staffProvider)!);

  Future<void> _change(StaffUser who,
      {required String email, StaffRole? role, String? agentId, required String done}) async {
    if (_saving.contains(email)) return;
    setState(() => _saving.add(email));
    final ok = await _act(
      context,
      () => ref.read(adminActionsProvider).setStaffRole(who, email: email, role: role, agentId: agentId),
      done,
    );
    if (!mounted) return;
    setState(() {
      _saving.remove(email);
      if (ok) _team = _load();
    });
  }

  Future<void> _edit(StaffUser who, {StaffMember? member}) async {
    final agents = await ref.read(adminRepositoryProvider).agents(who);
    if (!mounted) return;
    final r = await showDialog<_StaffChoice>(
      context: context,
      builder: (context) => _StaffDialog(member: member, agents: agents),
    );
    if (r == null || !mounted) return;
    await _change(who,
        email: r.email,
        role: r.role,
        agentId: r.agentId,
        done: '${r.email} is now ${label(r.role.name).toLowerCase()}. They get it on their next sign-in.');
  }

  Future<void> _remove(StaffUser who, StaffMember m) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${m.email ?? m.name ?? 'this person'} from staff?'),
        content: const Text('Their account stays, but they lose access to the admin on their next sign-in.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (yes != true || !mounted || m.email == null) return;
    await _change(who, email: m.email!, done: '${m.email} removed from staff.');
  }

  @override
  Widget build(BuildContext context) {
    final who = ref.watch(staffProvider)!;
    return _TablePage(
      title: 'Team',
      action: Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(
          onPressed: () => showDialog<void>(context: context, builder: (_) => const ReviewsDialog()),
          icon: const Icon(Icons.star_outline),
          label: const Text('Reviews…'),
        ),
        OutlinedButton.icon(
          onPressed: () => showDialog<void>(context: context, builder: (_) => const AgentProfilesDialog()),
          icon: const Icon(Icons.badge_outlined),
          label: const Text('Agent profiles…'),
        ),
      ]),
      subtitle: who.canManageStaff
          ? 'Add people after they have signed in to this admin once. Changes apply on their next sign-in.'
          : 'Only owners change roles.',
      filters: who.canManageStaff
          ? Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: () => _edit(who),
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Add someone'),
              ),
            )
          : null,
      table: FutureBuilder<List<StaffMember>>(
        future: _team,
        builder: (context, snap) {
          if (snap.hasError) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Text("Couldn't load the team: ${snap.error}",
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            );
          }
          final team = snap.data;
          if (team == null) {
            return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
          }
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Email')),
                DataColumn(label: Text('Name')),
                DataColumn(label: Text('Role')),
                DataColumn(label: Text('Acts as agent')),
                DataColumn(label: Text('Typical reply')),
              ],
              rows: [
                for (final m in team)
                  DataRow(cells: [
                    DataCell(Text(m.email ?? '—')),
                    DataCell(Text(m.name ?? '—')),
                    DataCell(_MenuCell(
                      text: label(m.role.name),
                      tooltip: 'Change ${m.email ?? m.uid}',
                      saving: _saving.contains(m.email),
                      // Owners change anyone but themselves (no lock-out).
                      options: who.canManageStaff && m.uid != who.uid && m.email != null
                          ? const ['edit', 'remove']
                          : const [],
                      labelOf: (o) => o == 'edit' ? 'Change role…' : 'Remove from staff…',
                      onSelected: (o) => o == 'edit' ? _edit(who, member: m) : _remove(who, m),
                    )),
                    DataCell(Text(m.agentName ?? m.agentId ?? '')),
                    DataCell(Text(m.agentReplyMins == null ? (m.agentId == null ? '' : '—') : minutesLabel(m.agentReplyMins!))),
                  ]),
              ],
            ),
          );
        },
      ),
    );
  }
}

typedef _StaffChoice = ({String email, StaffRole role, String? agentId});

/// Email (fixed when changing someone), role, and the agent record for agents.
class _StaffDialog extends StatefulWidget {
  const _StaffDialog({this.member, required this.agents});
  final StaffMember? member;
  final List<AgentOption> agents;

  @override
  State<_StaffDialog> createState() => _StaffDialogState();
}

class _StaffDialogState extends State<_StaffDialog> {
  late final _email = TextEditingController(text: widget.member?.email ?? '');
  late StaffRole _role = widget.member?.role ?? StaffRole.agent;
  late String? _agentId = widget.member?.agentId;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  bool get _valid {
    final e = _email.text.trim();
    return e.contains('@') && e.contains('.') && (_role != StaffRole.agent || _agentId != null);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.member == null ? 'Add someone to staff' : 'Change ${widget.member!.email}'),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (widget.member == null)
              TextField(
                controller: _email,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Their email',
                  helperText: 'They must have signed in to this admin once.',
                ),
                onChanged: (_) => setState(() {}),
              ),
            const SizedBox(height: 16),
            DropdownButtonFormField<StaffRole>(
              initialValue: _role,
              decoration: const InputDecoration(labelText: 'Role'),
              items: [for (final r in StaffRole.values) DropdownMenuItem(value: r, child: Text(label(r.name)))],
              onChanged: (r) => setState(() => _role = r ?? _role),
            ),
            if (_role == StaffRole.agent) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: widget.agents.any((a) => a.id == _agentId) ? _agentId : null,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Acts as agent', helperText: 'Sees only this agent\'s leads and listings.'),
                items: [for (final a in widget.agents) DropdownMenuItem(value: a.id, child: Text(a.name))],
                onChanged: (id) => setState(() => _agentId = id),
              ),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: _valid
                ? () => Navigator.pop<_StaffChoice>(context, (
                      email: _email.text.trim().toLowerCase(),
                      role: _role,
                      agentId: _role == StaffRole.agent ? _agentId : null,
                    ))
                : null,
            child: const Text('Save'),
          ),
        ],
      );
}

/// Data subject requests (DPA 2019): find what is held about one person by
/// the phone or email they gave, then export it or delete it. The Functions
/// do both, and the audit log records each request without the person's details.
class PrivacyScreen extends ConsumerStatefulWidget {
  const PrivacyScreen({super.key});
  @override
  ConsumerState<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends ConsumerState<PrivacyScreen> {
  final _phone = TextEditingController();
  final _email = TextEditingController();
  bool _busy = false;
  DataRequestResult? _result;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  String? get _phoneValue => _phone.text.trim().isEmpty ? null : normaliseKenyanPhone(_phone.text);
  bool get _phoneInvalid => _phone.text.trim().isNotEmpty && _phoneValue == null;
  String? get _emailValue => _email.text.trim().contains('@') ? _email.text.trim() : null;
  bool get _ready => !_busy && !_phoneInvalid && (_phoneValue != null || _emailValue != null);
  String get _who => [_phoneValue, _emailValue].whereType<String>().join(' / ');

  Future<void> _run(DataRequestKind kind) async {
    if (kind == DataRequestKind.delete) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Delete everything held about $_who?'),
          content: const Text('Their enquiries and viewing requests are deleted for good. This cannot be undone. '
              'Export first if they also asked for a copy.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
          ],
        ),
      );
      if (yes != true || !mounted) return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final r = await ref
          .read(adminActionsProvider)
          .dataRequest(ref.read(staffProvider)!, kind: kind, phone: _phoneValue, email: _emailValue);
      if (mounted) setState(() => _result = r);
    } on AdminActionException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final r = _result;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Privacy requests', style: t.headlineSmall),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Under the Data Protection Act 2019 a person may ask for a copy of what we hold about them, '
            'or for it to be deleted. Find them by the phone or email they gave.',
            style: t.bodyMedium,
          ),
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Phone',
                hintText: '0712 345 678',
                errorText: _phoneInvalid ? 'Enter a Kenyan mobile number' : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              FilledButton(onPressed: _ready ? () => _run(DataRequestKind.export) : null, child: const Text('Export')),
              OutlinedButton(onPressed: _ready ? () => _run(DataRequestKind.delete) : null, child: const Text('Delete…')),
            ]),
          ]),
        ),
        if (_busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text("Couldn't do that: $_error", style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        if (r != null) ...[
          const SizedBox(height: 16),
          Text(
            r.kind == DataRequestKind.delete
                ? 'Deleted ${r.leads} enquiries, ${r.viewings} viewing requests and ${r.reviews} reviews.'
                : r.foundNothing
                    ? 'Nothing is held for $_who.'
                    : 'Found ${r.leads} enquiries, ${r.viewings} viewing requests and ${r.reviews} reviews. Send them this copy.',
            style: t.titleMedium,
          ),
          if (r.exportJson != null && !r.foundNothing) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: r.exportJson!));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied.')));
                  }
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copy'),
              ),
            ),
            Card(child: Padding(padding: const EdgeInsets.all(12), child: SelectableText(r.exportJson!))),
          ],
        ],
      ],
    );
  }
}

/// Paste a sheet saved as CSV, check it, then import its rows as pending
/// listings (P5-s02). Pops with how many listings were made.
class _ImportDialog extends ConsumerStatefulWidget {
  const _ImportDialog();
  @override
  ConsumerState<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends ConsumerState<_ImportDialog> {
  final _text = TextEditingController();
  ListingCsv? _checked;
  bool _busy = false;
  int _made = 0;
  List<({int line, String problem})> _refused = const [];
  bool _done = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final csv = _checked!;
    setState(() => _busy = true);
    final refused = <({int line, String problem})>[];
    var made = 0;
    try {
      for (var i = 0; i < csv.rows.length; i += importChunk) {
        final chunk = csv.rows.skip(i).take(importChunk).toList();
        final r = await ref.read(adminActionsProvider).importListings(ref.read(staffProvider)!, [for (final c in chunk) c.row]);
        made += r.created.length;
        refused.addAll([for (final f in r.failed) (line: chunk[f.row - 1].line, problem: f.error)]);
      }
    } on AdminActionException catch (e) {
      refused.add((line: 0, problem: e.message));
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _done = true;
      _made = made;
      _refused = refused;
    });
  }

  @override
  Widget build(BuildContext context) {
    final csv = _checked;
    final t = Theme.of(context).textTheme;
    final err = TextStyle(color: Theme.of(context).colorScheme.error);
    Widget problems(List<({int line, String problem})> list) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final p in list.take(20)) Text(p.line == 0 ? p.problem : 'Line ${p.line}: ${p.problem}', style: err)],
        );
    return AlertDialog(
      title: const Text('Import listings'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            if (_done) ...[
              Text('Imported $_made listings. They wait in Pending for approval.', style: t.titleMedium),
              if (_refused.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Not imported (${_refused.length}):', style: t.titleSmall),
                problems(_refused),
              ],
            ] else ...[
              Text(
                'Save the sheet as CSV and paste it here. The first line names the columns: '
                '${listingCsvColumns.join(', ')}. Amenities are separated by ";".',
                style: t.bodyMedium,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _text,
                minLines: 6,
                maxLines: 12,
                decoration: const InputDecoration(labelText: 'CSV', border: OutlineInputBorder()),
                onChanged: (_) => setState(() => _checked = null),
              ),
              if (csv != null) ...[
                const SizedBox(height: 8),
                Text('${csv.rows.length} listings ready to import.', style: t.titleSmall),
                if (!csv.ok) ...[
                  Text('These lines will be left out:', style: t.bodyMedium),
                  problems(csv.problems),
                ],
              ],
              if (_busy) const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator())),
            ],
          ]),
        ),
      ),
      actions: _done
          ? [FilledButton(onPressed: () => Navigator.pop(context, _made), child: const Text('Done'))]
          : [
              TextButton(onPressed: _busy ? null : () => Navigator.pop(context, 0), child: const Text('Cancel')),
              if (csv == null)
                FilledButton(
                  onPressed: _text.text.trim().isEmpty ? null : () => setState(() => _checked = ListingCsv.parse(_text.text)),
                  child: const Text('Check'),
                )
              else
                FilledButton(
                  onPressed: _busy || csv.rows.isEmpty ? null : _import,
                  child: Text('Import ${csv.rows.length}'),
                ),
            ],
    );
  }
}


/// Picks a new day and time for a viewing, from the slots clients can book.
class _RescheduleDialog extends StatefulWidget {
  const _RescheduleDialog({required this.from});
  final DateTime from;
  @override
  State<_RescheduleDialog> createState() => _RescheduleDialogState();
}

class _RescheduleDialogState extends State<_RescheduleDialog> {
  final _days = viewingDays(DateTime.now());
  String? _day, _time;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Reschedule viewing'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Now ${shortDateTime(widget.from)}. Pick the time agreed with the client; it is saved as confirmed.'),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Day', border: OutlineInputBorder()),
              items: [for (final d in _days) DropdownMenuItem(value: d.value, child: Text(d.label))],
              onChanged: (v) => setState(() => _day = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Time', border: OutlineInputBorder()),
              items: [for (final t in viewingTimes) DropdownMenuItem(value: t, child: Text(t))],
              onChanged: (v) => setState(() => _time = v),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: _day == null || _time == null ? null : () => Navigator.pop(context, viewingSlot(_day!, _time!)),
            child: const Text('Move viewing'),
          ),
        ],
      );
}

/// Time an agent blocks out (P5-s05): no viewing can be booked or moved
/// into it. Agents manage their own; managers anyone's.
class _TimeOffDialog extends ConsumerStatefulWidget {
  const _TimeOffDialog();
  @override
  ConsumerState<_TimeOffDialog> createState() => _TimeOffDialogState();
}

class _TimeOffDialogState extends ConsumerState<_TimeOffDialog> {
  final _days = viewingDays(DateTime.now(), count: 26);
  final _note = TextEditingController();
  List<AgentBlock>? _blocks;
  List<AgentOption> _agents = const [];
  String? _agent, _fromDay, _toDay, _error;
  String _fromTime = '08:00', _toTime = '18:00';
  bool _busy = false;

  /// Start times, plus 18:00 to end at the close of the viewing day.
  static final _ends = [...viewingTimes.skip(1), '18:00'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final who = ref.read(staffProvider)!;
    final repo = ref.read(adminRepositoryProvider);
    final (blocks, agents) = await (repo.timeOff(who, DateTime.now()), who.isManager ? repo.agents(who) : Future.value(const <AgentOption>[])).wait;
    if (mounted) {
      setState(() {
        _blocks = blocks;
        _agents = agents;
      });
    }
  }

  Future<void> _run(Future<void> Function() change) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await change();
      await _load();
    } on AdminActionException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() {
    final who = ref.read(staffProvider)!;
    return _run(() async {
      await ref.read(adminActionsProvider).addTimeOff(who,
          agentId: who.isManager ? _agent : null,
          start: viewingSlot(_fromDay!, _fromTime),
          end: viewingSlot(_toDay ?? _fromDay!, _toTime),
          note: _note.text);
      _note.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final who = ref.watch(staffProvider)!;
    final blocks = _blocks;
    final t = Theme.of(context).textTheme;
    DropdownButtonFormField<String> pick(String label, String? value, List<(String, String)> options, ValueChanged<String?> onChanged) =>
        DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
          items: [for (final (v, l) in options) DropdownMenuItem(value: v, child: Text(l))],
          onChanged: _busy ? null : onChanged,
        );
    final dayOptions = [for (final d in _days) (d.value, d.label)];
    final ready = _fromDay != null && (!who.isManager || _agent != null);
    return AlertDialog(
      title: const Text('Time off'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text('Clients cannot book a viewing in these times, and viewings cannot be moved into them.', style: t.bodyMedium),
            const SizedBox(height: 8),
            if (blocks == null)
              const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()))
            else if (blocks.isEmpty)
              Text('None coming up.', style: t.bodySmall)
            else
              for (final b in blocks)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${shortDateTime(b.start)} to ${shortDateTime(b.end)}'),
                  subtitle: Text([if (who.isManager) b.agentName, if (b.note != null) b.note!].join(' · ')),
                  trailing: IconButton(
                    tooltip: 'Remove this time off',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: _busy ? null : () => _run(() => ref.read(adminActionsProvider).removeTimeOff(who, blockId: b.id)),
                  ),
                ),
            const Divider(height: 24),
            Text('Add time off', style: t.titleSmall),
            const SizedBox(height: 8),
            if (who.isManager) ...[
              pick('Agent', _agent, [for (final a in _agents) (a.id, a.name)], (v) => setState(() => _agent = v)),
              const SizedBox(height: 8),
            ],
            Row(children: [
              Expanded(child: pick('From', _fromDay, dayOptions, (v) => setState(() => _fromDay = v))),
              const SizedBox(width: 8),
              SizedBox(width: 140, child: pick('At', _fromTime, [for (final x in viewingTimes) (x, x)], (v) => setState(() => _fromTime = v!))),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: pick('To (same day if empty)', _toDay, dayOptions, (v) => setState(() => _toDay = v))),
              const SizedBox(width: 8),
              SizedBox(width: 140, child: pick('Until', _toTime, [for (final x in _ends) (x, x)], (v) => setState(() => _toTime = v!))),
            ]),
            const SizedBox(height: 8),
            TextField(
              controller: _note,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'Note for the team (optional)', border: OutlineInputBorder(), isDense: true),
            ),
            if (_error != null) Text("Couldn't save: $_error", style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        FilledButton(onPressed: _busy || !ready ? null : _add, child: const Text('Add time off')),
      ],
    );
  }
}
