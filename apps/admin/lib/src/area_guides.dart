import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_core/realtor_core.dart';

import 'providers.dart';

/// Managers' list of area guides (P3-s05): what each `/area/<slug>` page and
/// the listing form's area picker show.
class AreaGuidesDialog extends ConsumerStatefulWidget {
  const AreaGuidesDialog({super.key});
  @override
  ConsumerState<AreaGuidesDialog> createState() => _AreaGuidesDialogState();
}

class _AreaGuidesDialogState extends ConsumerState<AreaGuidesDialog> {
  List<AreaGuide>? _areas;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await ref.read(adminRepositoryProvider).areaGuides();
    if (mounted) setState(() => _areas = list);
  }

  Future<void> _edit(AreaGuide? a) async {
    final saved = await showDialog<String>(context: context, builder: (_) => AreaEditorDialog(area: a));
    if (saved != null) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final areas = _areas;
    return AlertDialog(
      title: const Text('Areas'),
      content: SizedBox(
        width: 560,
        child: areas == null
            ? const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  for (final a in areas)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(a.name),
                      subtitle: Text([
                        a.county,
                        '${a.listings} live',
                        if (a.medianRentKES != null) 'typical rent ${formatKes(a.medianRentKES!)}',
                        if (a.guide.isEmpty) 'no guide yet',
                      ].join(' · ')),
                      trailing: IconButton(tooltip: 'Edit ${a.name}', icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(a)),
                    ),
                ]),
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        FilledButton.icon(onPressed: () => _edit(null), icon: const Icon(Icons.add_location_alt_outlined), label: const Text('Add area')),
      ],
    );
  }
}

/// One area's guide. Typical rent and live listings update every night.
class AreaEditorDialog extends ConsumerStatefulWidget {
  const AreaEditorDialog({super.key, this.area});
  final AreaGuide? area;
  @override
  ConsumerState<AreaEditorDialog> createState() => _AreaEditorDialogState();
}

class _AreaEditorDialogState extends ConsumerState<AreaEditorDialog> {
  late final AreaGuide _a = widget.area ?? const AreaGuide(county: 'Nairobi');
  late final _name = TextEditingController(text: _a.name),
      _county = TextEditingController(text: _a.county),
      _lat = TextEditingController(text: _a.lat == 0 ? '' : '${_a.lat}'),
      _lng = TextEditingController(text: _a.lng == 0 ? '' : '${_a.lng}'),
      _guide = TextEditingController(text: _a.guide),
      _amenities = TextEditingController(text: _a.amenities.join(', '));
  bool _tried = false, _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _county, _lat, _lng, _guide, _amenities]) {
      c.dispose();
    }
    super.dispose();
  }

  AreaGuide get _current => AreaGuide(
        slug: _a.slug,
        name: _name.text,
        county: _county.text,
        lat: double.tryParse(_lat.text.trim()) ?? 0,
        lng: double.tryParse(_lng.text.trim()) ?? 0,
        guide: _guide.text,
        amenities: [for (final x in _amenities.text.split(',')) if (x.trim().isNotEmpty) x.trim()],
      );

  Future<void> _save() async {
    final a = _current;
    setState(() {
      _tried = true;
      _error = null;
    });
    if (a.problems().isNotEmpty) return;
    setState(() => _busy = true);
    try {
      final slug = await ref.read(adminActionsProvider).saveArea(ref.read(staffProvider)!, a);
      if (mounted) Navigator.pop(context, slug);
    } on AdminActionException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final problems = _tried ? _current.problems() : const <String, String>{};
    TextField field(TextEditingController c, String label, String key, {int lines = 1, String? hint}) => TextField(
          controller: c,
          minLines: lines,
          maxLines: lines == 1 ? 1 : lines * 2,
          decoration: InputDecoration(labelText: label, hintText: hint, errorText: problems[key], border: const OutlineInputBorder()),
          onChanged: (_) => _tried ? setState(() {}) : null,
        );
    return AlertDialog(
      title: Text(_a.slug == null ? 'Add area' : 'Edit ${_a.name}'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 4),
            field(_name, 'Name', 'name', hint: 'Kilimani'),
            const SizedBox(height: 12),
            field(_county, 'County', 'county'),
            const SizedBox(height: 12),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: field(_lat, 'Centre latitude', 'location', hint: '-1.2921')),
              const SizedBox(width: 12),
              Expanded(child: field(_lng, 'Centre longitude', 'location', hint: '36.7856')),
            ]),
            const SizedBox(height: 12),
            field(_guide, 'Guide: what living there is like', 'guide', lines: 5),
            const SizedBox(height: 12),
            field(_amenities, 'Nearby, separated by commas', 'amenities', hint: 'Yaya Centre, Nairobi Hospital'),
            if (_a.slug != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${_a.listings} live listings${_a.medianRentKES == null ? '' : ', typical rent ${formatKes(_a.medianRentKES!)}'}. Updated every night.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
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
