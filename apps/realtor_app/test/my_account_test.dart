import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtor_app/src/account/account_data.dart';
import 'package:realtor_app/src/account/account_screen.dart';
import 'package:realtor_app/src/account/activity.dart';
import 'package:realtor_app/src/app.dart';
import 'package:realtor_app/src/providers.dart';
import 'package:realtor_app/src/search/demo_search.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'listing_screen_test.dart' show tenant;

class MemoryActivity implements ActivityStore {
  final kept = <ActivityKind, List<ActivityEntry>>{};
  @override
  Future<List<ActivityEntry>> load(ActivityKind kind) async => kept[kind] ?? const [];
  @override
  Future<void> save(ActivityKind kind, List<ActivityEntry> entries) async => kept[kind] = entries;
}

late DemoAccount account;
late MemoryActivity activity;
final opened = <Uri>[];

Future<ProviderContainer> open(WidgetTester tester, String path, {bool signedIn = true}) async {
  tester.view.physicalSize = const Size(412, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (signedIn) await account.signInWithGoogle();
  final c = ProviderContainer(overrides: [
    tenantProvider.overrideWithValue(tenant()),
    demoAccountProvider.overrideWithValue(account),
    activityStoreProvider.overrideWithValue(activity),
    urlOpenerProvider.overrideWithValue((u) async {
      opened.add(u);
      return true;
    }),
  ]);
  addTearDown(c.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const RealtorApp()));
  await tester.pumpAndSettle();
  c.read(routerProvider).go(path);
  await tester.pumpAndSettle();
  return c;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    account = DemoAccount();
    activity = MemoryActivity();
    opened.clear();
  });

  testWidgets('My account, as on Bayut: Hi and Edit Profile, My Activity, the site pages, Sign out at the foot', (tester) async {
    await open(tester, '/account');
    expect(find.byKey(const Key('scroll-away-bar')), findsNothing, reason: 'no top bar with the logo');
    expect(find.text('Hi there'), findsOneWidget);
    expect(find.byKey(const Key('edit-profile')), findsOneWidget);
    expect(find.text('My Activity'), findsOneWidget);
    expect(find.text('More from Realtime Estates Ltd'), findsOneWidget);
    final signOut = find.text('Sign out');
    expect(tester.getTopLeft(signOut).dy, greaterThan(tester.getTopLeft(find.text('Terms')).dy), reason: 'at the bottom');
  });

  testWidgets('Edit Profile checks the WhatsApp number, saves the name, sets a password; Hi uses the name', (tester) async {
    final c = await open(tester, '/account');
    await tester.tap(find.byKey(const Key('edit-profile')));
    await tester.pumpAndSettle();
    expect(c.read(routerProvider).state.uri.path, '/account/edit');
    expect(find.text('Password'), findsOneWidget, reason: 'a Google account has no password to set');

    await tester.enterText(find.byKey(const Key('profile-name')), 'Amina Wanjiru');
    await tester.enterText(find.byKey(const Key('profile-whatsapp')), '12345');
    await tester.tap(find.byKey(const Key('save-profile')));
    await tester.pumpAndSettle();
    expect(find.text('Enter a Kenyan mobile number, e.g. 0712 345 678'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('profile-whatsapp')), '0712 345 678');
    await tester.tap(find.byKey(const Key('save-profile')));
    await tester.pumpAndSettle();
    final p = await account.load();
    expect(p.name, 'Amina Wanjiru');
    expect(p.whatsapp, '+254712345678', reason: 'stored as +254…');
    expect(c.read(routerProvider).state.uri.path, '/account');
    expect(find.text('Hi, Amina Wanjiru'), findsOneWidget);
  });

  testWidgets('an email account sets a password (8+, typed twice) and can delete the account', (tester) async {
    await account.completeSignInLink(Uri.parse('https://x/?mode=signIn&oobCode=1'), 'amina@example.com');
    final c = await open(tester, '/account/edit', signedIn: false);
    expect(find.text('Set a password'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('profile-name')), 'Amina');
    await tester.enterText(find.byKey(const Key('profile-password')), 'short');
    await tester.tap(find.byKey(const Key('save-profile')));
    await tester.pumpAndSettle();
    expect(find.text('At least 8 characters'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('profile-password')), 'long enough 1');
    await tester.enterText(find.byKey(const Key('profile-password-confirm')), 'long enough 2');
    await tester.tap(find.byKey(const Key('save-profile')));
    await tester.pumpAndSettle();
    expect(find.text('The passwords do not match'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('profile-password-confirm')), 'long enough 1');
    await tester.tap(find.byKey(const Key('save-profile')));
    await tester.pumpAndSettle();
    expect((await account.load()).hasPassword, isTrue);

    // Signed out, the password signs in again.
    await account.signOut();
    c.read(routerProvider).go('/account');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('use-password')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('email')), 'amina@example.com');
    await tester.enterText(find.byKey(const Key('password')), 'long enough 1');
    await tester.tap(find.byKey(const Key('password-sign-in')));
    await tester.pumpAndSettle();
    expect(c.read(customerProvider).value?.email, 'amina@example.com');

    c.read(routerProvider).go('/account/edit');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('delete-account')));
    await tester.tap(find.byKey(const Key('delete-account')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-delete')));
    await tester.pumpAndSettle();
    expect(account.deleted, isTrue);
    expect(c.read(customerProvider).value, isNull);
    expect(c.read(routerProvider).state.uri.path, '/');
  });

  testWidgets('My Activity: recent searches, the homes viewed, and the ones contacted, by day', (tester) async {
    final home = demoListings.first;
    activity.kept[ActivityKind.viewed] = [(home: home, at: DateTime.now(), channel: null)];
    activity.kept[ActivityKind.contacted] = [(home: home, at: DateTime(2026, 3, 7, 10), channel: 'whatsapp')];
    final c = await open(tester, '/account');
    await tester.tap(find.byKey(const Key('my-activity')));
    await tester.pumpAndSettle();
    expect(c.read(routerProvider).state.uri.path, '/account/activity');
    expect(find.text('Your searches will show here.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('activity-viewed')));
    await tester.pumpAndSettle();
    expect(find.text('Today'), findsOneWidget);
    expect(find.text(home.title), findsOneWidget);
    await tester.tap(find.byKey(const Key('activity-contacted')));
    await tester.pumpAndSettle();
    expect(find.text('7th March, 2026'), findsOneWidget);
    expect(find.text('WhatsApp'), findsOneWidget);
  });

  testWidgets('opening a home records the view', (tester) async {
    final home = demoListings.first;
    await open(tester, '/listing/${home.slug}');
    expect(activity.kept[ActivityKind.viewed]!.single.home.id, home.id);
  });

  test('day headings and initials', () {
    final now = DateTime(2026, 11, 19, 12);
    expect(activityDay(DateTime(2026, 11, 19, 8), now), 'Today');
    expect(activityDay(DateTime(2026, 11, 18, 23), now), 'Yesterday');
    expect(activityDay(DateTime(2026, 11, 15), now), '15th November, 2026');
    expect(activityDay(DateTime(2026, 11, 22), DateTime(2026, 11, 30)), '22nd November, 2026');
    expect(initialsOf('Amina Wanjiru'), 'AW');
    expect(initialsOf('amina@example.com'), 'A');
  });

  testWidgets('Saved: Favourites first by default, Searches second; a plain bar with "Saved"', (tester) async {
    await account.saveSearch('demo-customer', const ListingFilters(purpose: Purpose.rent, areas: ['kilimani']));
    await open(tester, '/saved');
    expect(find.text('Saved'), findsWidgets);
    expect(find.byKey(const Key('scroll-away-bar')), findsNothing, reason: 'no logo bar');
    expect(find.textContaining('No saved homes yet'), findsOneWidget);
    await tester.tap(find.byKey(const Key('saved-tab-searches')));
    await tester.pumpAndSettle();
    expect(find.text('Homes to rent'), findsOneWidget);
    expect(find.text('Kilimani'), findsOneWidget);
  });

  testWidgets('the phone menu: initials, icons, Download the app, no Company or Get in touch; Log out only when signed in', (tester) async {
    final c = await open(tester, '/');
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    final drawer = find.byKey(const Key('app-drawer'));
    expect(find.descendant(of: drawer, matching: find.text('D')), findsOneWidget, reason: 'initials of demo@example.com');
    expect(find.descendant(of: drawer, matching: find.byIcon(Icons.home_outlined)), findsOneWidget);
    for (final gone in ['COMPANY', 'GET IN TOUCH', 'Privacy', 'Terms', 'About us']) {
      expect(find.descendant(of: drawer, matching: find.text(gone)), findsNothing, reason: gone);
    }
    expect(find.text('Download the Realtime Estates Ltd app'), findsOneWidget);
    await tester.tap(find.byKey(const Key('badge-google-play')));
    await tester.pumpAndSettle();
    expect(opened.last.host, 'play.google.com');

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('drawer-logout')));
    await tester.pumpAndSettle();
    expect(c.read(customerProvider).value, isNull);
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('drawer-logout')), findsNothing);
  });

  testWidgets('the phone top bar says Saved in words, not a solid block', (tester) async {
    await open(tester, '/rent');
    expect(find.descendant(of: find.byKey(const Key('top-saved')), matching: find.text('Saved')), findsOneWidget);
    expect(tester.widget(find.byKey(const Key('top-saved'))), isA<TextButton>());
  });

  testWidgets('Log in / Sign up opens over the page, as on Bayut: Google, or email; switches to creating an account; closes once signed in', (tester) async {
    final c = await open(tester, '/', signedIn: false);
    tester.view.physicalSize = const Size(1400, 900);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-login')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sign-in-dialog')), findsOneWidget);
    expect(find.text('Log in to your Realtime Estates Ltd account'), findsOneWidget);
    expect(find.text('Log in with Google'), findsOneWidget);
    expect(find.byKey(const Key('use-link')), findsOneWidget);
    expect(find.byKey(const Key('use-password')), findsOneWidget);

    await tester.tap(find.byKey(const Key('auth-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Create your Realtime Estates Ltd account'), findsOneWidget);
    expect(find.text('Join with Google'), findsOneWidget);
    expect(find.textContaining('When creating a new account you agree to Realtime Estates Ltd', findRichText: true), findsOneWidget);
    await tester.tap(find.byKey(const Key('link-terms')));
    await tester.pumpAndSettle();
    expect(opened.last.toString(), 'https://realtimeestates.co.ke/terms');
    await tester.tap(find.byKey(const Key('link-privacy')));
    await tester.pumpAndSettle();
    expect(opened.last.toString(), 'https://realtimeestates.co.ke/privacy');
    expect(find.byKey(const Key('use-password')), findsNothing, reason: 'a password is set later, in Edit Profile');

    await tester.tap(find.byKey(const Key('use-link')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('email')), 'amina@example.com');
    await tester.tap(find.byKey(const Key('send-link')));
    await tester.pumpAndSettle();
    expect(account.sentLinks, ['amina@example.com']);
    expect(find.textContaining('Check amina@example.com'), findsOneWidget);

    await tester.tap(find.byKey(const Key('google')));
    await tester.pumpAndSettle();
    expect(c.read(customerProvider).value, isNotNull);
    expect(find.byKey(const Key('sign-in-dialog')), findsNothing, reason: 'closes once signed in');
  });

  testWidgets('phones: Log in opens the same panel from the bottom', (tester) async {
    await open(tester, '/', signedIn: false);
    await tester.tap(find.byKey(const Key('home-login')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sign-in-sheet')), findsOneWidget);
    await tester.tap(find.byKey(const Key('sign-in-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sign-in-sheet')), findsNothing);
  });
}
