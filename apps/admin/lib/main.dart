import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:realtor_ui/realtor_ui.dart';

import 'src/app.dart';
import 'src/firebase/callable_actions.dart';
import 'src/firebase/firebase_auth.dart';
import 'src/firebase/firestore_admin.dart';
import 'src/firebase/hosting_config.dart';
import 'src/providers.dart';

Future<void> main() async {
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  final (tenant, _, firebase) = await (loadTenant(), loadTenantFonts(), hostingFirebaseOptions(Uri.base)).wait;
  final overrides = [tenantProvider.overrideWithValue(tenant)];
  // On Firebase Hosting: real sign-in, Firestore and the Functions. Anywhere
  // else (flutter run, a plain web server): demo accounts over demo data.
  if (firebase != null) {
    await Firebase.initializeApp(options: firebase);
    overrides.addAll([
      adminAuthProvider.overrideWithValue(FirebaseAdminAuth(FirebaseAuth.instance, link: Uri.base)),
      adminRepositoryProvider.overrideWithValue(FirestoreAdminRepository(FirebaseFirestore.instance)),
      adminActionsProvider.overrideWithValue(
        CallableAdminActions.firebase(FirebaseFunctions.instanceFor(region: tenant.firebaseRegion)),
      ),
    ]);
  }
  runApp(ProviderScope(overrides: overrides, child: const AdminApp()));
}
