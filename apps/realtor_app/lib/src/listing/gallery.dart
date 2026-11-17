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

/// A video's poster with a play mark; tapping plays it.
class VideoTile extends StatelessWidget {
  const VideoTile({super.key, required this.video, required this.label, this.fit = BoxFit.cover});
  final ListingVideo video;
  final String label;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Play $label',
        child: InkWell(
          key: const Key('play-video'),
          onTap: () => showDialog<void>(context: context, builder: (_) => VideoDialog(video: video)),
          child: Stack(fit: StackFit.expand, children: [
            _image(context, video.poster, fit: fit),
            Center(child: Icon(Icons.play_circle_fill, size: 72, color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9))),
          ]),
        ),
      );
}

/// Desktop: the first photo large on the left and the next three stacked on
/// the right, as on the big portals. Any photo opens the gallery; Map opens
/// it on the map; the last tile says how many there are.
class GalleryMosaic extends StatelessWidget {
  const GalleryMosaic({super.key, required this.items, required this.title, required this.onOpen, this.onMap, this.verified = false});
  final List<GalleryItem> items;
  final String title;
  final ValueChanged<int> onOpen;
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
                    pill('Video', Icons.play_arrow, () => onOpen(items.indexWhere((i) => i.video != null))),
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
}) =>
    showDialog<void>(
      context: context,
      builder: (context) => _GalleryDialog(items: items, title: title, contact: contact, lat: lat, lng: lng, startOnMap: map),
    );

class _GalleryDialog extends StatefulWidget {
  const _GalleryDialog({required this.items, required this.title, required this.contact, this.lat, this.lng, this.startOnMap = false});
  final List<GalleryItem> items;
  final String title;
  final Widget contact;
  final double? lat, lng;
  final bool startOnMap;

  @override
  State<_GalleryDialog> createState() => _GalleryDialogState();
}

class _GalleryDialogState extends State<_GalleryDialog> {
  late bool _map = widget.startOnMap;

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
                  : GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2, mainAxisSpacing: b.spacing.sm, crossAxisSpacing: b.spacing.sm, childAspectRatio: 16 / 9),
                      itemCount: items.length,
                      itemBuilder: (context, i) => ClipRRect(
                        borderRadius: BorderRadius.circular(b.radiusSm),
                        child: InkWell(
                          key: Key('gallery-photo-$i'),
                          onTap: () => showPhotoViewer(context, items: items, title: widget.title, initial: i, fromGallery: true),
                          child: Stack(fit: StackFit.expand, children: [
                            _image(context, items[i].image, label: '${widget.title}, ${items[i].video == null ? 'photo' : 'video'} ${i + 1}'),
                            if (items[i].video != null) Center(child: Icon(Icons.play_circle_fill, size: 56, color: scheme.surface.withValues(alpha: 0.9))),
                          ]),
                        ),
                      ),
                    ),
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
Future<void> showPhotoViewer(BuildContext context, {required List<GalleryItem> items, required String title, int initial = 0, bool fromGallery = false}) =>
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.92),
      transitionDuration: const Duration(milliseconds: 200),
      transitionBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      pageBuilder: (context, _, __) => _Viewer(items: items, title: title, initial: initial, fromGallery: fromGallery),
    );

class _Viewer extends StatefulWidget {
  const _Viewer({required this.items, required this.title, required this.initial, required this.fromGallery});
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

/// Where the home is: the realtor's map tiles with a pin. Scroll-wheel zoom
/// is off so the page scrolls past it.
class ListingMap extends ConsumerWidget {
  const ListingMap({super.key, required this.lat, required this.lng, required this.title});
  final double lat, lng;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(tenantProvider);
    final scheme = Theme.of(context).colorScheme;
    final here = LatLng(lat, lng);
    return Semantics(
      label: 'Map of where $title is',
      child: FlutterMap(
        key: const Key('listing-map'),
        options: MapOptions(
          initialCenter: here,
          initialZoom: 15,
          interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.scrollWheelZoom & ~InteractiveFlag.rotate),
        ),
        children: [
          if (ref.watch(mapTilesEnabledProvider)) TileLayer(urlTemplate: tenant.mapTiles, userAgentPackageName: tenant.androidId, maxZoom: 19),
          MarkerLayer(markers: [
            Marker(point: here, width: 40, height: 40, alignment: Alignment.topCenter, child: Icon(Icons.location_on, size: 40, color: scheme.primary)),
          ]),
        ],
      ),
    );
  }
}

/// Plays a listing video: the MP4 on the web (browsers without HLS), the
/// adaptive HLS stream on phones. Tap to pause or play.
class VideoDialog extends StatefulWidget {
  const VideoDialog({super.key, required this.video});
  final ListingVideo video;

  @override
  State<VideoDialog> createState() => _VideoDialogState();
}

class _VideoDialogState extends State<VideoDialog> {
  late final VideoPlayerController _player;
  String? _error;

  @override
  void initState() {
    super.initState();
    final v = widget.video;
    _player = VideoPlayerController.networkUrl(Uri.parse(kIsWeb && v.mp4 != null ? v.mp4! : v.hls))..addListener(_changed);
    _player.initialize().then((_) => _player.play(), onError: (Object _) {
      if (mounted) setState(() => _error = 'This video could not be played here.');
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _player
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = _player.value;
    return Dialog(
      insetPadding: EdgeInsets.all(context.brand.spacing.md),
      clipBehavior: Clip.antiAlias,
      child: Stack(alignment: Alignment.center, children: [
        AspectRatio(
          aspectRatio: value.isInitialized ? value.aspectRatio : 16 / 9,
          child: _error != null
              ? Center(child: Text(_error!, textAlign: TextAlign.center))
              : !value.isInitialized
                  ? const Center(child: CircularProgressIndicator())
                  : GestureDetector(
                      onTap: () => value.isPlaying ? _player.pause() : _player.play(),
                      child: Stack(alignment: Alignment.bottomCenter, children: [
                        VideoPlayer(_player),
                        VideoProgressIndicator(_player, allowScrubbing: true),
                        if (!value.isPlaying) const Center(child: Icon(Icons.play_arrow, size: 64)),
                      ]),
                    ),
        ),
        Positioned(
            top: 4, right: 4, child: IconButton.filledTonal(tooltip: 'Close', onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close))),
      ]),
    );
  }
}
