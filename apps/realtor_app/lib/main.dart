import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_ui/realtor_ui.dart';

import 'src/app.dart';
import 'src/account/account_data.dart';
import 'src/firebase/firebase_account.dart';
import 'src/firebase/firebase_data.dart';
import 'src/providers.dart';

Future<void> main() async {
  // Clean URLs on the web (/listing/<slug>, not /#/listing/<slug>); a no-op elsewhere.
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  // Web: Hosting's init.json. Phones: the asset `tenant firebase-config` writes.
  final (tenant, _, firebase) = await (
    loadTenant(),
    loadTenantFonts(),
    kIsWeb ? hostingFirebaseOptions(Uri.base) : bundledFirebaseOptions(rootBundle, tenantAssetDir(), defaultTargetPlatform),
  ).wait;
  final overrides = [tenantProvider.overrideWithValue(tenant)];
  // On Firebase Hosting: live listings from Firestore and leads to the
  // Functions. Anywhere else (flutter run, a plain server): demo data.
  if (firebase != null) {
    await Firebase.initializeApp(options: firebase);
    final db = FirebaseFirestore.instance, bucket = '${firebase.projectId}-media';
    // On the web, "Get alerts" sign-in links come back to this site.
    overrides.addAll([
      listingSearchProvider.overrideWithValue(FirestoreListingSearch(db, bucket: bucket)),
      listingRepositoryProvider.overrideWithValue(FirestoreListingRepository(db, bucket: bucket)),
      customerAccountProvider.overrideWithValue(FirebaseCustomerAccount(FirebaseAuth.instance)),
      alertsRepositoryProvider.overrideWithValue(FirestoreAlerts(db)),
      leadRepositoryProvider.overrideWithValue(
        CallableLeadRepository.firebase(FirebaseFunctions.instanceFor(region: tenant.firebaseRegion)),
      ),
    ]);
  }
  runApp(ProviderScope(overrides: overrides, child: const RealtorApp()));
}
