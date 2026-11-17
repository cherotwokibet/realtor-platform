import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';
import 'package:video_player/video_player.dart';

import '../providers.dart';
import '../search/results_map.dart' show mapTilesEnabledProvider;

/// One thing in a listing's gallery: a photo, or a video shown by its poster.
class GalleryItem {
  const GalleryItem.photo(this.image) : video = null;
  GalleryItem.video(ListingVideo this.video) : image = video.poster;
  final String image;
  final ListingVideo? video;
}

/// The photos, then the videos.
List<GalleryItem> galleryOf(ListingDetail d) => [for (final p in d.photos) GalleryItem.photo(p), for (final v in d.videos) GalleryItem.video(v)];

Widget _image(BuildContext context, String url, {BoxFit fit = BoxFit.cover, String? label}) => Image.network(
      url,
      fit: fit,
      semanticLabel: label,
      excludeFromSemantics: label == null,
      errorBuilder: (_, __, ___) => ColoredBox(color: context.brand.surfaceAlt),
    );

/// A video in place: its poster with a play mark until tapped (or at once
/// with [autoplay]), then the video itself, right there, with its controls.
/// No second screen opens.
class VideoTile extends StatefulWidget {
  const VideoTile({super.key, required this.video, required this.label, this.fit = BoxFit.cover, this.autoplay = false});
  final ListingVideo video;
  final String label;
  final BoxFit fit;
  final bool autoplay;

  @override
  State<VideoTile> createState() => _VideoTileState();
}

class _VideoTileState extends State<VideoTile> {
  late bool _playing = widget.autoplay;

  @override
  Widget build(BuildContext context) {
    if (_playing) return VideoPlayerView(video: widget.video, label: widget.label);
    return Semantics(
      button: true,
      label: 'Play ${widget.label}',
      child: InkWell(
        key: const Key('play-video'),
        onTap: () => setState(() => _playing = true),
        child: Stack(fit: StackFit.expand, children: [
          _image(context, widget.video.poster, fit: widget.fit),
          Center(child: Icon(Icons.play_circle_fill, size: 72, color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9))),
        ]),
      ),
    );
  }
}

/// Desktop: the first photo large on the left and the next three stacked on
/// the right, as on the big portals. Any photo opens the gallery; Map opens
/// it on the map; the last tile says how many there are.
class GalleryMosaic extends StatelessWidget {
  const GalleryMosaic({super.key, required this.items, required this.title, required this.onOpen, this.onMap, this.onVideo, this.verified = false});
  final List<GalleryItem> items;
  final String title;
  final ValueChanged<int> onOpen;

  /// Plays the first video straight away.
  final ValueChanged<int>? onVideo;
  final VoidCallback? onMap;
  final bool verified;

