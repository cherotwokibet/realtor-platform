import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:realtor_admin/src/firebase/callable_actions.dart';
import 'package:realtor_admin/src/firebase/firestore_admin.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart' show parseHostingConfig, hostingFirebaseOptions;

const agent = StaffUser(uid: 'u-a', name: 'Agent A', role: StaffRole.agent, agentId: 'agent-a');
const manager = StaffUser(uid: 'u-m', name: 'Manager', role: StaffRole.manager);

void main() {
  group('Hosting config', () {
    const config = {
      'apiKey': 'k',
      'appId': '1:2:web:3',
      'projectId': 'acme-realty-dev',
      'messagingSenderId': '2',
      'authDomain': 'acme-realty-dev.firebaseapp.com',
    };

    test('parses the init.json Hosting serves', () {
      final o = parseHostingConfig(jsonEncode(config))!;
      expect((o.projectId, o.appId, o.authDomain, o.storageBucket),
          ('acme-realty-dev', '1:2:web:3', 'acme-realty-dev.firebaseapp.com', null));
    });

    test('anything else means no Firebase (demo mode)', () {
      expect(parseHostingConfig('<!doctype html><html></html>'), isNull);
      expect(parseHostingConfig('[]'), isNull);
      expect(parseHostingConfig(jsonEncode({...config, 'apiKey': ''})), isNull);
      expect(parseHostingConfig(jsonEncode({...config}..remove('projectId'))), isNull);
    });

    test('fetches from the same origin; a 404 or a network error is demo mode', () async {
      Uri? asked;
      final ok = MockClient((r) async {
        asked = r.url;
        return http.Response(jsonEncode(config), 200);
      });
      expect((await hostingFirebaseOptions(Uri.parse('https://acme-admin.web.app/leads?x=1'), client: ok))!.projectId,
          'acme-realty-dev');
      expect(asked.toString(), 'https://acme-admin.web.app/__/firebase/init.json');
      final missing = MockClient((_) async => http.Response('not found', 404));
      expect(await hostingFirebaseOptions(Uri.parse('http://localhost:8080/'), client: missing), isNull);
      final down = MockClient((_) async => throw http.ClientException('offline'));
      expect(await hostingFirebaseOptions(Uri.parse('http://localhost:8080/'), client: down), isNull);
    });
  });

  group('FirestoreAdminRepository', () {
    late FakeFirebaseFirestore db;
    late FirestoreAdminRepository repo;
    final t0 = DateTime(2026, 10, 27, 12);

    setUp(() async {
      db = FakeFirebaseFirestore();
      repo = FirestoreAdminRepository(db);
      await db.collection('agents').doc('agent-a').set({'name': 'Agent A', 'active': true, 'responseMins': 25});
      await db.collection('agents').doc('agent-b').set({'name': 'Agent B', 'active': true});
      for (var i = 0; i < 5; i++) {
        final agentId = i.isEven ? 'agent-a' : 'agent-b';
        await db.collection('listings').doc('l$i').set({
          'slug': 'listing-$i',
          'title': 'Listing $i',
          'area': 'kilimani',
          'priceKES': 50000 + i,
          'status': i == 0 ? 'pending' : 'live',
          'agentId': agentId,
          'stats': {'views': 0, 'leads': i, 'calls': 2 * i},
          'updatedAt': Timestamp.fromDate(t0.subtract(Duration(hours: i))),
        });
      }
      for (var i = 0; i < 7; i++) {
        await db.collection('leads').doc('lead$i').set({
          'listingId': 'l${i % 5}',
          'agentId': (i % 5).isEven ? 'agent-a' : 'agent-b',
          'channel': 'form',
          'contact': {'name': 'Client $i', 'phone': '+25470000000$i'},
          'stage': i < 3 ? 'new' : 'contacted',
          'createdAt': Timestamp.fromDate(t0.subtract(Duration(hours: i))),
        });
      }
      await db.collection('audit').doc('a1').set({
        'at': Timestamp.fromDate(t0),
        'actor': {'uid': 'u-m', 'role': 'manager', 'agentId': null, 'name': 'Manager'},
        'action': 'listing.approve',
        'target': {'collection': 'listings', 'id': 'l0', 'label': 'Listing 0'},
        'from': 'pending',
        'to': 'live',
      });
      await db.collection('audit').doc('a0').set({
        'at': Timestamp.fromDate(t0.subtract(const Duration(days: 1))),
        'actor': {'uid': null, 'role': null, 'agentId': null, 'name': 'owner bootstrap script'},
        'action': 'staff.role',
        'target': {'collection': 'staff', 'id': 'u-o'},
        'from': null,
        'to': 'owner',
      });
    });

    test('an agent gets only their own leads, newest first, with titles and names', () async {
      final page = await repo.leads(agent, limit: 10);
      expect(page.rows.map((r) => r.id), ['lead0', 'lead2', 'lead4', 'lead5']);
      expect(page.rows.every((r) => r.agentId == 'agent-a' && r.agentName == 'Agent A'), isTrue);
      expect((page.rows.first.listingTitle, page.rows.first.contactPhone), ('Listing 0', '+254700000000'));
      expect(page.next, isNull);
    });

    test('managers page through everyone with cursors, and filter by stage', () async {
      final p1 = await repo.leads(manager, limit: 3);
      expect(p1.rows.map((r) => r.id), ['lead0', 'lead1', 'lead2']);
      expect(p1.next, 'lead2');
      final p2 = await repo.leads(manager, after: p1.next, limit: 3);
      expect(p2.rows.map((r) => r.id), ['lead3', 'lead4', 'lead5']);
      final p3 = await repo.leads(manager, after: p2.next, limit: 3);
      expect(p3.rows.map((r) => r.id), ['lead6']);
      expect(p3.next, isNull);
      expect((await repo.leads(manager, stage: 'new')).rows.map((r) => r.stage).toSet(), {'new'});
    });

    test('listings are scoped and filtered the same way', () async {
      expect((await repo.listings(agent)).rows.map((r) => r.id), ['l0', 'l2', 'l4']);
      final pending = await repo.listings(manager, status: 'pending');
      expect(pending.rows.single.id, 'l0');
      final l2 = (await repo.listings(manager)).rows.firstWhere((r) => r.id == 'l2');
      expect((l2.priceKES, l2.leads, l2.calls, l2.whatsapps, l2.agentName), (50002, 2, 4, 0, 'Agent A'));
    });

    test('the editor reads a listing (own only for agents) and the areas with their centres', () async {
      await db.collection('listings').doc('l2').update({
        'purpose': 'rent',
        'type': 'apartment',
        'beds': 2,
        'baths': 1,
        'depositMonths': 2,
        'geo': {'lat': -1.29, 'lng': 36.78, 'geohash': 'kzf0'},
        'amenities': ['Borehole'],
      });
      final d = (await repo.listingDraft(manager, 'l2'))!;
      expect((d.listingId, d.title, d.beds, d.depositMonths, d.lat, d.lng, d.agentId), ('l2', 'Listing 2', 2, 2, -1.29, 36.78, 'agent-a'));
      expect(d.amenities, ['Borehole']);
      expect(await repo.listingDraft(agent, 'l1'), isNull, reason: "another agent's listing");
      expect(await repo.listingDraft(manager, 'missing'), isNull);

      await db.collection('areas').doc('westlands').set({'name': 'Westlands', 'centre': {'lat': -1.27, 'lng': 36.81}});
      await db.collection('areas').doc('kilimani').set({'name': 'Kilimani', 'centre': {'lat': -1.29, 'lng': 36.79}});
      expect([for (final a in await repo.areas()) (a.slug, a.lat)], [('kilimani', -1.29), ('westlands', -1.27)]);
    });

    test('managers see which listings have a photo flagged; agents do not', () async {
      await db.collection('photoFlags').doc('l2_abc').set({'listingId': 'l2', 'mediaId': 'abc', 'matches': []});
      final rows = (await repo.listings(manager)).rows;
      expect(rows.where((r) => r.photoMatch).map((r) => r.id), ['l2']);
      expect((await repo.listings(agent)).rows.any((r) => r.photoMatch), isFalse);
    });

    test('viewings: open ones from a date, earliest first and scoped; history by status, latest first', () async {
      DateTime at(int h) => t0.add(Duration(hours: h));
      Future<void> v(String id, String agentId, String status, DateTime slot) => db.collection('viewings').doc(id).set({
            'listingId': 'l0',
            'agentId': agentId,
            'slot': Timestamp.fromDate(slot),
            'status': status,
            'client': {'name': 'Client $id', 'phone': '+2547000009${id.substring(1)}'},
          });
      await v('v1', 'agent-a', 'confirmed', at(-30)); // yesterday-ish, still open
      await v('v2', 'agent-a', 'requested', at(20));
      await v('v3', 'agent-b', 'requested', at(10));
      await v('v4', 'agent-a', 'done', at(-50));
      await v('v5', 'agent-a', 'requested', at(-24 * 30)); // too old for the open list
      final from = t0.subtract(const Duration(days: 14));
      expect((await repo.viewings(manager, from: from)).rows.map((r) => r.id), ['v1', 'v3', 'v2']);
      final mine = (await repo.viewings(agent, from: from)).rows;
      expect(mine.map((r) => r.id), ['v1', 'v2']);
      expect((mine.first.listingTitle, mine.first.clientName, mine.first.agentName), ('Listing 0', 'Client v1', 'Agent A'));
      expect((await repo.viewings(manager, status: 'done', from: from)).rows.map((r) => r.id), ['v4']);
    });

    test('the team: managers only, by email, with agent names; unknown roles skipped', () async {
      await db.collection('staff').doc('u2').set({'email': 'b@example.com', 'role': 'agent', 'agentId': 'agent-a'});
      await db.collection('staff').doc('u1').set({'email': 'a@example.com', 'name': 'Boss', 'role': 'owner'});
      await db.collection('staff').doc('u3').set({'email': 'c@example.com', 'role': 'intern'});
      expect(() => repo.team(agent), throwsA(isA<StaffAccessException>()));
      final team = await repo.team(manager);
      expect(team.map((m) => m.email), ['a@example.com', 'b@example.com']);
      expect((team.last.role, team.last.agentName, team.last.agentReplyMins), (StaffRole.agent, 'Agent A', 25));
      expect(team.first.agentReplyMins, isNull);
      expect((await repo.agents(manager)).map((a) => a.name), ['Agent A', 'Agent B']);
    });

    test('the audit log: managers only, newest first, scripts shown as such', () async {
      expect(() => repo.audit(agent), throwsA(isA<StaffAccessException>()));
      final rows = (await repo.audit(manager)).rows;
      expect(rows.map((r) => r.action), ['listing.approve', 'staff.role']);
      expect((rows.first.actorRole, rows.first.target), (StaffRole.manager, 'Listing 0'));
      expect(rows.last.target, 'staff/u-o', reason: 'no label: falls back to collection/id');
      expect((rows.last.actorRole, rows.last.actorName, rows.last.from), (null, 'owner bootstrap script', null));
    });
  });

  group('CallableAdminActions', () {
    test('web errors read plainly: no "functions/" prefix, no HTTP status', () async {
      final actions = CallableAdminActions(
        (name, data) async => throw FirebaseException(
          plugin: 'firebase_functions',
          code: 'functions/failed-precondition',
          message: 'a lead cannot go from contacted to contacted [400]',
        ),
      );
      await expectLater(
        actions.moveLead(manager, leadId: 'lead1', stage: 'contacted'),
        throwsA(isA<AdminActionException>()
            .having((e) => e.code, 'code', 'failed-precondition')
            .having((e) => e.message, 'message', 'a lead cannot go from contacted to contacted')),
      );
    });

    test('calls the Functions by name with only what they need', () async {
      final calls = <(String, Map<String, Object?>)>[];
      final actions = CallableAdminActions((name, data) async {
        calls.add((name, data));
        return null;
      });
      await actions.moveLead(agent, leadId: 'lead1', stage: 'contacted');
      await actions.moderateListing(manager, listingId: 'l0', action: 'approve');
      await actions.moderateListing(manager, listingId: 'l1', action: 'reject', reason: 'Blurry');
      expect(calls.map((c) => c.$1), ['updateLeadStage', 'moderateListing', 'moderateListing']);
      expect(calls[0].$2, {'leadId': 'lead1', 'stage': 'contacted'});
      expect(calls[1].$2, {'listingId': 'l0', 'action': 'approve'});
      expect(calls[2].$2, {'listingId': 'l1', 'action': 'reject', 'reason': 'Blurry'});
      await actions.setStaffRole(manager, email: ' a@example.com ', role: StaffRole.agent, agentId: 'agent-a');
      await actions.setStaffRole(manager, email: 'b@example.com', role: StaffRole.manager, agentId: 'ignored');
      await actions.setStaffRole(manager, email: 'c@example.com', role: null);
      expect(calls.skip(3).map((c) => c.$1).toSet(), {'setStaffRole'});
      expect(calls[3].$2, {'email': 'a@example.com', 'role': 'agent', 'agentId': 'agent-a'});
      expect(calls[4].$2, {'email': 'b@example.com', 'role': 'manager'});
      expect(calls[5].$2, {'email': 'c@example.com', 'role': null});
    });

    test('confirmListing sends the id and reads the new expiry', () async {
      final calls = <(String, Map<String, Object?>)>[];
      final actions = CallableAdminActions((name, data) async {
        calls.add((name, data));
        return {'expiresAt': '2026-11-27T09:00:00.000Z'};
      });
      final until = await actions.confirmListing(agent, listingId: 'l2');
      expect(calls.single.$1, 'confirmListing');
      expect(calls.single.$2, {'listingId': 'l2'});
      expect(until, DateTime.utc(2026, 11, 27, 9));
    });

    test('data requests send the kind and the person, and read back counts and the export', () async {
      final calls = <(String, Map<String, Object?>)>[];
      final actions = CallableAdminActions((name, data) async {
        calls.add((name, data));
        return data['kind'] == 'export'
            ? {
                'kind': 'export',
                'data': {
                  'leads': [
                    {'id': 'l1', 'contact': {'phone': '+254712345678'}}
                  ],
                  'viewings': <Object?>[],
                },
              }
            : {
                'kind': 'delete',
                'deleted': {'leads': 2, 'viewings': 1},
              };
      });
      final export = await actions.dataRequest(manager, kind: DataRequestKind.export, phone: '+254712345678');
      expect(calls.single.$1, 'dataRequest');
      expect(calls.single.$2, {'kind': 'export', 'phone': '+254712345678'});
      expect([export.leads, export.viewings], [1, 0]);
      expect(export.exportJson, contains('"phone": "+254712345678"'));
      final delete = await actions.dataRequest(manager, kind: DataRequestKind.delete, email: ' a@example.com ');
      expect(calls.last.$2, {'kind': 'delete', 'email': 'a@example.com'});
      expect([delete.leads, delete.viewings, delete.exportJson], [2, 1, null]);
    });

    test('featureListing and importListings send what the Functions take and read their answers', () async {
      final calls = <(String, Map<String, Object?>)>[];
      final actions = CallableAdminActions((name, data) async {
        calls.add((name, data));
        return name == 'featureListing'
            ? {'featuredUntil': data['days'] == 0 ? null : '2026-11-27T09:00:00.000Z'}
            : {
                'created': [
                  {'row': 1, 'listingId': 'x', 'slug': 'x'}
                ],
                'failed': [
                  {'row': 2, 'error': 'agentId: no agent "ghost"'}
                ],
              };
      });
      expect(await actions.featureListing(manager, listingId: 'l1', days: 30), DateTime.utc(2026, 11, 27, 9));
      expect(await actions.featureListing(manager, listingId: 'l1', days: 0), isNull);
      expect(calls.first.$2, {'listingId': 'l1', 'days': 30});
      final r = await actions.importListings(manager, [
        {'title': 'a'},
        {'title': 'b'}
      ]);
      expect(calls.last.$1, 'importListings');
      expect(r.created, [1]);
      expect((r.failed.single.row, r.failed.single.error), (2, 'agentId: no agent "ghost"'));
    });

    test('submitListing sends the draft and returns the listing id', () async {
      final calls = <(String, Map<String, Object?>)>[];
      final actions = CallableAdminActions((name, data) async {
        calls.add((name, data));
        return {'listingId': 'new-1', 'slug': 'x'};
      });
      const draft = ListingDraft(title: 'Studio, Kilimani', type: 'studio', beds: 0, priceKES: 25000, lat: -1.29, lng: 36.78, area: 'kilimani', agentId: 'agent-a');
      expect(await actions.submitListing(manager, draft), 'new-1');
      expect(calls.single.$1, 'submitListing');
      expect(calls.single.$2['priceKES'], 25000);
      expect(calls.single.$2.containsKey('media'), isFalse, reason: 'media stays as it is');
    });

    test('updateViewing calls updateViewingStatus', () async {
      final calls = <(String, Map<String, Object?>)>[];
      final actions = CallableAdminActions((name, data) async {
        calls.add((name, data));
        return {'status': data['status']};
      });
      await actions.updateViewing(agent, viewingId: 'agent-a_1', status: 'confirmed');
      expect(calls.single.$1, 'updateViewingStatus');
      expect(calls.single.$2, {'viewingId': 'agent-a_1', 'status': 'confirmed'});
      final moved = CallableAdminActions((name, data) async {
        calls.add((name, data));
        return {'viewingId': 'agent-a_2'};
      });
      expect(await moved.rescheduleViewing(agent, viewingId: 'agent-a_1', slot: '2026-10-29T15:00:00+03:00'), 'agent-a_2');
      expect(calls.last.$1, 'rescheduleViewing');
      expect(calls.last.$2, {'viewingId': 'agent-a_1', 'slot': '2026-10-29T15:00:00+03:00'});
    });

    test('a refusal becomes an AdminActionException with the callable code', () async {
      final actions = CallableAdminActions(
        (name, data) async => throw FirebaseException(
            plugin: 'firebase_functions', code: 'failed-precondition', message: 'a lead cannot go from new to won'),
      );
      await expectLater(
        actions.moveLead(manager, leadId: 'lead1', stage: 'won'),
        throwsA(isA<AdminActionException>()
            .having((e) => e.code, 'code', 'failed-precondition')
            .having((e) => e.message, 'message', 'a lead cannot go from new to won')),
      );
    });
  });
}
