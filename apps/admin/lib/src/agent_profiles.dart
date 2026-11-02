import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_core/realtor_core.dart';

import 'format.dart';
import 'listing_media.dart';
import 'providers.dart';

/// Managers' list of agent profiles (P5-s04): what each public agent page
/// shows. Add or edit one; an inactive agent's page is taken down.
class AgentProfilesDialog extends ConsumerStatefulWidget {
  const AgentProfilesDialog({super.key});
  @override
  ConsumerState<AgentProfilesDialog> createState() => _AgentProfilesDialogState();
}

class _AgentProfilesDialogState extends ConsumerState<AgentProfilesDialog> {
  List<AgentProfile>? _agents;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await ref.read(adminRepositoryProvider).agentProfiles(ref.read(staffProvider)!);
    if (mounted) setState(() => _agents = list);
  }

  Future<void> _edit(AgentProfile? p) async {
    final saved = await showDialog<String>(context: context, builder: (_) => AgentEditorDialog(profile: p));
    if (saved != null) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final agents = _agents;
    return AlertDialog(
      title: const Text('Agent profiles'),
      content: SizedBox(
        width: 560,
        child: agents == null
            ? const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  for (final a in agents)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(a.active ? Icons.badge_outlined : Icons.person_off_outlined),
                      title: Text(a.active ? a.name : '${a.name} (inactive)'),
                      subtitle: Text([
                        'EARB ${a.earbNo}',
                        a.languages.map((l) => agentLanguages[l] ?? l).join(', '),
                        if (a.responseMins != null) 'replies in ${minutesLabel(a.responseMins!)}',
                        if (a.photo == null) 'no photo',
                      ].join(' · ')),
                      trailing: IconButton(tooltip: 'Edit ${a.name}', icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(a)),
                    ),
                ]),
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        FilledButton.icon(onPressed: () => _edit(null), icon: const Icon(Icons.person_add_alt), label: const Text('Add agent')),
      ],
    );
  }
}

/// One agent's profile. Saving goes through `saveAgent`; the photo through
/// the media pipeline, so it shows on the page a moment later.
class AgentEditorDialog extends ConsumerStatefulWidget {
  const AgentEditorDialog({super.key, this.profile});
  final AgentProfile? profile;
  @override
  ConsumerState<AgentEditorDialog> createState() => _AgentEditorDialogState();
}

class _AgentEditorDialogState extends ConsumerState<AgentEditorDialog> {
  late final AgentProfile _p = widget.profile ?? const AgentProfile();
  late final _name = TextEditingController(text: _p.name),
      _earb = TextEditingController(text: _p.earbNo),
      _phone = TextEditingController(text: _p.phone),
      _whatsapp = TextEditingController(text: _p.whatsapp);
  late final _languages = {..._p.languages};
  late bool _active = _p.active;
  bool _tried = false, _busy = false;
  String? _error, _photoStatus;

  @override
  void dispose() {
    for (final c in [_name, _earb, _phone, _whatsapp]) {
      c.dispose();
    }
    super.dispose();
  }

  AgentProfile get _current => AgentProfile(
        id: _p.id,
        name: _name.text,
        earbNo: _earb.text,
        phone: _phone.text,
        whatsapp: _whatsapp.text.trim().isEmpty ? _phone.text : _whatsapp.text,
        languages: [for (final l in agentLanguages.keys) if (_languages.contains(l)) l],
        active: _active,
      );

  Future<void> _save() async {
    final p = _current;
    setState(() {
      _tried = true;
      _error = null;
    });
    if (p.problems().isNotEmpty) return;
    setState(() => _busy = true);
    try {
      final id = await ref.read(adminActionsProvider).saveAgent(ref.read(staffProvider)!, p);
      if (mounted) Navigator.pop(context, id);
    } on AdminActionException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _photo() async {
    final files = await ref.read(filePickerProvider).pick(accept: photoTypes.join(','));
    if (files.isEmpty || !mounted) return;
    setState(() => _photoStatus = 'Uploading…');
    try {
      await ref.read(listingMediaProvider).uploadAgentPhoto(ref.read(staffProvider)!, _p.id!, files.first);
      if (mounted) setState(() => _photoStatus = 'Uploaded. It shows on the agent page in a minute.');
    } on Object catch (e) {
      if (mounted) setState(() => _photoStatus = 'Could not upload: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final problems = _tried ? _current.problems() : const <String, String>{};
    TextField field(TextEditingController c, String label, String key, {String? hint}) => TextField(
          controller: c,
          decoration: InputDecoration(labelText: label, hintText: hint, errorText: problems[key], border: const OutlineInputBorder()),
          onChanged: (_) => _tried ? setState(() {}) : null,
        );
    final media = ref.watch(listingMediaProvider);
    final photoUrl = _p.photo == null ? null : media.url(_p.photo!);
    return AlertDialog(
      title: Text(_p.id == null ? 'Add agent' : 'Edit ${_p.name}'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 4),
            field(_name, 'Name', 'name'),
            const SizedBox(height: 12),
            field(_earb, 'EARB registration number', 'earbNo'),
            const SizedBox(height: 12),
            field(_phone, 'Phone', 'phone', hint: '0712 345 678'),
            const SizedBox(height: 12),
            field(_whatsapp, 'WhatsApp (same as phone if empty)', 'whatsapp'),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              for (final e in agentLanguages.entries)
                FilterChip(
                  label: Text(e.value),
                  selected: _languages.contains(e.key),
                  onSelected: (on) => setState(() => on ? _languages.add(e.key) : _languages.remove(e.key)),
                ),
            ]),
            if (problems['languages'] != null)
              Text(problems['languages']!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active'),
              subtitle: const Text('Off takes the public agent page down.'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
            if (_p.id == null)
              Text('Save first, then open the agent again to add a photo.', style: Theme.of(context).textTheme.bodySmall)
            else
              Row(children: [
                if (photoUrl != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: ClipOval(child: Image.network(photoUrl, width: 48, height: 48, fit: BoxFit.cover)),
                  ),
                Expanded(child: Text(_photoStatus ?? (_p.photo == null ? 'No photo yet.' : 'Photo set.'))),
                OutlinedButton.icon(onPressed: _photo, icon: const Icon(Icons.add_a_photo_outlined), label: const Text('Upload photo')),
              ]),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text("Couldn't save: $_error", style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving…' : 'Save')),
      ],
    );
  }
}
