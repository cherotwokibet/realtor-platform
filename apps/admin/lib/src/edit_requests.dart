import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';

import 'format.dart';
import 'providers.dart';

/// Property edit requests: an agent's changes to a live listing wait here for
/// a manager, while the listing stays live as it was. Managers see what is
/// waiting and approve or reject each; agents see their own and what became
/// of them (with the reason when rejected).
class EditRequestsScreen extends ConsumerStatefulWidget {
  const EditRequestsScreen({super.key});

  @override
  ConsumerState<EditRequestsScreen> createState() => _EditRequestsScreenState();
}

class _EditRequestsScreenState extends ConsumerState<EditRequestsScreen> {
  late Future<List<EditRequestRow>> _edits = _load();
  Map<String, String> _areas = const {}, _agents = const {};

  Future<List<EditRequestRow>> _load() async {
    final who = ref.read(staffProvider)!, repo = ref.read(adminRepositoryProvider);
    final (edits, areas, agents) = await (
      repo.editRequests(who),
      repo.areas(),
      who.isManager ? repo.agents(who) : Future.value(const <AgentOption>[]),
    ).wait;
    _areas = {for (final a in areas) a.slug: a.name};
    _agents = {for (final a in agents) a.id: a.name};
    return edits;
  }

  Future<void> _review(EditRequestRow e) async {
    final done = await showDialog<bool>(context: context, builder: (_) => _ReviewDialog(edit: e, areaNames: _areas, agentNames: _agents));
    if (done == true && mounted) {
      setState(() {
        _edits = _load();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final who = ref.watch(staffProvider)!;
    final b = context.brand;
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return FutureBuilder<List<EditRequestRow>>(
      future: _edits,
      builder: (context, snap) {
        final edits = snap.data;
        return ListView(padding: const EdgeInsets.all(24), children: [
          Text('Edit requests', style: t.headlineSmall),
          const SizedBox(height: 4),
          Text(
            who.isManager
                ? 'Agents\' changes to live listings. The listing stays live as it is until you approve.'
                : 'Your changes to live listings. The listing stays live as it is until a manager approves.',
            style: t.bodyMedium?.copyWith(color: b.textMuted),
          ),
          const SizedBox(height: 16),
          if (snap.hasError) Text("Couldn't load: ${snap.error}", style: TextStyle(color: scheme.error)),
          if (edits == null && !snap.hasError) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          if (edits != null && edits.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(children: [
                Icon(Icons.task_alt, size: 36, color: b.textMuted),
                const SizedBox(height: 8),
                Text(who.isManager ? 'No edits waiting.' : 'No edits yet.', style: t.bodyMedium?.copyWith(color: b.textMuted)),
              ]),
            ),
          if (edits != null && edits.isNotEmpty)
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                for (final e in edits)
                  ListTile(
                    key: Key('edit-${e.listingId}'),
                    leading: CircleAvatar(
                      backgroundColor: switch (e.status) {
                        'approved' => b.success.withValues(alpha: 0.15),
                        'rejected' => scheme.errorContainer,
                        _ => b.primarySoft
                      },
                      child: Icon(
                        switch (e.status) { 'approved' => Icons.check, 'rejected' => Icons.close, _ => Icons.edit_note },
                        color: switch (e.status) { 'approved' => b.success, 'rejected' => scheme.error, _ => scheme.primary },
                      ),
                    ),
                    title: Text(e.title),
                    subtitle: Text([
                      if (who.isManager) e.agentName,
                      'sent ${shortDateTime(e.submittedAt)}',
                      '${e.changed.isEmpty ? editChanges(e.current ?? e.proposed, e.proposed).length : e.changed.length} changes',
                      if (e.status != 'pending') label(e.status),
                      if (e.reason != null) '"${e.reason}"',
                    ].join(' · ')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _review(e),
                  ),
              ]),
            ),
        ]);
      },
    );
  }
}

/// The changes, field by field (now → proposed), and Approve / Reject for managers.
class _ReviewDialog extends ConsumerStatefulWidget {
  const _ReviewDialog({required this.edit, required this.areaNames, required this.agentNames});
  final EditRequestRow edit;
  final Map<String, String> areaNames, agentNames;