  static const height = 460.0;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(b.radiusMd);
    if (items.isEmpty) {
      return ClipRRect(
        borderRadius: radius,
        child: SizedBox(
          height: height,
          child: ColoredBox(
              color: b.surfaceAlt, child: Center(child: Icon(Icons.home_work_outlined, size: 64, color: b.textMuted, semanticLabel: 'No photos yet'))),
        ),
      );
    }
    Widget pill(String label, IconData icon, VoidCallback onTap, {Key? key}) => Material(
          color: scheme.inverseSurface.withValues(alpha: 0.75),
          shape: const StadiumBorder(),
          child: InkWell(
            key: key,
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: b.spacing.md, vertical: b.spacing.xs + 2),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 16, color: scheme.onInverseSurface),
                SizedBox(width: b.spacing.xs),
                Text(label, style: text.labelMedium?.copyWith(color: scheme.onInverseSurface, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        );
    Widget tile(int i) => Semantics(
          button: true,
          label: 'Open the gallery at photo ${i + 1} of ${items.length}',
          child: InkWell(
            onTap: () => onOpen(i),
            child: Stack(fit: StackFit.expand, children: [
              _image(context, items[i].image, label: i == 0 ? title : null),
              if (items[i].video != null) Center(child: Icon(Icons.play_circle_fill, size: 56, color: scheme.surface.withValues(alpha: 0.9))),
            ]),
          ),
        );
    final side = items.length - 1 > 3 ? 3 : items.length - 1;
    final hasVideo = items.any((i) => i.video != null);
    final count = pill('${items.length}', Icons.photo_camera_outlined, () => onOpen(0), key: const Key('gallery-count'));
    return ClipRRect(
      key: const ValueKey('listing-photos'),
      borderRadius: radius,
      child: SizedBox(
        height: height,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            flex: side == 0 ? 1 : 2,
            child: Stack(fit: StackFit.expand, children: [
              tile(0),
              if (verified) Positioned(left: b.spacing.md, top: b.spacing.md, child: const VerifiedBadge()),
              Positioned(
                left: b.spacing.md,
                bottom: b.spacing.md,
                child: Row(children: [
                  if (onMap != null) pill('Map', Icons.place_outlined, onMap!, key: const Key('gallery-map')),
                  if (hasVideo) ...[
                    SizedBox(width: b.spacing.sm),
                    pill('Video', Icons.play_arrow, () => (onVideo ?? onOpen)(items.indexWhere((i) => i.video != null)), key: const Key('gallery-video')),
                  ],
                ]),
              ),
              if (side == 0) Positioned(right: b.spacing.md, bottom: b.spacing.md, child: count),
            ]),
          ),
          if (side > 0) ...[
            SizedBox(width: b.spacing.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var i = 1; i <= side; i++) ...[
                  if (i > 1) SizedBox(height: b.spacing.sm),
                  Expanded(
                    child: Stack(fit: StackFit.expand, children: [
                      tile(i),
                      if (i == side) Positioned(right: b.spacing.md, bottom: b.spacing.md, child: count),
                    ]),
                  ),
                ],
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Phones: the photos across the width, to swipe; "2 / 8" says where you are
/// and a tap opens them full screen.
class PhotoStrip extends StatefulWidget {
  const PhotoStrip({super.key, required this.items, required this.title, required this.onOpen, this.verified = false});
  final List<GalleryItem> items;
  final String title;
  final ValueChanged<int> onOpen;
  final bool verified;

  @override
  State<PhotoStrip> createState() => _PhotoStripState();
}

class _PhotoStripState extends State<PhotoStrip> {
  int _at = 0;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final scheme = Theme.of(context).colorScheme;
    final items = widget.items;
    return AspectRatio(
      key: const ValueKey('listing-photos'),
      aspectRatio: 4 / 3,
      child: items.isEmpty
          ? ColoredBox(color: b.surfaceAlt, child: Center(child: Icon(Icons.home_work_outlined, size: 64, color: b.textMuted, semanticLabel: 'No photos yet')))
          : Stack(fit: StackFit.expand, children: [
              PageView.builder(
                itemCount: items.length,
                onPageChanged: (i) => setState(() => _at = i),
                itemBuilder: (context, i) => GestureDetector(
                  onTap: () => widget.onOpen(i),
                  child: Stack(fit: StackFit.expand, children: [
                    _image(context, items[i].image, label: '${widget.title}, ${items[i].video == null ? 'photo' : 'video'} ${i + 1} of ${items.length}'),
                    if (items[i].video != null) Center(child: Icon(Icons.play_circle_fill, size: 64, color: scheme.surface.withValues(alpha: 0.9))),
                  ]),
                ),
              ),
              if (widget.verified) Positioned(left: b.spacing.md, top: b.spacing.md, child: const VerifiedBadge()),
              if (items.length > 1)
                Positioned(
                  right: b.spacing.md,
                  bottom: b.spacing.md,
                  child: _Count(text: '${_at + 1} / ${items.length}'),
                ),
            ]),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(color: scheme.inverseSurface.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(b.radiusSm)),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: b.spacing.sm, vertical: 2),
        child: Text(text, key: const Key('photo-count'), style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onInverseSurface)),
      ),
    );
  }
}

/// The gallery window on wide screens, as on the big portals: Photos and Map
/// tabs, every photo in two columns (a click shows it full size), and the
/// listing's contact buttons along the bottom.
Future<void> showGallery(
  BuildContext context, {
  required List<GalleryItem> items,
  required String title,
  required Widget contact,
  double? lat,
  double? lng,
  bool map = false,
  int initial = 0,
}) =>
    showDialog<void>(
      context: context,
      builder: (context) => _GalleryDialog(items: items, title: title, contact: contact, lat: lat, lng: lng, startOnMap: map, initial: initial),
    );

class _GalleryDialog extends StatefulWidget {
  const _GalleryDialog({required this.items, required this.title, required this.contact, this.lat, this.lng, this.startOnMap = false, this.initial = 0});
  final List<GalleryItem> items;
  final String title;
  final Widget contact;
  final double? lat, lng;
  final bool startOnMap;

  /// The photo that was clicked: the window opens scrolled to it.
  final int initial;

