import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:realtor_core/realtor_core.dart' as core;
import 'package:realtor_ui/realtor_ui.dart';

import 'providers.dart';

/// Map tiles load from the network; tests switch them off.
final adminMapTilesProvider = Provider<bool>((ref) => true);

LatLng _ll(core.GeoPoint p) => LatLng(p.lat, p.lng);
core.GeoPoint _gp(LatLng p) => core.GeoPoint(p.latitude, p.longitude);

/// The tiles, the zoom buttons and the attribution every admin map shares.
class _BaseMap extends ConsumerWidget {
  const _BaseMap({required this.controller, required this.options, required this.layers, this.height = 320});
  final MapController controller;
  final MapOptions options;
  final List<Widget> layers;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(tenantProvider);
    final b = context.brand;
    final scheme = Theme.of(context).colorScheme;
    void zoom(double by) {
      final c = controller.camera;
      controller.move(c.center, (c.zoom + by).clamp(5.0, 19.0));
    }

    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(b.radiusMd),
        child: Stack(children: [
          FlutterMap(
            mapController: controller,
            options: options,
            children: [
              if (ref.watch(adminMapTilesProvider)) TileLayer(urlTemplate: tenant.mapTiles, userAgentPackageName: tenant.androidId, maxZoom: 19),
              ...layers,
              SimpleAttributionWidget(source: Text(tenant.mapAttribution, style: Theme.of(context).textTheme.labelSmall)),
            ],
          ),
          Positioned(
            right: 8,
            top: 8,
            child: Material(
              color: scheme.surface,
              elevation: 2,
              borderRadius: BorderRadius.circular(b.radiusSm),
              clipBehavior: Clip.antiAlias,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                IconButton(tooltip: 'Zoom in', onPressed: () => zoom(1), icon: const Icon(Icons.add)),
                IconButton(tooltip: 'Zoom out', onPressed: () => zoom(-1), icon: const Icon(Icons.remove)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// A listing's position: tap the map or drag the pin. The chosen area's
/// outline shows, so it is plain when the pin falls outside it.
class PinMap extends StatefulWidget {
  const PinMap({super.key, required this.pin, required this.onPin, this.outline = const [], this.centre});
  final core.GeoPoint? pin;
  final ValueChanged<core.GeoPoint> onPin;
  final List<core.GeoPoint> outline;

  /// Where to look with no pin yet (the area's centre).
  final core.GeoPoint? centre;

  @override
  State<PinMap> createState() => _PinMapState();
}

class _PinMapState extends State<PinMap> {
  final _controller = MapController();
  bool _holding = false;

  @override
  void didUpdateWidget(PinMap old) {
    super.didUpdateWidget(old);
    // A pin from elsewhere (a pasted link, a new area): bring it into view.
    final p = widget.pin;
    if (p != null && p != old.pin && !_holding) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.move(_ll(p), _controller.camera.zoom < 14 ? 15 : _controller.camera.zoom);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final start = widget.pin ?? widget.centre ?? const core.GeoPoint(-1.2864, 36.8172);
    return _BaseMap(
      controller: _controller,
      options: MapOptions(
        initialCenter: _ll(start),
        initialZoom: widget.pin == null ? 13 : 15,
        minZoom: 5,
        maxZoom: 19,
        interactionOptions: InteractionOptions(
          flags: (InteractiveFlag.all & ~InteractiveFlag.rotate) & (_holding ? ~(InteractiveFlag.drag | InteractiveFlag.flingAnimation) : InteractiveFlag.all),
        ),
        onTap: (_, at) => widget.onPin(_gp(at)),
      ),
      layers: [
        if (widget.outline.length >= 3)
          PolygonLayer(polygons: [
            Polygon(
              points: [for (final p in widget.outline) _ll(p)],
              color: scheme.primary.withValues(alpha: 0.08),
              borderColor: scheme.primary,
              borderStrokeWidth: 2,
            ),
          ]),
        if (widget.pin != null)
          MarkerLayer(markers: [
            Marker(
              point: _ll(widget.pin!),
              width: 44,
              height: 44,
              alignment: Alignment.topCenter,
              child: Listener(
                onPointerDown: (_) => setState(() => _holding = true),
                onPointerUp: (_) => setState(() => _holding = false),
                onPointerCancel: (_) => setState(() => _holding = false),
                child: GestureDetector(
                  key: const Key('listing-pin'),
                  dragStartBehavior: DragStartBehavior.down,
                  onPanUpdate: (d) {
                    final c = _controller.camera;
                    widget.onPin(_gp(c.screenOffsetToLatLng(c.latLngToScreenOffset(_ll(widget.pin!)) + d.delta)));
                  },
                  child: MouseRegion(cursor: SystemMouseCursors.grab, child: Icon(Icons.location_on, size: 44, color: scheme.primary)),
                ),
              ),
            ),
          ]),
      ],
    );
  }
}

/// An area's outline (geofence): tap to add corners, which join where they
/// belong so the edges never cross; drag a corner to move it. Other areas'
/// outlines show faintly, to draw up to them.
class OutlineMap extends StatefulWidget {
  const OutlineMap({super.key, required this.outline, required this.onOutline, required this.centre, this.others = const []});
  final List<core.GeoPoint> outline;
  final ValueChanged<List<core.GeoPoint>> onOutline;
  final core.GeoPoint centre;
  final List<List<core.GeoPoint>> others;

  @override
  State<OutlineMap> createState() => _OutlineMapState();
}

class _OutlineMapState extends State<OutlineMap> {
  final _controller = MapController();
  bool _holding = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _drag(int i, Offset delta) {
    final c = _controller.camera;
    final moved = [...widget.outline]..[i] = _gp(c.screenOffsetToLatLng(c.latLngToScreenOffset(_ll(widget.outline[i])) + delta));
    widget.onOutline(moved);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final b = context.brand;
    return _BaseMap(
      controller: _controller,
      height: 380,
      options: MapOptions(
        initialCameraFit: widget.outline.length >= 3
            ? CameraFit.coordinates(coordinates: [for (final p in widget.outline) _ll(p)], padding: const EdgeInsets.all(40), maxZoom: 16)
            : null,
        initialCenter: _ll(widget.centre),
        initialZoom: 14,
        minZoom: 5,
        maxZoom: 19,
        interactionOptions: InteractionOptions(
          flags: (InteractiveFlag.all & ~InteractiveFlag.rotate) & (_holding ? ~(InteractiveFlag.drag | InteractiveFlag.flingAnimation) : InteractiveFlag.all),
        ),
        onTap: (_, at) {
          if (widget.outline.length < 60) widget.onOutline(core.addOutlineCorner(widget.outline, _gp(at)));
        },
      ),
      layers: [
        PolygonLayer(polygons: [
          for (final o in widget.others)
            if (o.length >= 3)
              Polygon(
                  points: [for (final p in o) _ll(p)],
                  color: b.textMuted.withValues(alpha: 0.06),
                  borderColor: b.textMuted.withValues(alpha: 0.5),
                  borderStrokeWidth: 1),
          if (widget.outline.length >= 2)
            Polygon(
              points: [for (final p in widget.outline) _ll(p)],
              color: scheme.primary.withValues(alpha: 0.12),
              borderColor: scheme.primary,
              borderStrokeWidth: 2,
            ),
        ]),
        MarkerLayer(markers: [
          Marker(point: _ll(widget.centre), width: 16, height: 16, child: Icon(Icons.add_circle, size: 16, color: b.accent)),
          for (final (i, p) in widget.outline.indexed)
            Marker(
              point: _ll(p),
              width: 36,
              height: 36,
              child: Listener(
                onPointerDown: (_) => setState(() => _holding = true),
                onPointerUp: (_) => setState(() => _holding = false),
                onPointerCancel: (_) => setState(() => _holding = false),
                child: GestureDetector(
                  key: Key('outline-corner-$i'),
                  behavior: HitTestBehavior.opaque,
                  dragStartBehavior: DragStartBehavior.down,
                  onPanUpdate: (d) => _drag(i, d.delta),
                  onPanEnd: (_) => widget.onOutline(core.untangleOutline(widget.outline)),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.move,
                    child: Center(
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle, border: Border.all(color: scheme.onPrimary, width: 3)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ],
    );
  }
}
