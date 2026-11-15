import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';

import '../providers.dart';
import 'results_screen.dart';

/// Results as a list or on the map (P3-s04, P4-s02). Kept while filters
/// change, so drawing an area or removing a chip stays on the map.
class ResultsViewNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool map) => state = map;
}

final resultsOnMapProvider = NotifierProvider<ResultsViewNotifier, bool>(ResultsViewNotifier.new);

/// Map tiles load from the network; tests switch them off.
final mapTilesEnabledProvider = Provider<bool>((ref) => true);

/// "65K", "9.5K", "12.5M": a price short enough for a map pin.
String pinPrice(int kes) {
  String trim(double v) => v.toStringAsFixed(v < 100 ? 1 : 0).replaceAll(RegExp(r'\.0$'), '');
  if (kes >= 1000000) return '${trim(kes / 1000000)}M';
  if (kes >= 1000) return '${trim(kes / 1000)}K';
  return '$kes';
}

/// Nairobi CBD: where the map opens when there is nothing to show yet.
const _fallbackCentre = LatLng(-1.2864, 36.8172);

/// The results on an OpenStreetMap map (or the tenant's own tiles), one price
/// pin per home, and "Draw area": tap corners, then search inside them.
class ResultsMap extends ConsumerStatefulWidget {
  const ResultsMap({super.key, required this.hits, required this.filters, required this.onChange});
  final List<ListingSummary> hits;
  final ListingFilters filters;
  final ValueChanged<ListingFilters> onChange;

  @override
  ConsumerState<ResultsMap> createState() => _ResultsMapState();
}

class _ResultsMapState extends ConsumerState<ResultsMap> {
  bool _drawing = false;
  final _corners = <LatLng>[];
  ListingSummary? _selected;

  LatLng _ll(GeoPoint p) => LatLng(p.lat, p.lng);

  MapOptions _options() {
    final points = [
      for (final p in widget.filters.polygon) _ll(p),
      if (widget.filters.polygon.isEmpty)
        for (final l in widget.hits) LatLng(l.lat, l.lng),
    ];
    return MapOptions(
      initialCenter: points.isEmpty ? _fallbackCentre : points.first,
      initialZoom: 12,
      initialCameraFit: points.length < 2 ? null : CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(48), maxZoom: 15),
      minZoom: 5,
      maxZoom: 18,
      onTap: (_, at) => setState(() {
        if (_drawing) {
          if (_corners.length < maxPolygonPoints) _corners.add(at);
        } else {
          _selected = null;
        }
      }),
    );
  }

  void _search() {
    final area = [for (final c in _corners) roundedPoint(c.latitude, c.longitude)];
    setState(() {
      _drawing = false;
      _corners.clear();
    });
    widget.onChange(widget.filters.copyWith(polygon: area));
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final tenant = ref.watch(tenantProvider);
    final area = _drawing ? _corners : [for (final p in widget.filters.polygon) _ll(p)];
    return Stack(children: [
      FlutterMap(
        options: _options(),
        children: [
          if (ref.watch(mapTilesEnabledProvider)) TileLayer(urlTemplate: tenant.mapTiles, userAgentPackageName: tenant.androidId, maxZoom: 19),
          if (area.length >= 2)
            PolygonLayer(polygons: [
              Polygon(
                points: area,
                color: scheme.primary.withValues(alpha: 0.12),
                borderColor: scheme.primary,
                borderStrokeWidth: 2,
              ),
            ]),
          MarkerLayer(markers: [
            if (!_drawing)
              for (final l in widget.hits)
                Marker(
                  point: LatLng(l.lat, l.lng),
                  width: 72,
                  height: 32,
                  child: _Pin(label: pinPrice(l.priceKES), selected: _selected?.id == l.id, onTap: () => setState(() => _selected = l)),
                ),
            for (final c in _corners)
              Marker(
                point: c,
                width: 14,
                height: 14,
                child: DecoratedBox(
                    decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle, border: Border.all(color: scheme.onPrimary, width: 2))),
              ),
          ]),
          SimpleAttributionWidget(source: Text(tenant.mapAttribution, style: text.labelSmall)),
        ],
      ),
      Positioned(
        top: b.spacing.sm,
        left: b.spacing.sm,
        right: b.spacing.sm,
        child: Wrap(spacing: b.spacing.sm, runSpacing: b.spacing.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (!_drawing) ...[
            FilledButton.tonalIcon(
              onPressed: () => setState(() {
                _drawing = true;
                _selected = null;
              }),
              icon: const Icon(Icons.draw_outlined),
              label: Text(widget.filters.polygon.isEmpty ? 'Draw area' : 'Redraw area'),
            ),
            if (widget.filters.polygon.isNotEmpty)
              OutlinedButton(
                style: OutlinedButton.styleFrom(backgroundColor: scheme.surface),
                onPressed: () => widget.onChange(widget.filters.copyWith(polygon: const [])),
                child: const Text('Clear area'),
              ),
          ] else ...[
            Card(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: b.spacing.md, vertical: b.spacing.sm),
                child: Text(_corners.length < 3 ? 'Tap the map to mark the corners (${_corners.length} of at least 3)' : '${_corners.length} corners',
                    style: text.bodySmall),
              ),
            ),
            FilledButton(onPressed: _corners.length >= 3 ? _search : null, child: const Text('Search this area')),
            OutlinedButton(
              style: OutlinedButton.styleFrom(backgroundColor: scheme.surface),
              onPressed: _corners.isEmpty ? null : () => setState(_corners.removeLast),
              child: const Text('Undo'),
            ),
            TextButton(
              onPressed: () => setState(() {
                _drawing = false;
                _corners.clear();
              }),
              child: const Text('Cancel'),
            ),
          ],
        ]),
      ),
      if (_selected != null) Positioned(left: b.spacing.sm, right: b.spacing.sm, bottom: b.spacing.xl, child: ListingCard(listing: _selected!, compact: true)),
    ]);
  }
}

class _Pin extends StatelessWidget {
  const _Pin({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: b.spacing.sm, vertical: 2),
          decoration: BoxDecoration(
            color: selected ? b.accent : scheme.primary,
            borderRadius: BorderRadius.circular(b.radiusSm),
            border: Border.all(color: scheme.onPrimary),
          ),
          child: Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: selected ? b.onAccent : scheme.onPrimary)),
        ),
      ),
    );
  }
}
