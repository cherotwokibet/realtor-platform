import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';

import 'maps.dart';
import 'providers.dart';

/// Areas (P3-s05): where the realtor works. Each has its guide for the
/// site's area page, a centre, and an outline (geofence): listings
/// in an area must be pinned inside its outline. Managers and admins.
class AreasScreen extends ConsumerStatefulWidget {
  const AreasScreen({super.key});
  @override
  ConsumerState<AreasScreen> createState() => _AreasScreenState();
}

class _AreasScreenState extends ConsumerState<AreasScreen> {
  List<AreaGuide>? _areas;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final list = await ref.read(adminRepositoryProvider).areaGuides();
    if (mounted) setState(() => _areas = list);
  }

  Future<void> _edit(AreaGuide? a) async {
    final all = _areas ?? const <AreaGuide>[];
    final saved = await showDialog<String>(
      context: context,
      builder: (_) => AreaEditorDialog(area: a, others: [
        for (final o in all)
          if (o.slug != a?.slug) o.boundary
      ]),
    );
    if (saved != null) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final q = _search.text.trim().toLowerCase();
    final areas = _areas?.where((a) => q.isEmpty || a.name.toLowerCase().contains(q) || a.county.toLowerCase().contains(q)).toList();
    final drawn = _areas?.where((a) => a.boundary.length >= 3).length ?? 0;
    return ListView(padding: const EdgeInsets.all(24), children: [
      Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 16, runSpacing: 12, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Areas', style: t.headlineSmall),
          const SizedBox(height: 4),
          Text(
            _areas == null
                ? 'Where you work.'
                : 'Where you work: ${_areas!.length} areas, $drawn with an outline. A listing must be pinned inside its area\'s outline.',
            style: t.bodyMedium?.copyWith(color: b.textMuted),
          ),
        ]),
        FilledButton.icon(
          key: const Key('add-area'),
          onPressed: () => _edit(null),
          icon: const Icon(Icons.add_location_alt_outlined),
          label: const Text('Add area'),
        ),
      ]),
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: 340,
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search), hintText: 'Search areas', border: OutlineInputBorder()),
          ),
        ),
      ),
      const SizedBox(height: 16),
      if (areas == null)
        const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
      else
        LayoutBuilder(builder: (context, box) {
          final across = box.maxWidth >= 1100 ? 3 : (box.maxWidth >= 640 ? 2 : 1);
          final w = (box.maxWidth - 16 * (across - 1)) / across;
          return Wrap(spacing: 16, runSpacing: 16, children: [
            for (final a in areas)
              SizedBox(
                width: w,
                child: Material(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(b.radiusMd + 4),
                  child: InkWell(
                    key: Key('area-${a.slug}'),
                    borderRadius: BorderRadius.circular(b.radiusMd + 4),
                    onTap: () => _edit(a),
                    child: Ink(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(b.radiusMd + 4), border: Border.all(color: scheme.outlineVariant)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(a.name, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                          Tooltip(
                            message: a.boundary.length >= 3 ? 'Outline drawn: pins are checked against it' : 'No outline yet: any pin is accepted',
                            child: Chip(
                              visualDensity: VisualDensity.compact,
                              avatar: Icon(a.boundary.length >= 3 ? Icons.check_circle : Icons.radio_button_unchecked,
                                  size: 16, color: a.boundary.length >= 3 ? b.success : b.textMuted),
                              label: Text(a.boundary.length >= 3 ? 'Outline' : 'No outline'),
                            ),
                          ),
                        ]),
                        Text(a.county, style: t.bodySmall?.copyWith(color: b.textMuted)),
                        const SizedBox(height: 12),
                        Text(
                          [
                            '${a.listings} live',
                            if (a.medianRentKES != null) 'typical rent ${formatKes(a.medianRentKES!)}',
                            if (a.guide.isEmpty) 'no guide yet',
                          ].join(' · '),
                          style: t.bodyMedium,
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
          ]);
        }),
    ]);
  }
}

/// One area's guide. Typical rent and live listings update every night.
class AreaEditorDialog extends ConsumerStatefulWidget {
  const AreaEditorDialog({super.key, this.area, this.others = const []});
  final AreaGuide? area;

  /// The other areas' outlines, shown faintly to draw up to.
  final List<List<GeoPoint>> others;
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
  late List<GeoPoint> _outline = _a.boundary;
  final _history = <List<GeoPoint>>[];

  void _setOutline(List<GeoPoint> next) {
    setState(() {
      _history.add(_outline);
      _outline = next;
      // A new area takes the outline's middle as its centre.
      if (next.length >= 3 && (_lat.text.trim().isEmpty || _lng.text.trim().isEmpty)) {
        final m = outlineMiddle(next);
        _lat.text = m.lat.toStringAsFixed(6);
        _lng.text = m.lng.toStringAsFixed(6);
      }
    });
  }

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
        amenities: [
          for (final x in _amenities.text.split(','))
            if (x.trim().isNotEmpty) x.trim()
        ],
        boundary: _outline,
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
        width: 720,
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
            Text('Outline (geofence)', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(
              'Tap the map to place the corners around the area; drag a corner to move it. Listings in this area must be pinned inside. '
              'Other areas show faintly.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            OutlineMap(
              outline: _outline,
              onOutline: _setOutline,
              centre: GeoPoint(double.tryParse(_lat.text.trim()) ?? -1.2864, double.tryParse(_lng.text.trim()) ?? 36.8172),
              others: widget.others,
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('${_outline.length} corners', key: const Key('outline-count')),
              TextButton.icon(
                onPressed: _history.isEmpty ? null : () => setState(() => _outline = _history.removeLast()),
                icon: const Icon(Icons.undo, size: 18),
                label: const Text('Undo'),
              ),
              TextButton.icon(
                onPressed: _outline.isEmpty ? null : () => _setOutline(const []),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Clear outline'),
              ),
              TextButton.icon(
                onPressed: _outline.length < 3
                    ? null
                    : () => setState(() {
                          final m = outlineMiddle(_outline);
                          _lat.text = m.lat.toStringAsFixed(6);
                          _lng.text = m.lng.toStringAsFixed(6);
                        }),
                icon: const Icon(Icons.center_focus_strong_outlined, size: 18),
                label: const Text('Centre in the middle'),
              ),
            ]),
            if (problems['boundary'] != null) Text(problems['boundary']!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
