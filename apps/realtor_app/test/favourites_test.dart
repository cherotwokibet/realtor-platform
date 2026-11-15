import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtor_app/src/account/account_data.dart';
import 'package:realtor_app/src/app.dart';
import 'package:realtor_app/src/providers.dart';
import 'package:realtor_app/src/saved/favourites.dart';
import 'package:realtor_app/src/search/demo_search.dart';
import 'package:realtor_core/realtor_core.dart';

import 'listing_screen_test.dart' show tenant;

class MemoryStore implements FavouritesStore {
  MemoryStore([List<String>? rows]) : rows = rows ?? [];
  List<String> rows;
  @override
  Future<List<String>> load() async => rows;
  @override
  Future<void> save(List<String> rows) async => this.rows = rows;
}

Future<ProviderContainer> open(WidgetTester tester, MemoryStore store, String path, {DemoAccount? account}) async {
  tester.view.physicalSize = const Size(412, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final c = ProviderContainer(overrides: [
    tenantProvider.overrideWithValue(tenant()),
    favouritesStoreProvider.overrideWithValue(store),
    if (account != null) demoAccountProvider.overrideWithValue(account),
  ]);
  addTearDown(c.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const RealtorApp()));
  await tester.pumpAndSettle();
  c.read(routerProvider).go(path);
  await tester.pumpAndSettle();
  return c;
}

void main() {
  final first = demoListings.first;

  test('a saved row survives the round trip; a damaged one is skipped', () {
    final back = ListingSummary.fromJson(first.toJson())!;
    expect((back.id, back.slug, back.priceKES, back.purpose, back.verified), (first.id, first.slug, first.priceKES, first.purpose, first.verified));
    expect(ListingSummary.fromJson({'id': 'x'}), isNull);
    expect(ListingSummary.fromJson('nope'), isNull);
  });

  testWidgets('signed out: the heart saves on the device and says to sign in; Saved asks to sign in', (tester) async {
    final store = MemoryStore();
    final c = await open(tester, store, '/listing/${first.slug}');
    await tester.tap(find.byTooltip('Save this home'));
    await tester.pumpAndSettle();
    expect(store.rows, hasLength(1));
    expect(find.text('Saved on this device. Sign in to see your saved homes.'), findsOneWidget);
    c.read(routerProvider).go('/saved');
    await tester.pumpAndSettle();
    expect(find.text('Sign in to see the homes you have saved.'), findsOneWidget);
    expect(find.text(first.title), findsNothing);
  });

  testWidgets('a heart on the listing saves it on the device; Saved lists it; the heart removes it', (tester) async {
    final store = MemoryStore(['{broken']);
    final account = DemoAccount();
    await account.signInWithGoogle();
    final c = await open(tester, store, '/listing/${first.slug}', account: account);
    await tester.tap(find.byTooltip('Save this home'));
    await tester.pumpAndSettle();
    expect(store.rows, hasLength(1));
    expect(find.byTooltip('Remove from saved'), findsOneWidget);
    expect(find.textContaining('Sign in to see'), findsNothing, reason: 'already signed in');

    c.read(routerProvider).go('/saved');
    await tester.pumpAndSettle();
    expect(find.text('Saved homes'), findsOneWidget);
    expect(find.text(first.title), findsOneWidget);
    await tester.tap(find.byTooltip('Remove from saved'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Tap the heart on a home'), findsOneWidget);
    expect(store.rows, isEmpty);
  });
}
