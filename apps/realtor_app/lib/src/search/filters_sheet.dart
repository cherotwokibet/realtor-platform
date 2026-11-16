import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';

import 'purpose.dart';

/// Which part of the filters a button on the results bar opens. [more] is
/// "More Filters": furnishing, features, amenities, verified, floor plans
/// and tours. The purpose and the location have their own controls in the bar.
enum FilterSection { type, beds, price, more }

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

/// Features of the home itself; the same words typed search understands.
/// (Furnished has its own All / Furnished / Unfurnished choice.)
const filterFeatures = <(String, String)>[
  ('balcony', 'Balcony'),
  ('garden', 'Garden'),
  ('parking', 'Parking'),
];

/// What the building or compound offers.
const filterAmenities = <(String, String)>[
  ('security', 'Security'),
  ('borehole', 'Borehole'),
  ('wifi', 'Wi-Fi'),
  ('lift', 'Lift'),
  ('gym', 'Gym'),
  ('swimming-pool', 'Swimming pool'),
];

/// What a location box holds: names of known areas become area filters;
/// anything else is searched as words.
(List<String> areas, String? q) parseLocation(String text, Map<String, String> areaNames) {
  final areas = <String>[];
  final words = <String>[];
  for (final part in text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty)) {
    final key = part.toLowerCase();
    final slug = areaNames.entries.where((e) => e.value.toLowerCase() == key || e.key == key.replaceAll(' ', '-')).map((e) => e.key).firstOrNull;
    slug == null ? words.add(part) : areas.add(slug);
  }
  return (areas, words.isEmpty ? null : words.join(' '));
}

/// The text a location box shows for [f].
String locationText(ListingFilters f) => [...f.areas.map(areaName), if (f.q != null) f.q!].join(', ');

/// Opens one part of the filters and returns the new filters, or null when
/// it was closed without "Show homes". On wide screens it drops down from
/// the button that opened it ([anchor]); on phones it is a bottom sheet.
Future<ListingFilters?> showFiltersSheet(BuildContext context, ListingFilters filters, {required FilterSection section, BuildContext? anchor}) {
  final screen = MediaQuery.sizeOf(context);
  final box = anchor?.findRenderObject();
  if (screen.width >= 840 && box is RenderBox && box.hasSize) {
    final at = box.localToGlobal(Offset.zero) & box.size;
    final width = section == FilterSection.more ? 440.0 : 380.0;
    // More Filters sits at the right end of the bar, so it opens leftwards.
    final left = (section == FilterSection.more ? at.right - width : at.left).clamp(8.0, screen.width - width - 8);
    final top = at.bottom + 6;
    return showDialog<ListingFilters>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (context) => Stack(children: [
        Positioned(
          left: left,
          top: top,
          width: width,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: screen.height - top - 16),
            child: Material(
              key: const Key('filter-popover'),
              elevation: 8,
              clipBehavior: Clip.antiAlias,
              borderRadius: BorderRadius.circular(context.brand.radiusMd),
              child: Padding(
                padding: EdgeInsets.only(top: context.brand.spacing.md),
                child: FiltersSheet(initial: filters, section: section),
              ),
            ),
          ),
        ),
      ]),
    );
  }
  return showModalBottomSheet<ListingFilters>(
    context: context,
    isScrollControlled: true,
    // Over the bottom tabs, as a sheet of its own.
    useRootNavigator: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => FiltersSheet(initial: filters, section: section),
  );
}

class FiltersSheet extends ConsumerStatefulWidget {
  const FiltersSheet({super.key, required this.initial, required this.section});
  final ListingFilters initial;
  final FilterSection section;

