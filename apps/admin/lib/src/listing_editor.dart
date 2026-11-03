import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_core/realtor_core.dart';

import 'format.dart';
import 'listing_media.dart';
import 'providers.dart';

/// Create or edit a listing (P5-s02). Saving sends it for review: it goes to
/// Pending until a manager approves it. Pops with the listing id once saved.
class ListingEditorDialog extends ConsumerStatefulWidget {
  const ListingEditorDialog({super.key, this.listingId});

  /// Null for a new listing.
  final String? listingId;

  @override
  ConsumerState<ListingEditorDialog> createState() => _ListingEditorDialogState();
}

class _ListingEditorDialogState extends ConsumerState<ListingEditorDialog> {
  ListingDraft? _draft;
  List<AreaOption> _areas = const [];
  List<AgentOption> _agents = const [];
  String? _loadError, _saveError;
  bool _saving = false, _tried = false;

  final _title = TextEditingController(),
      _price = TextEditingController(),
      _deposit = TextEditingController(),
      _service = TextEditingController(),
      _viewingFee = TextEditingController(),
      _estate = TextEditingController(),
      _amenities = TextEditingController(),
      _description = TextEditingController(),
      _lat = TextEditingController(),
      _lng = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_title, _price, _deposit, _service, _viewingFee, _estate, _amenities, _description, _lat, _lng]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final who = ref.read(staffProvider)!;
    final repo = ref.read(adminRepositoryProvider);
    try {
      final (areas, agents, existing) = await (
        repo.areas(),
        who.isManager ? repo.agents(who) : Future.value(const <AgentOption>[]),
        widget.listingId == null ? Future<ListingDraft?>.value() : repo.listingDraft(who, widget.listingId!),
      ).wait;
      if (!mounted) return;
      if (widget.listingId != null && existing == null) {
        setState(() => _loadError = 'This listing is not there, or not yours to edit.');
        return;
      }
      final d = existing ?? ListingDraft(agentId: who.agentId);
      _title.text = d.title;
      _price.text = d.priceKES == 0 ? '' : '${d.priceKES}';
      _deposit.text = d.depositMonths?.toString() ?? '';
      _service.text = d.serviceChargeKES?.toString() ?? '';
      _viewingFee.text = d.viewingFeeKES?.toString() ?? '';
      _estate.text = d.estate ?? '';
      _amenities.text = d.amenities.join(', ');
      _description.text = d.description;
      _setPosition(d.lat, d.lng);
      setState(() {
        _areas = areas;
        _agents = agents;
        _draft = d;
      });
    } on Object catch (e) {
      if (mounted) setState(() => _loadError = 'Could not load: $e');
    }
  }

  void _setPosition(double lat, double lng) {
    _lat.text = lat == 0 && lng == 0 ? '' : lat.toStringAsFixed(6);
    _lng.text = lat == 0 && lng == 0 ? '' : lng.toStringAsFixed(6);
  }

  int? _int(TextEditingController c) => int.tryParse(c.text.replaceAll(RegExp(r'kes|ksh|[\s,]', caseSensitive: false), ''));

  /// The form's current values on top of the loaded draft.
  ListingDraft get _current => _draft!.copyWith(
        title: _title.text,
        priceKES: _int(_price) ?? 0,
        depositMonths: () => _int(_deposit),
        serviceChargeKES: () => _int(_service),
        viewingFeeKES: () => _int(_viewingFee),
        estate: () => _estate.text.trim().isEmpty ? null : _estate.text,
        amenities: [for (final a in _amenities.text.split(',')) if (a.trim().isNotEmpty) a.trim()],
        description: _description.text,
        lat: double.tryParse(_lat.text.trim()) ?? 0,
        lng: double.tryParse(_lng.text.trim()) ?? 0,
      );

  /// Copy assistant (P7-s02): a title and description from the facts in the
  /// form, for the agent to edit. Asks before replacing text already there.
  Future<void> _suggest() async {
    final draft = _current;
    final area = _areas.where((a) => a.slug == draft.area).firstOrNull?.name ?? '';
    final copy = suggestListingCopy(draft, areaName: area);
    final hasText = _title.text.trim().isNotEmpty || _description.text.trim().isNotEmpty;
    if (hasText) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Replace the title and description?'),
          content: Text('Suggested title: ${copy.title}'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep mine')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Replace')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() {
      _title.text = copy.title;
      _description.text = copy.description;
    });
  }

  Future<void> _save() async {
    final draft = _current;
    setState(() {
      _tried = true;
      _saveError = null;
    });
    if (draft.problems().isNotEmpty || (ref.read(staffProvider)!.isManager && draft.agentId == null)) return;
    setState(() => _saving = true);
    try {
      final id = await ref.read(adminActionsProvider).submitListing(ref.read(staffProvider)!, draft);
      if (mounted) Navigator.pop(context, id);
    } on AdminActionException catch (e) {
      if (mounted) setState(() => _saveError = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final who = ref.watch(staffProvider)!;
    final d = _draft;
    final problems = _tried && d != null ? _current.problems() : const <String, String>{};
    Widget gap() => const SizedBox(height: 12, width: 12);
    Widget pair(Widget a, Widget b) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: a), gap(), Expanded(child: b)]);
    TextField text(TextEditingController c, String labelText, String field, {bool number = false, String? hint}) => TextField(
          controller: c,
          keyboardType: number ? TextInputType.number : null,
          inputFormatters: number ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9, ]'))] : null,
          decoration: InputDecoration(labelText: labelText, hintText: hint, errorText: problems[field], border: const OutlineInputBorder()),
          onChanged: (_) => _tried ? setState(() {}) : null,
        );
    DropdownButtonFormField<T> pick<T>(String labelText, T? value, Map<T, String> options, ValueChanged<T?> onChanged, {String? error}) =>
        DropdownButtonFormField<T>(
          initialValue: options.containsKey(value) ? value : null,
          decoration: InputDecoration(labelText: labelText, errorText: error, border: const OutlineInputBorder()),
          items: [for (final e in options.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: onChanged,
        );

    return AlertDialog(
      title: Text(widget.listingId == null ? 'New listing' : 'Edit listing'),
      content: SizedBox(
        width: 620,
        child: d == null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Center(child: _loadError == null ? const CircularProgressIndicator() : Text(_loadError!)),
              )
            : SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                  const SizedBox(height: 4),
                  text(_title, 'Title', 'title', hint: '2 bedroom apartment, Kilimani'),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _suggest,
                      icon: const Icon(Icons.auto_awesome_outlined),
                      label: const Text('Suggest title & description'),
                    ),
                  ),
                  pair(
                    pick('For', d.purpose, {for (final p in Purpose.values) p.value: label(p.value)},
                        (v) => setState(() => _draft = d.copyWith(purpose: v)), error: problems['purpose']),
                    pick('Type', d.type, {for (final t in listingTypeSlugs.keys) t: label(t)},
                        (v) => setState(() => _draft = d.copyWith(type: v)), error: problems['type']),
                  ),
                  gap(),
                  pair(
                    pick('Bedrooms', d.beds, {for (var i = 0; i <= 10; i++) i: i == 0 ? 'None' : '$i'},
                        (v) => setState(() => _draft = d.copyWith(beds: v))),
                    pick('Bathrooms', d.baths, {for (var i = 0; i <= 10; i++) i: '$i'},
                        (v) => setState(() => _draft = d.copyWith(baths: v))),
                  ),
                  gap(),
                  text(_price, d.purpose == 'rent' ? 'Rent a month (KES)' : d.purpose == 'short-stay' ? 'Price a night (KES)' : 'Price (KES)',
                      'priceKES',
                      number: true),
                  if (d.purpose == 'rent') ...[
                    gap(),
                    pair(text(_deposit, 'Deposit (months)', 'depositMonths', number: true),
                        text(_service, 'Service charge a month (KES)', 'serviceChargeKES', number: true)),
                  ],
                  // Viewing fees are paid by M-Pesa (P6-s01): only where the tenant has it on.
                  if (ref.watch(tenantProvider).features.isOn(Feature.mpesa)) ...[
                    gap(),
                    text(_viewingFee, 'Viewing fee (KES, optional, paid by M-Pesa)', 'viewingFeeKES', number: true),
                  ],
                  gap(),
                  pick('Area', d.area, {for (final a in _areas) a.slug: a.name}, (v) {
                    final a = _areas.firstWhere((x) => x.slug == v);
                    // A new area moves the pin to its centre; adjust it after.
                    _setPosition(a.lat, a.lng);
                    setState(() => _draft = d.copyWith(area: v));
                  }, error: problems['area']),
                  gap(),
                  text(_estate, 'Estate or building (optional)', 'estate'),
                  gap(),
                  pair(text(_lat, 'Latitude', 'location'), text(_lng, 'Longitude', 'location')),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Starts at the area centre. Paste the exact position from Google Maps for a better pin.',
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                  gap(),
                  text(_amenities, 'Amenities, separated by commas', 'amenities', hint: 'Borehole, Parking, Lift'),
                  gap(),
                  TextField(
                    controller: _description,
                    minLines: 3,
                    maxLines: 8,
                    maxLength: 3000,
                    decoration: InputDecoration(
                      labelText: 'Description',
                      helperText: 'Fill in the facts above, then "Suggest" writes a first draft to edit.',
                      errorText: problems['description'],
                      border: const OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  if (who.isManager) ...[
                    gap(),
                    pick('Agent', d.agentId, {for (final a in _agents) a.id: a.name},
                        (v) => setState(() => _draft = d.copyWith(agentId: v)),
                        error: _tried && d.agentId == null ? 'Pick the agent' : null),
                  ],
                  gap(),
                  if (widget.listingId == null)
                    Text('Save the listing first, then open it again to add photos.', style: Theme.of(context).textTheme.bodySmall)
                  else
                    ListingMediaSection(listingId: widget.listingId!),
                  if (_saveError != null) ...[
                    gap(),
                    Text("Couldn't save: $_saveError", style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  gap(),
                  Text('Saving sends the listing to Pending; a manager approves it before it goes live.',
                      style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: d == null || _saving || (who.isManager && _tried && d.agentId == null) ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save and send for review'),
        ),
      ],
    );
  }
}

/// The listing's photos and videos, and a button to add more. Uploads are
/// checked and resized by the media pipeline, so they appear after a moment.
class ListingMediaSection extends ConsumerStatefulWidget {
  const ListingMediaSection({super.key, required this.listingId});
  final String listingId;

  @override
  ConsumerState<ListingMediaSection> createState() => _ListingMediaSectionState();
}

class _ListingMediaSectionState extends ConsumerState<ListingMediaSection> {
  ListingMediaState? _state;
  String? _status;
  final _problems = <String>[];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final s = await ref.read(listingMediaProvider).state(ref.read(staffProvider)!, widget.listingId);
    if (mounted) setState(() => _state = s);
  }

  Future<void> _add() async {
    final files = await ref.read(filePickerProvider).pick(accept: [...photoTypes, ...videoTypes].join(','));
    if (files.isEmpty || !mounted) return;
    final media = ref.read(listingMediaProvider), who = ref.read(staffProvider)!;
    setState(() {
      _busy = true;
      _problems.clear();
    });
    var sent = 0;
    for (final (i, f) in files.indexed) {
      final problem = uploadProblem(f);
      if (problem != null) {
        _problems.add(problem);
        continue;
      }
      setState(() => _status = 'Uploading ${i + 1} of ${files.length}…');
      try {
        await media.upload(who, widget.listingId, f);
        sent++;
      } on Object catch (e) {
        _problems.add('${f.name}: could not upload ($e)');
      }
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = sent == 0 ? null : 'Uploaded $sent. They are checked and resized, then appear here; press Refresh in a minute.';
    });
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final s = _state, media = ref.watch(listingMediaProvider);
    final t = Theme.of(context).textTheme, err = TextStyle(color: Theme.of(context).colorScheme.error);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: Text(
            s == null
                ? 'Photos and video'
                : 'Photos and video: ${s.thumbs.length} photo${s.thumbs.length == 1 ? '' : 's'}'
                    '${s.videos > 0 ? ', ${s.videos} video${s.videos == 1 ? '' : 's'}' : ''}',
            style: t.titleSmall,
          ),
        ),
        IconButton(tooltip: 'Refresh', onPressed: _busy ? null : _refresh, icon: const Icon(Icons.refresh)),
        OutlinedButton.icon(
          onPressed: _busy ? null : _add,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: const Text('Add photos or a video'),
        ),
      ]),
      if (s != null && s.thumbs.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final p in s.thumbs)
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox.square(
                  dimension: 72,
                  child: switch (media.url(p)) {
                    final String u => Image.network(u, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.image_outlined)),
                    null => const Icon(Icons.image_outlined),
                  },
                ),
              ),
          ]),
        ),
      if (s?.lastError != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Last upload refused: ${s!.lastError}', style: err)),
      if (_status != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_status!, style: t.bodySmall)),
      for (final p in _problems) Text(p, style: err),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text('Photos at least 1024 px on the long side, under 20 MB. A video up to 3 minutes, 720p or better, under 200 MB.', style: t.bodySmall),
      ),
    ]);
  }
}
