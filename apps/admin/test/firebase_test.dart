import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:realtor_admin/src/firebase/callable_actions.dart';
import 'package:realtor_admin/src/firebase/firestore_admin.dart';
import 'package:realtor_admin/src/firebase/hosting_config.dart';
import 'package:realtor_core/realtor_core.dart';

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
      await db.collection('agents').doc('agent-a').set({'name': 'Agent A', 'active': true});
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

    test('the team: managers only, by email, with agent names; unknown roles skipped', () async {
      await db.collection('staff').doc('u2').set({'email': 'b@example.com', 'role': 'agent', 'agentId': 'agent-a'});
      await db.collection('staff').doc('u1').set({'email': 'a@example.com', 'name': 'Boss', 'role': 'owner'});
      await db.collection('staff').doc('u3').set({'email': 'c@example.com', 'role': 'intern'});
      expect(() => repo.team(agent), throwsA(isA<StaffAccessException>()));
      final team = await repo.team(manager);
      expect(team.map((m) => m.email), ['a@example.com', 'b@example.com']);
      expect((team.last.role, team.last.agentName), (StaffRole.agent, 'Agent A'));
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
      final actions = CallableAdminActions((name, data) async => calls.add((name, data)));
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
