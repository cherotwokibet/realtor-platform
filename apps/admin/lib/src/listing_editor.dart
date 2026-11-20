import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';

import 'format.dart';
import 'listing_media.dart';
import 'maps.dart';
import 'providers.dart';

/// Create or edit a listing (P5-s02). Saving sends it for review: it goes to
/// Pending until a manager approves it. Pops with the listing id once saved.
///
/// In sections, as the big portals' listing forms are: the basics, the price
/// and what else is paid, where it is (area, then a pin by map, pasted link
/// or coordinates, checked against the area's outline), features and
/// amenities to tick, the description, and who lists it.
class ListingEditorDialog extends ConsumerStatefulWidget {
  const ListingEditorDialog({super.key, this.listingId});

  /// Null for a new listing.
  final String? listingId;

  @override
  ConsumerState<ListingEditorDialog> createState() => _ListingEditorDialogState();
}

/// One extra charge's fields.
class _ChargeRow {
  _ChargeRow([ExtraCharge? c])
      : name = TextEditingController(text: c?.name ?? ''),
        amount = TextEditingController(text: c == null ? '' : '${c.amountKES}'),
        per = c?.per ?? 'once';
  final TextEditingController name, amount;
  String per;
  void dispose() {
    name.dispose();
    amount.dispose();
  }
}

class _ListingEditorDialogState extends ConsumerState<ListingEditorDialog> {
  ListingDraft? _draft;
  List<AreaOption> _areas = const [];
  List<AgentOption> _agents = const [];
  String? _loadError, _saveError, _pasteNote;
  bool _saving = false, _tried = false;
  final _charges = <_ChargeRow>[];
  final _amenities = <String>{};