  @override
  ConsumerState<FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends ConsumerState<FiltersSheet> {
  late Set<String> _types = {...widget.initial.types};
  late int? _minBeds = widget.initial.minBeds;
  late final _min = TextEditingController(text: widget.initial.minPriceKES?.toString() ?? '');
  late final _max = TextEditingController(text: widget.initial.maxPriceKES?.toString() ?? '');
  late bool? _furnished = widget.initial.furnished ?? (widget.initial.amenities.contains('furnished') ? true : null);
  late Set<String> _amenities = {...widget.initial.amenities}..remove('furnished');
  late bool _verifiedFirst = widget.initial.verifiedFirst;
  late bool _verifiedOnly = widget.initial.verifiedOnly;
  late bool _floorPlan = widget.initial.floorPlan;
  late bool _tour = widget.initial.tour;

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  FilterSection get _section => widget.section;

  void _reset() => setState(() {
        switch (_section) {
          case FilterSection.type:
            _types = {};
          case FilterSection.beds:
            _minBeds = null;
          case FilterSection.price:
            _min.clear();
            _max.clear();
          case FilterSection.more:
            _furnished = null;
            _amenities = {};
            _verifiedFirst = _verifiedOnly = _floorPlan = _tour = false;
        }
      });

  static int? _kes(String s) => int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), ''));

  /// The filters with this section's choices; the rest stay as they were.
  ListingFilters _result() {
    final f = widget.initial;
    var min = _kes(_min.text), max = _kes(_max.text);
    if (min != null && max != null && min > max) (min, max) = (max, min);
    return ListingFilters(
      purpose: f.purpose,
      q: f.q,
      types: [..._types],
      areas: f.areas,
      minBeds: _minBeds,
      minPriceKES: min,
      maxPriceKES: max,
      amenities: [..._amenities],
      verifiedOnly: _verifiedOnly,
      verifiedFirst: _verifiedFirst,
      furnished: _furnished,
      floorPlan: _floorPlan,
      tour: _tour,
      near: f.near,
      polygon: f.polygon,
      sort: f.sort,
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final period = widget.initial.purpose.period;
    Widget heading(String s) => Padding(
          padding: EdgeInsets.only(top: b.spacing.lg, bottom: b.spacing.sm),
          child: Text(s, style: text.titleSmall),
        );
    Widget chips(List<(String, String)> options) => Wrap(spacing: b.spacing.sm, runSpacing: b.spacing.sm, children: [
          for (final (key, label) in options)
            FilterChip(
              label: Text(label),
              selected: _amenities.contains(key),
              onSelected: (on) => setState(() => on ? _amenities.add(key) : _amenities.remove(key)),
            ),
        ]);
    Widget tick(String label, bool value, ValueChanged<bool> onChanged, {String? note}) => CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(label),
          subtitle: note == null ? null : Text(note),
          value: value,
          onChanged: (v) => setState(() => onChanged(v ?? false)),
        );
    final title = switch (_section) {
      FilterSection.type => 'Property type',
      FilterSection.beds => 'Bedrooms',
      FilterSection.price => period == null ? 'Price (KES)' : 'Price a $period (KES)',
      FilterSection.more => 'More filters',
    };

    final sections = switch (_section) {
      FilterSection.type => <Widget>[
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
      FilterSection.beds => <Widget>[
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
      FilterSection.price => <Widget>[
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
      FilterSection.more => <Widget>[
          Text('Furnishing', style: text.titleSmall),
          SizedBox(height: b.spacing.sm),
          SegmentedButton<bool?>(
            key: const Key('filter-furnished'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: null, label: Text('All')),
              ButtonSegment(value: true, label: Text('Furnished')),
              ButtonSegment(value: false, label: Text('Unfurnished')),
            ],
            selected: {_furnished},
            onSelectionChanged: (s) => setState(() => _furnished = s.first),
          ),
          heading('Features'),
          chips(filterFeatures),
          heading('Amenities'),
          chips(filterAmenities),
          heading('Verified homes'),
          tick('Verified homes first', _verifiedFirst, (v) => _verifiedFirst = v, note: 'Homes our agents re-confirmed in the last 30 days, at the top.'),
          tick('Verified homes only', _verifiedOnly, (v) => _verifiedOnly = v),
          heading('Floor plans and virtual tours'),
          tick('Has a floor plan', _floorPlan, (v) => _floorPlan = v),
          tick('Has a video or virtual tour', _tour, (v) => _tour = v),
        ],
    };

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: b.spacing.gutter),
          child: Row(children: [
            Expanded(child: Text(title, style: text.titleMedium)),
            IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ]),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.fromLTRB(b.spacing.gutter, b.spacing.sm, b.spacing.gutter, b.spacing.lg),
            children: sections,
          ),
        ),
        const Divider(height: 1),
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
