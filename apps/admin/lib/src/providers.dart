import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_core/realtor_core.dart';

import 'demo_admin.dart';
import 'session.dart';

/// Overridden in main() with the tenant loaded from assets.
final tenantProvider = Provider<TenantConfig>((ref) => throw UnimplementedError('tenantProvider not overridden'));

/// Demo data and actions; main() swaps in Firestore and the Functions when
/// the admin is served by Firebase Hosting.
final demoAdminProvider = Provider<DemoAdminRepository>((ref) => DemoAdminRepository());

final adminRepositoryProvider = Provider<AdminRepository>((ref) => ref.watch(demoAdminProvider));

final adminActionsProvider = Provider<AdminActions>((ref) => ref.watch(demoAdminProvider));

/// Demo accounts until main() swaps in Firebase email-link sign-in.
final adminAuthProvider = Provider<AdminAuth>((ref) => DemoAuth(demoStaff));

class SessionNotifier extends Notifier<Session> {
  @override
  Session build() {
    final sub = ref.watch(adminAuthProvider).sessions.listen((s) => state = s);
    ref.onDispose(sub.cancel);
    return const Starting();
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, Session>(SessionNotifier.new);

/// The signed-in staff member, or null.
final staffProvider = Provider<StaffUser?>((ref) => switch (ref.watch(sessionProvider)) {
      SignedIn(:final user) => user,
      _ => null,
    });

/// Rows per table page.
const pageSize = 15;
