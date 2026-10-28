import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:realtor_admin/src/app.dart';
import 'package:realtor_admin/src/demo_admin.dart';
import 'package:realtor_admin/src/format.dart';
import 'package:realtor_admin/src/listing_media.dart';
import 'package:realtor_admin/src/providers.dart';
import 'package:realtor_admin/src/session.dart';
import 'package:realtor_core/realtor_core.dart';

TenantConfig tenant() => TenantConfig.fromJson(
    jsonDecode(File('../../tenants/realtime-estates.json').readAsStringSync()) as Map<String, Object?>);

final owner = demoStaff.firstWhere((s) => s.role == StaffRole.owner);
final manager = demoStaff.firstWhere((s) => s.role == StaffRole.manager);
final wanjiku = demoStaff.firstWhere((s) => s.agentId == 'agent-wanjiku');

late ProviderContainer container;

/// Taps [f] after scrolling it into view (wide tables scroll sideways).
Future<void> tapVisible(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// Actions that wait for [gate] before reaching the demo data, like a
/// callable on a cold start.
class SlowActions implements AdminActions {
  SlowActions(this.inner);
  final AdminActions inner;
  final gate = Completer<void>();
  var calls = 0;

  @override
  Future<void> moveLead(StaffUser who, {required String leadId, required String stage}) async {
    calls++;
    await gate.future;
    return inner.moveLead(who, leadId: leadId, stage: stage);
  }

  @override
  Future<void> moderateListing(StaffUser who,
      {required String listingId, required String action, String? reason}) async {
    calls++;
    await gate.future;
    return inner.moderateListing(who, listingId: listingId, action: action, reason: reason);
  }

  @override
  Future<DateTime> confirmListing(StaffUser who, {required String listingId}) async {
    calls++;
    await gate.future;
    return inner.confirmListing(who, listingId: listingId);
  }

  @override
  Future<void> updateViewing(StaffUser who, {required String viewingId, required String status}) async {
    calls++;
    await gate.future;
    return inner.updateViewing(who, viewingId: viewingId, status: status);
  }

  @override
  Future<String> rescheduleViewing(StaffUser who, {required String viewingId, required String slot}) async {
    calls++;
    await gate.future;
    return inner.rescheduleViewing(who, viewingId: viewingId, slot: slot);
  }

  @override
  Future<String> addTimeOff(StaffUser who, {String? agentId, required String start, required String end, String? note}) async {
    calls++;
    await gate.future;
    return inner.addTimeOff(who, agentId: agentId, start: start, end: end, note: note);
  }

  @override
  Future<void> removeTimeOff(StaffUser who, {required String blockId}) async {
    calls++;
    await gate.future;
    return inner.removeTimeOff(who, blockId: blockId);
  }

  @override
  Future<DateTime?> featureListing(StaffUser who, {required String listingId, required int days}) async {
    calls++;
    await gate.future;
    return inner.featureListing(who, listingId: listingId, days: days);
  }

  @override
  Future<String> submitListing(StaffUser who, ListingDraft draft) async {
    calls++;
    await gate.future;
    return inner.submitListing(who, draft);
  }

  @override
  Future<ImportOutcome> importListings(StaffUser who, List<Map<String, Object?>> rows) async {
    calls++;
    await gate.future;
    return inner.importListings(who, rows);
  }

  @override
  Future<void> setStaffRole(StaffUser who, {required String email, required StaffRole? role, String? agentId}) async {
    calls++;
    await gate.future;
    return inner.setStaffRole(who, email: email, role: role, agentId: agentId);
  }

  @override
  Future<DataRequestResult> dataRequest(StaffUser who,
      {required DataRequestKind kind, String? phone, String? email}) async {
    calls++;
    await gate.future;
    return inner.dataRequest(who, kind: kind, phone: phone, email: email);
  }
}

late SlowActions slow;

class _FakePicker implements FilePicker {
  _FakePicker(this.files);
  final List<PickedFile> files;
  @override
  Future<List<PickedFile>> pick({required String accept}) async => files;
}

Future<void> open(WidgetTester tester,
    {StaffUser? as, double width = 1280, bool slowActions = false, List<Override> overrides = const []}) async {
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final demo = DemoAdminRepository();
  slow = SlowActions(demo);
  container = ProviderContainer(overrides: [
    tenantProvider.overrideWithValue(tenant()),
    demoAdminProvider.overrideWithValue(demo),
    if (slowActions) adminActionsProvider.overrideWithValue(slow),
    ...overrides,
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const AdminApp()));
  await tester.pumpAndSettle();
  if (as != null) {
    await tester.tap(find.text(as.name));
    await tester.pumpAndSettle();
  }
}

String location() => container.read(routerProvider).routerDelegate.currentConfiguration.uri.path;

void main() {
  group('adminRedirect', () {
    test('signed out goes to sign in; signed in leaves it', () {
      expect(adminRedirect(const SignedOut(), '/leads'), signInPath);
      expect(adminRedirect(const SignedOut(), signInPath), isNull);
      expect(adminRedirect(const NotStaff('x@example.com'), '/leads'), signInPath);
      expect(adminRedirect(SignedIn(manager), signInPath), '/leads');
      expect(adminRedirect(SignedIn(manager), '/'), '/leads');
    });

    test('while starting, a deep link stays put', () {
      expect(adminRedirect(const Starting(), '/listings'), isNull);
    });

    test('nobody opens a section their role does not cover', () {
      expect(adminRedirect(SignedIn(wanjiku), '/audit'), '/leads');
      expect(adminRedirect(SignedIn(wanjiku), '/listings'), isNull);
      expect(adminRedirect(SignedIn(manager), '/audit'), isNull);
      expect(adminRedirect(SignedIn(owner), '/nowhere'), '/leads');
    });
  });

  group('DemoAdminRepository', () {
    final repo = DemoAdminRepository();

    test('confirming: own or manager, live or expired only', () async {
      final otieno = demoStaff.firstWhere((s) => s.agentId == 'agent-otieno');
      final all = (await repo.listings(manager, limit: 50)).rows;
      final wanjikus = all.firstWhere((r) => r.agentId == 'agent-wanjiku' && r.status == 'live');
      await expectLater(repo.confirmListing(otieno, listingId: wanjikus.id),
          throwsA(isA<AdminActionException>().having((e) => e.code, 'code', 'permission-denied')));
      final pending = all.firstWhere((r) => r.status == 'pending');
      await expectLater(repo.confirmListing(manager, listingId: pending.id),
          throwsA(isA<AdminActionException>().having((e) => e.code, 'code', 'failed-precondition')));
      expect(listingActionsFor(otieno, status: 'live', agentId: 'agent-otieno'), ['confirm']);
      expect(listingActionsFor(otieno, status: 'live', agentId: 'agent-wanjiku'), isEmpty);
      expect(listingActionsFor(manager, status: 'live', agentId: 'x'), [...moderationsFor('live'), 'confirm', 'feature']);
      expect(listingActionsFor(manager, status: 'live', agentId: 'x', featured: true).last, 'unfeature');
      expect(listingActionsFor(manager, status: 'pending', agentId: 'x'), isNot(contains('feature')));
    });

    test('photo flags are for managers: the agent gets the listing without the flag', () async {
      final otieno = demoStaff.firstWhere((s) => s.agentId == 'agent-otieno');
      final asManager = (await repo.listings(manager, limit: 50)).rows.firstWhere((r) => r.id == 'listing-005');
      final asAgent = (await repo.listings(otieno, limit: 50)).rows.firstWhere((r) => r.id == 'listing-005');
      expect((asManager.photoMatch, asAgent.photoMatch), (true, false));
    });

    test('agents get only their own leads and listings, and no audit log', () async {
      final leads = await repo.leads(wanjiku, limit: 100);
      final listings = await repo.listings(wanjiku, limit: 100);
      expect(leads.rows, isNotEmpty);
      expect(listings.rows, isNotEmpty);
      expect(leads.rows.map((r) => r.agentId).toSet(), {'agent-wanjiku'});
      expect(listings.rows.map((r) => r.agentId).toSet(), {'agent-wanjiku'});
      expect(() => repo.audit(wanjiku), throwsA(isA<StaffAccessException>()));
    });

    test('managers get every agent', () async {
      final leads = await repo.leads(manager, limit: 100);
      expect(leads.rows.map((r) => r.agentId).toSet().length, 3);
      expect((await repo.audit(manager)).rows, isNotEmpty);
    });
  });

  group('DemoAdminRepository actions (what the Functions check)', () {
    test('an agent moves their own lead one allowed step, and it is in the audit log', () async {
      final repo = DemoAdminRepository(clock: () => DateTime(2026, 10, 28, 9));
      final lead = (await repo.leads(wanjiku, stage: 'new')).rows.first;
      await repo.moveLead(wanjiku, leadId: lead.id, stage: 'contacted');
      final moved = (await repo.leads(wanjiku, limit: 100)).rows.firstWhere((r) => r.id == lead.id);
      expect(moved.stage, 'contacted');
      final entry = (await repo.audit(manager)).rows.first;
      expect(
          (entry.actorName, entry.action, entry.from, entry.to), ('Wanjiku Mwangi', 'lead.stage', 'new', 'contacted'));
      expect(entry.at, DateTime(2026, 10, 28, 9));
    });

    test("refuses other agents' leads, impossible moves and agents moderating", () async {
      final repo = DemoAdminRepository();
      final others =
          (await repo.leads(manager, stage: 'new', limit: 100)).rows.firstWhere((r) => r.agentId != 'agent-wanjiku');
      Future<void> fails(Future<void> f, String code) =>
          expectLater(f, throwsA(isA<AdminActionException>().having((e) => e.code, 'code', code)));
      await fails(repo.moveLead(wanjiku, leadId: others.id, stage: 'contacted'), 'permission-denied');
      await fails(repo.moveLead(manager, leadId: others.id, stage: 'won'), 'failed-precondition');
      final pending = (await repo.listings(manager, status: 'pending')).rows.first;
      await fails(repo.moderateListing(wanjiku, listingId: pending.id, action: 'approve'), 'permission-denied');
      await fails(
          repo.moderateListing(manager, listingId: pending.id, action: 'reject', reason: ' '), 'invalid-argument');
      await fails(repo.moderateListing(manager, listingId: pending.id, action: 'sold'), 'failed-precondition');
      await repo.moderateListing(manager, listingId: pending.id, action: 'approve');
      expect((await repo.listings(manager, status: 'live', limit: 100)).rows.map((r) => r.id), contains(pending.id));
    });
  });

  group('DemoAdminRepository team (what setStaffRole checks)', () {
    test('an owner adds someone who has signed in, as an agent of a real agent record', () async {
      final repo = DemoAdminRepository();
      await repo.setStaffRole(owner, email: 'New.Agent@example.com', role: StaffRole.agent, agentId: 'agent-achieng');
      final added = (await repo.team(owner)).firstWhere((m) => m.email == 'new.agent@example.com');
      expect((added.role, added.agentId, added.agentName), (StaffRole.agent, 'agent-achieng', 'Achieng Odhiambo'));
      final entry = (await repo.audit(owner)).rows.first;
      expect(
          (entry.action, entry.target, entry.from, entry.to), ('staff.role', 'new.agent@example.com', 'none', 'agent'));
    });

    test('refuses non-owners, unknown emails, agents without a record and owner lock-out', () async {
      final repo = DemoAdminRepository();
      Future<void> fails(Future<void> f, String code) =>
          expectLater(f, throwsA(isA<AdminActionException>().having((e) => e.code, 'code', code)));
      await fails(
          repo.setStaffRole(manager, email: 'new.agent@example.com', role: StaffRole.manager), 'permission-denied');
      await fails(repo.setStaffRole(owner, email: 'nobody@example.com', role: StaffRole.manager), 'not-found');
      await fails(repo.setStaffRole(owner, email: 'new.agent@example.com', role: StaffRole.agent), 'invalid-argument');
      await fails(repo.setStaffRole(owner, email: 'owner@example.com', role: StaffRole.manager), 'failed-precondition');
      expect(() => repo.team(wanjiku), throwsA(isA<StaffAccessException>()));
    });
  });

  testWidgets('signed out, the admin opens on sign in', (tester) async {
    await open(tester);
    expect(location(), signInPath);
    expect(find.text('Demo Owner'), findsOneWidget);
  });

  testWidgets("an agent sees only their own leads, and no audit log", (tester) async {
    await open(tester, as: wanjiku);
    expect(location(), '/leads');
    expect(find.text('Your leads, newest first.'), findsOneWidget);
    expect(find.text('Audit log'), findsNothing);
    expect(find.text('Agent'), findsNothing);
    final own = (await DemoAdminRepository().leads(wanjiku, limit: pageSize)).rows;
    final others =
        (await DemoAdminRepository().leads(manager, limit: 100)).rows.where((r) => r.agentId != 'agent-wanjiku');
    expect(find.text(own.first.contactPhone!), findsOneWidget);
    for (final r in others) {
      expect(find.text(r.contactPhone!), findsNothing, reason: r.id);
    }

    container.read(routerProvider).go('/audit');
    await tester.pumpAndSettle();
    expect(location(), '/leads');
  });

  testWidgets('a manager sees every agent, the audit log, and pages through', (tester) async {
    await open(tester, as: manager);
    expect(find.text('Agent'), findsOneWidget);
    expect(find.text('Page 1'), findsOneWidget);
    final all = (await DemoAdminRepository().leads(manager, limit: 100)).rows;
    expect(find.text(all.first.contactPhone!), findsOneWidget);
    expect(find.text(all[pageSize].contactPhone!), findsNothing);

    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(find.text('Page 2'), findsOneWidget);
    expect(find.text(all[pageSize].contactPhone!), findsOneWidget);
    expect(find.text(all.first.contactPhone!), findsNothing);

    await tester.tap(find.byTooltip('Previous page'));
    await tester.pumpAndSettle();
    expect(find.text('Page 1'), findsOneWidget);
    expect(find.text(all.first.contactPhone!), findsOneWidget);

    await tester.tap(find.text('Audit log'));
    await tester.pumpAndSettle();
    expect(location(), '/audit');
    expect(find.text('Photos missing'), findsWidgets);
  });

  testWidgets('a status filter starts again from page 1 with only that status', (tester) async {
    await open(tester, as: manager);
    await tester.tap(find.text('Listings'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Live'));
    await tester.pumpAndSettle();
    final live = (await DemoAdminRepository().listings(manager, status: 'live', limit: 100)).rows;
    final notLive = (await DemoAdminRepository().listings(manager, limit: 100)).rows.where((r) => r.status != 'live');
    expect(live, isNotEmpty);
    for (final r in live) {
      expect(find.text(r.title), findsWidgets);
    }
    expect(find.text('Page 1'), findsOneWidget);
    for (final r in notLive.where((r) => live.every((l) => l.title != r.title))) {
      expect(find.text(r.title), findsNothing, reason: r.id);
    }
  });

  testWidgets('an agent moves a lead on from its stage menu', (tester) async {
    await open(tester, as: wanjiku);
    await tester.tap(find.widgetWithText(ChoiceChip, 'New'));
    await tester.pumpAndSettle();
    final lead = (await container.read(adminRepositoryProvider).leads(wanjiku, stage: 'new')).rows.first;
    await tapVisible(tester, find.byTooltip('Move ${lead.contactName} on'));
    expect(find.text('Lost'), findsWidgets);
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'Contacted'));
    await tester.pumpAndSettle();
    expect(find.text('${lead.contactName} moved to Contacted'), findsOneWidget);
    // Filtered on New, the moved lead leaves the page.
    expect(find.byTooltip('Move ${lead.contactName} on'), findsNothing);
  });

  testWidgets('while a stage change saves, the row shows it and offers nothing else', (tester) async {
    await open(tester, as: wanjiku, slowActions: true);
    await tester.tap(find.widgetWithText(ChoiceChip, 'New'));
    await tester.pumpAndSettle();
    final lead = (await container.read(adminRepositoryProvider).leads(wanjiku, stage: 'new')).rows.first;
    await tapVisible(tester, find.byTooltip('Move ${lead.contactName} on'));
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'Contacted'));
    await tester.pump();

    expect(find.bySemanticsLabel('Saving'), findsOneWidget);
    expect(find.byTooltip('Move ${lead.contactName} on'), findsNothing, reason: 'no second pick while saving');
    expect(slow.calls, 1);

    slow.gate.complete();
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Saving'), findsNothing);
    expect(find.text('${lead.contactName} moved to Contacted'), findsOneWidget);
    expect(slow.calls, 1);
  });

  testWidgets('agents get no moderation, only "Confirm still available" on their live or expired listings',
      (tester) async {
    await open(tester, as: wanjiku);
    await tester.tap(find.text('Listings'));
    await tester.pumpAndSettle();
    final mine = (await container.read(adminRepositoryProvider).listings(wanjiku, limit: 50)).rows;
    final confirmable = mine.where((r) => r.status == 'live' || r.status == 'expired').toList();
    expect(confirmable, isNotEmpty);
    expect(find.byType(PopupMenuButton<String>), findsNWidgets(confirmable.length));

    final picked = confirmable.first;
    await tapVisible(tester, find.byTooltip('Change ${picked.title}'));
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Mark expired'), findsNothing);
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'Confirm still available'));
    await tester.pumpAndSettle();
    expect(find.text('${picked.title}: confirmed, verified for 30 days'), findsOneWidget);
    final after = (await container.read(adminRepositoryProvider).listings(wanjiku, limit: 50))
        .rows
        .firstWhere((r) => r.id == picked.id);
    expect(after.status, 'live');
    expect(after.expiresAt!.isAfter(DateTime.now().add(const Duration(days: 29))), isTrue);
  });

  testWidgets('a manager rejects a pending listing with a reason, and the audit log shows it', (tester) async {
    await open(tester, as: manager);
    await tester.tap(find.text('Listings'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Pending'));
    await tester.pumpAndSettle();
    final listing = (await container.read(adminRepositoryProvider).listings(manager, status: 'pending')).rows.first;
    await tapVisible(tester, find.byTooltip('Change ${listing.title}'));
    await tester.tap(find.text('Reject…'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save')).onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'Blurry photos');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('${listing.title}: Draft'), findsOneWidget);

    await tester.tap(find.text('Audit log'));
    await tester.pumpAndSettle();
    expect(find.text('Blurry photos'), findsOneWidget);
    expect(find.text('Listing reject'), findsWidgets);
  });

  testWidgets('cancelling the reason leaves the listing as it was', (tester) async {
    await open(tester, as: manager);
    await tester.tap(find.text('Listings'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Pending'));
    await tester.pumpAndSettle();
    final listing = (await container.read(adminRepositoryProvider).listings(manager, status: 'pending')).rows.first;
    await tapVisible(tester, find.byTooltip('Change ${listing.title}'));
    await tester.tap(find.text('Reject…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    final still = (await container.read(adminRepositoryProvider).listings(manager, status: 'pending')).rows;
    expect(still.map((r) => r.id), contains(listing.id));
  });

  testWidgets('an owner adds someone to the team as an agent, then removes them', (tester) async {
    await open(tester, as: owner);
    await tester.tap(find.text('Team'));
    await tester.pumpAndSettle();
    expect(find.text('manager@example.com'), findsOneWidget);
    expect(find.byTooltip('Change owner@example.com'), findsNothing, reason: 'no menu on your own row');

    await tester.tap(find.text('Add someone'));
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, 'Save');
    await tester.enterText(find.widgetWithText(TextField, 'Their email'), 'new.agent@example.com');
    await tester.pump();
    expect(tester.widget<FilledButton>(save).onPressed, isNull, reason: 'an agent needs an agent record');
    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Acts as agent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Achieng Odhiambo').last);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.textContaining('new.agent@example.com is now agent'), findsOneWidget);
    expect(find.text('new.agent@example.com'), findsOneWidget);

    await tapVisible(tester, find.byTooltip('Change new.agent@example.com'));
    await tester.tap(find.text('Remove from staff…'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(find.text('new.agent@example.com'), findsNothing);
  });

  testWidgets('the team loads once, not again on every rebuild', (tester) async {
    await open(tester, as: owner);
    final demo = container.read(demoAdminProvider);
    final before = demo.teamCalls;
    await tester.tap(find.text('Team'));
    await tester.pumpAndSettle();
    expect(demo.teamCalls, before + 1);
    // A full rebuild (what a token refresh or theme change does) must not refetch.
    tester.binding.buildOwner!.reassemble(tester.binding.rootElement!);
    await tester.pump(const Duration(seconds: 1));
    expect(demo.teamCalls, before + 1);
    expect(find.text('owner@example.com'), findsOneWidget);
  });

  testWidgets('managers see the team but cannot change it; agents do not see it', (tester) async {
    await open(tester, as: manager);
    await tester.tap(find.text('Team'));
    await tester.pumpAndSettle();
    expect(find.text('Only owners change roles.'), findsOneWidget);
    expect(find.text('Add someone'), findsNothing);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    await tester.tap(find.byTooltip('Sign out (${manager.name})'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(wanjiku.name));
    await tester.pumpAndSettle();
    expect(find.text('Team'), findsNothing);
    container.read(routerProvider).go('/team');
    await tester.pumpAndSettle();
    expect(location(), '/leads');
  });

  testWidgets('a manager exports what is held about a phone, then deletes it; the audit log keeps no number',
      (tester) async {
    await open(tester, as: manager);
    await tester.tap(find.text('Privacy'));
    await tester.pumpAndSettle();
    expect(location(), '/privacy');
    final export = find.widgetWithText(FilledButton, 'Export');
    expect(tester.widget<FilledButton>(export).onPressed, isNull, reason: 'nothing typed yet');
    await tester.enterText(find.widgetWithText(TextField, 'Phone'), '0712');
    await tester.pump();
    expect(find.text('Enter a Kenyan mobile number'), findsOneWidget);
    expect(tester.widget<FilledButton>(export).onPressed, isNull);

    // Demo leads carry phones +254700000200 to +254700000299.
    await tester.enterText(find.widgetWithText(TextField, 'Phone'), '0700 000 201');
    await tester.pump();
    await tester.tap(export);
    await tester.pumpAndSettle();
    expect(find.textContaining('Found 1 enquiries and 0 viewing requests'), findsOneWidget);
    expect(find.textContaining('"phone": "+254700000201"'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete…'));
    await tester.pumpAndSettle();
    expect(find.text('Delete everything held about +254700000201?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Deleted 1 enquiries and 0 viewing requests.'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Export'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing is held for +254700000201.'), findsOneWidget);

    await tester.tap(find.text('Audit log'));
    await tester.pumpAndSettle();
    expect(find.text('Privacy delete'), findsOneWidget);
    expect(find.textContaining('700000201'), findsNothing);
  });

  testWidgets('agents have no privacy page', (tester) async {
    await open(tester, as: wanjiku);
    expect(find.text('Privacy'), findsNothing);
    container.read(routerProvider).go('/privacy');
    await tester.pumpAndSettle();
    expect(location(), '/leads');
  });

  testWidgets('managers see a flag on a listing whose photo matches another; agents do not', (tester) async {
    const why = 'A photo here matches another listing. Check it is theirs to use.';
    await open(tester, as: manager);
    await tester.tap(find.text('Listings'));
    await tester.pumpAndSettle();
    expect(find.byTooltip(why), findsOneWidget);
    await tester.tap(find.byTooltip('Sign out (${manager.name})'));
    await tester.pumpAndSettle();
    // listing-005 (the flagged one) is Brian Otieno's.
    final otieno = demoStaff.firstWhere((s) => s.agentId == 'agent-otieno');
    await tester.tap(find.text(otieno.name));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Listings'));
    await tester.pumpAndSettle();
    expect(find.byTooltip(why), findsNothing);
  });

  test('reply times read as minutes, hours or days', () {
    expect([minutesLabel(0), minutesLabel(59), minutesLabel(90), minutesLabel(1440), minutesLabel(4000)],
        ['0 min', '59 min', '2 h', '1 day', '3 days']);
  });

  testWidgets("the team shows each agent's typical reply; new leads show how long they have waited", (tester) async {
    await open(tester, as: manager);
    await tester.tap(find.text('Team'));
    await tester.pumpAndSettle();
    expect(find.text('Typical reply'), findsOneWidget);
    expect(find.text('25 min'), findsOneWidget); // Wanjiku
    expect(find.text('2 h'), findsOneWidget); // Otieno, 140 min
    await tester.tap(find.text('Leads'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'New'));
    await tester.pumpAndSettle();
    expect(find.textContaining('waiting '), findsWidgets);
  });

  testWidgets('a manager features a live listing and stops it; the star follows', (tester) async {
    await open(tester, as: manager);
    await tester.tap(find.text('Listings'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Live'));
    await tester.pumpAndSettle();
    final rows = (await container.read(adminRepositoryProvider).listings(manager, status: 'live', limit: 50)).rows;
    final plain = rows.firstWhere((r) => !r.featuredAt(DateTime.now()));
    expect(find.byIcon(Icons.star), findsOneWidget, reason: 'the demo has one featured listing');
    await tapVisible(tester, find.byTooltip('Change ${plain.title}'));
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'Feature for $featureDays days'));
    await tester.pumpAndSettle();
    expect(find.text('${plain.title}: featured for $featureDays days'), findsOneWidget);
    expect(find.byIcon(Icons.star), findsNWidgets(2));
    await tapVisible(tester, find.byTooltip('Change ${plain.title}'));
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'Stop featuring'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.star), findsOneWidget);
  });

  testWidgets('a manager imports a CSV: checked first, bad lines named, good ones land in Pending', (tester) async {
    await open(tester, as: manager);
    await tester.tap(find.text('Listings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import CSV…'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'CSV'),
      'title,purpose,type,beds,baths,priceKES,lat,lng,area,agentId\n'
      'Imported studio Kilimani,rent,studio,0,1,"25,000",-1.29,36.78,kilimani,agent-wanjiku\n'
      'Broken row,rent,castle,1,1,20000,-1.29,36.78,kilimani,agent-wanjiku\n'
      'Ghost agent flat,rent,apartment,1,1,30000,-1.29,36.78,kilimani,agent-ghost\n',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Check'));
    await tester.pumpAndSettle();
    expect(find.text('2 listings ready to import.'), findsOneWidget);
    expect(find.textContaining('Line 3: type "castle"'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Import 2'));
    await tester.pumpAndSettle();
    expect(find.text('Imported 1 listings. They wait in Pending for approval.'), findsOneWidget);
    expect(find.textContaining('Line 4: agentId: no agent "agent-ghost"'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    final pending = (await container.read(adminRepositoryProvider).listings(manager, status: 'pending', limit: 50)).rows;
    expect(pending.map((r) => r.title), contains('Imported studio Kilimani'));
  });

  testWidgets('an agent adds a listing: problems shown first, then it lands in Pending as theirs', (tester) async {
    await open(tester, as: wanjiku);
    await tester.tap(find.text('Listings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New listing'));
    await tester.pumpAndSettle();
    expect(find.text('Agent'), findsNothing, reason: 'an agent lists as themself');
    await tester.tap(find.text('Save and send for review'));
    await tester.pumpAndSettle();
    expect(find.text('Use 5 to 120 characters.'), findsOneWidget);
    expect(find.text('Pick an area.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Title'), '2 bedroom flat near Yaya');
    await tester.enterText(find.widgetWithText(TextField, 'Rent a month (KES)'), '68,000');
    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Area'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kilimani').last);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Latitude')).controller!.text, '-1.292100');
    await tester.tap(find.text('Save and send for review'));
    await tester.pumpAndSettle();
    expect(find.text('Saved. The listing waits in Pending for approval.'), findsOneWidget);

    final mine = (await container.read(adminRepositoryProvider).listings(wanjiku, status: 'pending', limit: 50)).rows;
    final row = mine.firstWhere((r) => r.title == '2 bedroom flat near Yaya');
    expect((row.priceKES, row.area, row.agentId), (68000, 'kilimani', wanjiku.agentId));
    final draft = await container.read(adminRepositoryProvider).listingDraft(wanjiku, row.id);
    expect((draft!.lat, draft.lng), (-1.2921, 36.7856));
  });

  testWidgets('a manager edits a listing from its title; the edit goes back to Pending', (tester) async {
    await open(tester, as: manager);
    await tester.tap(find.text('Listings'));
    await tester.pumpAndSettle();
    final first = (await container.read(adminRepositoryProvider).listings(manager, limit: 1)).rows.single;
    await tester.tap(find.text(first.title).first);
    await tester.pumpAndSettle();
    expect(find.text('Edit listing'), findsOneWidget);
    expect(find.widgetWithText(DropdownButtonFormField<String>, 'Agent'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Title'), '${first.title}, renovated');
    await tester.tap(find.text('Save and send for review'));
    await tester.pumpAndSettle();
    final row = (await container.read(adminRepositoryProvider).listings(manager, limit: 1)).rows.single;
    expect((row.id, row.title, row.status), (first.id, '${first.title}, renovated', 'pending'));
  });

  testWidgets('photos: a new listing says to save first; an existing one uploads, refusing what the rules would', (tester) async {
    final picked = <PickedFile>[
      (name: 'lounge.jpg', bytes: Uint8List(2048), type: 'image/jpeg'),
      (name: 'notes.pdf', bytes: Uint8List(10), type: 'application/pdf'),
      (name: 'tour.mp4', bytes: Uint8List(4096), type: 'video/mp4'),
    ];
    await open(tester, as: wanjiku, overrides: [filePickerProvider.overrideWithValue(_FakePicker(picked))]);
    await tester.tap(find.text('Listings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New listing'));
    await tester.pumpAndSettle();
    expect(find.text('Save the listing first, then open it again to add photos.'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    final mine = (await container.read(adminRepositoryProvider).listings(wanjiku, limit: 1)).rows.single;
    await tester.tap(find.text(mine.title).first);
    await tester.pumpAndSettle();
    expect(find.text('Photos and video: 0 photos'), findsOneWidget);
    await tapVisible(tester, find.text('Add photos or a video'));
    expect(find.textContaining('notes.pdf: not a photo or video'), findsOneWidget);
    expect(find.text('Photos and video: 1 photo, 1 video'), findsOneWidget);
    expect(find.textContaining('Uploaded 2.'), findsOneWidget);
  });

  test('upload paths follow storage.rules: agents under their agent id, managers under their uid', () {
    final at = DateTime.utc(2026, 10, 28);
    expect(uploadPath(wanjiku, 'l1', 'My Lounge (1).jpg', at),
        'uploads/agents/agent-wanjiku/listings/l1/${at.millisecondsSinceEpoch}-My-Lounge-1-.jpg');
    expect(uploadPath(manager, 'l1', 'a.jpg', at), 'uploads/staff/${manager.uid}/listings/l1/${at.millisecondsSinceEpoch}-a.jpg');
    expect(uploadProblem((name: 'big.jpg', bytes: Uint8List(maxPhotoBytes), type: 'image/jpeg')), contains('under 20 MB'));
  });

  testWidgets('agents get no import button', (tester) async {
    await open(tester, as: wanjiku);
    await tester.tap(find.text('Listings'));
    await tester.pumpAndSettle();
    expect(find.text('Import CSV…'), findsNothing);
  });

  testWidgets('viewings: a past confirmed one comes first to close; marking it a no-show moves it to history',
      (tester) async {
    await open(tester, as: manager);
    await tester.tap(find.text('Viewings'));
    await tester.pumpAndSettle();
    expect(location(), '/viewings');
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day - openViewingsDays);
    final openRows = (await container.read(adminRepositoryProvider).viewings(manager, from: from, limit: 50)).rows;
    final past = openRows.first;
    expect(past.slot.isBefore(now), isTrue, reason: 'earliest first: yesterday\'s confirmed viewing leads');
    expect(openRows.every((v) => v.status == 'requested' || v.status == 'confirmed'), isTrue);

    await tapVisible(tester, find.byTooltip('Update the viewing ${shortDateTime(past.slot)}'));
    expect(find.text('Mark done'), findsOneWidget);
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'Mark no-show'));
    await tester.pumpAndSettle();
    expect(find.text('Viewing ${shortDateTime(past.slot)}: No show'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'No show'));
    await tester.pumpAndSettle();
    final noShows = (await container.read(adminRepositoryProvider).viewings(manager, status: 'no-show', from: from)).rows;
    expect(noShows.map((v) => v.id), contains(past.id));
  });

  testWidgets('a future viewing can only be confirmed or cancelled; agents see only their own', (tester) async {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day - openViewingsDays);
    await open(tester, as: wanjiku);
    await tester.tap(find.text('Viewings'));
    await tester.pumpAndSettle();
    final mine = (await container.read(adminRepositoryProvider).viewings(wanjiku, from: from, limit: 50)).rows;
    expect(mine, isNotEmpty);
    expect(mine.every((v) => v.agentId == 'agent-wanjiku'), isTrue);
    final future = mine.firstWhere((v) => v.slot.isAfter(now) && v.status == 'requested');
    await tapVisible(tester, find.byTooltip('Update the viewing ${shortDateTime(future.slot)}'));
    expect(find.text('Mark done'), findsNothing);
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'Confirm'));
    await tester.pumpAndSettle();
    expect(find.text('Viewing ${shortDateTime(future.slot)}: Confirmed'), findsOneWidget);
  });

  testWidgets('an agent reschedules a viewing: confirmed at the new time, the old one cancelled', (tester) async {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day - openViewingsDays);
    await open(tester, as: wanjiku);
    await tester.tap(find.text('Viewings'));
    await tester.pumpAndSettle();
    final repo = container.read(adminRepositoryProvider);
    final future = (await repo.viewings(wanjiku, from: from, limit: 50)).rows.firstWhere((v) => v.slot.isAfter(now));
    await tapVisible(tester, find.byTooltip('Update the viewing ${shortDateTime(future.slot)}'));
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'Reschedule…'));
    await tester.pumpAndSettle();
    final day = viewingDays(now)[3];
    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Day'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(day.label).last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Time'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('15:00').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move viewing'));
    await tester.pumpAndSettle();

    final at = DateTime.parse(viewingSlot(day.value, '15:00')).toLocal();
    expect(find.text('Viewing moved to ${shortDateTime(at)}, confirmed'), findsOneWidget);
    final open_ = (await repo.viewings(wanjiku, from: from, limit: 50)).rows;
    expect(open_.where((v) => v.id == future.id), isEmpty, reason: 'the old one is cancelled');
    final moved = open_.singleWhere((v) => v.slot == at);
    expect((moved.status, moved.clientName), ('confirmed', future.clientName));
  });

  testWidgets('an agent blocks out time off; rescheduling into it is refused; removing it frees the time', (tester) async {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day - openViewingsDays);
    await open(tester, as: wanjiku);
    await tester.tap(find.text('Viewings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Time off…'));
    await tester.pumpAndSettle();
    expect(find.text('None coming up.'), findsOneWidget);
    expect(find.widgetWithText(DropdownButtonFormField<String>, 'Agent'), findsNothing);
    final day = viewingDays(now, count: 26)[4];
    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'From'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(day.label).last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Note for the team (optional)'), 'Leave');
    await tester.tap(find.text('Add time off').last);
    await tester.pumpAndSettle();
    final blocks = await container.read(adminRepositoryProvider).timeOff(wanjiku, now);
    expect(blocks.single.start, DateTime.parse(viewingSlot(day.value, '08:00')).toLocal());
    expect(blocks.single.end, DateTime.parse(viewingSlot(day.value, '18:00')).toLocal());
    expect(find.text('Leave'), findsOneWidget);

    final actions = container.read(adminActionsProvider);
    final v = (await container.read(adminRepositoryProvider).viewings(wanjiku, from: from, limit: 50)).rows.firstWhere((v) => v.slot.isAfter(now));
    await expectLater(actions.rescheduleViewing(wanjiku, viewingId: v.id, slot: viewingSlot(day.value, '10:00')),
        throwsA(isA<AdminActionException>().having((e) => e.code, 'code', 'already-exists')));

    await tester.tap(find.byTooltip('Remove this time off'));
    await tester.pumpAndSettle();
    expect(find.text('None coming up.'), findsOneWidget);
    expect(await actions.rescheduleViewing(wanjiku, viewingId: v.id, slot: viewingSlot(day.value, '10:00')), isNotEmpty);
  });

  testWidgets('signing out returns to sign in', (tester) async {
    await open(tester, as: owner);
    await tester.tap(find.byTooltip('Sign out (${owner.name})'));
    await tester.pumpAndSettle();
    expect(location(), signInPath);
  });

  testWidgets('narrow windows get a bottom bar and no overflow', (tester) async {
    await open(tester, as: manager, width: 412);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Demo Manager · Manager'), findsNothing);
    expect(find.byTooltip('Sign out (Demo Manager)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
