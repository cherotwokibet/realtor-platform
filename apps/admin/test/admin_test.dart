import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtor_admin/src/app.dart';
import 'package:realtor_admin/src/demo_admin.dart';
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
  Future<void> setStaffRole(StaffUser who, {required String email, required StaffRole? role, String? agentId}) async {
    calls++;
    await gate.future;
    return inner.setStaffRole(who, email: email, role: role, agentId: agentId);
  }
}

late SlowActions slow;

Future<void> open(WidgetTester tester, {StaffUser? as, double width = 1280, bool slowActions = false}) async {
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final demo = DemoAdminRepository();
  slow = SlowActions(demo);
  container = ProviderContainer(overrides: [
    tenantProvider.overrideWithValue(tenant()),
    demoAdminProvider.overrideWithValue(demo),
    if (slowActions) adminActionsProvider.overrideWithValue(slow),
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

  testWidgets('agents get no moderation menu on listings', (tester) async {
    await open(tester, as: wanjiku);
    await tester.tap(find.text('Listings'));
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuButton<String>), findsNothing);
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
