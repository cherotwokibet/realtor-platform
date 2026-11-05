import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:realtor_core/realtor_core.dart';

import '../account/account_data.dart';

/// On a phone, where emailed links come back to: the project's app site
/// (its Hosting domain, so Firebase accepts it) and the app's ids.
typedef PhoneLinks = ({String appSite, String androidId, String iosId});

/// The customer app's Hosting site for a project, as Terraform names it
/// (google_firebase_hosting_site.app; tenant-cli appSiteHost).
String appSiteHost(String projectId) {
  final id = projectId.length > 26 ? projectId.substring(0, 26) : projectId;
  return '${id.endsWith('-') ? id.substring(0, id.length - 1) : id}-app.web.app';
}

/// The settings for an emailed sign-in link. On the web it returns to
/// [continueUrl]; on a phone it goes through the app site, whose verified
/// App Link (`tenant flavors`) opens the app at /__/auth/links.
ActionCodeSettings signInLinkSettings(Uri continueUrl, PhoneLinks? phone) => phone == null
    ? ActionCodeSettings(url: continueUrl.toString(), handleCodeInApp: true)
    : ActionCodeSettings(
        url: Uri.https(phone.appSite, '/account').toString(),
        handleCodeInApp: true,
        linkDomain: phone.appSite,
        androidPackageName: phone.androidId,
        androidInstallApp: false,
        iOSBundleId: phone.iosId,
      );

/// Firebase Auth: an emailed sign-in link, or Google where switched on.
class FirebaseCustomerAccount implements CustomerAccount {
  FirebaseCustomerAccount(this._auth, {this.phone});
  final FirebaseAuth _auth;

  /// Set in the Android and iOS apps; null on the web.
  final PhoneLinks? phone;

  @override
  Stream<Customer?> get customer => _auth.authStateChanges().map((u) => u == null ? null : (uid: u.uid, email: u.email));

  Future<T> _reported<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on FirebaseAuthException catch (e) {
      throw SignInFailure(e.code);
    }
  }

  @override
  Future<void> sendSignInLink(String email, Uri continueUrl) => _reported(
        () => _auth.sendSignInLinkToEmail(email: email, actionCodeSettings: signInLinkSettings(continueUrl, phone)),
      );

  @override
  Future<bool> completeSignInLink(Uri link, String email) => _reported(() async {
        final emailLink = emailLinkFrom(link).toString();
        if (!_auth.isSignInWithEmailLink(emailLink)) return false;
        await _auth.signInWithEmailLink(email: email, emailLink: emailLink);
        return true;
      });

  @override
  Future<void> signInWithGoogle() => _reported(
        () => kIsWeb ? _auth.signInWithPopup(GoogleAuthProvider()) : _auth.signInWithProvider(GoogleAuthProvider()),
      );

  @override
  Future<void> signOut() => _auth.signOut();
}

/// savedSearches (rules check the shape) and users/{uid}/alerts.
class FirestoreAlerts implements AlertsRepository {
  FirestoreAlerts(this._db);
  final FirebaseFirestore _db;

  @override
  Stream<List<SavedSearchRow>> searches(String uid) => _db
      .collection('savedSearches')
      .where('userId', isEqualTo: uid)
      .snapshots()
      .map((s) => [
            for (final d in s.docs)
              (
                id: d.id,
                filters: filtersFromAlert((d.data()['filters'] as Map?) ?? const {}),
                lastNotifiedAt: (d.data()['lastNotifiedAt'] as Timestamp?)?.toDate(),
              ),
          ]);

  @override
  Future<void> saveSearch(String uid, ListingFilters filters) => _db.collection('savedSearches').add({
        'userId': uid,
        'filters': alertFilters(filters),
        'channels': ['inbox'],
        'lastNotifiedAt': null,
        'createdAt': FieldValue.serverTimestamp(),
      });

  @override
  Future<void> deleteSearch(String id) => _db.collection('savedSearches').doc(id).delete();

  CollectionReference<Map<String, Object?>> _alerts(String uid) => _db.collection('users').doc(uid).collection('alerts');

  @override
  Stream<List<AlertRow>> alerts(String uid) => _alerts(uid).orderBy('createdAt', descending: true).limit(50).snapshots().map((s) => [
        for (final d in s.docs)
          (
            id: d.id,
            slug: d.data()['slug'] as String? ?? '',
            title: d.data()['title'] as String? ?? '',
            priceKES: (d.data()['priceKES'] as num?)?.toInt() ?? 0,
            purpose: Purpose.values.firstWhere((p) => p.value == d.data()['purpose'], orElse: () => Purpose.rent),
            area: d.data()['area'] as String? ?? '',
            createdAt: (d.data()['createdAt'] as Timestamp?)?.toDate() ?? DateTime(0),
            read: d.data()['readAt'] != null,
          ),
      ]);

  @override
  Future<void> markRead(String uid, String alertId) => _alerts(uid).doc(alertId).update({'readAt': FieldValue.serverTimestamp()});

  @override
  Future<void> clear(String uid, String alertId) => _alerts(uid).doc(alertId).delete();
}
