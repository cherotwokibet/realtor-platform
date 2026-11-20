import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:realtor_admin/src/app.dart';
import 'package:realtor_admin/src/dashboard.dart';
import 'package:realtor_admin/src/demo_admin.dart';
import 'package:realtor_admin/src/format.dart';
import 'package:realtor_admin/src/links.dart';
import 'package:realtor_admin/src/listing_media.dart';
import 'package:realtor_admin/src/maps.dart';
import 'package:realtor_admin/src/providers.dart';
import 'package:realtor_admin/src/reports.dart';
import 'package:realtor_admin/src/session.dart';
import 'package:realtor_core/realtor_core.dart';

TenantConfig tenant([String id = 'realtime-estates']) =>
    TenantConfig.fromJson(jsonDecode(File('../../tenants/$id.json').readAsStringSync()) as Map<String, Object?>);

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
  Future<void> followUpLead(StaffUser who, {required String leadId, String? note, DateTime? followUpAt, bool clearFollowUp = false}) =>
      inner.followUpLead(who, leadId: leadId, note: note, followUpAt: followUpAt, clearFollowUp: clearFollowUp);

  @override
  Future<void> moderateListing(StaffUser who, {required String listingId, required String action, String? reason}) async {
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
  Future<MonthlyReport> monthlyReport(StaffUser who, String month) => inner.monthlyReport(who, month);

  @override
  Future<String> saveArea(StaffUser who, AreaGuide area) => inner.saveArea(who, area);

  @override
  Future<void> savePage(StaffUser who, SitePageRow page) => inner.savePage(who, page);

  @override
  Future<String> saveProject(StaffUser who, OffPlanProject project) => inner.saveProject(who, project);

  @override
  Future<({double? rating, int count})> moderateReview(StaffUser who, {required String reviewId, required String action}) =>
      inner.moderateReview(who, reviewId: reviewId, action: action);

  @override
  Future<String> saveAgent(StaffUser who, AgentProfile profile) async {
    calls++;
    await gate.future;
    return inner.saveAgent(who, profile);
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
  Future<bool> setHotListing(StaffUser who, {required String listingId, required bool hot}) async {
    calls++;
    await gate.future;
    return inner.setHotListing(who, listingId: listingId, hot: hot);
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
  Future<bool> setPlacement(StaffUser who, {required String listingId, required String placement, required bool on}) =>
      inner.setPlacement(who, listingId: listingId, placement: placement, on: on);

  @override
  Future<void> moderateEdit(StaffUser who, {required String listingId, required bool approve, String? reason}) =>
      inner.moderateEdit(who, listingId: listingId, approve: approve, reason: reason);

  @override
  Future<void> updateFeedback(StaffUser who, {required String feedbackId, String? status, String? note}) =>
      inner.updateFeedback(who, feedbackId: feedbackId, status: status, note: note);

  @override
  Future<String> saveAd(StaffUser who, AdRow ad) => inner.saveAd(who, ad);

  @override
  Future<void> deleteAd(StaffUser who, String adId) => inner.deleteAd(who, adId);

  @override
  Future<void> saveMyProfile(StaffUser who, {required String name, String? phone}) => inner.saveMyProfile(who, name: name, phone: phone);

  @override
  Future<DataRequestResult> dataRequest(StaffUser who, {required DataRequestKind kind, String? phone, String? email}) async {
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

/// Opens the admin; signed in [as] someone, it then goes to [at] (Leads by
/// default, where most tests start; null stays on the Dashboard).
Future<void> open(WidgetTester tester,
    {StaffUser? as,
    double width = 1280,
    bool slowActions = false,
    List<Override> overrides = const [],
    String tenantId = 'realtime-estates',
    String? at = '/leads'}) async {
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final demo = DemoAdminRepository();
  slow = SlowActions(demo);
  container = ProviderContainer(overrides: [
    tenantProvider.overrideWithValue(tenant(tenantId)),
    demoAdminProvider.overrideWithValue(demo),
    adminMapTilesProvider.overrideWithValue(false),
    if (slowActions) adminActionsProvider.overrideWithValue(slow),
    ...overrides,
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const AdminApp()));
  await tester.pumpAndSettle();
  if (as != null) {
    await tester.tap(find.text(as.name));
    await tester.pumpAndSettle();
    if (at != null) {
      container.read(routerProvider).go(at);
      await tester.pumpAndSettle();
    }
  }
}

String location() => container.read(routerProvider).routerDelegate.currentConfiguration.uri.path;

void main() {
  group('adminRedirect', () {
    test('signed out goes to sign in; signed in leaves it', () {
      expect(adminRedirect(const SignedOut(), '/leads'), signInPath);
      expect(adminRedirect(const SignedOut(), signInPath), isNull);
      expect(adminRedirect(const NotStaff('x@example.com'), '/leads'), signInPath);
      expect(adminRedirect(SignedIn(manager), signInPath), '/dashboard');
      expect(adminRedirect(SignedIn(manager), '/'), '/dashboard');
    });

    test('while starting, a deep link stays put', () {
      expect(adminRedirect(const Starting(), '/listings'), isNull);
    });

    test('nobody opens a section their role does not cover', () {
      expect(adminRedirect(SignedIn(wanjiku), '/audit'), '/dashboard');
      expect(adminRedirect(SignedIn(wanjiku), '/listings'), isNull);
      expect(adminRedirect(SignedIn(manager), '/audit'), isNull);
      expect(adminRedirect(SignedIn(owner), '/nowhere'), '/dashboard');
    });
  });

  group('DemoAdminRepository', () {
    final repo = DemoAdminRepository();

    test('confirming: own or manager, live or expired only', () async {
      final otieno = demoStaff.firstWhere((s) => s.agentId == 'agent-otieno');
      final all = (await repo.listings(manager, limit: 50)).rows;
      final wanjikus = all.firstWhere((r) => r.agentId == 'agent-wanjiku' && r.status == 'live');
      await expectLater(
          repo.confirmListing(otieno, listingId: wanjikus.id), throwsA(isA<AdminActionException>().having((e) => e.code, 'code', 'permission-denied')));
      final pending = all.firstWhere((r) => r.status == 'pending');
      await expectLater(
          repo.confirmListing(manager, listingId: pending.id), throwsA(isA<AdminActionException>().having((e) => e.code, 'code', 'failed-precondition')));
      expect(listingActionsFor(otieno, status: 'live', agentId: 'agent-otieno'), ['confirm']);
      expect(listingActionsFor(otieno, status: 'live', agentId: 'agent-wanjiku'), isEmpty);
      expect(listingActionsFor(manager, status: 'live', agentId: 'x'), [...moderationsFor('live'), 'confirm', 'hot', 'feature']);
      expect(listingActionsFor(manager, status: 'live', agentId: 'x', hot: true), contains('unhot'));
      expect(listingActionsFor(manager, status: 'pending', agentId: 'x'), isNot(contains('hot')));
      expect(listingActionsFor(otieno, status: 'live', agentId: 'agent-otieno'), isNot(contains('hot')), reason: 'managers only');
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
      expect((entry.actorName, entry.action, entry.from, entry.to), ('Wanjiku Mwangi', 'lead.stage', 'new', 'contacted'));
      expect(entry.at, DateTime(2026, 10, 28, 9));
    });

    test("refuses other agents' leads, impossible moves and agents moderating", () async {
      final repo = DemoAdminRepository();
      final others = (await repo.leads(manager, stage: 'new', limit: 100)).rows.firstWhere((r) => r.agentId != 'agent-wanjiku');
      Future<void> fails(Future<void> f, String code) => expectLater(f, throwsA(isA<AdminActionException>().having((e) => e.code, 'code', code)));
      await fails(repo.moveLead(wanjiku, leadId: others.id, stage: 'contacted'), 'permission-denied');
      await fails(repo.moveLead(manager, leadId: others.id, stage: 'won'), 'failed-precondition');
      final pending = (await repo.listings(manager, status: 'pending')).rows.first;
      await fails(repo.moderateListing(wanjiku, listingId: pending.id, action: 'approve'), 'permission-denied');
      await fails(repo.moderateListing(manager, listingId: pending.id, action: 'reject', reason: ' '), 'invalid-argument');
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
      expect((entry.action, entry.target, entry.from, entry.to), ('staff.role', 'new.agent@example.com', 'none', 'agent'));
    });

    test('refuses non-owners, unknown emails, agents without a record and owner lock-out', () async {
      final repo = DemoAdminRepository();
      Future<void> fails(Future<void> f, String code) => expectLater(f, throwsA(isA<AdminActionException>().having((e) => e.code, 'code', code)));
      await fails(repo.setStaffRole(manager, email: 'new.agent@example.com', role: StaffRole.manager), 'permission-denied');
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
    expect(find.textContaining('Your leads, newest first.'), findsOneWidget);
    expect(find.text('Audit log'), findsNothing);
    expect(find.descendant(of: find.byType(DataTable), matching: find.text('Agent')), findsNothing, reason: 'no Agent column');
    final own = (await DemoAdminRepository().leads(wanjiku, limit: pageSize)).rows;
    final others = (await DemoAdminRepository().leads(manager, limit: 100)).rows.where((r) => r.agentId != 'agent-wanjiku');
    expect(find.text(own.first.contactPhone!), findsOneWidget);
    for (final r in others) {
      expect(find.text(r.contactPhone!), findsNothing, reason: r.id);
    }

    container.read(routerProvider).go('/audit');
    await tester.pumpAndSettle();
    expect(location(), '/dashboard');
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

  testWidgets('agents get no moderation, only "Confirm still available" on their live or expired listings', (tester) async {
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
    final after = (await container.read(adminRepositoryProvider).listings(wanjiku, limit: 50)).rows.firstWhere((r) => r.id == picked.id);
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
    await tester.tap(find.byKey(const Key('nav-team')));
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
    await tester.tap(find.byKey(const Key('nav-team')));
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
    await tester.tap(find.byKey(const Key('nav-team')));
    await tester.pumpAndSettle();
    expect(find.text('Only admins change roles.'), findsOneWidget);
    expect(find.text('Add someone'), findsNothing);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    await tester.tap(find.byTooltip('Sign out (${manager.name})'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(wanjiku.name));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nav-team')), findsNothing);
    container.read(routerProvider).go('/team');
    await tester.pumpAndSettle();
    expect(location(), '/dashboard');
  });

  testWidgets('a manager exports what is held about a phone, then deletes it; the audit log keeps no number', (tester) async {
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
    expect(find.textContaining('Found 1 enquiries, 0 viewing requests and 0 reviews'), findsOneWidget);
    expect(find.textContaining('"phone": "+254700000201"'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete…'));
    await tester.pumpAndSettle();
    expect(find.text('Delete everything held about +254700000201?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Deleted 1 enquiries, 0 viewing requests and 0 reviews.'), findsOneWidget);

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
    expect(location(), '/dashboard');
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
    expect([minutesLabel(0), minutesLabel(59), minutesLabel(90), minutesLabel(1440), minutesLabel(4000)], ['0 min', '59 min', '2 h', '1 day', '3 days']);
  });

  testWidgets("the team shows each agent's typical reply; new leads show how long they have waited", (tester) async {
    await open(tester, as: manager);
    await tester.tap(find.byKey(const Key('nav-team')));
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

  testWidgets('a manager adds a live listing to Hot Properties and removes it; the flame follows', (tester) async {
    await open(tester, as: manager);
    await tester.tap(find.text('Listings'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Live'));
    await tester.pumpAndSettle();
    final rows = (await container.read(adminRepositoryProvider).listings(manager, status: 'live', limit: 50)).rows;
    final plain = rows.firstWhere((r) => !r.hot);
    expect(find.byIcon(Icons.local_fire_department), findsNothing);
    await tapVisible(tester, find.byTooltip('Change ${plain.title}'));
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'Add to Hot Properties'));
    await tester.pumpAndSettle();
    expect(find.text('${plain.title}: in Hot Properties on the home page'), findsOneWidget);
    expect(find.byIcon(Icons.local_fire_department), findsOneWidget);
    await tapVisible(tester, find.byTooltip('Change ${plain.title}'));
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'Remove from Hot Properties'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.local_fire_department), findsNothing);
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
    expect(find.descendant(of: find.byType(Dialog), matching: find.text('Agent')), findsNothing, reason: 'an agent lists as themself');
    await tester.tap(find.text('Save and send for review'));
    await tester.pumpAndSettle();
    expect(find.text('Use 5 to 120 characters.'), findsOneWidget);
    expect(find.text('Pick an area.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('listing-title')), '2 bedroom flat near Yaya');
    await tester.enterText(find.byKey(const Key('listing-price')), '68,000');
    await tapVisible(tester, find.byKey(const Key('listing-area')));
    await tester.tap(find.text('Kilimani').last);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const Key('listing-lat'))).controller!.text, '-1.292100');
    await tester.tap(find.text('Save and send for review'));
    await tester.pumpAndSettle();
    expect(find.text('Saved. The listing waits in Pending for approval.'), findsOneWidget);

    final mine = (await container.read(adminRepositoryProvider).listings(wanjiku, status: 'pending', limit: 50)).rows;
    final row = mine.firstWhere((r) => r.title == '2 bedroom flat near Yaya');
    expect((row.priceKES, row.area, row.agentId), (68000, 'kilimani', wanjiku.agentId));
    final draft = await container.read(adminRepositoryProvider).listingDraft(wanjiku, row.id);
    expect((draft!.lat, draft.lng), (-1.2921, 36.7856));
  });

  testWidgets('New listing: pin by pasted link, checked against the area outline; amenities and extra charges saved', (tester) async {
    await open(tester, as: wanjiku);
    await tester.tap(find.text('Listings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New listing'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('listing-title')), 'Riverside Heights, 2 bedroom');
    await tester.enterText(find.byKey(const Key('listing-price')), '70000');
    // A pasted Westlands position first, with no area: Westlands has no outline, so nothing is picked.
    await tester.enterText(find.byKey(const Key('listing-paste')), 'https://www.google.com/maps/@-1.2676,36.8108,16z');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const Key('listing-lat'))).controller!.text, '-1.267600');
    // Kilimani has an outline (demo); the Westlands pin is outside it.
    await tapVisible(tester, find.byKey(const Key('listing-area')));
    await tester.tap(find.text('Kilimani').last);
    await tester.pumpAndSettle();
    expect(find.text('The pin is outside Kilimani.'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('amenity-parking')));
    await tapVisible(tester, find.byKey(const Key('amenity-swimming-pool')));
    await tapVisible(tester, find.byKey(const Key('add-charge')));
    await tester.enterText(find.byKey(const Key('charge-name-0')), 'Water');
    await tester.enterText(find.byKey(const Key('charge-amount-0')), '500');
    await tester.tap(find.text('Save and send for review'));
    await tester.pumpAndSettle();
    expect(find.text('New listing'), findsWidgets, reason: 'not saved: the pin is outside');
    // Coordinates inside Kilimani clear it.
    await tester.enterText(find.byKey(const Key('listing-paste')), '-1.2925, 36.7871');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pin-outside')), findsNothing);
    await tester.tap(find.text('Save and send for review'));
    await tester.pumpAndSettle();
    final row =
        (await container.read(adminRepositoryProvider).listings(wanjiku, status: 'pending', limit: 50)).rows.firstWhere((r) => r.title.startsWith('Riverside'));
    final d = (await container.read(adminRepositoryProvider).listingDraft(wanjiku, row.id))!;
    expect((d.lat, d.lng, d.area), (-1.2925, 36.7871, 'kilimani'));
    expect(d.amenities.toSet(), {'parking', 'swimming-pool'});
    expect(d.extraCharges, [const ExtraCharge(name: 'Water', amountKES: 500)]);
  });

  testWidgets('a pin inside an area outline picks that area when none is chosen yet', (tester) async {
    await open(tester, as: wanjiku);
    await tester.tap(find.text('Listings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New listing'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('listing-paste')), '-1.2925, 36.7871');
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byKey(const Key('listing-area')), matching: find.text('Kilimani')), findsOneWidget);
  });

  testWidgets('Areas: a manager clears and redraws an outline by tapping the map', (tester) async {
    await open(tester, as: manager, at: '/areas');
    expect(find.descendant(of: find.byKey(const Key('area-kilimani')), matching: find.text('Outline')), findsOneWidget);
    await tester.tap(find.byKey(const Key('area-kilimani')));
    await tester.pumpAndSettle();
    expect(find.text('4 corners'), findsOneWidget);
    await tester.tap(find.text('Clear outline'));
    await tester.pumpAndSettle();
    expect(find.text('0 corners'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('4 corners'), findsOneWidget);
    await tester.tap(find.text('Clear outline'));
    await tester.pumpAndSettle();
    final map = tester.getRect(find.byType(OutlineMap));
    for (final o in [const Offset(-120, -100), const Offset(120, -100), const Offset(120, 100), const Offset(-120, 100)]) {
      await tester.tapAt(map.center + o);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
    }
    expect(find.text('4 corners'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final k = (await container.read(adminRepositoryProvider).areaGuides()).firstWhere((a) => a.slug == 'kilimani');
    expect(k.boundary, hasLength(4));
    expect(outlineCrosses(k.boundary), isFalse);
    expect(insideOutline(GeoPoint(k.lat, k.lng), k.boundary), isTrue, reason: 'the centre (map middle) is inside');
  });

  testWidgets('"Suggest title & description" drafts both from the facts; asks before replacing (P7-s02)', (tester) async {
    await open(tester, as: wanjiku);
    await tester.tap(find.text('Listings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New listing'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('listing-price')), '68,000');
    await tapVisible(tester, find.byKey(const Key('listing-area')));
    await tester.tap(find.text('Kilimani').last);
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('amenity-parking')));
    await tapVisible(tester, find.byKey(const Key('amenity-borehole')));
    await tapVisible(tester, find.text('Suggest title & description'));
    final title = tester.widget<TextField>(find.byKey(const Key('listing-title'))).controller!.text;
    expect(title, '1 bedroom apartment to let in Kilimani');
    final description = tester.widget<TextField>(find.widgetWithText(TextField, 'Description')).controller!.text;
    expect(description, contains('It comes with parking and a borehole.'));

    // With text already there, it asks first; "Keep mine" changes nothing.
    await tester.enterText(find.byKey(const Key('listing-title')), 'My own title here');
    await tapVisible(tester, find.text('Suggest title & description'));
    expect(find.text('Replace the title and description?'), findsOneWidget);
    await tester.tap(find.text('Keep mine'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const Key('listing-title'))).controller!.text, 'My own title here');

    await tapVisible(tester, find.text('Save and send for review'));
    final row =
        (await container.read(adminRepositoryProvider).listings(wanjiku, status: 'pending', limit: 50)).rows.firstWhere((r) => r.title == 'My own title here');
    final draft = await container.read(adminRepositoryProvider).listingDraft(wanjiku, row.id);
    expect(draft!.description, description, reason: 'the description is saved with the listing');
  });

  testWidgets('a manager edits a listing from its title: a draft goes to Pending, a live one stays live', (tester) async {
    await open(tester, as: manager);
    await tester.tap(find.text('Listings'));
    await tester.pumpAndSettle();
    final rows = (await container.read(adminRepositoryProvider).listings(manager, limit: 15)).rows;
    for (final first in [rows.firstWhere((r) => r.status == 'draft'), rows.firstWhere((r) => r.status == 'live')]) {
      await tapVisible(tester, find.text(first.title).first);
      expect(find.text('Edit listing'), findsOneWidget);
      expect(find.byKey(const Key('listing-agent')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('listing-title')), '${first.title}, renovated');
      await tester.tap(find.text('Save and send for review'));
      await tester.pumpAndSettle();
      final row = (await container.read(adminRepositoryProvider).listings(manager, limit: 50)).rows.firstWhere((r) => r.id == first.id);
      expect((row.title, row.status), ('${first.title}, renovated', first.status == 'live' ? 'live' : 'pending'));
      if (first.status == 'live') expect(find.text('Saved. The changes are live.'), findsOneWidget);
      // Rows reorder after a save: tap the next one by its title, found afresh.
      await tester.pumpAndSettle(const Duration(seconds: 5));
    }
  });

  testWidgets("an agent's change to a live listing waits in Edit requests; a manager sees the changes and approves", (tester) async {
    await open(tester, as: wanjiku);
    await tester.tap(find.text('Listings'));
    await tester.pumpAndSettle();
    final live = (await container.read(adminRepositoryProvider).listings(wanjiku, status: 'live', limit: 5)).rows.first;
    await tapVisible(tester, find.text(live.title).first);
    await tester.enterText(find.byKey(const Key('listing-price')), '99000');
    await tester.tap(find.text('Save and send for review'));
    await tester.pumpAndSettle();
    expect(find.textContaining('stays live as it was'), findsOneWidget);
    var row = (await container.read(adminRepositoryProvider).listings(manager, limit: 50)).rows.firstWhere((r) => r.id == live.id);
    expect((row.status, row.priceKES), ('live', live.priceKES), reason: 'unchanged until approved');
    await tester.tap(find.byKey(const Key('nav-edits')));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('edit-${live.id}')), findsOneWidget, reason: 'the agent sees their own');

    await container.read(adminAuthProvider).signOut();
    await tester.pumpAndSettle();
    await tester.tap(find.text(manager.name));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-edits')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('edit-${live.id}')));
    await tester.pumpAndSettle();
    expect(find.text('Price'), findsOneWidget);
    expect(find.text('KES 99,000'), findsOneWidget);
    await tester.tap(find.byKey(const Key('edit-approve')));
    await tester.pumpAndSettle();
    row = (await container.read(adminRepositoryProvider).listings(manager, limit: 50)).rows.firstWhere((r) => r.id == live.id);
    expect((row.status, row.priceKES), ('live', 99000));
    expect(find.text('No edits waiting.'), findsOneWidget);
  });

  testWidgets('a manager rejects an edit with a reason; the agent sees why', (tester) async {
    await open(tester, as: wanjiku);
    final live = (await container.read(adminRepositoryProvider).listings(wanjiku, status: 'live', limit: 5)).rows.first;
    final draft = (await container.read(adminRepositoryProvider).listingDraft(wanjiku, live.id))!;
    await container.read(adminActionsProvider).submitListing(wanjiku, draft.copyWith(priceKES: 1));
    await container.read(adminAuthProvider).signOut();
    await tester.pumpAndSettle();
    await tester.tap(find.text(manager.name));
    await tester.pumpAndSettle();
    container.read(routerProvider).go('/edits');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('edit-${live.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-reject')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-reject')));
    await tester.pumpAndSettle();
    expect(find.text('Say why, so the agent can fix it.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('edit-reason')), 'That price looks wrong');
    await tester.tap(find.byKey(const Key('edit-reject')));
    await tester.pumpAndSettle();
    final mine = await container.read(adminRepositoryProvider).editRequests(wanjiku);
    expect((mine.first.status, mine.first.reason), ('rejected', 'That price looks wrong'));
  });

  testWidgets('Home page: a manager adds a live listing to Recommended and takes one out of Hot properties', (tester) async {
    await open(tester, as: manager, at: '/homePage');
    final repo = container.read(adminRepositoryProvider);
    final before = (await repo.listings(manager, status: 'live', limit: 100)).rows;
    final candidate = before.firstWhere((l) => !l.recommended);
    final rec = find.byKey(const Key('placement-recommended'));
    await tester.tap(find.descendant(of: rec, matching: find.text('Add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pick-listing-search')), candidate.title);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(Dialog), matching: find.text(candidate.title)).last);
    await tester.pumpAndSettle();
    expect((await repo.listings(manager, status: 'live', limit: 100)).rows.firstWhere((l) => l.id == candidate.id).recommended, isTrue);
    expect(find.descendant(of: rec, matching: find.text(candidate.title)), findsOneWidget);
    await tester.tap(find.descendant(of: rec, matching: find.byTooltip('Take out of Recommended')).first);
    await tester.pumpAndSettle();
    expect((await repo.listings(manager, status: 'live', limit: 100)).rows.where((l) => l.recommended), hasLength(before.where((l) => l.recommended).length));
  });

  testWidgets('agents see their own edit requests but not the Home page', (tester) async {
    await open(tester, as: wanjiku);
    expect(find.byKey(const Key('nav-edits')), findsOneWidget);
    expect(find.byKey(const Key('nav-homePage')), findsNothing);
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
    expect(uploadPath(wanjiku, 'l1', 'My Lounge (1).jpg', at), 'uploads/agents/agent-wanjiku/listings/l1/${at.millisecondsSinceEpoch}-My-Lounge-1-.jpg');
    expect(uploadPath(manager, 'l1', 'a.jpg', at), 'uploads/staff/${manager.uid}/listings/l1/${at.millisecondsSinceEpoch}-a.jpg');
    expect(uploadProblem((name: 'big.jpg', bytes: Uint8List(maxPhotoBytes), type: 'image/jpeg')), contains('under 20 MB'));
  });

  testWidgets('agents get no import button', (tester) async {
    await open(tester, as: wanjiku);
    await tester.tap(find.text('Listings'));
    await tester.pumpAndSettle();
    expect(find.text('Import CSV…'), findsNothing);
  });

  testWidgets('viewings: a past confirmed one comes first to close; marking it a no-show moves it to history', (tester) async {
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
    expect(find.byKey(const Key('listing-agent')), findsNothing);
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

  testWidgets('week calendar: the same bookings as the list, day by day in Nairobi time; weeks move', (tester) async {
    await open(tester, as: manager);
    await tester.tap(find.text('Viewings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Week'));
    await tester.pumpAndSettle();
    final start = weekStart(DateTime.now());
    expect(find.text('Week of ${nairobiDayLabel(start)}'), findsOneWidget);
    expect(find.text('This week'), findsNothing);
    final repo = container.read(adminRepositoryProvider);
    final week = await repo.viewingsBetween(manager, start, start.add(const Duration(days: 7)));
    expect(week.every((v) => v.status != 'cancelled'), isTrue);
    for (var i = 0; i < 7; i++) {
      expect(find.text(nairobiDayLabel(start.add(Duration(days: i)))), findsOneWidget);
    }
    // Every booking this week shows once, with its time and agent (managers).
    for (final v in week) {
      expect(find.text([v.clientName ?? '—', label(v.status), v.agentName].join(' · ')), findsWidgets, reason: v.id);
    }

    await tester.tap(find.byTooltip('Next week'));
    await tester.pumpAndSettle();
    final next = start.add(const Duration(days: 7));
    expect(find.text('Week of ${nairobiDayLabel(next)}'), findsOneWidget);
    final nextWeek = await repo.viewingsBetween(manager, next, next.add(const Duration(days: 7)));
    expect(find.text('Nothing booked'), findsNWidgets(7 - {for (final v in nextWeek) nairobiDayLabel(v.slot)}.length));
    await tester.tap(find.text('This week'));
    await tester.pumpAndSettle();
    expect(find.text('Week of ${nairobiDayLabel(start)}'), findsOneWidget);
  });

  testWidgets('week calendar: an agent sees only their own viewings and their time off', (tester) async {
    await open(tester, as: wanjiku);
    await tester.tap(find.text('Viewings'));
    await tester.pumpAndSettle();
    final repo = container.read(adminRepositoryProvider);
    final start = weekStart(DateTime.now());
    // Time off on the last viewing day of next week, so it is always ahead.
    final day = start.add(const Duration(days: 12));
    await container.read(adminActionsProvider).addTimeOff(wanjiku,
        start: day.add(const Duration(hours: 10)).toIso8601String(), end: day.add(const Duration(hours: 14)).toIso8601String(), note: 'Clinic');
    await tester.tap(find.text('Week'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next week'));
    await tester.pumpAndSettle();
    expect(find.text('Time off'), findsOneWidget);
    expect(find.text('Clinic'), findsOneWidget);
    expect(find.text('10:00–14:00'), findsOneWidget);
    final next = start.add(const Duration(days: 7));
    final mine = await repo.viewingsBetween(wanjiku, next, next.add(const Duration(days: 7)));
    expect(mine.every((v) => v.agentId == 'agent-wanjiku'), isTrue);
    for (final v in mine) {
      expect(find.text([v.clientName ?? '—', label(v.status)].join(' · ')), findsWidgets, reason: v.id);
    }
  });

  testWidgets('a manager adds an agent profile, then gives them a photo', (tester) async {
    final picked = <PickedFile>[(name: 'mercy.jpg', bytes: Uint8List(4096), type: 'image/jpeg')];
    await open(tester, as: manager, overrides: [filePickerProvider.overrideWithValue(_FakePicker(picked))]);
    await tester.tap(find.byKey(const Key('nav-team')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agent profiles…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add agent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter the EARB registration number.'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Mercy Wambui');
    await tester.enterText(find.widgetWithText(TextField, 'EARB registration number'), 'EARB/2026/0412');
    await tester.enterText(find.widgetWithText(TextField, 'Phone'), '0711 000 111');
    await tester.tap(find.text('Kiswahili'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Mercy Wambui'), findsOneWidget);

    final made = (await container.read(adminRepositoryProvider).agentProfiles(manager)).singleWhere((a) => a.name == 'Mercy Wambui');
    expect((made.id, made.phone, made.whatsapp), ('agent-mercy-wambui', '+254711000111', '+254711000111'));
    expect(made.languages, ['en', 'sw']);
    expect((await container.read(adminRepositoryProvider).agents(manager)).map((a) => a.id), contains('agent-mercy-wambui'));

    await tester.tap(find.byTooltip('Edit Mercy Wambui'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload photo'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Uploaded.'), findsOneWidget);
    expect((container.read(listingMediaProvider) as DemoListingMedia).agentPhotos, ['agent-mercy-wambui']);
  });

  testWidgets('agents do not see agent profiles', (tester) async {
    await open(tester, as: wanjiku);
    expect(find.text('Team'), findsNothing);
    expect(() => container.read(adminRepositoryProvider).agentProfiles(wanjiku), throwsA(isA<StaffAccessException>()));
  });

  testWidgets('a manager reads the monthly report and downloads it as CSV; agents have no reports', (tester) async {
    final saver = MemoryFileSaver();
    await open(tester, as: manager, overrides: [fileSaverProvider.overrideWithValue(saver)]);
    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();
    expect(location(), '/reports');
    final month = reportMonths(DateTime.now()).first;
    final r = await container.read(adminActionsProvider).monthlyReport(manager, month);
    expect(find.text('${r.leads} leads, ${r.viewings} viewings'), findsOneWidget);
    expect(find.text('Agents'), findsOneWidget);
    expect(find.text('Shown 120 times, opened 14 (12%)'), findsOneWidget);
    await tester.tap(find.text('Download CSV'));
    await tester.pump();
    expect(saver.saved.single.$1, 'report-$month.csv');
    expect(saver.saved.single.$2, startsWith('Report,$month'));
    expect(saver.saved.single.$2.contains('+2547'), isFalse, reason: 'no client numbers');
  });

  testWidgets('agents cannot open reports', (tester) async {
    await open(tester, as: wanjiku);
    expect(find.text('Reports'), findsNothing);
    await expectLater(container.read(adminActionsProvider).monthlyReport(wanjiku, '2026-10'),
        throwsA(isA<AdminActionException>().having((e) => e.code, 'code', 'permission-denied')));
  });

  testWidgets('a manager adds an area guide; it is offered in the listing form', (tester) async {
    await open(tester, as: manager);
    await tester.tap(find.byKey(const Key('nav-areas')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add area'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Muthaiga North');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('A position in Kenya, e.g. -1.2921, 36.7856.'), findsNWidgets(2));
    await tester.enterText(find.widgetWithText(TextField, 'Centre latitude'), '-1.23');
    await tester.enterText(find.widgetWithText(TextField, 'Centre longitude'), '36.84');
    await tester.enterText(find.widgetWithText(TextField, 'Guide: what living there is like'), 'Quiet and leafy.');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Muthaiga North'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('area-muthaiga-north')), matching: find.text('No outline')), findsOneWidget);
    final options = await container.read(adminRepositoryProvider).areas();
    expect(options.map((a) => a.slug), contains('muthaiga-north'));
  });

  // demo-homes has offPlan on, realtime-estates has it off (P5-s06).
  testWidgets('a manager adds an off-plan project; the payment plan must make 100%', (tester) async {
    await open(tester, as: manager, tenantId: 'demo-homes');
    await tester.tap(find.text('Listings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Off-plan projects…'));
    await tester.pumpAndSettle();
    expect(find.text('Sample Gardens'), findsOneWidget);
    await tester.tap(find.text('Add project'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Project name'), 'Riverside Towers');
    await tester.enterText(find.widgetWithText(TextField, 'Developer'), 'Demo Developers Ltd');
    await tester.enterText(find.widgetWithText(TextField, 'Handover month'), '2029-03');
    await tester.enterText(find.widgetWithText(TextField, 'From KES'), '6,500,000');
    await tester.enterText(find.widgetWithText(TextField, 'Left'), '30');
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Westlands').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '%').last, '80');
    await tapVisible(tester, find.text('Save'));
    expect(find.text('The stages add up to 90%; they must make 100%.'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '%').last, '90');
    await tapVisible(tester, find.text('Save'));
    expect(find.text('Riverside Towers'), findsOneWidget);
    final saved = await container.read(adminRepositoryProvider).projects(manager);
    final p = saved.firstWhere((p) => p.slug == 'riverside-towers');
    expect(p.fromKES, 6500000);
    expect(p.planTotal, 100);
    expect(p.area, 'westlands');
    expect(p.published, isFalse);
  });

  testWidgets('no project editor when the tenant has offPlan off, or for agents', (tester) async {
    await open(tester, as: manager);
    await tester.tap(find.text('Listings'));
    await tester.pumpAndSettle();
    expect(find.text('Off-plan projects…'), findsNothing);
    await expectLater(container.read(adminRepositoryProvider).projects(wanjiku), throwsA(isA<StaffAccessException>()));
  });

  testWidgets('agents get no area editor', (tester) async {
    await open(tester, as: wanjiku);
    await tester.tap(find.text('Listings'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nav-areas')), findsNothing);
  });

  testWidgets('a done viewing offers its review link on WhatsApp to the client', (tester) async {
    final links = MemoryLinkOpener();
    await open(tester, as: manager, overrides: [linkOpenerProvider.overrideWithValue(links)]);
    await tester.tap(find.text('Viewings'));
    await tester.pumpAndSettle();
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day - openViewingsDays);
    final past = (await container.read(adminRepositoryProvider).viewings(manager, from: from, limit: 50))
        .rows
        .firstWhere((v) => v.status == 'confirmed' && v.slot.isBefore(now));
    await tapVisible(tester, find.byTooltip('Update the viewing ${shortDateTime(past.slot)}'));
    expect(find.text('Ask for a review…'), findsNothing, reason: 'not done yet');
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'Mark done'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Done'));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byTooltip('Update the viewing ${shortDateTime(past.slot)}'));
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'Ask for a review…'));
    await tester.pumpAndSettle();
    final uri = links.opened.single;
    expect(uri.host, 'wa.me');
    expect(uri.path, '/${past.clientPhone!.replaceAll('+', '')}');
    expect(uri.queryParameters['text'], contains('https://realtimeestates.co.ke/review/demo-review-'));
  });

  test('review links point at the share site next to this admin', () {
    expect(shareHost('realtimeestates.co.ke', Uri.parse('https://rte-realtor-dev-admin.web.app/viewings')), 'rte-realtor-dev-share.web.app');
    expect(shareHost('realtimeestates.co.ke', Uri.parse('https://admin.realtimeestates.co.ke/')), 'realtimeestates.co.ke');
    expect(shareHost('realtimeestates.co.ke', Uri.parse('http://localhost:8080/')), 'realtimeestates.co.ke');
  });

  testWidgets('a manager approves a waiting review and sees the new rating', (tester) async {
    await open(tester, as: manager);
    await tester.tap(find.byKey(const Key('nav-team')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reviews…'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Showed us three flats'), findsOneWidget);
    await tester.tap(find.text('Approve').first);
    await tester.pumpAndSettle();
    expect(find.text('Wanjiku Mwangi is now rated 4.5 from 2 reviews.'), findsOneWidget);
    expect(find.textContaining('Showed us three flats'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Approved'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Showed us three flats'), findsOneWidget);
  });

  testWidgets('Content: a manager writes the Privacy Policy, previews it as the site shows it, and publishes', (tester) async {
    await open(tester, as: manager, at: '/content');
    expect(find.text('Published · /about'), findsOneWidget);
    await tester.tap(find.byKey(const Key('page-privacy')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('page-body')), '# Who we are\nRealtime Estates Ltd.\n\n- We keep your number\n- Only to reply');
    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();
    expect(find.text('Who we are'), findsOneWidget, reason: 'the heading, without its #');
    expect(find.text('We keep your number'), findsOneWidget, reason: 'a list item, without its -');
    await tester.tap(find.text('Published'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Published · /privacy'), findsOneWidget);
    final privacy = (await container.read(adminRepositoryProvider).sitePages(manager)).firstWhere((p) => p.slug == 'privacy');
    expect((privacy.title, privacy.published, privacy.body.startsWith('# Who we are')), ('Privacy Policy', true, true));
  });

  testWidgets('Bookings & payments: this month in numbers, filtered by status; a viewing fee links to Viewings', (tester) async {
    await open(tester, as: manager, at: '/payments');
    expect(find.text('Bookings & payments'), findsWidgets);
    expect(find.byKey(const Key('pay-total')), findsOneWidget);
    expect(find.text('Viewing fee'), findsWidgets);
    await tester.tap(find.byKey(const Key('pay-status-failed')));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(DataTable), matching: find.text('Paid')), findsNothing);
    expect(find.descendant(of: find.byType(DataTable), matching: find.text('Failed')), findsWidgets);
  });

  testWidgets('Ads: a manager adds an ad that runs on the home page, then pauses it', (tester) async {
    await open(tester, as: manager, at: '/ads');
    expect(find.text('Riverside Gardens: now letting'), findsOneWidget);
    await tester.tap(find.byKey(const Key('add-ad')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ad-save')));
    await tester.pumpAndSettle();
    expect(find.text('Use 2 to 80 characters.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('ad-title-field')), 'Kilimani Heights: show flat open');
    await tester.enterText(find.byKey(const Key('ad-link-field')), 'http://not-secure.example');
    await tester.tap(find.byKey(const Key('ad-placement-home')));
    await tester.tap(find.byKey(const Key('ad-save')));
    await tester.pumpAndSettle();
    expect(find.text('A full https:// address, or leave it empty.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('ad-link-field')), '');
    await tester.tap(find.byKey(const Key('ad-save')));
    await tester.pumpAndSettle();
    var ads = await container.read(adminRepositoryProvider).ads(manager);
    final mine = ads.firstWhere((a) => a.title == 'Kilimani Heights: show flat open');
    expect((mine.placement, mine.active, mine.linkUrl), ('home', true, null));
    expect(find.text('Kilimani Heights: show flat open'), findsOneWidget);

    await tester.tap(find.byKey(Key('ad-${mine.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ad-active')));
    await tester.tap(find.byKey(const Key('ad-save')));
    await tester.pumpAndSettle();
    ads = await container.read(adminRepositoryProvider).ads(manager);
    expect(ads.firstWhere((a) => a.id == mine.id).stateOn(DateTime.now()), 'paused');
    expect(find.descendant(of: find.byKey(Key('ad-${mine.id}')), matching: find.text('Paused')), findsOneWidget);
  });

  testWidgets('Support: a manager opens a new message, adds a note and resolves it', (tester) async {
    await open(tester, as: manager, at: '/support');
    expect(find.textContaining('Do you have bedsitters in Ruaka'), findsOneWidget);
    await tester.tap(find.byKey(const Key('message-fb-1')));
    await tester.pumpAndSettle();
    expect(find.text('+254722000111'), findsOneWidget, reason: 'call them back');
    await tester.enterText(find.byKey(const Key('message-note')), 'Sent three Ruaka bedsitters on WhatsApp');
    await tester.tap(find.text('Resolved'));
    await tester.tap(find.byKey(const Key('message-save')));
    await tester.pumpAndSettle();
    final f = (await container.read(adminRepositoryProvider).feedback(manager)).firstWhere((m) => m.id == 'fb-1');
    expect((f.status, f.notes.last.text), ('resolved', 'Sent three Ruaka bedsitters on WhatsApp'));
    expect(find.byKey(const Key('message-fb-1')), findsNothing, reason: 'New shows only new ones');
  });

  testWidgets('agents see none of Bookings & payments, Ads, Support or Content', (tester) async {
    await open(tester, as: wanjiku);
    for (final s in ['payments', 'ads', 'support', 'content']) {
      expect(find.byKey(Key('nav-$s')), findsNothing, reason: s);
    }
  });

  testWidgets('following up a lead: a note and a next time; Follow-ups due lists those that have come', (tester) async {
    await open(tester, as: wanjiku);
    final repo = container.read(adminRepositoryProvider);
    final now = DateTime.now();
    final due = (await repo.leads(wanjiku, dueBy: now, limit: 50)).rows;
    expect(due, isNotEmpty, reason: 'the demo has follow-ups due');
    expect(due.every((l) => l.agentId == 'agent-wanjiku' && l.dueAt(now)), isTrue);
    await tester.tap(find.byKey(const Key('leads-due')));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('lead-${due.first.id}')), findsOneWidget);

    // Open a lead from the full list, note the call and plan tomorrow.
    await tester.tap(find.byKey(const Key('leads-due')));
    await tester.pumpAndSettle();
    final lead = (await repo.leads(wanjiku, limit: 15)).rows.firstWhere((l) => l.followUpAt == null && l.stage != 'won' && l.stage != 'lost');
    await tapVisible(tester, find.byKey(Key('lead-${lead.id}')));
    expect(find.text('Nothing planned'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('lead-note')), 'Called; viewing on Saturday');
    await tester.tap(find.byKey(const Key('lead-pick-Tomorrow 9:00')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lead-save')));
    await tester.pumpAndSettle();
    final after = (await repo.leads(wanjiku, limit: 50)).rows.firstWhere((l) => l.id == lead.id);
    expect(after.notes.last.text, 'Called; viewing on Saturday');
    final t = DateTime.now().add(const Duration(days: 1));
    expect((after.followUpAt!.day, after.followUpAt!.hour), (t.day, 9));
    expect(after.dueAt(DateTime.now()), isFalse);
  });

  testWidgets("the Dashboard counts follow-ups due in New leads' line", (tester) async {
    await open(tester, as: manager, at: null);
    final d = await container.read(adminRepositoryProvider).dashboard(manager, DateTime.now());
    expect(d.followUpsDue, greaterThan(0));
    expect(find.textContaining('${d.followUpsDue} follow-ups due'), findsOneWidget);
  });

  testWidgets('the audit log filters by kind of action', (tester) async {
    await open(tester, as: manager, at: '/audit');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Leads and viewings'));
    await tester.pumpAndSettle();
    expect(find.text('Listing approve'), findsNothing);
    expect(find.text('Lead stage'), findsWidgets);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Listings'));
    await tester.pumpAndSettle();
    expect(find.text('Lead stage'), findsNothing);
  });

  testWidgets('signing out returns to sign in', (tester) async {
    await open(tester, as: owner);
    await tester.tap(find.byTooltip('Sign out (${owner.name})'));
    await tester.pumpAndSettle();
    expect(location(), signInPath);
  });

  testWidgets('narrow windows get a menu with every section, and no overflow', (tester) async {
    await open(tester, as: manager, width: 412, at: null);
    expect(find.byKey(const Key('nav-leads')), findsNothing, reason: 'the sidebar is in the menu');
    expect(find.byTooltip('Sign out (Demo Manager)'), findsOneWidget);
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-leads')));
    await tester.pumpAndSettle();
    expect(location(), '/leads');
    expect(find.byKey(const Key('nav-leads')), findsNothing, reason: 'the menu closes');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Dashboard is home: numbers that open their pages, a leads chart, next viewings, new leads, activity', (tester) async {
    await open(tester, as: manager, at: null, overrides: [dashboardClockProvider.overrideWithValue(() => DateTime(2026, 11, 20, 14))]);
    expect(location(), '/dashboard');
    expect(find.text('Good afternoon, Demo'), findsOneWidget);
    final data = await container.read(adminRepositoryProvider).dashboard(manager, DateTime(2026, 11, 20, 14));
    expect(find.descendant(of: find.byKey(const Key('stat-new-leads')), matching: find.text('${data.newLeads}')), findsOneWidget);
    expect(data.leadsByDay, hasLength(dashboardDays));
    expect(find.text('Leads per day'), findsOneWidget);
    expect(find.text('Upcoming viewings'), findsOneWidget);
    expect(find.text('New leads to contact'), findsOneWidget);
    expect(find.text('Recent activity'), findsOneWidget);
    await tester.tap(find.byKey(const Key('stat-live-listings')));
    await tester.pumpAndSettle();
    expect(location(), '/listings');
  });

  testWidgets("an agent's Dashboard counts only their own, with no activity feed", (tester) async {
    await open(tester, as: wanjiku, at: null);
    final mine = await container.read(adminRepositoryProvider).dashboard(wanjiku, DateTime.now());
    final all = await container.read(adminRepositoryProvider).dashboard(manager, DateTime.now());
    expect(mine.newLeads, lessThan(all.newLeads));
    expect(mine.latestLeads.every((l) => l.agentId == 'agent-wanjiku'), isTrue);
    expect(mine.activity, isEmpty);
    expect(find.text('Recent activity'), findsNothing);
    expect(find.textContaining('Your leads, viewings and listings'), findsOneWidget);
  });

  testWidgets('Users: search by name, email or phone, and filter by role', (tester) async {
    await open(tester, as: owner, at: '/team');
    expect(find.text('Users'), findsWidgets);
    expect(find.text('Wanjiku Mwangi'), findsWidgets);
    await tester.enterText(find.byKey(const Key('team-search')), '0722 444');
    await tester.pumpAndSettle();
    expect(find.text('otieno@example.com'), findsOneWidget);
    expect(find.text('wanjiku@example.com'), findsNothing);
    await tester.enterText(find.byKey(const Key('team-search')), 'MANAGER@');
    await tester.pumpAndSettle();
    expect(find.text('manager@example.com'), findsOneWidget);
    expect(find.text('owner@example.com'), findsNothing);
    await tester.enterText(find.byKey(const Key('team-search')), 'nobody here');
    await tester.pumpAndSettle();
    expect(find.text('Nobody matches "nobody here".'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('team-role-agent')));
    await tester.pumpAndSettle();
    expect(find.text('owner@example.com'), findsNothing);
    expect(find.text('wanjiku@example.com'), findsOneWidget);
  });

  testWidgets('Account: change the name and phone, then the password', (tester) async {
    await open(tester, as: wanjiku, at: null);
    await tester.tap(find.byKey(const Key('nav-account')));
    await tester.pumpAndSettle();
    expect(location(), '/account');
    expect(find.text('wanjiku@example.com'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('account-phone'))).controller!.text, '+254711222333');
    await tester.enterText(find.byKey(const Key('account-name')), 'Wanjiku M. Mwangi');
    await tester.enterText(find.byKey(const Key('account-phone')), '0711 999 888');
    await tester.tap(find.byKey(const Key('account-save')));
    await tester.pumpAndSettle();
    expect(find.text('Profile saved.'), findsOneWidget);
    expect((await container.read(adminRepositoryProvider).me(wanjiku))!.phone, '+254711999888');
    expect(find.text('Wanjiku M. Mwangi'), findsWidgets, reason: 'the sidebar shows the new name');

    await tester.enterText(find.byKey(const Key('password-current')), 'wrong');
    await tester.enterText(find.byKey(const Key('password-new')), 'newpassword1');
    await tester.enterText(find.byKey(const Key('password-again')), 'newpassword2');
    await tester.tap(find.byKey(const Key('password-change')));
    await tester.pumpAndSettle();
    expect(find.text('The two new passwords are not the same.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('password-again')), 'newpassword1');
    await tester.tap(find.byKey(const Key('password-change')));
    await tester.pumpAndSettle();
    expect(find.text('Your current password is not right.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('password-current')), 'oldpassword1');
    await tester.tap(find.byKey(const Key('password-change')));
    await tester.pumpAndSettle();
    expect(find.text('Your current password is not right.'), findsNothing);
    expect(tester.widget<TextField>(find.byKey(const Key('password-new'))).controller!.text, isEmpty, reason: 'cleared once changed');
  });
}
