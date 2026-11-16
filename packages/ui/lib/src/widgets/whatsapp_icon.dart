import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The WhatsApp glyph (a speech bubble with a handset), which Material's
/// icon set lacks. Takes its colour and size from the icon theme, like
/// [Icon], so it sits in a button the same way.
class WhatsAppIcon extends StatelessWidget {
  const WhatsAppIcon({super.key, this.size, this.color});
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final s = size ?? theme.size ?? 24;
    final c = color ?? theme.color ?? DefaultTextStyle.of(context).style.color!;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: s,
        child: Stack(alignment: Alignment.center, children: [
          Positioned.fill(child: CustomPaint(painter: _Bubble(c))),
          Icon(Icons.call, size: s * 0.5, color: c),
        ]),
      ),
    );
  }
}

class _Bubble extends CustomPainter {
  const _Bubble(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide, w = s * 0.09;
    final centre = Offset(s / 2, s / 2), r = s / 2 - w;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    // A ring, open at the bottom left, where the tail runs out to the corner.
    const from = math.pi * 0.86, sweep = math.pi * 1.78;
    final a = centre + Offset(math.cos(from), math.sin(from)) * r;
    final b = centre + Offset(math.cos(from + sweep), math.sin(from + sweep)) * r;
    canvas.drawPath(
      Path()
        ..moveTo(a.dx, a.dy)
        ..arcTo(Rect.fromCircle(center: centre, radius: r), from, sweep, false)
        ..lineTo(w, s - w)
        ..lineTo(b.dx, b.dy)
        ..close(),
      stroke,
    );
  }

  @override
  bool shouldRepaint(_Bubble old) => old.color != color;
}
