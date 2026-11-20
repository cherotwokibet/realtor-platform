import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtor_app/src/app.dart';
import 'package:realtor_app/src/providers.dart';
import 'package:latlong2/latlong.dart';
import 'package:realtor_app/src/search/draw_area.dart';
import 'package:realtor_app/src/search/results_map.dart';
import 'package:realtor_core/realtor_core.dart';

import 'feature_flags_test.dart' show tenantWith;

/// Map search (P3-s04, P4-s02): results on the map, and a drawn area filters them.
void main() {
  String path(WidgetTester t) => ProviderScope.containerOf(t.element(find.byType(RealtorApp))).read(routerProvider).state.uri.toString();

  Future<void> openResults(WidgetTester tester, String location, {Size size = const Size(800, 1400)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [tenantProvider.overrideWithValue(tenantWith({})), mapTilesEnabledProvider.overrideWithValue(false)],
      child: const RealtorApp(),
    ));
    await tester.pumpAndSettle();
    ProviderScope.containerOf(tester.element(find.byType(RealtorApp))).read(routerProvider).go(location);
    await tester.pumpAndSettle();
  }

  test('pin prices are short', () {
    expect(pinPrice(65000), '65K');
    expect(pinPrice(9500), '9.5K');
    expect(pinPrice(12500000), '12.5M');
    expect(pinPrice(800), '800');
  });

  testWidgets('Map shows a price pin per home; a pin opens its card', (tester) async {
    await openResults(tester, '/rent');
    await tester.tap(find.byTooltip('Map'));
    await tester.pumpAndSettle();
    expect(find.text('65K'), findsOneWidget, reason: '2 bedroom apartment, Kilimani');
    await tester.tap(find.text('65K'));
    await tester.pumpAndSettle();
    expect(find.text('2 bedroom apartment, Kilimani'), findsOneWidget);
    await tester.tap(find.byTooltip('List'));
    await tester.pumpAndSettle();
    expect(find.text('Draw area'), findsNothing);
  });

  testWidgets('Draw area: four corners at least, never crossing, each can be dragged; then save the search', (tester) async {
    await openResults(tester, '/rent');
    await tester.tap(find.byTooltip('Map'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Draw area'));
    await tester.pumpAndSettle();
    Future<void> tapMap(Offset o) async {
      await tester.tapAt(tester.getRect(find.byType(ResultsMap)).center + o);
      // The map waits out the double-tap window before reporting a tap.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
    }

    FilledButton search() => tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Search this area'));
    // Tapped in a crossing order: top left, bottom right, top right, bottom left.
    for (final o in [const Offset(-150, -100), const Offset(150, 200), const Offset(150, -100)]) {
      await tapMap(o);
    }
    expect(search().onPressed, isNull, reason: 'needs $minDrawCorners corners');
    expect(find.textContaining('3 of 4'), findsOneWidget);
    await tapMap(const Offset(-150, 200));
    expect(find.text('4 corners. Tap to add more, drag to move.'), findsOneWidget);
    expect(search().onPressed, isNotNull);

    // Drag a corner; Undo puts it back.
    final before = tester.getCenter(find.byKey(const Key('corner-0')));
    final other = tester.getCenter(find.byKey(const Key('corner-2')));
    // As a finger does: press, a frame, then move in steps.
    final finger = await tester.startGesture(before);
    await tester.pump();
    for (var k = 0; k < 5; k++) {
      await finger.moveBy(const Offset(-8, -6));
      await tester.pump();
    }
    await finger.up();
    await tester.pumpAndSettle();
    expect(tester.getCenter(find.byKey(const Key('corner-2'))), other, reason: 'the map held still');
    expect((tester.getCenter(find.byKey(const Key('corner-0'))) - before).distance, moreOrLessEquals(50, epsilon: 1),
        reason: 'the corner followed the finger all the way');
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect((tester.getCenter(find.byKey(const Key('corner-0'))) - before).distance, lessThan(1));

    await tester.tap(find.text('Search this area'));
    await tester.pumpAndSettle();
    final area = ListingFilters.fromUri(Uri.parse(path(tester)))!.polygon;
    expect(area, hasLength(4));
    expect(selfIntersects([for (final p in area) LatLng(p.lat, p.lng)]), isFalse, reason: 'the outline does not cross itself');
    expect(find.widgetWithText(InputChip, 'Drawn area'), findsOneWidget);

    // The drawn search can be saved: signed out, Account asks to sign in first.
    await tester.tap(find.byKey(const Key('map-save-search')));
    await tester.pumpAndSettle();
    expect(path(tester), '/account');
  });

  testWidgets('Clear area drops the drawn area', (tester) async {
    await openResults(tester, '/rent?poly=-1.20,36.88~-1.20,36.92~-1.24,36.92~-1.24,36.88');
    await tester.tap(find.byTooltip('Map'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear area'));
    await tester.pumpAndSettle();
    expect(path(tester), isNot(contains('poly=')));
  });

  testWidgets('a shared link with a drawn area filters the homes', (tester) async {
    // A triangle around Kasarani only.
    await openResults(tester, '/rent?poly=-1.20,36.88~-1.20,36.92~-1.24,36.90');
    expect(find.text('Student hostel bed, Kasarani'), findsOneWidget);
    expect(find.text('2 bedroom apartment, Kilimani'), findsNothing);
  });
  testWidgets('wide: the map fits the window and the page scrolls with the window scrollbar', (tester) async {
    await openResults(tester, '/rent', size: const Size(1366, 800));
    await tester.tap(find.text('Map').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('window-scrollbar')), findsOneWidget);
    final fit = tester.getRect(find.byKey(const Key('results-map-fit')));
    expect(fit.bottom, moreOrLessEquals(800), reason: 'the heading and the map just fill the window');
    expect(tester.getRect(find.byType(ResultsMap)).height, greaterThan(400));
    // The arrow scrolls the page down to the footer.
    final before = tester.getTopLeft(find.byType(ResultsMap)).dy;
    await tester.tap(find.byKey(const Key('scroll-down')));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byType(ResultsMap)).dy, lessThan(before));
    // The wheel over the map scrolls the page too, and says how to zoom.
    final mid = tester.getRect(find.byType(ResultsMap)).center, top = tester.getTopLeft(find.byType(ResultsMap)).dy;
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(mid));
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, 120)));
    await tester.pump();
    expect(tester.getTopLeft(find.byType(ResultsMap)).dy, lessThan(top));
    expect(tester.widget<AnimatedOpacity>(find.ancestor(of: find.byKey(const Key('map-zoom-hint')), matching: find.byType(AnimatedOpacity))).opacity, 1);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    // Ctrl + wheel reaches Flutter as a scale (as browsers send it) and zooms the map; so does +.
    double spread() => (tester.getCenter(find.text('110K')) - tester.getCenter(find.text('65K'))).distance;
    final wide = spread();
    await tester.sendEventToBinding(mouse.hover(tester.getRect(find.byType(ResultsMap)).center));
    await tester.sendEventToBinding(mouse.scale(2));
    await tester.pumpAndSettle();
    expect(spread(), moreOrLessEquals(wide * 2, epsilon: 2));
    await tester.tap(find.byTooltip('Zoom out'));
    await tester.pumpAndSettle();
    expect(spread(), moreOrLessEquals(wide, epsilon: 2));
    expect(find.byTooltip('Zoom in'), findsOneWidget);
  });
}
