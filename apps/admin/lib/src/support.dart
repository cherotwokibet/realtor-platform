import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';

import 'format.dart';
import 'links.dart';
import 'providers.dart';

/// Support and feedback (managers): what people sent from the site's Help &
/// feedback form, newest first; new, open or resolved; each with the
/// person's details to reply, and notes on what was done.
class SupportScreen extends ConsumerStatefulWidget {
  const SupportScreen({super.key});

  @override
  ConsumerState<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends ConsumerState<SupportScreen> {
  String? _status = 'new';
  late Future<List<FeedbackRow>> _rows = _load();

  Future<List<FeedbackRow>> _load() => ref.read(adminRepositoryProvider).feedback(ref.read(staffProvider)!);

  Future<void> _open(FeedbackRow f) async {
    final changed = await showDialog<bool>(context: context, builder: (_) => _MessageDialog(message: f));
    if (changed == true && mounted) {
      setState(() {
        _rows = _load();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return FutureBuilder<List<FeedbackRow>>(
      future: _rows,
      builder: (context, snap) {
        final all = snap.data;
        final shown = [
          for (final f in all ?? const <FeedbackRow>[])
            if (_status == null || f.status == _status) f
        ];
        int count(String s) => (all ?? const <FeedbackRow>[]).where((f) => f.status == s).length;
        return ListView(padding: const EdgeInsets.all(24), children: [
          Text('Support', style: t.headlineSmall),
          const SizedBox(height: 4),
          Text('Questions, problems, feedback and complaints sent from the site\'s Help & feedback.', style: t.bodyMedium?.copyWith(color: b.textMuted)),
          const SizedBox(height: 16),
          Wrap(spacing: 8, children: [
            for (final s in <String?>[...feedbackStatuses, null])
              ChoiceChip(
                key: Key('support-${s ?? 'all'}'),
                label: Text(s == null ? 'All' : '${label(s)} · ${count(s)}'),
                selected: _status == s,
                showCheckmark: false,
                onSelected: (_) => setState(() => _status = s),
              ),
          ]),
          const SizedBox(height: 12),
          if (snap.hasError) Text("Couldn't load: ${snap.error}", style: TextStyle(color: scheme.error)),
          if (all == null && !snap.hasError) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          if (all != null && shown.isEmpty)
            Padding(padding: const EdgeInsets.all(32), child: Center(child: Text('Nothing here.', style: t.bodyMedium?.copyWith(color: b.textMuted)))),
          if (shown.isNotEmpty)
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                for (final f in shown)
                  ListTile(
                    key: Key('message-${f.id}'),
                    leading: CircleAvatar(
                      backgroundColor: f.kind == 'complaint' || f.kind == 'problem' ? scheme.error.withValues(alpha: 0.12) : b.primarySoft,
                      child: Icon(
                        switch (f.kind) {
                          'question' => Icons.help_outline,
                          'problem' => Icons.bug_report_outlined,
                          'complaint' => Icons.report_outlined,
                          _ => Icons.chat_bubble_outline
                        },
                        color: f.kind == 'complaint' || f.kind == 'problem' ? scheme.error : scheme.primary,
                      ),
                    ),
                    title: Text(f.message, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text([
                      label(f.kind),
                      f.name ?? f.phone ?? f.email ?? 'No name',
                      shortDateTime(f.createdAt),
                      if (f.notes.isNotEmpty) '${f.notes.length} notes'
                    ].join(' · ')),
                    trailing: Text(label(f.status), style: t.labelLarge?.copyWith(color: f.status == 'new' ? scheme.primary : b.textMuted)),
                    onTap: () => _open(f),
                  ),
              ]),
            ),
        ]);
      },
    );
  }
}

class _MessageDialog extends ConsumerStatefulWidget {
  const _MessageDialog({required this.message});
  final FeedbackRow message;

  @override
  ConsumerState<_MessageDialog> createState() => _MessageDialogState();
}

class _MessageDialogState extends ConsumerState<_MessageDialog> {
  final _note = TextEditingController();
  late String _status = widget.message.status;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final f = widget.message;
    if (_status == f.status && _note.text.trim().isEmpty) return Navigator.pop(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(adminActionsProvider).updateFeedback(ref.read(staffProvider)!,
          feedbackId: f.id, status: _status == f.status ? null : _status, note: _note.text.trim().isEmpty ? null : _note.text.trim());
      if (mounted) Navigator.pop(context, true);
    } on AdminActionException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.message;
    final b = context.brand;
    final t = Theme.of(context).textTheme;
    final opener = ref.read(linkOpenerProvider);
    void open(Uri u) => opener.open(u);
    final tenant = ref.watch(tenantProvider);
    return AlertDialog(
      title: Text('${label(f.kind)} · ${shortDateTime(f.createdAt)}'),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            SelectableText(f.message, style: t.bodyLarge),
            const SizedBox(height: 12),
            Text(
              [f.name ?? 'No name', if (f.page != null) 'sent from ${f.page}'].join(' · '),
              style: t.bodySmall?.copyWith(color: b.textMuted),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (f.phone != null) ...[
                OutlinedButton.icon(
                    onPressed: () => open(Uri(scheme: 'tel', path: f.phone)), icon: const Icon(Icons.call_outlined, size: 18), label: Text(f.phone!)),
                OutlinedButton.icon(
                  onPressed: () => open(Uri.https('wa.me', '/${f.phone!.replaceAll('+', '')}',
                      {'text': 'Hello${f.name == null ? '' : ' ${f.name}'}, this is ${tenant.name} about your message.'})),
                  icon: const Icon(Icons.chat_outlined, size: 18),
                  label: const Text('WhatsApp'),
                ),
              ],
              if (f.email != null)
                OutlinedButton.icon(
                  onPressed: () => open(Uri(scheme: 'mailto', path: f.email, queryParameters: {'subject': 'Your message to ${tenant.name}'})),
                  icon: const Icon(Icons.mail_outline, size: 18),
                  label: Text(f.email!),
                ),
              if (f.phone == null && f.email == null) Text('They left no way to reply.', style: t.bodySmall),
            ]),
            if (f.notes.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Notes', style: t.labelLarge),
              for (final n in f.notes)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('${shortDateTime(n.at)}${n.by == null ? '' : ' · ${n.by}'}: ${n.text}', style: t.bodyMedium),
                ),
            ],
            const SizedBox(height: 16),
            Text('Status', style: t.labelLarge),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              key: const Key('message-status'),
              segments: [for (final s in feedbackStatuses) ButtonSegment(value: s, label: Text(label(s)))],
              selected: {_status},
              onSelectionChanged: (s) => setState(() => _status = s.first),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('message-note'),
              controller: _note,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Add a note (what you did, what you replied)', border: OutlineInputBorder()),
            ),
            if (_error != null)
              Padding(
                  padding: const EdgeInsets.only(top: 8), child: Text("Couldn't save: $_error", style: TextStyle(color: Theme.of(context).colorScheme.error))),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Close')),
        FilledButton(key: const Key('message-save'), onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving…' : 'Save')),
      ],
    );
  }
}
