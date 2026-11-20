import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';

import '../account/account_screen.dart' show AlertButton;
import '../providers.dart';
import 'draw_area.dart';
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
  const ResultsMap({super.key, required this.hits, required this.filters, required this.onChange, this.inPage = false});
  final List<ListingSummary> hits;
  final ListingFilters filters;
  final ValueChanged<ListingFilters> onChange;

  /// True when the map sits in a page that scrolls (wide screens): the mouse
  /// wheel then scrolls the page and Ctrl + wheel zooms the map, as maps set
  /// in a web page do, with + and - buttons beside it.
  final bool inPage;

  @override
  ConsumerState<ResultsMap> createState() => _ResultsMapState();
}

class _ResultsMapState extends ConsumerState<ResultsMap> {
  bool _drawing = false;
  var _corners = <LatLng>[];

  /// The shapes before each change, for Undo.
  final _history = <List<LatLng>>[];

  /// A finger or the mouse is down on a corner: the map holds still while it moves.
  bool _holding = false;
  ListingSummary? _selected;
  final _controller = MapController();
  bool _hint = false;
  Timer? _hintTimer;

  @override
  void dispose() {
    _hintTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _zoomBy(double by, {Offset? at}) {
    final camera = _controller.camera;
    final zoom = (camera.zoom + by).clamp(5.0, 18.0);
    _controller.move(at == null ? camera.center : camera.focusedZoomCenter(at, zoom), zoom);
  }

  /// In a page: Ctrl (or Cmd) + wheel zooms; a plain wheel scrolls the page
  /// and says once how to zoom.
  void _wheel(PointerSignalEvent e) {
    // Browsers send Ctrl + wheel (and a trackpad pinch) as a scale.
    if (e is PointerScaleEvent) {
      if (e.scale > 0 && e.scale != 1) {
        GestureBinding.instance.pointerSignalResolver.register(e, (e) => _zoomBy(math.log((e as PointerScaleEvent).scale) / math.ln2, at: e.localPosition));
      }
      return;
    }
    if (e is! PointerScrollEvent || e.scrollDelta.dy == 0) return;
    final keys = HardwareKeyboard.instance;
    if (keys.isControlPressed || keys.isMetaPressed) {
      GestureBinding.instance.pointerSignalResolver.register(e, (e) => _zoomBy(-(e as PointerScrollEvent).scrollDelta.dy * 0.005, at: e.localPosition));
    } else {
      _hintTimer?.cancel();
      if (!_hint) setState(() => _hint = true);
      _hintTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _hint = false);
      });
    }
  }

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
      // In a page the wheel belongs to the page (Ctrl + wheel zooms, below).
      interactionOptions: InteractionOptions(
        flags: (widget.inPage ? InteractiveFlag.all & ~InteractiveFlag.scrollWheelZoom : InteractiveFlag.all) &
            (_holding ? ~(InteractiveFlag.drag | InteractiveFlag.flingAnimation | InteractiveFlag.pinchMove) : InteractiveFlag.all),
      ),
      onTap: (_, at) => setState(() {
        if (_drawing) {
          if (_corners.length < maxPolygonPoints) {
            _history.add(_corners);
            _corners = addCorner(_corners, at);
          }
        } else {
          _selected = null;
        }
      }),
    );
  }

  void _search() {
    final area = [for (final c in _corners) roundedPoint(c.latitude, c.longitude)];
    _stopDrawing();
    widget.onChange(widget.filters.copyWith(polygon: area));
  }

  void _stopDrawing() => setState(() {
        _drawing = false;
        _corners = [];
        _history.clear();
      });

  /// Moves corner [i] by a drag of [delta] on the screen.
  void _drag(int i, Offset delta) {
    final camera = _controller.camera;
    setState(() => _corners = [..._corners]..[i] = camera.screenOffsetToLatLng(camera.latLngToScreenOffset(_corners[i]) + delta));
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final tenant = ref.watch(tenantProvider);
    final area = _drawing ? _corners : [for (final p in widget.filters.polygon) _ll(p)];
    final map = FlutterMap(
      mapController: _controller,
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
          // Each corner can be dragged; let go and the outline is put back
          // in order if the move made its edges cross.
          for (final (i, c) in _corners.indexed)
            Marker(
              point: c,
              width: 40,
              height: 40,
              child: Listener(
                onPointerDown: (_) => setState(() => _holding = true),
                onPointerUp: (_) => setState(() => _holding = false),
                onPointerCancel: (_) => setState(() => _holding = false),
                child: GestureDetector(
                  key: Key('corner-$i'),
                  behavior: HitTestBehavior.opaque,
                  // The corner keeps up with the finger from where it pressed.
                  dragStartBehavior: DragStartBehavior.down,
                  onPanStart: (_) => _history.add(_corners),
                  onPanUpdate: (d) => _drag(i, d.delta),
                  onPanEnd: (_) => setState(() => _corners = untangle(_corners)),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.move,
                    child: Center(
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: scheme.onPrimary, width: 3),
                          boxShadow: [BoxShadow(color: scheme.scrim.withValues(alpha: 0.3), blurRadius: 4)],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ]),
        SimpleAttributionWidget(source: Text(tenant.mapAttribution, style: text.labelSmall)),
      ],
    );
    Widget zoomButton(IconData icon, String tip, double by) => IconButton(
          tooltip: tip,
          onPressed: () => _zoomBy(by),
          icon: Icon(icon),
          style: IconButton.styleFrom(shape: const RoundedRectangleBorder()),
        );
    return Stack(children: [
      if (widget.inPage) Listener(onPointerSignal: _wheel, child: map) else map,
      if (widget.inPage) ...[
        Positioned(
          right: b.spacing.sm,
          bottom: b.spacing.xl,
          child: Material(
            color: scheme.surface,
            elevation: 2,
            borderRadius: BorderRadius.circular(b.radiusSm),
            clipBehavior: Clip.antiAlias,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              zoomButton(Icons.add, 'Zoom in', 1),
              SizedBox(width: 40, child: Divider(height: 1, color: scheme.outlineVariant)),
              zoomButton(Icons.remove, 'Zoom out', -1),
            ]),
          ),
        ),
        // A plain wheel scrolls the page; this says how to zoom instead.
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: _hint ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: ColoredBox(
                color: scheme.scrim.withValues(alpha: 0.35),
                child: Center(
                  child: Text('Use Ctrl + scroll to zoom the map',
                      key: const Key('map-zoom-hint'), style: text.titleMedium?.copyWith(color: scheme.onPrimary, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ),
        ),
      ],
      Positioned(
        top: b.spacing.sm,
        left: b.spacing.sm,
        right: b.spacing.sm,
        child: !_drawing
            ? Wrap(spacing: b.spacing.sm, runSpacing: b.spacing.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
                FilledButton.tonalIcon(
                  onPressed: () => setState(() {
                    _drawing = true;
                    _selected = null;
                  }),
                  icon: const Icon(Icons.draw_outlined),
                  label: Text(widget.filters.polygon.isEmpty ? 'Draw area' : 'Redraw area'),
                ),
                if (widget.filters.polygon.isNotEmpty) ...[
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(backgroundColor: scheme.surface),
                    onPressed: () => widget.onChange(widget.filters.copyWith(polygon: const [])),
                    child: const Text('Clear area'),
                  ),
                  // The homes in a drawn area can be saved like any search, for alerts.
                  AlertButton(
                    filters: widget.filters,
                    builder: (save) => FilledButton.icon(
                      key: const Key('map-save-search'),
                      onPressed: save,
                      icon: const Icon(Icons.notifications_active_outlined, size: 18),
                      label: const Text('Save search'),
                    ),
                  ),
                ],
              ])
            // Drawing: one panel that says what to do, with Cancel, Undo and Search.
            : Material(
                key: const Key('draw-panel'),
                color: scheme.surface,
                elevation: 3,
                shadowColor: scheme.scrim.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(b.radiusMd),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(b.spacing.md, b.spacing.md, b.spacing.md, b.spacing.sm),
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.touch_app_outlined, size: 20, color: scheme.primary),
                      SizedBox(width: b.spacing.sm),
                      Expanded(
                        child: Text(
                          _corners.length < minDrawCorners
                              ? 'Tap the map to place at least $minDrawCorners corners (${_corners.length} of $minDrawCorners). Drag a corner to move it.'
                              : '${_corners.length} corners. Tap to add more, drag to move.',
                          key: const Key('draw-hint'),
                          style: text.bodyMedium,
                        ),
                      ),
                    ]),
                    SizedBox(height: b.spacing.sm),
                    Row(children: [
                      TextButton(onPressed: _stopDrawing, child: const Text('Cancel')),
                      TextButton.icon(
                        onPressed: _history.isEmpty ? null : () => setState(() => _corners = _history.removeLast()),
                        icon: const Icon(Icons.undo, size: 18),
                        label: const Text('Undo'),
                      ),
                      const Spacer(),
                      Flexible(
                        flex: 4,
                        child: FilledButton(
                          onPressed: _corners.length >= minDrawCorners ? _search : null,
                          child: const Text('Search this area', maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ]),
                  ]),
                ),
              ),
      ),
      if (_selected != null)
        Positioned(left: b.spacing.sm, right: b.spacing.sm, bottom: b.spacing.xl, child: ListingCard(listing: _selected!, layout: CardLayout.compact)),
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