  final _title = TextEditingController(),
      _price = TextEditingController(),
      _deposit = TextEditingController(),
      _service = TextEditingController(),
      _viewingFee = TextEditingController(),
      _estate = TextEditingController(),
      _custom = TextEditingController(),
      _description = TextEditingController(),
      _paste = TextEditingController(),
      _lat = TextEditingController(),
      _lng = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_title, _price, _deposit, _service, _viewingFee, _estate, _custom, _description, _paste, _lat, _lng]) {
      c.dispose();
    }
    for (final c in _charges) {
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
      _amenities.addAll(d.amenities);
      _charges.addAll(d.extraCharges.map(_ChargeRow.new));
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

  GeoPoint? get _pin {
    final lat = double.tryParse(_lat.text.trim()), lng = double.tryParse(_lng.text.trim());
    return lat == null || lng == null || (lat == 0 && lng == 0) ? null : GeoPoint(lat, lng);
  }

  AreaOption? get _area => _areas.where((a) => a.slug == _draft?.area).firstOrNull;

  /// The pin is outside the chosen area's outline (when it has one).
  bool get _outside {
    final a = _area, p = _pin;
    return a != null && p != null && a.boundary.length >= 3 && !insideOutline(p, a.boundary);
  }

  /// A new pin: from the map, a pasted link or the boxes. With no area yet,
  /// the area whose outline holds it is picked.
  void _pinTo(GeoPoint p) {
    _setPosition(p.lat, p.lng);
    final d = _draft!;
    if (d.area.isEmpty) {
      final holding = areasHolding(p, _areas, (a) => a.boundary);
      if (holding.length == 1) {
        setState(() => _draft = d.copyWith(area: holding.single.slug));
        return;
      }
    }
    setState(() {});
  }

  void _pasted(String text) {
    if (text.trim().isEmpty) return setState(() => _pasteNote = null);
    final p = parseMapPosition(text);
    if (p == null) {
      return setState(() => _pasteNote = text.contains('goo.gl')
          ? 'Short links have to be opened first: open it, then copy the full address from the browser, or the coordinates.'
          : 'No position found. Paste a Google Maps link, or coordinates like -1.2921, 36.7856.');
    }
    _pasteNote = 'Pin set to ${p.lat.toStringAsFixed(5)}, ${p.lng.toStringAsFixed(5)}.';
    _pinTo(p);
  }

  /// The form's current values on top of the loaded draft.
  ListingDraft get _current => _draft!.copyWith(
        title: _title.text,
        priceKES: _int(_price) ?? 0,
        depositMonths: () => _int(_deposit),
        serviceChargeKES: () => _int(_service),
        viewingFeeKES: () => _int(_viewingFee),
        estate: () => _estate.text.trim().isEmpty ? null : _estate.text,
        amenities: _amenities.toList(),
        extraCharges: [
          for (final c in _charges)
            if (c.name.text.trim().isNotEmpty || c.amount.text.trim().isNotEmpty)
              ExtraCharge(name: c.name.text.trim(), amountKES: _int(c.amount) ?? 0, per: c.per),
        ],
        description: _description.text,
        lat: _pin?.lat ?? 0,
        lng: _pin?.lng ?? 0,
      );

  Map<String, String> _problems() => {
        ..._current.problems(),
        if (_outside) 'location': 'The pin is outside ${_area!.name}. Move it, or pick the area it is in.',
      };

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
    if (_problems().isNotEmpty || (ref.read(staffProvider)!.isManager && draft.agentId == null)) return;
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
    final tenant = ref.watch(tenantProvider);
    final d = _draft;
    final b = context.brand;
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final problems = _tried && d != null ? _problems() : const <String, String>{};
    Widget gap() => const SizedBox(height: 12, width: 12);
    Widget pair(Widget a, Widget c) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: a), gap(), Expanded(child: c)]);
    TextField text(TextEditingController c, String labelText, String field, {bool number = false, String? hint, String? prefix, Key? key}) => TextField(
          key: key,
          controller: c,
          keyboardType: number ? TextInputType.number : null,
          inputFormatters: number ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9, ]'))] : null,
          decoration: InputDecoration(labelText: labelText, hintText: hint, prefixText: prefix, errorText: problems[field], border: const OutlineInputBorder()),
          onChanged: (_) => _tried ? setState(() {}) : null,
        );
    DropdownButtonFormField<T> pick<T>(String labelText, T? value, Map<T, String> options, ValueChanged<T?> onChanged, {String? error, Key? key}) =>
        DropdownButtonFormField<T>(
          key: key,
          initialValue: options.containsKey(value) ? value : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: labelText, errorText: error, border: const OutlineInputBorder()),
          items: [for (final e in options.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: onChanged,
        );
    Widget section(String title, String? note, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            if (note != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(note, style: t.bodySmall?.copyWith(color: b.textMuted))),
            const SizedBox(height: 12),
            ...children,
          ]),
        );

    final List<Widget> body;
    if (d == null) {
      body = [Padding(padding: const EdgeInsets.all(24), child: Center(child: _loadError == null ? const CircularProgressIndicator() : Text(_loadError!)))];
    } else {
      final pin = _pin;
      final holding = pin == null ? const <AreaOption>[] : areasHolding(pin, _areas, (a) => a.boundary);
      final groups = <String, List<(String, String, String)>>{};
      for (final a in listingAmenities) {
        (groups[a.$3] ??= []).add(a);
      }
      final own = _amenities.where((a) => !listingAmenities.any((x) => x.$1 == a)).toList();
      body = [
        section('Basics', null, [
          text(_title, 'Title (name of the building or home)', 'title', hint: 'Riverside Heights, 2 bedroom apartment', key: const Key('listing-title')),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(onPressed: _suggest, icon: const Icon(Icons.auto_awesome_outlined), label: const Text('Suggest title & description')),
          ),
          Text('For', style: t.labelLarge),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            for (final p in Purpose.values)
              if (tenant.features.isOn(switch (p) { Purpose.rent => Feature.rent, Purpose.sale => Feature.sale, Purpose.shortStay => Feature.shortStay }))
                ChoiceChip(
                  key: Key('purpose-${p.value}'),
                  label: Text(switch (p) { Purpose.rent => 'Rent', Purpose.sale => 'Sale', Purpose.shortStay => 'Short stay' }),
                  selected: d.purpose == p.value,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _draft = d.copyWith(purpose: p.value)),
                ),
          ]),
          if (problems['purpose'] != null) Text(problems['purpose']!, style: TextStyle(color: scheme.error)),
          gap(),
          pick('Type', d.type, {for (final ty in listingTypeSlugs.keys) ty: label(ty)}, (v) => setState(() => _draft = d.copyWith(type: v)),
              error: problems['type'], key: const Key('listing-type')),
          gap(),
          pair(
            pick('Bedrooms', d.beds, {for (var i = 0; i <= 10; i++) i: i == 0 ? 'None (bedsitter, studio)' : '$i'},
                (v) => setState(() => _draft = d.copyWith(beds: v))),
            pick('Bathrooms', d.baths, {for (var i = 0; i <= 10; i++) i: '$i'}, (v) => setState(() => _draft = d.copyWith(baths: v))),
          ),
        ]),
        section('Price and additional expenses', 'What the tenant or buyer pays, all in whole shillings.', [
          text(
              _price,
              d.purpose == 'rent'
                  ? 'Rent a month'
                  : d.purpose == 'short-stay'
                      ? 'Price a night'
                      : 'Price',
              'priceKES',
              number: true,
              prefix: 'KES ',
              key: const Key('listing-price')),
          if (d.purpose == 'rent') ...[
            gap(),
            pair(text(_deposit, 'Deposit (months of rent)', 'depositMonths', number: true),
                text(_service, 'Service charge a month', 'serviceChargeKES', number: true, prefix: 'KES ')),
          ],
          // Viewing fees are paid by M-Pesa (P6-s01): only where the tenant has it on.
          if (tenant.features.isOn(Feature.mpesa)) ...[
            gap(),
            text(_viewingFee, 'Viewing fee (optional, paid by M-Pesa)', 'viewingFeeKES', number: true, prefix: 'KES '),
          ],
          gap(),
          for (final (i, c) in _charges.indexed) ...[
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                flex: 3,
                child: TextField(
                  key: Key('charge-name-$i'),
                  controller: c.name,
                  decoration: const InputDecoration(labelText: 'What for', hintText: 'Water, garbage, agency fee', border: OutlineInputBorder()),
                ),
              ),
              gap(),
              Expanded(
                flex: 2,
                child: TextField(
                  key: Key('charge-amount-$i'),
                  controller: c.amount,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9, ]'))],
                  decoration: const InputDecoration(labelText: 'Amount', prefixText: 'KES ', border: OutlineInputBorder()),
                ),
              ),
              gap(),
              SizedBox(
                width: 130,
                child: DropdownButtonFormField<String>(
                  initialValue: c.per,
                  isExpanded: true,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  items: [for (final per in ExtraCharge.periods) DropdownMenuItem(value: per, child: Text(per == 'once' ? 'Once' : 'A $per'))],
                  onChanged: (v) => setState(() => c.per = v ?? c.per),
                ),
              ),
              IconButton(
                tooltip: 'Remove this expense',
                onPressed: () => setState(() => _charges.removeAt(i).dispose()),
                icon: const Icon(Icons.delete_outline),
              ),
            ]),
            gap(),
          ],
          if (problems['extraCharges'] != null)
            Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(problems['extraCharges']!, style: TextStyle(color: scheme.error))),
          if (_charges.length < 10)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const Key('add-charge'),
                onPressed: () => setState(() => _charges.add(_ChargeRow())),
                icon: const Icon(Icons.add),
                label: const Text('Add an expense'),
              ),
            ),
        ]),
        section('Location', 'Pick the area, then set the pin: tap the map, drag the pin, paste a Google Maps link, or type the coordinates.', [
          pair(
            pick('Area', d.area.isEmpty ? null : d.area, {for (final a in _areas) a.slug: a.name}, (v) {
              final a = _areas.firstWhere((x) => x.slug == v);
              // A new area with no pin yet starts the pin at its centre; a pin
              // already set stays (the outline check says if it is outside).
              if (_pin == null) _setPosition(a.lat, a.lng);
              setState(() => _draft = d.copyWith(area: v));
            }, error: problems['area'], key: const Key('listing-area')),
            text(_estate, 'Estate, street or building (optional)', 'estate'),
          ),
          gap(),
          TextField(
            key: const Key('listing-paste'),
            controller: _paste,
            onChanged: _pasted,
            decoration: InputDecoration(
              labelText: 'Paste a Google Maps link or coordinates',
              hintText: 'https://www.google.com/maps/place/…  or  -1.2921, 36.7856',
              helperText: _pasteNote,
              prefixIcon: const Icon(Icons.link),
              border: const OutlineInputBorder(),
            ),
          ),
          gap(),
          PinMap(
            pin: pin,
            centre: _area == null ? null : GeoPoint(_area!.lat, _area!.lng),
            outline: _area?.boundary ?? const [],
            onPin: _pinTo,
          ),
          gap(),
          pair(
            TextField(
              key: const Key('listing-lat'),
              controller: _lat,
              decoration: InputDecoration(labelText: 'Latitude', errorText: problems['location'] == null ? null : '', border: const OutlineInputBorder()),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              key: const Key('listing-lng'),
              controller: _lng,
              decoration: InputDecoration(labelText: 'Longitude', errorText: problems['location'] == null ? null : '', border: const OutlineInputBorder()),
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (_outside || problems['location'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                Icon(Icons.wrong_location_outlined, color: scheme.error, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _outside ? 'The pin is outside ${_area!.name}${holding.isEmpty ? '.' : ': it is in ${holding.first.name}.'}' : problems['location']!,
                    key: const Key('pin-outside'),
                    style: TextStyle(color: scheme.error),
                  ),
                ),
                if (_outside && holding.isNotEmpty)
                  TextButton(
                    key: const Key('use-holding-area'),
                    onPressed: () => setState(() => _draft = d.copyWith(area: holding.first.slug)),
                    child: Text('Use ${holding.first.name}'),
                  ),
              ]),
            ),
        ]),
        section('Features and amenities', 'Tick all that apply; people filter by these.', [
          for (final g in groups.entries) ...[
            Text(g.key, style: t.labelLarge?.copyWith(color: b.textMuted)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final a in g.value)
                FilterChip(
                  key: Key('amenity-${a.$1}'),
                  label: Text(a.$2),
                  selected: _amenities.contains(a.$1),
                  onSelected: (on) => setState(() => on ? _amenities.add(a.$1) : _amenities.remove(a.$1)),
                ),
            ]),
            const SizedBox(height: 12),
          ],
          if (own.isNotEmpty) ...[
            Text('Others', style: t.labelLarge?.copyWith(color: b.textMuted)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final a in own) InputChip(label: Text(a), onDeleted: () => setState(() => _amenities.remove(a))),
            ]),
            const SizedBox(height: 12),
          ],
          Row(children: [
            Expanded(
              child: TextField(
                key: const Key('amenity-custom'),
                controller: _custom,
                decoration: const InputDecoration(labelText: 'Something else', hintText: 'Rooftop terrace', border: OutlineInputBorder(), isDense: true),
                onSubmitted: (v) => setState(() {
                  if (v.trim().isNotEmpty) _amenities.add(v.trim());
                  _custom.clear();
                }),
              ),
            ),
            gap(),
            OutlinedButton(
              onPressed: () => setState(() {
                if (_custom.text.trim().isNotEmpty) _amenities.add(_custom.text.trim());
                _custom.clear();
              }),
              child: const Text('Add'),
            ),
          ]),
          if (problems['amenities'] != null) Text(problems['amenities']!, style: TextStyle(color: scheme.error)),
        ]),
        section('Description', null, [
          TextField(
            controller: _description,
            minLines: 4,
            maxLines: 10,
            maxLength: 3000,
            decoration: InputDecoration(
              labelText: 'Description',
              helperText: 'Fill in the facts above, then "Suggest" writes a first draft to edit.',
              errorText: problems['description'],
              border: const OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
        ]),
        if (who.isManager)
          section('Agent', 'Who this listing is for: they get its leads and viewings.', [
            pick('Assign an agent', d.agentId, {for (final a in _agents) a.id: a.name}, (v) => setState(() => _draft = d.copyWith(agentId: v)),
                error: _tried && d.agentId == null ? 'Pick the agent' : null, key: const Key('listing-agent')),
          ]),
        section('Photos and video', null, [
          if (widget.listingId == null)
            Text('Save the listing first, then open it again to add photos.', style: t.bodySmall)
          else
            ListingMediaSection(listingId: widget.listingId!),
        ]),
        if (_saveError != null) ...[gap(), Text("Couldn't save: $_saveError", style: TextStyle(color: scheme.error))],
        gap(),
        Text('Saving sends the listing to Pending; a manager approves it before it goes live.', style: t.bodySmall),
      ];
    }

    return AlertDialog(
      title: Text(widget.listingId == null ? 'New listing' : 'Edit listing'),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: body)),
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
