import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';

import '../providers.dart';
import 'purpose.dart';

/// Which part of the filters a chip on the results screen opens; [all] is
/// the whole sheet ("Filters", or "Search" with the location field first).
enum FilterSection { all, type, beds, price }

/// Property types offered in the filters, most asked-for first, with icons.
const filterTypes = <(String, IconData)>[
  ('apartment', Icons.apartment_outlined),
  ('bedsitter', Icons.bed_outlined),
  ('single-room', Icons.meeting_room_outlined),
  ('studio', Icons.weekend_outlined),
  ('maisonette', Icons.home_work_outlined),
  ('townhouse', Icons.holiday_village_outlined),
  ('bungalow', Icons.cottage_outlined),
  ('villa', Icons.villa_outlined),
  ('hostel', Icons.hotel_outlined),
  ('land', Icons.landscape_outlined),
  ('commercial', Icons.storefront_outlined),
];

/// Features people filter by; the same words typed search understands.
const filterAmenities = <(String, String)>[
  ('furnished', 'Furnished'),
  ('parking', 'Parking'),
  ('security', 'Security'),
  ('borehole', 'Borehole'),
  ('wifi', 'Wi-Fi'),
  ('lift', 'Lift'),
  ('gym', 'Gym'),
  ('swimming-pool', 'Swimming pool'),
  ('garden', 'Garden'),
  ('balcony', 'Balcony'),
];

/// Opens the filters as a bottom sheet (a centred panel on wide screens) and
/// returns the new filters, or null when it was closed without "Show homes".
Future<ListingFilters?> showFiltersSheet(BuildContext context, ListingFilters filters, {FilterSection section = FilterSection.all}) {
  final wide = MediaQuery.sizeOf(context).width >= 840;
  return showModalBottomSheet<ListingFilters>(
    context: context,
    isScrollControlled: true,
    // Over the bottom tabs, as a sheet of its own.
    useRootNavigator: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: BoxConstraints(maxWidth: wide ? 640 : double.infinity),
    builder: (_) => FiltersSheet(initial: filters, section: section),
  );
}

class FiltersSheet extends ConsumerStatefulWidget {
  const FiltersSheet({super.key, required this.initial, this.section = FilterSection.all});
  final ListingFilters initial;
  final FilterSection section;

