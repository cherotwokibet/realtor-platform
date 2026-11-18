import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';

import '../providers.dart';
import 'purpose.dart';

/// Which dropdown of the results bar is open. [more] is "More Filters":
/// viewing options, and features and amenities. [all] is every one of them
/// in one sheet (the filters button on phones). Furnishing, the sort and
/// verified-first sit over the list instead; the location has its own box.
enum FilterSection { type, bedsBaths, price, more, all }

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

/// Room types that are their own "bedroom" count, offered first under Beds.
const filterRoomTypes = <(String, String)>[('single-room', 'Single room'), ('studio', 'Studio'), ('bedsitter', 'Bedsitter')];

/// Features and amenities people filter by; the same words typed search
/// understands. (Furnished is the All / Furnished / Unfurnished choice over the list.)
const filterAmenities = <(String, String)>[
  ('parking', 'Parking'),
  ('security', 'Security'),
  ('borehole', 'Borehole'),
  ('wifi', 'Wi-Fi'),
  ('balcony', 'Balcony'),
  ('garden', 'Garden'),
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

/// "2000" shows as "2,000" while it is typed.
class ThousandsFormatter extends TextInputFormatter {
  const ThousandsFormatter();

  static String format(String digits) {
    final d = digits.replaceAll(RegExp(r'[^0-9]'), '').replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final out = StringBuffer();
    for (var i = 0; i < d.length; i++) {
      if (i > 0 && (d.length - i) % 3 == 0) out.write(',');
      out.write(d[i]);
    }
    return out.toString();
  }

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = format(newValue.text);
    // Keep the cursor after the same number of digits.
    final digitsBefore = newValue.text.substring(0, newValue.selection.end.clamp(0, newValue.text.length)).replaceAll(RegExp(r'[^0-9]'), '').length;
    var at = 0, seen = 0;
    while (at < text.length && seen < digitsBefore) {
      if (text[at] != ',') seen++;
      at++;
    }
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: at));
  }
}

/// Opens one dropdown of the results bar and returns the new filters, or
/// null when it was closed without "Done". On wide screens it drops down from
/// the button that opened it ([anchor]), as on the big portals; on phones it
/// is a bottom sheet.
Future<ListingFilters?> showFiltersSheet(BuildContext context, ListingFilters filters, {required FilterSection section, BuildContext? anchor}) {
  final screen = MediaQuery.sizeOf(context);
  final box = anchor?.findRenderObject();
  if (screen.width >= 840 && box is RenderBox && box.hasSize) {
    final at = box.localToGlobal(Offset.zero) & box.size;
    final width = switch (section) { FilterSection.type => 380.0, FilterSection.more => 360.0, _ => 340.0 };
    // More Filters sits at the right end of the bar, so it opens leftwards.
    final left = (section == FilterSection.more ? at.right - width : at.left).clamp(8.0, screen.width - width - 8);
    final top = at.bottom + 4;
    // It eases down out of its button, as a menu does.
    return showGeneralDialog<ListingFilters>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 180),
      transitionBuilder: (_, animation, __, child) {
        final eased = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
        return FadeTransition(
          opacity: eased,
          child: SlideTransition(position: Tween(begin: const Offset(0, -0.015), end: Offset.zero).animate(eased), child: child),
        );
      },
      pageBuilder: (context, _, __) => Stack(children: [
        Positioned(
          left: left,
          top: top,
          width: width,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: (screen.height - top - 16).clamp(200.0, 560.0)),
            child: Material(
              key: const Key('filter-popover'),
              elevation: 6,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(context.brand.radiusSm),
                side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: FiltersSheet(initial: filters, section: section, popover: true),
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
    // Lean, as on the portals' apps: no handle; one part of the filters has
    // no close button either (tap outside or Done).
    showDragHandle: false,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(context.brand.radiusMd * 2))),
    sheetAnimationStyle: const AnimationStyle(duration: Duration(milliseconds: 260), reverseDuration: Duration(milliseconds: 200)),
    builder: (_) => FiltersSheet(initial: filters, section: section),
  );
}

class FiltersSheet extends ConsumerStatefulWidget {
  const FiltersSheet({super.key, required this.initial, required this.section, this.popover = false});
  final ListingFilters initial;
  final FilterSection section;

