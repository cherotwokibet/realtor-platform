import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtor_app/src/firebase/firebase_data.dart';
import 'package:realtor_core/realtor_core.dart';

void main() {
  final now = DateTime(2026, 10, 29, 12);
  late FakeFirebaseFirestore db;

  Map<String, Object?> listing(String slug, {String purpose = 'rent', String status = 'live', int price = 50000, String area = 'kilimani'}) => {
        'slug': slug,
        'title': 'Flat $slug',
        'purpose': purpose,
        'type': 'apartment',
        'beds': 2,
        'baths': 1,
        'priceKES': price,
        'area': area,
        'geo': {'lat': -1.29, 'lng': 36.78, 'geohash': 'kzf'},
        'status': status,
        'agentId': 'agent-a',
        'verifiedAt': Timestamp.fromDate(now.subtract(const Duration(days: 3))),
        'expiresAt': Timestamp.fromDate(now.add(const Duration(days: 27))),
        'media': [
          {
            'kind': 'photo',
            'variants': {'thumb': 'media/listings/x/a/thumb.webp', 'card': 'media/listings/x/a/card.webp'},
            'blurhash': 'LKO2'
          },
          {
            'kind': 'video',
            'variants': {'hls': 'media/listings/x/v/hls/master.m3u8'}
          },
        ],
      };

  setUp(() async {
    db = FakeFirebaseFirestore();
    await db.collection('listings').doc('l1').set(listing('flat-1'));
    await db.collection('listings').doc('l2').set(listing('flat-2', price: 90000, area: 'westlands'));
    await db.collection('listings').doc('l3').set(listing('flat-3', status: 'pending'));
    await db.collection('listings').doc('l4').set(listing('house-4', purpose: 'sale', price: 9000000));
    await db.collection('agents').doc('agent-a').set({'name': 'Agent A', 'phone': '+254700000001', 'whatsapp': '+254700000002', 'active': true});
  });

  test('a listing document becomes a results row: verified, photo thumb from the media bucket', () {
    final s = summaryFromDoc('l1', listing('flat-1'), bucket: 'p-media', now: now);
    expect((s.slug, s.purpose, s.priceKES, s.verified, s.featured, s.blurhash), ('flat-1', Purpose.rent, 50000, true, false, 'LKO2'));
    expect(s.thumb, 'https://firebasestorage.googleapis.com/v0/b/p-media/o/media%2Flistings%2Fx%2Fa%2Fthumb.webp?alt=media');
    // The card carousel gets card-size photos; the video counts as a tour.
    expect(s.photos, ['https://firebasestorage.googleapis.com/v0/b/p-media/o/media%2Flistings%2Fx%2Fa%2Fcard.webp?alt=media']);
    expect((s.hasVideo, s.has360, s.hasFloorPlan), (true, false, false));
    final lapsed = summaryFromDoc('l1', {...listing('flat-1'), 'expiresAt': Timestamp.fromDate(now.subtract(const Duration(days: 1)))}, bucket: 'b', now: now);
    expect(lapsed.verified, isFalse);
  });

  test('search reads live listings of the purpose and filters them in memory, read once per few minutes', () async {
    var t = now;
    final search = FirestoreListingSearch(db, bucket: 'b', clock: () => t);
    final all = await search.search(const ListingFilters(purpose: Purpose.rent));
    expect(all.hits.map((h) => h.slug).toSet(), {'flat-1', 'flat-2'}, reason: 'live rentals only');
    final cheap = await search.search(const ListingFilters(purpose: Purpose.rent, maxPriceKES: 60000));
    expect(cheap.hits.map((h) => h.slug), ['flat-1']);
    expect((await search.search(const ListingFilters(purpose: Purpose.sale))).hits.single.slug, 'house-4');

    await db.collection('listings').doc('l5').set(listing('flat-5'));
    expect((await search.search(const ListingFilters(purpose: Purpose.rent))).found, 2, reason: 'cached');
    t = now.add(const Duration(minutes: 6));
    expect((await search.search(const ListingFilters(purpose: Purpose.rent))).found, 3);
  });

  test('a returning visitor sees the homes kept from last time at once; fresh ones are fetched and kept for next time', () async {
    final store = _MemorySnapshots();
    // First visit: nothing kept, so it waits for Firestore, then keeps the homes.
    final first = SnapshotListingSearch(FirestoreListingSearch(db, bucket: 'b', clock: () => now).rows, store: store, clock: () => now);
    expect((await first.search(const ListingFilters(purpose: Purpose.rent))).found, 2);
    await Future<void>.delayed(Duration.zero);
    expect(store.kept[Purpose.rent]!.rows, hasLength(2));

    // Next visit, Firebase still starting (never ready here): the kept homes show.
    final slow = Completer<List<ListingSummary>>();
    final next = SnapshotListingSearch((_) => slow.future, store: store, clock: () => now.add(const Duration(hours: 1)));
    final r = await next.search(const ListingFilters(purpose: Purpose.rent, maxPriceKES: 60000));
    expect(r.hits.map((h) => h.slug), ['flat-1'], reason: 'filtered from the kept copy, without waiting');

    // A copy older than half a day is not trusted: the search waits for fresh homes.
    final stale =
        SnapshotListingSearch(FirestoreListingSearch(db, bucket: 'b', clock: () => now).rows, store: store, clock: () => now.add(const Duration(days: 2)));
    await db.collection('listings').doc('l6').set(listing('flat-6'));
    expect((await stale.search(const ListingFilters(purpose: Purpose.rent))).found, 3);
  });

  test('the listings file: homes by purpose, newest by area or agent, times in milliseconds; a failed read is tried again', () async {
    final at = now.millisecondsSinceEpoch;
    final file = '{"at":$at,"rows":['
        '{"id":"a","slug":"flat-a","title":"A","purpose":"rent","priceKES":50000,"area":"kilimani","agentId":"g1","updatedAt":${at - 2000},'
        '"verifiedAt":${at - 1000},"expiresAt":${at + 86400000},"media":[{"kind":"photo","blurhash":"x","variants":{"card":"c.webp","thumb":"t.webp"}}]},'
        '{"id":"b","slug":"flat-b","title":"B","purpose":"rent","priceKES":60000,"area":"kasarani","agentId":"g2","updatedAt":${at - 1000}},'
        '{"id":"c","slug":"house-c","title":"C","purpose":"sale","priceKES":9000000,"area":"kilimani","agentId":"g1","updatedAt":$at}]}';
    var calls = 0;
    final index = ListingIndex(() async {
      if (++calls == 1) throw StateError('offline');
      return file;
    }, bucket: 'b', clock: () => now);
    await expectLater(index.rows(Purpose.rent), throwsStateError);
    final rent = await index.rows(Purpose.rent);
    expect(rent.map((h) => h.slug), ['flat-a', 'flat-b']);
    expect(rent.first.verified, isTrue);
    expect(rent.first.photos.single, contains('c.webp'));
    expect((await index.live()).map((h) => h.slug), ['house-c', 'flat-b', 'flat-a'], reason: 'newest first');
    expect((await index.live(area: 'kilimani', limit: 1)).map((h) => h.slug), ['house-c']);
    expect((await index.live(agentId: 'g2')).map((h) => h.slug), ['flat-b']);
    expect(calls, 2, reason: 'read once per visit after it works');
  });

  test('details by slug: live only, card photos, the agent while active', () async {
    final repo = FirestoreListingRepository(db, bucket: 'b', clock: () => now);
    final d = (await repo.bySlug('flat-1'))!;
    expect(d.photos.single, endsWith('card.webp?alt=media'));
    expect((d.agent!.name, d.agent!.whatsapp), ('Agent A', '+254700000002'));
    expect(await repo.bySlug('flat-3'), isNull, reason: 'pending');
    expect(await repo.bySlug('nope'), isNull);
    await db.collection('agents').doc('agent-a').update({'active': false});
    expect((await repo.bySlug('flat-1'))!.agent, isNull);
  });

  test('open times come from openSlots; on any failure the app shows every time', () async {
    final ok = CallableLeadRepository((name, data) async {
      expect((name, data['listingId'], data['day']), ('openSlots', 'l1', '2026-10-30'));
      return {
        'times': ['08:00', '09:30']
      };
    });
    expect(await ok.openTimes(listingId: 'l1', day: '2026-10-30'), ['08:00', '09:30']);
    final down = CallableLeadRepository((name, data) async => throw FirebaseException(plugin: 'functions', code: 'unavailable'));
    expect(await down.openTimes(listingId: 'l1', day: '2026-10-30'), isNull);
  });

  test('area guide, active agent only, and live homes by area or agent', () async {
    await db.collection('areas').doc('kilimani').set({
      'name': 'Kilimani',
      'county': 'Nairobi',
      'centre': {'lat': -1.29, 'lng': 36.78},
      'guide': 'Leafy.',
      'amenities': ['Yaya Centre'],
      'stats': {'medianRentKES': 70000, 'listings': 1},
    });
    final repo = FirestoreListingRepository(db, bucket: 'b', clock: () => now);
    expect((await repo.area('kilimani'))!.medianRentKES, 70000);
    expect(await repo.area('nowhere'), isNull);
    expect((await repo.agent('agent-a'))!.whatsapp, '+254700000002');
    expect((await repo.live(area: 'kilimani')).map((l) => l.slug).toSet(), {'flat-1', 'house-4'});
    expect(await repo.live(area: 'westlands'), hasLength(1));
    expect((await repo.live(agentId: 'agent-a')).map((l) => l.slug).toSet(), {'flat-1', 'flat-2', 'house-4'});
    await db.collection('agents').doc('agent-a').update({'active': false});
    expect(await repo.agent('agent-a'), isNull);
  });

  test('leads go to the Functions with consent; refusals become LeadException', () async {
    final calls = <(String, Map<String, Object?>)>[];
    final leads = CallableLeadRepository((name, data) async {
      calls.add((name, data));
      if (name == 'bookViewing') throw FirebaseException(plugin: 'functions', code: 'functions/already-exists', message: 'that time is taken [409]');
      return null;
    });
    await leads.enquire(listingId: 'l1', phone: '+254712345678', name: 'Amina');
    expect(calls.single.$1, 'createLead');
    expect(calls.single.$2, {
      'listingId': 'l1',
      'channel': 'form',
      'contact': {'phone': '+254712345678', 'name': 'Amina'},
      'consent': true
    });
    await leads.logTap(listingId: 'l1', channel: 'whatsapp');
    expect(calls.last.$2, {'listingId': 'l1', 'channel': 'whatsapp'});
    await expectLater(
      leads.bookViewing(listingId: 'l1', slot: '2026-10-30T10:00:00+03:00', name: 'Amina', phone: '+254712345678'),
      throwsA(isA<LeadException>().having((e) => (e.code, e.message), 'code', ('already-exists', 'that time is taken'))),
    );
  });

  test('a booking returns its id and fee; paying calls the M-Pesa Function with no amount (P6-s01)', () async {
    final calls = <(String, Map<String, Object?>)>[];
    final leads = CallableLeadRepository((name, data) async {
      calls.add((name, data));
      return name == 'bookViewing' ? {'viewingId': 'agent-a_1', 'leadId': 'x', 'feeKES': 500} : {'paymentId': 'p', 'status': 'pending'};
    });
    final booked = await leads.bookViewing(listingId: 'l1', slot: '2026-10-30T10:00:00+03:00', name: 'Amina', phone: '+254712345678');
    expect(booked, (viewingId: 'agent-a_1', feeKES: 500));
    await leads.payViewingFee(viewingId: booked.viewingId, phone: '+254712345678');
    expect(calls.last.$1, 'payments-startViewingPayment');
    expect(calls.last.$2, {'viewingId': 'agent-a_1', 'phone': '+254712345678'});
  });

  test('video media entries become playable videos; photos and broken entries do not', () {
    const bucket = 'b';
    final v = videoFromMedia({
      'kind': 'video',
      'variants': {'hls': 'media/listings/l/m/hls/master.m3u8', 'mp4': 'media/listings/l/m/video.mp4', 'poster': 'media/listings/l/m/poster.jpg'},
    }, bucket)!;
    expect(v.hls, 'https://firebasestorage.googleapis.com/v0/b/b/o/media%2Flistings%2Fl%2Fm%2Fhls%2Fmaster.m3u8?alt=media');
    expect(v.mp4, endsWith('video.mp4?alt=media'));
    expect(v.poster, endsWith('poster.jpg?alt=media'));
    expect(
        videoFromMedia({
          'kind': 'video',
          'variants': {'hls': 'a', 'poster': 'b'}
        }, bucket)!
            .mp4,
        isNull,
        reason: 'older videos have no MP4');
    expect(
        videoFromMedia({
          'kind': 'photo',
          'variants': {'card': 'x'}
        }, bucket),
        isNull);
    expect(
        videoFromMedia({
          'kind': 'video',
          'variants': {'hls': 'a'}
        }, bucket),
        isNull);
  });
}

class _MemorySnapshots implements ListingSnapshotStore {
  final kept = <Purpose, ({DateTime at, List<ListingSummary> rows})>{};
  @override
  Future<({DateTime at, List<ListingSummary> rows})?> load(Purpose purpose) async => kept[purpose];
  @override
  Future<void> save(Purpose purpose, DateTime at, List<ListingSummary> rows) async => kept[purpose] = (at: at, rows: rows);
}