  @override
  ConsumerState<FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends ConsumerState<FiltersSheet> {
  late Purpose _purpose = widget.initial.purpose;
  late final _location = TextEditingController(
    text: [...widget.initial.areas.map(areaName), if (widget.initial.q != null) widget.initial.q!].join(', '),
  );
  late Set<String> _types = {...widget.initial.types};
  late int? _minBeds = widget.initial.minBeds;
  late final _min = TextEditingController(text: widget.initial.minPriceKES?.toString() ?? '');
  late final _max = TextEditingController(text: widget.initial.maxPriceKES?.toString() ?? '');
  late Set<String> _amenities = {...widget.initial.amenities};
  late bool _verified = widget.initial.verifiedOnly;

  @override
  void dispose() {
    _location.dispose();
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  bool get _all => widget.section == FilterSection.all;

  void _reset() => setState(() {
        if (_all || widget.section == FilterSection.type) _types = {};
        if (_all || widget.section == FilterSection.beds) _minBeds = null;
        if (_all || widget.section == FilterSection.price) {
          _min.clear();
          _max.clear();
        }
        if (_all) {
          _location.clear();
          _amenities = {};
          _verified = false;
        }
      });

  static int? _kes(String s) => int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), ''));

  /// The location box: names of known areas become area filters; anything
  /// else is searched as words.
  (List<String>, String?) _where() {
    final names = ref.read(areaNamesProvider).value ?? const <String, String>{};
    final areas = <String>[];
    final words = <String>[];
    for (final part in _location.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty)) {
      final key = part.toLowerCase();
      final slug = names.entries.where((e) => e.value.toLowerCase() == key || e.key == key.replaceAll(' ', '-')).map((e) => e.key).firstOrNull;
      slug == null ? words.add(part) : areas.add(slug);
    }
    return (areas, words.isEmpty ? null : words.join(' '));
  }

  ListingFilters _result() {
    final f = widget.initial;
    var min = _kes(_min.text), max = _kes(_max.text);
    if (min != null && max != null && min > max) (min, max) = (max, min);
    final (areas, q) = _all ? _where() : (f.areas, f.q);
    return ListingFilters(
      purpose: _purpose,
      q: q,
      types: [..._types],
      areas: areas,
      minBeds: _minBeds,
      minPriceKES: min,
      maxPriceKES: max,
      amenities: [..._amenities],
      verifiedOnly: _verified,
      near: f.near,
      polygon: f.polygon,
      sort: f.sort,
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final features = ref.watch(tenantProvider).features;
    final purposes = [
      for (final p in Purpose.values)
        if (features.isOn(p.feature)) p
    ];
    Widget heading(String s) => Padding(
          padding: EdgeInsets.only(top: b.spacing.lg, bottom: b.spacing.sm),
          child: Text(s, style: text.titleMedium),
        );
    final title = switch (widget.section) {
      FilterSection.all => 'Filters',
      FilterSection.type => 'Property type',
      FilterSection.beds => 'Bedrooms',
      FilterSection.price => 'Price',
    };

    final sections = <Widget>[
      if (_all && purposes.length > 1) ...[
        heading('Purpose'),
        SegmentedButton<Purpose>(
          showSelectedIcon: false,
          segments: [for (final p in purposes) ButtonSegment(value: p, label: Text(p.label))],
          selected: {_purpose},
          onSelectionChanged: (s) => setState(() => _purpose = s.first),
        ),
      ],
      if (_all) ...[
        heading('Location'),
        TextField(
          key: const Key('filter-location'),
          controller: _location,
          decoration: const InputDecoration(hintText: 'Area or estate, e.g. Kilimani, Ruaka', prefixIcon: Icon(Icons.place_outlined)),
        ),
      ],
      if (_all || widget.section == FilterSection.type) ...[
        if (_all) heading('Property type'),
        Wrap(spacing: b.spacing.sm, runSpacing: b.spacing.sm, children: [
          for (final (type, icon) in filterTypes)
            _TypeTile(
              label: typeName(type),
              icon: icon,
              selected: _types.contains(type),
              onTap: () => setState(() => _types.contains(type) ? _types.remove(type) : _types.add(type)),
            ),
        ]),
      ],
      if (_all || widget.section == FilterSection.beds) ...[
        if (_all) heading('Bedrooms'),
        Wrap(spacing: b.spacing.sm, runSpacing: b.spacing.sm, children: [
          for (final (value, label) in const [(null, 'Any'), (1, '1+'), (2, '2+'), (3, '3+'), (4, '4+'), (5, '5+')])
            ChoiceChip(
              label: Text(label),
              selected: _minBeds == value,
              showCheckmark: false,
              onSelected: (_) => setState(() => _minBeds = value),
            ),
        ]),
      ],
      if (_all || widget.section == FilterSection.price) ...[
        if (_all) heading(_purpose.period == null ? 'Price (KES)' : 'Price a ${_purpose.period} (KES)'),
        Row(children: [
          Expanded(
            child: TextField(
              key: const Key('filter-min-price'),
              controller: _min,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Minimum', hintText: '0'),
            ),
          ),
          Padding(padding: EdgeInsets.symmetric(horizontal: b.spacing.sm), child: const Text('–')),
          Expanded(
            child: TextField(
              key: const Key('filter-max-price'),
              controller: _max,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Maximum', hintText: 'Any'),
            ),
          ),
        ]),
      ],
      if (_all) ...[
        heading('Features'),
        Wrap(spacing: b.spacing.sm, runSpacing: b.spacing.sm, children: [
          for (final (key, label) in filterAmenities)
            FilterChip(
              label: Text(label),
              selected: _amenities.contains(key),
              onSelected: (on) => setState(() => on ? _amenities.add(key) : _amenities.remove(key)),
            ),
        ]),
        SizedBox(height: b.spacing.md),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Verified homes first and only'),
          subtitle: const Text('Homes our agents have re-confirmed in the last 30 days.'),
          value: _verified,
          onChanged: (v) => setState(() => _verified = v),
        ),
      ],
    ];

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: b.spacing.gutter),
          child: Row(children: [
            Expanded(child: Text(title, style: text.titleLarge)),
            IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ]),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.fromLTRB(b.spacing.gutter, 0, b.spacing.gutter, b.spacing.lg),
            children: sections,
          ),
        ),
        const Divider(),
        Padding(
          padding: EdgeInsets.all(b.spacing.md),
          child: Row(children: [
            Expanded(child: OutlinedButton(onPressed: _reset, child: const Text('Reset'))),
            SizedBox(width: b.spacing.md),
            Expanded(
              flex: 2,
              child: FilledButton(onPressed: () => Navigator.pop(context, _result()), child: const Text('Show homes')),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// A property type with its icon, picked or not (several can be picked).
class _TypeTile extends StatelessWidget {
  const _TypeTile({required this.label, required this.icon, required this.selected, required this.onTap});
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(b.radiusMd),
        onTap: onTap,
        child: Container(
          width: 104,
          padding: EdgeInsets.symmetric(vertical: b.spacing.md, horizontal: b.spacing.xs),
          decoration: BoxDecoration(
            color: selected ? b.primarySoft : null,
            border: Border.all(color: selected ? scheme.primary : b.borderStrong),
            borderRadius: BorderRadius.circular(b.radiusMd),
          ),
          child: Column(children: [
            Icon(icon, color: selected ? scheme.primary : b.textMuted),
            SizedBox(height: b.spacing.xs),
            Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: selected ? scheme.primary : null)),
          ]),
        ),
      ),
    );
  }
}