  /// Dropped down from its button on a wide screen: no title or close
  /// button, as a menu would have none.
  final bool popover;

  @override
  ConsumerState<FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends ConsumerState<FiltersSheet> {
  late Set<String> _types = {...widget.initial.types};
  // An older "2+" link reads as 2 and every count above it.
  late Set<int> _beds = {
    ...widget.initial.beds,
    if (widget.initial.beds.isEmpty && widget.initial.minBeds != null)
      for (var n = widget.initial.minBeds!.clamp(1, maxBedsChoice); n <= maxBedsChoice; n++) n,
  };
  late Set<int> _baths = {...widget.initial.baths};
  late final _min = TextEditingController(text: ThousandsFormatter.format(widget.initial.minPriceKES?.toString() ?? ''));
  late final _max = TextEditingController(text: ThousandsFormatter.format(widget.initial.maxPriceKES?.toString() ?? ''));
  late Set<String> _amenities = {...widget.initial.amenities}..remove('furnished');
  late bool _floorPlan = widget.initial.floorPlan;
  late bool _video = widget.initial.video;
  late bool _tour = widget.initial.tour;

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  FilterSection get _section => widget.section;

  bool _covers(FilterSection s) => _section == s || _section == FilterSection.all;

  void _reset() => setState(() {
        for (final s in FilterSection.values) {
          if (s != FilterSection.all && _covers(s)) _resetOne(s);
        }
      });

  void _resetOne(FilterSection section) {
    switch (section) {
      case FilterSection.type:
        _types = {};
      case FilterSection.bedsBaths:
        _types.removeAll([for (final (t, _) in filterRoomTypes) t]);
        _beds = {};
        _baths = {};
      case FilterSection.price:
        _min.clear();
        _max.clear();
      case FilterSection.more:
        _amenities = {};
        _floorPlan = _video = _tour = false;
      case FilterSection.all:
        break;
    }
  }

  static int? _kes(String s) => int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), ''));

  /// The filters with this dropdown's choices; the rest stay as they were.
  ListingFilters _result() {
    final f = widget.initial;
    var min = _kes(_min.text), max = _kes(_max.text);
    if (min != null && max != null && min > max) (min, max) = (max, min);
    return ListingFilters(
      purpose: f.purpose,
      q: f.q,
      types: [
        for (final (t, _) in filterTypes)
          if (_types.contains(t)) t
      ],
      areas: f.areas,
      // Beds & Baths replaces an older "2+" choice.
      minBeds: _covers(FilterSection.bedsBaths) ? null : f.minBeds,
      beds: _beds.toList()..sort(),
      baths: _baths.toList()..sort(),
      minPriceKES: min,
      maxPriceKES: max,
      amenities: [if (f.amenities.contains('furnished')) 'furnished', ..._amenities],
      verifiedOnly: f.verifiedOnly,
      verifiedFirst: f.verifiedFirst,
      furnished: f.furnished,
      floorPlan: _floorPlan,
      video: _video,
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
    final scheme = Theme.of(context).colorScheme;
    final period = widget.initial.purpose.period;
    var first = true;
    Widget heading(String s) {
      final top = first ? 0.0 : b.spacing.lg;
      first = false;
      return Padding(padding: EdgeInsets.only(top: top, bottom: b.spacing.sm), child: Text(s, style: text.titleSmall));
    }

    // Pills as the portals draw them: outlined, filled softly once picked.
    Widget pill(String label, bool on, ValueChanged<bool> onTap, {Key? key}) => FilterChip(
          key: key,
          label: Text(label),
          selected: on,
          showCheckmark: false,
          shape: const StadiumBorder(),
          side: BorderSide(color: on ? scheme.primary : b.borderStrong),
          selectedColor: b.primarySoft,
          labelStyle: text.bodyMedium?.copyWith(color: on ? scheme.primary : null, fontWeight: on ? FontWeight.w600 : null),
          onSelected: (v) => setState(() => onTap(v)),
        );
    Widget pills(List<Widget> xs) => Wrap(spacing: b.spacing.sm, runSpacing: b.spacing.sm, children: xs);
    String count(int n, int max) => n == max ? '$n+' : '$n';
    Widget priceField(String label, String hint, TextEditingController c, Key key) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: text.labelMedium?.copyWith(color: b.textMuted)),
            SizedBox(height: b.spacing.xs),
            TextField(
              key: key,
              controller: c,
              keyboardType: TextInputType.number,
              inputFormatters: const [ThousandsFormatter()],
              decoration: InputDecoration(hintText: hint, isDense: true),
            ),
          ]),
        );
    final title = switch (_section) {
      FilterSection.type => 'Property type',
      FilterSection.bedsBaths => 'Beds & Baths',
      FilterSection.price => period == null ? 'Price (KES)' : 'Price a $period (KES)',
      FilterSection.more => 'More filters',
      FilterSection.all => 'Filters',
    };

    List<Widget> part(FilterSection section) => switch (section) {
          FilterSection.type => <Widget>[
              if (_section == FilterSection.all) heading('Property type'),
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
          FilterSection.bedsBaths => <Widget>[
              heading('Beds'),
              pills([
                for (final (type, label) in filterRoomTypes) pill(label, _types.contains(type), (on) => on ? _types.add(type) : _types.remove(type)),
                for (var n = 1; n <= maxBedsChoice; n++)
                  pill(count(n, maxBedsChoice), _beds.contains(n), (on) => on ? _beds.add(n) : _beds.remove(n), key: Key('beds-$n')),
              ]),
              heading('Baths'),
              pills([
                for (var n = 1; n <= maxBathsChoice; n++)
                  pill(count(n, maxBathsChoice), _baths.contains(n), (on) => on ? _baths.add(n) : _baths.remove(n), key: Key('baths-$n')),
              ]),
            ],
          FilterSection.price => <Widget>[
              if (widget.popover || _section == FilterSection.all)
                heading(_section == FilterSection.all ? (period == null ? 'Price (KES)' : 'Price a $period (KES)') : title),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                priceField('Minimum', '0', _min, const Key('filter-min-price')),
                SizedBox(width: b.spacing.md),
                priceField('Maximum', 'Any', _max, const Key('filter-max-price')),
              ]),
            ],
          FilterSection.more => <Widget>[
              heading('Viewing options'),
              pills([
                pill('Floor plans', _floorPlan, (v) => _floorPlan = v),
                pill('Video tours', _video, (v) => _video = v),
                pill('360° tours', _tour, (v) => _tour = v),
              ]),
              heading('Features & Amenities'),
              pills([
                for (final (key, label) in filterAmenities) pill(label, _amenities.contains(key), (on) => on ? _amenities.add(key) : _amenities.remove(key))
              ]),
            ],
          FilterSection.all => const <Widget>[],
        };
    final sections = _section == FilterSection.all
        ? [
            for (final s in [FilterSection.type, FilterSection.bedsBaths, FilterSection.price, FilterSection.more]) ...part(s)
          ]
        : part(_section);
    // The whole sheet says how many homes its choices find, as the portals do.
    final found = _section == FilterSection.all ? ref.watch(searchResultsProvider(_result())).value?.found : null;

    final pad = widget.popover ? b.spacing.md : b.spacing.gutter;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (!widget.popover)
          Padding(
            padding: EdgeInsets.fromLTRB(pad, b.spacing.lg, b.spacing.sm, 0),
            child: SizedBox(
              height: 40,
              child: Row(children: [
                Expanded(child: Text(title, style: text.titleMedium)),
                // Only the sheet with every filter, which is tall, has a close button.
                if (_section == FilterSection.all) IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ]),
            ),
          ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.fromLTRB(pad, widget.popover ? b.spacing.md : b.spacing.sm, pad, b.spacing.md),
            children: sections,
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(pad, b.spacing.sm, pad, pad),
          child: Row(children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: scheme.primary, side: BorderSide(color: scheme.primary)),
                onPressed: _reset,
                child: Text(_section == FilterSection.all ? 'Reset all filters' : 'Reset'),
              ),
            ),
            SizedBox(width: b.spacing.md),
            Expanded(
              flex: _section == FilterSection.all ? 2 : 1,
              child: FilledButton(
                key: const Key('filters-done'),
                onPressed: () => Navigator.pop(context, _result()),
                child: Text(found == null ? 'Done' : 'See $found ${found == 1 ? 'home' : 'homes'}'),
              ),
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