  @override
  State<_GalleryDialog> createState() => _GalleryDialogState();
}

class _GalleryDialogState extends State<_GalleryDialog> {
  late bool _map = widget.startOnMap;
  final _grid = ScrollController();
  static const _gap = 8.0;
  double _tileWidth = 0;

  @override
  void initState() {
    super.initState();
    // Open where the visitor clicked, as the portals do: the row with that
    // photo at the top, once the grid has its size.
    if (widget.initial > 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_grid.hasClients) return;
        _grid.jumpTo(((widget.initial ~/ 2) * (_tileWidth * 9 / 16 + _gap)).clamp(0.0, _grid.position.maxScrollExtent));
      });
    }
  }

  @override
  void dispose() {
    _grid.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final items = widget.items;
    final hasMap = widget.lat != null && widget.lng != null;
    Widget tab(bool map, IconData icon, String label) {
      final on = _map == map;
      return Expanded(
        child: Material(
          color: on ? b.primarySoft : Colors.transparent,
          borderRadius: BorderRadius.circular(b.radiusSm),
          child: InkWell(
            key: Key(map ? 'gallery-tab-map' : 'gallery-tab-photos'),
            borderRadius: BorderRadius.circular(b.radiusSm),
            onTap: () => setState(() => _map = map),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: b.spacing.sm),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 18, color: on ? scheme.primary : b.textMuted),
                SizedBox(width: b.spacing.sm),
                Text(label, style: text.labelLarge?.copyWith(color: on ? scheme.primary : b.textMuted)),
              ]),
            ),
          ),
        ),
      );
    }

    return Dialog(
      key: const Key('gallery'),
      insetPadding: EdgeInsets.all(b.spacing.xl),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 760),
        child: Padding(
          padding: EdgeInsets.all(b.spacing.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(border: Border.all(color: b.borderStrong), borderRadius: BorderRadius.circular(b.radiusSm)),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Row(children: [
                      tab(false, Icons.photo_outlined, 'Photos (${items.length})'),
                      if (hasMap) tab(true, Icons.place_outlined, 'Map'),
                    ]),
                  ),
                ),
              ),
              SizedBox(width: b.spacing.sm),
              IconButton(tooltip: 'Close', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ]),
            SizedBox(height: b.spacing.md),
            Expanded(
              child: _map && hasMap
                  ? ClipRRect(borderRadius: BorderRadius.circular(b.radiusMd), child: ListingMap(lat: widget.lat!, lng: widget.lng!, title: widget.title))
                  : LayoutBuilder(builder: (context, box) {
                      _tileWidth = (box.maxWidth - _gap) / 2;
                      return GridView.builder(
                        controller: _grid,
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2, mainAxisSpacing: _gap, crossAxisSpacing: _gap, childAspectRatio: 16 / 9),
                        itemCount: items.length,
                        itemBuilder: (context, i) => DecoratedBox(
                          // The photo that was clicked stays marked.
                          position: DecorationPosition.foreground,
                          decoration: BoxDecoration(
                            border: i == widget.initial && widget.initial > 0 ? Border.all(color: scheme.primary, width: 3) : null,
                            borderRadius: BorderRadius.circular(b.radiusSm),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(b.radiusSm),
                            child: InkWell(
                              key: Key('gallery-photo-$i'),
                              onTap: () =>
                                  showPhotoViewer(context, items: items, title: widget.title, initial: i, fromGallery: true, autoplay: items[i].video != null),
                              child: Stack(fit: StackFit.expand, children: [
                                _image(context, items[i].image, label: '${widget.title}, ${items[i].video == null ? 'photo' : 'video'} ${i + 1}'),
                                if (items[i].video != null) Center(child: Icon(Icons.play_circle_fill, size: 56, color: scheme.surface.withValues(alpha: 0.9))),
                              ]),
                            ),
                          ),
                        ),
                      );
                    }),
            ),
            const Divider(height: 24),
            widget.contact,
          ]),
        ),
      ),
    );
  }
}

/// One photo at a time, full screen on a dark backdrop: arrows, the keys,
/// a swipe or a mouse drag move through them; "2 / 8" and a strip of
/// thumbnails show where you are. From the gallery it offers the way back.
Future<void> showPhotoViewer(BuildContext context,
        {required List<GalleryItem> items, required String title, int initial = 0, bool fromGallery = false, bool autoplay = false}) =>
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.92),
      transitionDuration: const Duration(milliseconds: 200),
      transitionBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      pageBuilder: (context, _, __) => _Viewer(items: items, title: title, initial: initial, fromGallery: fromGallery, autoplay: autoplay),
    );

