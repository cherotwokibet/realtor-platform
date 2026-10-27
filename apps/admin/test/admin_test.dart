import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtor_admin/src/app.dart';
import 'package:realtor_admin/src/demo_admin.dart';
import 'package:realtor_admin/src/providers.dart';
import 'package:realtor_core/realtor_core.dart';

TenantConfig tenant() => TenantConfig.fromJson(
    jsonDecode(File('../../tenants/realtime-estates.json').readAsStringSync()) as Map<String, Object?>);

final owner = demoStaff.firstWhere((s) => s.role == StaffRole.owner);
final manager = demoStaff.firstWhere((s) => s.role == StaffRole.manager);
final wanjiku = demoStaff.firstWhere((s) => s.agentId == 'agent-wanjiku');

late ProviderContainer container;

Future<void> open(WidgetTester tester, {StaffUser? as, double width = 1280}) async {
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  container = ProviderContainer(overrides: [tenantProvider.overrideWithValue(tenant())]);
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
      expect(adminRedirect(null, '/leads'), signInPath);
      expect(adminRedirect(null, signInPath), isNull);
      expect(adminRedirect(manager, signInPath), '/leads');
      expect(adminRedirect(manager, '/'), '/leads');
    });

    test('nobody opens a section their role does not cover', () {
      expect(adminRedirect(wanjiku, '/audit'), '/leads');
      expect(adminRedirect(wanjiku, '/listings'), isNull);
      expect(adminRedirect(manager, '/audit'), isNull);
      expect(adminRedirect(owner, '/nowhere'), '/leads');
    });
  });

  group('DemoAdminRepository', () {
    final repo = DemoAdminRepository();

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
