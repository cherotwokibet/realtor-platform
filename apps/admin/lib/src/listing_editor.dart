import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_core/realtor_core.dart';

import 'format.dart';
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
      _estate = TextEditingController(),
      _amenities = TextEditingController(),
      _lat = TextEditingController(),
      _lng = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_title, _price, _deposit, _service, _estate, _amenities, _lat, _lng]) {
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
      _estate.text = d.estate ?? '';
      _amenities.text = d.amenities.join(', ');
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
        estate: () => _estate.text.trim().isEmpty ? null : _estate.text,
        amenities: [for (final a in _amenities.text.split(',')) if (a.trim().isNotEmpty) a.trim()],
        lat: double.tryParse(_lat.text.trim()) ?? 0,
        lng: double.tryParse(_lng.text.trim()) ?? 0,
      );

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
                  gap(),
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
                  if (who.isManager) ...[
                    gap(),
                    pick('Agent', d.agentId, {for (final a in _agents) a.id: a.name},
                        (v) => setState(() => _draft = d.copyWith(agentId: v)),
                        error: _tried && d.agentId == null ? 'Pick the agent' : null),
                  ],
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
