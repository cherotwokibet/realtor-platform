import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtor_app/src/firebase/firebase_account.dart';
import 'package:realtor_core/realtor_core.dart';

void main() {
  test('saved searches are written as the rules expect and read back; alerts newest first, read and cleared', () async {
    final db = FakeFirebaseFirestore();
    final alerts = FirestoreAlerts(db);
    await alerts.saveSearch('alice', const ListingFilters(purpose: Purpose.rent, areas: ['kilimani'], maxPriceKES: 60000, q: 'ignored'));
    final doc = (await db.collection('savedSearches').get()).docs.single.data();
    expect(doc['userId'], 'alice');
    expect(doc['filters'], {'purpose': 'rent', 'areas': ['kilimani'], 'maxPriceKES': 60000});
    expect(doc['channels'], ['inbox']);
    expect(doc['lastNotifiedAt'], isNull);
    final rows = await alerts.searches('alice').first;
    expect(rows.single.filters.areas, ['kilimani']);

    final a = db.collection('users').doc('alice').collection('alerts');
    await a.doc('old').set({'slug': 's1', 'title': 'Old', 'priceKES': 1, 'purpose': 'rent', 'area': 'x', 'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1)), 'readAt': null});
    await a.doc('new').set({'slug': 's2', 'title': 'New', 'priceKES': 2, 'purpose': 'sale', 'area': 'y', 'createdAt': Timestamp.fromDate(DateTime(2026, 10, 29)), 'readAt': null});
    expect((await alerts.alerts('alice').first).map((x) => x.title), ['New', 'Old']);
    await alerts.markRead('alice', 'new');
    expect((await alerts.alerts('alice').first).first.read, isTrue);
    await alerts.clear('alice', 'old');
    expect((await alerts.alerts('alice').first).map((x) => x.id), ['new']);
    await alerts.deleteSearch(rows.single.id);
    expect(await alerts.searches('alice').first, isEmpty);
  });
}
