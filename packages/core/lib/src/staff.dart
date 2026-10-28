/// Staff roles, set as custom claims by a Function (see firestore.rules).
enum StaffRole { owner, manager, agent }

/// The admin's parts. Which a role may open is decided here, once, and the
/// Firestore rules enforce the same split on the data.
enum AdminSection { leads, viewings, listings, reports, team, audit, privacy }

/// A signed-in staff member.
class StaffUser {
  const StaffUser({required this.uid, required this.name, required this.role, this.agentId});

  final String uid, name;
  final StaffRole role;

  /// The agent record an agent account acts as; null for owners and managers.
  final String? agentId;

  bool get isManager => role != StaffRole.agent;

  /// The agent whose leads and listings this user is limited to; null sees all.
  String? get agentScope => isManager ? null : agentId;

  bool canOpen(AdminSection s) => switch (s) {
        AdminSection.leads || AdminSection.viewings || AdminSection.listings => true,
        AdminSection.reports || AdminSection.team || AdminSection.audit || AdminSection.privacy => isManager,
      };

  /// Only owners give, change or take away staff roles (setStaffRole).
  bool get canManageStaff => role == StaffRole.owner;

  /// From the ID token's claims; null when the account is not staff, or is
  /// an agent with no agentId (the Functions refuse those too).
  static StaffUser? fromClaims(String uid, String name, Map<String, Object?> claims) {
    final role = switch (claims['role']) {
      'owner' => StaffRole.owner,
      'manager' => StaffRole.manager,
      'agent' => StaffRole.agent,
      _ => null,
    };
    final agentId = claims['agentId'];
    if (role == null) return null;
    if (role == StaffRole.agent && (agentId is! String || agentId.isEmpty)) return null;
    return StaffUser(uid: uid, name: name, role: role, agentId: role == StaffRole.agent ? agentId as String : null);
  }
}

/// Thrown when a staff member asks for data their role does not cover.
class StaffAccessException implements Exception {
  StaffAccessException(this.message);
  final String message;
  @override
  String toString() => 'StaffAccessException: $message';
}
