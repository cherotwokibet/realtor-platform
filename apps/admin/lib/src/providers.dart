import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_core/realtor_core.dart';

import 'demo_admin.dart';

/// Overridden in main() with the tenant loaded from assets.
final tenantProvider = Provider<TenantConfig>((ref) => throw UnimplementedError('tenantProvider not overridden'));

/// Demo data until the admin reads Firestore.
final adminRepositoryProvider = Provider<AdminRepository>((ref) => DemoAdminRepository());

/// The signed-in staff member, or null. Firebase Auth will fill this from the
/// ID token's claims (`StaffUser.fromClaims`); demo accounts until then.
class StaffSession extends Notifier<StaffUser?> {
  @override
  StaffUser? build() => null;

  void signIn(StaffUser user) => state = user;
  void signOut() => state = null;
}

final staffProvider = NotifierProvider<StaffSession, StaffUser?>(StaffSession.new);

/// Rows per table page.
const pageSize = 15;
