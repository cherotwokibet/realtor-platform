import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:realtor_app/src/search/draw_area.dart';

/// Draw area's outline: corners join where they belong, so edges never cross.
void main() {
  const tl = LatLng(1, 0), tr = LatLng(1, 1), br = LatLng(0, 1), bl = LatLng(0, 0);

  test('a bowtie crosses; a square does not', () {
    expect(selfIntersects([tl, br, tr, bl]), isTrue);
    expect(selfIntersects([tl, tr, br, bl]), isFalse);
  });

  test('corners tapped in a crossing order still make a square', () {
    var c = <LatLng>[];
    for (final p in [tl, br, tr, bl]) {
      c = addCorner(c, p);
    }
    expect(selfIntersects(c), isFalse);
    expect(c.toSet(), {tl, tr, br, bl});
  });

  test('a new corner goes between its two nearest corners', () {
    final c = addCorner([tl, tr, br, bl], const LatLng(0.5, 1.2));
    expect(c.indexOf(const LatLng(0.5, 1.2)), c.indexOf(tr) + 1, reason: 'on the right edge, between top right and bottom right');
  });

  test('untangle leaves a good outline alone and sorts a crossed one', () {
    expect(untangle([tl, tr, br, bl]), [tl, tr, br, bl]);
    expect(selfIntersects(untangle([tl, br, tr, bl])), isFalse);
  });
}