  @override
  ConsumerState<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends ConsumerState<_ReviewDialog> {
  final _reason = TextEditingController();
  bool _busy = false, _rejecting = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _decide(bool approve) async {
    if (!approve && _reason.text.trim().isEmpty) return setState(() => _error = 'Say why, so the agent can fix it.');
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(adminActionsProvider)
          .moderateEdit(ref.read(staffProvider)!, listingId: widget.edit.listingId, approve: approve, reason: approve ? null : _reason.text.trim());
      messenger.showSnackBar(SnackBar(content: Text(approve ? '${widget.edit.title}: changes applied' : '${widget.edit.title}: edit rejected')));
      if (mounted) Navigator.pop(context, true);
    } on AdminActionException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final who = ref.watch(staffProvider)!;
    final e = widget.edit;
    final b = context.brand;
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final rows = e.current == null
        ? const <(String, String, String)>[]
        : editChanges(e.current!, e.proposed, areaNames: widget.areaNames, agentNames: widget.agentNames);
    final pending = e.status == 'pending';
    return AlertDialog(
      title: Text('Changes to ${e.title}'),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text('${e.agentName} · sent ${shortDateTime(e.submittedAt)}${pending ? '' : ' · ${label(e.status)}'}',
                style: t.bodySmall?.copyWith(color: b.textMuted)),
            if (e.reason != null)
              Padding(padding: const EdgeInsets.only(top: 8), child: Text('Why it was rejected: ${e.reason}', style: TextStyle(color: scheme.error))),
            const SizedBox(height: 12),
            if (e.current == null) const Text('The listing has gone, so there is nothing to compare.'),
            if (e.current != null && rows.isEmpty) const Text('No changes to the facts (perhaps the photos were reordered).'),
            if (rows.isNotEmpty)
              Table(
                columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth(), 2: FlexColumnWidth()},
                defaultVerticalAlignment: TableCellVerticalAlignment.top,
                border: TableBorder(horizontalInside: BorderSide(color: scheme.outlineVariant)),
                children: [
                  TableRow(children: [
                    for (final h in ['', 'Now', 'Proposed'])
                      Padding(padding: const EdgeInsets.all(8), child: Text(h, style: t.labelLarge?.copyWith(color: b.textMuted))),
                  ]),
                  for (final (field, now, next) in rows)
                    TableRow(children: [
                      Padding(padding: const EdgeInsets.all(8), child: Text(field, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(now.isEmpty ? '—' : now, style: t.bodyMedium?.copyWith(color: b.textMuted, decoration: TextDecoration.lineThrough)),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: b.primarySoft, borderRadius: BorderRadius.circular(b.radiusSm)),
                          child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), child: Text(next.isEmpty ? '—' : next, style: t.bodyMedium)),
                        ),
                      ),
                    ]),
                ],
              ),
            if (who.isManager && pending && _rejecting) ...[
              const SizedBox(height: 16),
              TextField(
                key: const Key('edit-reason'),
                controller: _reason,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Why (the agent sees this)', border: OutlineInputBorder()),
              ),
            ],
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: scheme.error))),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Close')),
        if (who.isManager && pending) ...[
          OutlinedButton(
            key: const Key('edit-reject'),
            onPressed: _busy ? null : () => _rejecting ? _decide(false) : setState(() => _rejecting = true),
            child: Text(_rejecting ? 'Reject with this reason' : 'Reject…'),
          ),
          FilledButton(key: const Key('edit-approve'), onPressed: _busy ? null : () => _decide(true), child: const Text('Approve and apply')),
        ],
      ],
    );
  }
}
