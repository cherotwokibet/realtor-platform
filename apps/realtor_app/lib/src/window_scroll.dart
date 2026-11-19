import 'dart:async';

import 'package:flutter/material.dart';
import 'package:realtor_ui/realtor_ui.dart';

/// A page that scrolls with a scrollbar like a browser's, as on Bayut: a
/// lane of its own at the window's right edge (so the page's bars and lines
/// stop at it instead of running under it), an arrow at each end, and a
/// thumb sized to the page but never longer than a third of the lane.
///
/// [child] scrolls with `primary: true`; off ([enabled] false, phones) it is
/// left as it is.
class WindowScroll extends StatefulWidget {
  const WindowScroll({super.key, required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;

  /// The lane's width.
  static const width = 16.0;

  @override
  State<WindowScroll> createState() => _WindowScrollState();
}

class _WindowScrollState extends State<WindowScroll> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: PrimaryScrollController(
          controller: _controller,
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
            // The page grows as homes load: the thumb follows.
            child: NotificationListener<ScrollMetricsNotification>(
              onNotification: (n) {
                if (n.depth == 0) setState(() {});
                return false;
              },
              child: widget.child,
            ),
          ),
        ),
      ),
      _Lane(controller: _controller),
    ]);
  }
}

class _Lane extends StatefulWidget {
  const _Lane({required this.controller});
  final ScrollController controller;

  @override
  State<_Lane> createState() => _LaneState();
}

class _LaneState extends State<_Lane> {
  Timer? _repeat;
  bool _hover = false, _dragging = false;

  /// How far one press of an arrow moves the page.
  static const _step = 60.0;
  static const _minThumb = 36.0;

  ScrollPosition? get _position => widget.controller.hasClients ? widget.controller.position : null;

  void _by(double dy, {bool animate = true}) {
    final p = _position;
    if (p == null) return;
    final to = (p.pixels + dy).clamp(p.minScrollExtent, p.maxScrollExtent);
    animate ? p.animateTo(to, duration: const Duration(milliseconds: 120), curve: Curves.easeOut) : p.jumpTo(to);
  }

  /// One step now, then steadily while the arrow is held.
  void _hold(double dir) {
    _by(dir * _step);
    _repeat?.cancel();
    _repeat = Timer(const Duration(milliseconds: 350), () {
      _repeat = Timer.periodic(const Duration(milliseconds: 50), (_) => _by(dir * _step / 2, animate: false));
    });
  }

  void _release() {
    _repeat?.cancel();
    _repeat = null;
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final p = _position;
        final ready = p != null && p.hasContentDimensions && p.hasViewportDimension;
        final max = ready ? p.maxScrollExtent : 0.0;
        final scrolls = max > 0;
        Widget arrow(IconData icon, String tip, double dir, Key key) {
          final on = scrolls && (dir < 0 ? p!.pixels > p.minScrollExtent : p!.pixels < max);
          return Tooltip(
            message: tip,
            waitDuration: const Duration(seconds: 1),
            child: GestureDetector(
              key: key,
              behavior: HitTestBehavior.opaque,
              onTapDown: on ? (_) => _hold(dir) : null,
              onTapUp: (_) => _release(),
              onTapCancel: _release,
              child: SizedBox(
                width: WindowScroll.width,
                height: WindowScroll.width,
                child: Icon(dir < 0 ? Icons.arrow_drop_up : Icons.arrow_drop_down, size: 18, color: on ? b.textMuted : scheme.outlineVariant),
              ),
            ),
          );
        }

        return Container(
          key: const Key('window-scrollbar'),
          width: WindowScroll.width,
          // The page's own colour and no dividing line, as Bayut's: only the arrows and the thumb show.
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Column(children: [
            arrow(Icons.arrow_drop_up, 'Scroll up', -1, const Key('scroll-up')),
            Expanded(
              child: LayoutBuilder(builder: (context, box) {
                if (!scrolls) return const SizedBox.expand();
                final track = box.maxHeight;
                final vp = p!.viewportDimension;
                // Sized to the page, as browsers do, but kept short and easy to grab.
                final len = (track * vp / (vp + max)).clamp(_minThumb, track / 3);
                final room = track - len;
                final top = room * (p.pixels / max).clamp(0.0, 1.0);
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  // A click on the lane pages up or down, as in a browser.
                  onTapUp: (d) => _by((d.localPosition.dy < top ? -1 : 1) * vp * 0.9),
                  child: Stack(children: [
                    Positioned(
                      top: top,
                      left: 4,
                      right: 4,
                      height: len,
                      child: MouseRegion(
                        onEnter: (_) => setState(() => _hover = true),
                        onExit: (_) => setState(() => _hover = false),
                        child: GestureDetector(
                          key: const Key('scroll-thumb'),
                          onVerticalDragStart: (_) => setState(() => _dragging = true),
                          onVerticalDragEnd: (_) => setState(() => _dragging = false),
                          onVerticalDragUpdate: (d) => _by(room <= 0 ? 0 : d.delta.dy * max / room, animate: false),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: _hover || _dragging ? b.textMuted : b.textMuted.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ]),
                );
              }),
            ),
            arrow(Icons.arrow_drop_down, 'Scroll down', 1, const Key('scroll-down')),
          ]),
        );
      },
    );
  }
}
