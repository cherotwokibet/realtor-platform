import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';

import 'format.dart';
import 'links.dart';
import 'providers.dart';

/// One lead, to follow it up: who and what, call or WhatsApp them, the notes
/// on what was done, and when to get in touch next (quick picks or a day and
/// time). Pops true when something was saved.
class LeadDialog extends ConsumerStatefulWidget {
  const LeadDialog({super.key, required this.lead, this.now});
  final LeadRow lead;

  /// The time the quick picks count from; tests pin it.
  final DateTime? now;

  @override
  ConsumerState<LeadDialog> createState() => _LeadDialogState();
}

class _LeadDialogState extends ConsumerState<LeadDialog> {
  final _note = TextEditingController();
  late DateTime? _followUp = widget.lead.followUpAt;
  bool _busy = false;
  String? _error;

  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  bool get _changed => _note.text.trim().isNotEmpty || _followUp != widget.lead.followUpAt;

  Future<void> _save() async {
    if (!_changed) return Navigator.pop(context, false);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(adminActionsProvider).followUpLead(
            ref.read(staffProvider)!,
            leadId: widget.lead.id,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
            followUpAt: _followUp != widget.lead.followUpAt ? _followUp : null,
            clearFollowUp: _followUp == null && widget.lead.followUpAt != null,
          );
      if (mounted) Navigator.pop(context, true);
    } on AdminActionException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick() async {
    final start = _followUp ?? _now.add(const Duration(days: 1));
    final day = await showDatePicker(
        context: context, initialDate: start, firstDate: DateTime(_now.year, _now.month, _now.day), lastDate: _now.add(const Duration(days: 365)));
    if (day == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(start));
    if (time == null) return;
    setState(() => _followUp = DateTime(day.year, day.month, day.day, time.hour, time.minute));
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.lead;
    final b = context.brand;
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final opener = ref.read(linkOpenerProvider);
    final tenant = ref.watch(tenantProvider);
    final today = DateTime(_now.year, _now.month, _now.day);
    final picks = <(String, DateTime)>[
      if (_now.hour < 16) ('This afternoon', today.add(const Duration(hours: 17))),
      ('Tomorrow 9:00', today.add(const Duration(days: 1, hours: 9))),
      ('In 3 days', today.add(const Duration(days: 3, hours: 9))),
      ('Next week', today.add(const Duration(days: 7, hours: 9))),
    ];
    final due = _followUp != null && !_followUp!.isAfter(_now);
    return AlertDialog(
      title: Text(l.contactName ?? l.contactPhone ?? 'Lead'),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text(
              [l.listingTitle, label(l.channel), label(l.stage), 'received ${shortDateTime(l.createdAt)}'].join(' · '),
              style: t.bodySmall?.copyWith(color: b.textMuted),
            ),
            const SizedBox(height: 12),
            if (l.contactPhone != null)
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                  onPressed: () => opener.open(Uri(scheme: 'tel', path: l.contactPhone)),
                  icon: const Icon(Icons.call_outlined, size: 18),
                  label: Text(l.contactPhone!),
                ),
                OutlinedButton.icon(
                  onPressed: () => opener.open(Uri.https('wa.me', '/${l.contactPhone!.replaceAll('+', '')}', {
                    'text': 'Hello${l.contactName == null ? '' : ' ${l.contactName!.split(' ').first}'}, this is ${tenant.name} about ${l.listingTitle}.',
                  })),
                  icon: const Icon(Icons.chat_outlined, size: 18),
                  label: const Text('WhatsApp'),
                ),
              ]),
            const SizedBox(height: 16),
            Text('Notes', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            if (l.notes.isEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('None yet.', style: t.bodySmall?.copyWith(color: b.textMuted))),
            for (final n in l.notes)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.sticky_note_2_outlined, size: 16, color: b.textMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: n.text),
                      TextSpan(text: '  ${shortDateTime(n.at)}${n.by == null ? '' : ' · ${n.by}'}', style: t.bodySmall?.copyWith(color: b.textMuted)),
                    ])),
                  ),
                ]),
              ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('lead-note'),
              controller: _note,
              minLines: 2,
              maxLines: 4,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Add a note: what you did or agreed', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            Text('Follow up', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Row(children: [
              Icon(due ? Icons.alarm : Icons.event_outlined, size: 18, color: due ? scheme.error : scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _followUp == null ? 'Nothing planned' : '${due ? 'Due ' : ''}${shortDateTime(_followUp!)}',
                  key: const Key('lead-followup'),
                  style: t.bodyMedium?.copyWith(color: due ? scheme.error : null, fontWeight: FontWeight.w600),
                ),
              ),
              if (_followUp != null) TextButton(onPressed: () => setState(() => _followUp = null), child: const Text('Clear')),
            ]),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (name, at) in picks)
                ChoiceChip(
                    key: Key('lead-pick-$name'),
                    label: Text(name),
                    selected: _followUp == at,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _followUp = at)),
              ActionChip(avatar: const Icon(Icons.edit_calendar_outlined, size: 18), label: const Text('Pick a day and time'), onPressed: _pick),
            ]),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text("Couldn't save: $_error", style: TextStyle(color: scheme.error))),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Close')),
        FilledButton(key: const Key('lead-save'), onPressed: _busy || !_changed ? null : _save, child: Text(_busy ? 'Saving…' : 'Save')),
      ],
    );
  }
}
