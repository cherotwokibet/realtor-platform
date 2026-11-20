import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_core/realtor_core.dart';
import 'package:realtor_ui/realtor_ui.dart';

import 'src/app.dart';
import 'src/account/account_data.dart';
import 'src/account/push.dart';
import 'src/firebase/deferred_backends.dart';
import 'src/firebase/firebase_account.dart';
import 'src/firebase/firebase_data.dart';
import 'src/firebase/firebase_push.dart';
import 'src/providers.dart';
import 'src/support/site_services.dart';

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
    // The first screen does not wait for Firebase: on the web, starting it
    // downloads and runs its SDK, seconds on a mid-range phone (P3-s01).
    // Each backend call waits for it instead.
    final ready = Firebase.initializeApp(options: firebase);
    Future<T> once<T>(T Function() make) {
      // A start-up failure reaches each caller; it is not also an uncaught error.
      final backend = ready.then((_) => make())..ignore();
      return backend;
    }

    final bucket = '${firebase.projectId}-media';
    // The web reads the live homes from one small, cached file first (P3-s01).
    final index = kIsWeb ? ListingIndex.url(Uri.base.resolve('/api/listings.json'), bucket: bucket) : null;
    final firestoreSearch = once(() => FirestoreListingSearch(FirebaseFirestore.instance, bucket: bucket));
    Future<List<ListingSummary>> fromFirestore(Purpose p) => firestoreSearch.then((s) => s.rows(p));
    // On the web, "Get alerts" sign-in links come back to this site.
    overrides.addAll([
      // Homes from the last visit show at once; fresh ones follow (P3-s01).
      listingSearchProvider.overrideWithValue(
        SnapshotListingSearch(
          (p) => index == null ? fromFirestore(p) : index.rows(p).catchError((Object _) => fromFirestore(p)),
          store: PrefsListingSnapshotStore(),
        ),
      ),
      listingRepositoryProvider.overrideWithValue(
        DeferredListingRepository(once(() => FirestoreListingRepository(FirebaseFirestore.instance, bucket: bucket)), quickLive: index?.live),
      ),
      customerAccountProvider.overrideWithValue(DeferredCustomerAccount(once(() => FirebaseCustomerAccount(
            FirebaseAuth.instance,
            phone: kIsWeb
                ? null
                : (
                    appSite: appSiteHost(firebase.projectId),
                    linkDomain: authLinkDomain(firebase.projectId),
                    androidId: tenant.androidId,
                    iosId: tenant.iosId,
                  ),
          )))),
      alertsRepositoryProvider.overrideWithValue(DeferredAlertsRepository(once(() => FirestoreAlerts(FirebaseFirestore.instance)))),
      profileRepositoryProvider.overrideWithValue(DeferredProfile(once(() {
        final functions = FirebaseFunctions.instanceFor(region: tenant.firebaseRegion);
        return FirebaseProfile(
            FirebaseAuth.instance, FirebaseFirestore.instance, (name, data) async => (await functions.httpsCallable(name).call<Object?>(data)).data);
      }))),
      // Push alerts on phones (P4-s03); web push needs a VAPID key first.
      if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS))
        pushAlertsProvider.overrideWithValue(DeferredPushAlerts(once(() => DevicePushAlerts(
              FcmPushClient(FirebaseMessaging.instance),
              FirebaseFirestore.instance,
              platform: defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
            )))),
      leadRepositoryProvider.overrideWithValue(
        DeferredLeadRepository(once(() => CallableLeadRepository.firebase(FirebaseFunctions.instanceFor(region: tenant.firebaseRegion)))),
      ),
      siteServicesProvider.overrideWithValue(DeferredSiteServices(once(() {
        final functions = FirebaseFunctions.instanceFor(region: tenant.firebaseRegion);
        return FirebaseSiteServices(FirebaseFirestore.instance, (name, data) async => (await functions.httpsCallable(name).call<Object?>(data)).data,
            bucket: bucket);
      }), bucket: bucket)),
      listingReviewsProvider.overrideWithValue(DeferredListingReviews(once(() {
        final functions = FirebaseFunctions.instanceFor(region: tenant.firebaseRegion);
        return FirestoreListingReviews(FirebaseFirestore.instance, (name, data) async => (await functions.httpsCallable(name).call<Object?>(data)).data);
      }))),
    ]);
  }
  runApp(ProviderScope(overrides: overrides, child: const RealtorApp()));
}
