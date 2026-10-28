import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_core/realtor_core.dart';

import 'format.dart';
import 'paged_table.dart';
import 'providers.dart';

/// Heading, optional filters and a table, in a scrollable page.
class _TablePage extends StatelessWidget {
  const _TablePage({required this.title, this.subtitle, this.filters, required this.table});
  final String title;
  final String? subtitle;
  final Widget? filters;
  final Widget table;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(title, style: t.headlineSmall),
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
          TableColumn('Received', (r) => Text(shortDateTime(r.createdAt))),
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
    final to = action == 'confirm' ? 'live' : moderationTargets[action]!;
    setState(() => _saving[r.id] = to);
    final actions = ref.read(adminActionsProvider);
    final ok = await _act(
      context,
      () => action == 'confirm'
          ? actions.confirmListing(who, listingId: r.id)
          : actions.moderateListing(who, listingId: r.id, action: action, reason: reason),
      action == 'confirm' ? '${r.title}: confirmed, verified for 30 days' : '${r.title}: ${label(to)}',
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
      title: 'Listings',
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
          TableColumn('Title', (r) => Text(r.title)),
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
                options: listingActionsFor(who, status: status, agentId: r.agentId),
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