class _Viewer extends StatefulWidget {
  const _Viewer({required this.items, required this.title, required this.initial, required this.fromGallery, this.autoplay = false});

  /// Start the video at [initial] playing, with no extra tap.
  final bool autoplay;
  final List<GalleryItem> items;
  final String title;
  final int initial;
  final bool fromGallery;

  @override
  State<_Viewer> createState() => _ViewerState();
}

class _ViewerState extends State<_Viewer> {
  late final _pages = PageController(initialPage: widget.initial);
  late final _thumbs = ScrollController();
  late int _at = widget.initial;
  static const _thumb = 88.0;

  @override
  void dispose() {
    _pages.dispose();
    _thumbs.dispose();
    super.dispose();
  }

  void _go(int to) {
    if (to < 0 || to >= widget.items.length) return;
    _pages.animateToPage(to, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  void _changed(int i) {
    setState(() => _at = i);
    // Keep the chosen thumbnail in view.
    if (_thumbs.hasClients) {
      final target = (i * (_thumb + 8) - (_thumbs.position.viewportDimension - _thumb) / 2).clamp(0.0, _thumbs.position.maxScrollExtent);
      _thumbs.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final items = widget.items;
    final n = items.length;
    final ink = scheme.surface;
    Widget arrow(IconData icon, String label, int to) => IconButton.filledTonal(
          key: Key(label),
          tooltip: label,
          iconSize: 28,
          onPressed: () => _go(to),
          icon: Icon(icon),
        );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _go(_at - 1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _go(_at + 1),
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(context),
      },
      child: Focus(
        autofocus: true,
        child: Material(
          key: const Key('photo-viewer'),
          type: MaterialType.transparency,
          child: SafeArea(
            child: Column(children: [
              Padding(
                padding: EdgeInsets.all(b.spacing.sm),
                child: Row(children: [
                  if (widget.fromGallery)
                    TextButton.icon(
                      key: const Key('back-to-gallery'),
                      style: TextButton.styleFrom(foregroundColor: ink, backgroundColor: ink.withValues(alpha: 0.12), shape: const StadiumBorder()),
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.chevron_left),
                      label: const Text('Back to gallery'),
                    ),
                  const Spacer(),
                  IconButton(tooltip: 'Close', color: ink, onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ]),
              ),
              Expanded(
                child: Stack(children: [
                  ScrollConfiguration(
                    // Flutter web leaves mouse dragging off for page views; turn it on.
                    behavior: ScrollConfiguration.of(context).copyWith(dragDevices: PointerDeviceKind.values.toSet()),
                    child: PageView.builder(
                      controller: _pages,
                      itemCount: n,
                      onPageChanged: _changed,
                      itemBuilder: (context, i) => Padding(
                        padding: EdgeInsets.symmetric(horizontal: b.spacing.xxl),
                        child: items[i].video != null
                            ? VideoTile(
                                key: ValueKey('video-$i'),
                                autoplay: widget.autoplay && i == widget.initial,
                                video: items[i].video!,
                                label: '${widget.title}, video ${items.take(i + 1).where((x) => x.video != null).length}',
                                fit: BoxFit.contain)
                            : _image(context, items[i].image, fit: BoxFit.contain, label: '${widget.title}, photo ${i + 1} of $n'),
                      ),
                    ),
                  ),
                  if (_at > 0) Positioned(left: b.spacing.sm, top: 0, bottom: 0, child: Center(child: arrow(Icons.chevron_left, 'Previous photo', _at - 1))),
                  if (_at < n - 1) Positioned(right: b.spacing.sm, top: 0, bottom: 0, child: Center(child: arrow(Icons.chevron_right, 'Next photo', _at + 1))),
                ]),
              ),
              Padding(
                padding: EdgeInsets.symmetric(vertical: b.spacing.sm),
                child: Text('${_at + 1} / $n', key: const Key('photo-count'), style: text.titleMedium?.copyWith(color: ink)),
              ),
              SizedBox(
                height: _thumb * 0.75,
                child: ListView.separated(
                  controller: _thumbs,
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: b.spacing.md),
                  itemCount: n,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) => GestureDetector(
                    onTap: () => _go(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: _thumb,
                      decoration: BoxDecoration(
                        border: Border.all(color: i == _at ? scheme.primary : Colors.transparent, width: 2),
                        borderRadius: BorderRadius.circular(b.radiusSm),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Opacity(opacity: i == _at ? 1 : 0.6, child: _image(context, items[i].image)),
                    ),
                  ),
                ),
              ),
              SizedBox(height: b.spacing.md),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Where the home is: the realtor's map tiles with a pin. Drag to move and
/// pinch to zoom; on a computer, the + and - buttons or Ctrl + scroll zoom
/// (a plain scroll keeps scrolling the page, as on the big portals), and
/// the corner button opens it full screen.
class ListingMap extends ConsumerStatefulWidget {
  const ListingMap({super.key, required this.lat, required this.lng, required this.title, this.fullScreen = false});
  final double lat, lng;
  final String title;
  final bool fullScreen;

  @override
  ConsumerState<ListingMap> createState() => _ListingMapState();
}

class _ListingMapState extends ConsumerState<ListingMap> {
  final _map = MapController();
  bool _hint = false;
  static const _start = 15.0;

  LatLng get _here => LatLng(widget.lat, widget.lng);

  void _zoom(double by) {
    final cam = _map.camera;
    _map.move(cam.center, (cam.zoom + by).clamp(3.0, 19.0));
  }

  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(tenantProvider);
    final scheme = Theme.of(context).colorScheme;
    final b = context.brand;
    Widget control(IconData icon, String tip, VoidCallback onTap, {Key? key}) => Material(
          color: scheme.surface,
          elevation: 2,
          borderRadius: BorderRadius.circular(b.radiusSm),
          child: IconButton(key: key, tooltip: tip, visualDensity: VisualDensity.compact, icon: Icon(icon), onPressed: onTap),
        );
    final map = FlutterMap(
      key: const Key('listing-map'),
      mapController: _map,
      options: MapOptions(
        initialCenter: _here,
        initialZoom: _start,
        minZoom: 3,
        maxZoom: 19,
        // Full screen: every gesture. In the page: wheel zoom only with Ctrl.
        interactionOptions: InteractionOptions(
          flags: widget.fullScreen
              ? InteractiveFlag.all & ~InteractiveFlag.rotate
              : InteractiveFlag.all & ~InteractiveFlag.scrollWheelZoom & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        if (ref.watch(mapTilesEnabledProvider)) TileLayer(urlTemplate: tenant.mapTiles, userAgentPackageName: tenant.androidId, maxZoom: 19),
        MarkerLayer(markers: [
          Marker(point: _here, width: 44, height: 44, alignment: Alignment.topCenter, child: Icon(Icons.location_on, size: 44, color: scheme.primary)),
        ]),
      ],
    );
    return Semantics(
      label: 'Map of where ${widget.title} is',
      child: Listener(
        onPointerSignal: (e) {
          if (widget.fullScreen || e is! PointerScrollEvent) return;
          if (HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed) {
            GestureBinding.instance.pointerSignalResolver.register(e, (_) => _zoom(e.scrollDelta.dy < 0 ? 1 : -1));
          } else if (!_hint) {
            setState(() => _hint = true);
            Future.delayed(const Duration(milliseconds: 1500), () {
              if (mounted) setState(() => _hint = false);
            });
          }
        },
        child: Stack(children: [
          Positioned.fill(child: map),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _hint ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: ColoredBox(
                  color: scheme.scrim.withValues(alpha: 0.45),
                  child: Center(
                    child: Text('Use Ctrl + scroll to zoom the map', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: scheme.surface)),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: b.spacing.sm,
            bottom: b.spacing.sm,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              control(Icons.my_location, 'Back to the home', () => _map.move(_here, _start)),
              SizedBox(height: b.spacing.sm),
              control(Icons.add, 'Zoom in', () => _zoom(1), key: const Key('map-zoom-in')),
              SizedBox(height: 2),
              control(Icons.remove, 'Zoom out', () => _zoom(-1), key: const Key('map-zoom-out')),
            ]),
          ),
          Positioned(
            right: b.spacing.sm,
            top: b.spacing.sm,
            child: widget.fullScreen
                ? control(Icons.close, 'Close', () => Navigator.pop(context))
                : control(Icons.fullscreen, 'Full screen map', key: const Key('map-full-screen'), () {
                    showDialog<void>(
                      context: context,
                      builder: (_) => Dialog.fullscreen(child: ListingMap(lat: widget.lat, lng: widget.lng, title: widget.title, fullScreen: true)),
                    );
                  }),
          ),
        ]),
      ),
    );
  }
}

/// Plays a listing video where it is: the poster shows while it loads
/// (no blank box), then it plays at once. The MP4 on the web (browsers
/// without HLS), the adaptive HLS stream on phones. Tap to pause or play;
/// the bar has play, a seek bar with the time, sound and full screen.
class VideoPlayerView extends StatefulWidget {
  const VideoPlayerView({super.key, required this.video, required this.label, this.fullScreen = false});
  final ListingVideo video;
  final String label;
  final bool fullScreen;

  @override
  State<VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<VideoPlayerView> {
  late final VideoPlayerController _player;
  String? _error;
  bool _controls = true;

  @override
  void initState() {
    super.initState();
    final v = widget.video;
    _player = VideoPlayerController.networkUrl(Uri.parse(kIsWeb && v.mp4 != null ? v.mp4! : v.hls))..addListener(_changed);
    _player.initialize().then((_) {
      // Browsers block sound before a click; the click that got here counts,
      // but start muted on the web if it is refused, so it always plays.
      _player.play().catchError((Object _) => _player.setVolume(0).then((_) => _player.play()));
      _hideSoon();
    }, onError: (Object _) {
      if (mounted) setState(() => _error = 'This video could not be played here.');
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _hideSoon() => Future.delayed(const Duration(seconds: 3), () {
        if (mounted && _player.value.isPlaying) setState(() => _controls = false);
      });

  @override
  void dispose() {
    _player
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  static String _time(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final value = _player.value;
    final scheme = Theme.of(context).colorScheme;
    final ink = scheme.surface;
    if (_error != null) {
      return ColoredBox(color: scheme.scrim, child: Center(child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: ink))));
    }
    final ready = value.isInitialized;
    return MouseRegion(
      onHover: (_) {
        if (!_controls) setState(() => _controls = true);
        _hideSoon();
      },
      child: GestureDetector(
        key: const Key('video-player'),
        onTap: () {
          if (!ready) return;
          value.isPlaying ? _player.pause() : _player.play();
          setState(() => _controls = true);
          _hideSoon();
        },
        child: ColoredBox(
          color: scheme.scrim,
          child: Stack(alignment: Alignment.center, children: [
            if (ready)
              Center(child: AspectRatio(aspectRatio: value.aspectRatio, child: VideoPlayer(_player)))
            else ...[
              Positioned.fill(child: _image(context, widget.video.poster, fit: BoxFit.contain, label: widget.label)),
              const CircularProgressIndicator(),
            ],
            if (ready && (value.isBuffering)) const CircularProgressIndicator(),
            if (ready)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: AnimatedOpacity(
                  opacity: _controls || !value.isPlaying ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                          begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [scheme.scrim.withValues(alpha: 0.75), Colors.transparent]),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 24, 8, 4),
                      child: Row(children: [
                        IconButton(
                          key: const Key('video-play-pause'),
                          tooltip: value.isPlaying ? 'Pause' : 'Play',
                          color: ink,
                          icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
                          onPressed: () => value.isPlaying ? _player.pause() : _player.play(),
                        ),
                        Text('${_time(value.position)} / ${_time(value.duration)}', style: TextStyle(color: ink, fontSize: 12)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: VideoProgressIndicator(
                            _player,
                            allowScrubbing: true,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            colors: VideoProgressColors(
                                playedColor: scheme.primary, bufferedColor: ink.withValues(alpha: 0.4), backgroundColor: ink.withValues(alpha: 0.2)),
                          ),
                        ),
                        IconButton(
                          tooltip: value.volume == 0 ? 'Sound on' : 'Mute',
                          color: ink,
                          icon: Icon(value.volume == 0 ? Icons.volume_off : Icons.volume_up),
                          onPressed: () => _player.setVolume(value.volume == 0 ? 1 : 0),
                        ),
                        if (!widget.fullScreen)
                          IconButton(
                            tooltip: 'Full screen',
                            color: ink,
                            icon: const Icon(Icons.fullscreen),
                            onPressed: () {
                              _player.pause();
                              showDialog<void>(
                                context: context,
                                builder: (_) => Dialog.fullscreen(
                                  backgroundColor: scheme.scrim,
                                  child: Stack(children: [
                                    Positioned.fill(child: VideoPlayerView(video: widget.video, label: widget.label, fullScreen: true)),
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: IconButton(tooltip: 'Close', color: ink, icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                                    ),
                                  ]),
                                ),
                              );
                            },
                          ),
                      ]),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
