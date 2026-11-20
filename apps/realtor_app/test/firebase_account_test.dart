import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtor_app/src/account/account_data.dart';
import 'package:realtor_app/src/firebase/firebase_account.dart';
import 'package:realtor_core/realtor_core.dart';

void main() {
  test('saved searches are written as the rules expect and read back; alerts newest first, read and cleared', () async {
    final db = FakeFirebaseFirestore();
    final alerts = FirestoreAlerts(db);
    await alerts.saveSearch('alice', const ListingFilters(purpose: Purpose.rent, areas: ['kilimani'], maxPriceKES: 60000, q: 'ignored'));
    final doc = (await db.collection('savedSearches').get()).docs.single.data();
    expect(doc['userId'], 'alice');
    expect(doc['filters'], {
      'purpose': 'rent',
      'areas': ['kilimani'],
      'maxPriceKES': 60000
    });
    expect(doc['channels'], ['inbox']);
    expect(doc['lastNotifiedAt'], isNull);
    final rows = await alerts.searches('alice').first;
    expect(rows.single.filters.areas, ['kilimani']);

    final a = db.collection('users').doc('alice').collection('alerts');
    await a.doc('old').set(
        {'slug': 's1', 'title': 'Old', 'priceKES': 1, 'purpose': 'rent', 'area': 'x', 'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1)), 'readAt': null});
    await a.doc('new').set(
        {'slug': 's2', 'title': 'New', 'priceKES': 2, 'purpose': 'sale', 'area': 'y', 'createdAt': Timestamp.fromDate(DateTime(2026, 10, 29)), 'readAt': null});
    expect((await alerts.alerts('alice').first).map((x) => x.title), ['New', 'Old']);
    await alerts.markRead('alice', 'new');
    expect((await alerts.alerts('alice').first).first.read, isTrue);
    await alerts.clear('alice', 'old');
    expect((await alerts.alerts('alice').first).map((x) => x.id), ['new']);
    await alerts.deleteSearch(rows.single.id);
    expect(await alerts.searches('alice').first, isEmpty);
  });

  test('the same search is saved once: again, in another order, or on a double tap', () async {
    final db = FakeFirebaseFirestore();
    final alerts = FirestoreAlerts(db);
    const f = ListingFilters(purpose: Purpose.rent, areas: ['kilimani', 'westlands'], maxPriceKES: 60000);
    expect(await alerts.saveSearch('alice', f), isTrue);
    expect(await alerts.saveSearch('alice', f), isFalse);
    expect(await alerts.saveSearch('alice', const ListingFilters(purpose: Purpose.rent, areas: ['westlands', 'kilimani'], maxPriceKES: 60000)), isFalse);
    expect((await db.collection('savedSearches').get()).docs.single.id, savedSearchId('alice', f));
    // Different searches, or someone else's same search, are their own.
    expect(await alerts.saveSearch('alice', f.copyWith(maxPriceKES: 70000)), isTrue);
    expect(await alerts.saveSearch('bob', f), isTrue);
    expect((await db.collection('savedSearches').get()).docs, hasLength(3));
    // One saved before ids came from the search still counts.
    await db.collection('savedSearches').add({
      'userId': 'carol',
      'filters': alertFilters(f),
      'channels': ['inbox']
    });
    expect(await alerts.saveSearch('carol', f), isFalse);
  });

  test('searchKey: same filters alike, different ones apart', () {
    const a = ListingFilters(purpose: Purpose.rent, types: ['studio', 'apartment'], areas: ['kilimani']);
    expect(searchKey(a), searchKey(const ListingFilters(purpose: Purpose.rent, types: ['apartment', 'studio'], areas: ['kilimani'], q: 'words do not count')));
    expect(searchKey(a), isNot(searchKey(a.copyWith(minBeds: 2))));
    expect(searchKey(a), isNot(searchKey(a.copyWith(purpose: Purpose.sale))));
    expect(savedSearchId('alice', a), savedSearchId('alice', a));
    expect(savedSearchId('alice', a), isNot(savedSearchId('alice', a.copyWith(minBeds: 2))));
  });

  test('phones get the link through the app site, with the app ids; the web returns to its own page', () {
    final web = signInLinkSettings(Uri.parse('https://app.example/account'), null);
    expect(web.url, 'https://app.example/account');
    expect(web.androidPackageName, isNull);
    expect(web.linkDomain, isNull);

    final phone = signInLinkSettings(
      Uri.parse('https://app.example/account'),
      (appSite: appSiteHost('demo-project-dev'), linkDomain: authLinkDomain('demo-project-dev'), androidId: 'ke.example.app', iosId: 'ke.example.ios'),
    );
    expect(phone.url, 'https://demo-project-dev-app.web.app/account');
    expect(phone.linkDomain, 'demo-project-dev.firebaseapp.com', reason: 'Firebase refuses other sites (invalid-hosting-link-domain)');
    expect(phone.androidPackageName, 'ke.example.app');
    expect(phone.androidInstallApp, isFalse);
    expect(phone.iOSBundleId, 'ke.example.ios');
    expect(phone.handleCodeInApp, isTrue);
  });

  test('app site names follow Terraform: 26 characters, no trailing dash, then -app', () {
    expect(appSiteHost('demo-project-dev'), 'demo-project-dev-app.web.app');
    expect(appSiteHost('a-very-long-project-name-x-prod'), 'a-very-long-project-name-x-app.web.app');
    expect(appSiteHost('a-very-long-project-name--prod'), 'a-very-long-project-name--app.web.app', reason: 'one dash trimmed, as trimsuffix does');
  });

  test('the sign-in link is taken out of the link that opened the app', () {
    const inner = 'https://demo-app.web.app/__/auth/action?mode=signIn&oobCode=abc';
    expect(emailLinkFrom(Uri.https('demo-app.web.app', '/__/auth/links', {'link': inner})).toString(), inner);
    expect(emailLinkFrom(Uri.parse(inner)).toString(), inner, reason: 'the web page itself');
  });
}
