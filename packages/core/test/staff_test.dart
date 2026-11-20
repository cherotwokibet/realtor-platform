import 'package:realtor_core/realtor_core.dart';
import 'package:test/test.dart';

void main() {
  group('StaffUser.fromClaims', () {
    test('reads the role and, for agents, the agent record', () {
      final a = StaffUser.fromClaims('u1', 'Agent', {'role': 'agent', 'agentId': 'agent-a'})!;
      expect((a.role, a.agentId, a.agentScope, a.isManager), (StaffRole.agent, 'agent-a', 'agent-a', false));
      final m = StaffUser.fromClaims('m1', 'Manager', {'role': 'manager', 'agentId': 'ignored'})!;
      expect((m.role, m.agentId, m.agentScope, m.isManager), (StaffRole.manager, null, null, true));
      expect(StaffUser.fromClaims('o1', 'Owner', {'role': 'owner'})!.role, StaffRole.owner);
    });

    test('is null for customers, unknown roles and agents with no agent record', () {
      expect(StaffUser.fromClaims('c', 'Customer', {}), isNull);
      expect(StaffUser.fromClaims('x', 'X', {'role': 'admin'}), isNull);
      expect(StaffUser.fromClaims('a', 'A', {'role': 'agent'}), isNull);
      expect(StaffUser.fromClaims('a', 'A', {'role': 'agent', 'agentId': ''}), isNull);
    });
  });

  test('only owners and managers open the team and audit log; only owners manage staff', () {
    const agent = StaffUser(uid: 'a', name: 'A', role: StaffRole.agent, agentId: 'agent-a');
    const manager = StaffUser(uid: 'm', name: 'M', role: StaffRole.manager);
    const owner = StaffUser(uid: 'o', name: 'O', role: StaffRole.owner);
    expect(AdminSection.values.where(agent.canOpen), [AdminSection.dashboard, AdminSection.leads, AdminSection.viewings, AdminSection.listings, AdminSection.edits, AdminSection.account]);
    expect(AdminSection.values.where(manager.canOpen), AdminSection.values);
    expect([agent, manager, owner].map((u) => u.canManageStaff), [false, false, true]);
  });

  group('scopedTo', () {
    final rows = [('l1', 'agent-a'), ('l2', 'agent-b'), ('l3', 'agent-a')];
    test('an agent gets only their own rows; a manager gets all', () {
      const agent = StaffUser(uid: 'a', name: 'A', role: StaffRole.agent, agentId: 'agent-a');
      const owner = StaffUser(uid: 'o', name: 'O', role: StaffRole.owner);
      expect(scopedTo(agent, rows, (r) => r.$2).map((r) => r.$1), ['l1', 'l3']);
      expect(scopedTo(owner, rows, (r) => r.$2).length, 3);
    });
  });

  group('pageAfter', () {
    final ids = [for (var i = 1; i <= 7; i++) 'r$i'];
    String id(String s) => s;

    test('walks the rows a page at a time, like startAfter + limit', () {
      final p1 = pageAfter(ids, id, limit: 3);
      expect(p1.rows, ['r1', 'r2', 'r3']);
      expect(p1.next, 'r3');
      final p2 = pageAfter(ids, id, after: p1.next, limit: 3);
      expect(p2.rows, ['r4', 'r5', 'r6']);
      expect(p2.next, 'r6');
      final p3 = pageAfter(ids, id, after: p2.next, limit: 3);
      expect(p3.rows, ['r7']);
      expect(p3.next, null);
    });

    test('an exact last page has no next cursor; empty and unknown cursors are safe', () {
      expect(pageAfter(ids.take(6).toList(), id, after: 'r3', limit: 3).next, isNull);
      expect(pageAfter(<String>[], id).rows, isEmpty);
      expect(pageAfter(ids, id, after: 'gone', limit: 2).rows, ['r1', 'r2']);
      expect(() => pageAfter(ids, id, limit: 0), throwsArgumentError);
    });
  });

  test('roles read as Admin, Manager, Agent; staff search matches name, email, phone and agent', () {
    expect(StaffRole.values.map(roleLabel), ['Admin', 'Manager', 'Agent']);
    const m = StaffMember(uid: 'u', role: StaffRole.agent, name: 'Wanjiku Mwangi', email: 'wanjiku@example.com', phone: '+254711222333', agentName: 'Wanjiku M.');
    for (final q in ['wanjiku', 'MWANGI', '@example', '0711 222', '711222333', '+254 711', '']) {
      expect(m.matches(q), isTrue, reason: q);
    }
    for (final q in ['otieno', '0722', '12']) {
      expect(m.matches(q), isFalse, reason: q);
    }
  });
}
