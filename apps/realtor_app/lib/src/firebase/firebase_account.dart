import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:realtor_core/realtor_core.dart';

import '../account/account_data.dart';

/// Firebase Auth: an emailed sign-in link, or Google where switched on.
class FirebaseCustomerAccount implements CustomerAccount {
  FirebaseCustomerAccount(this._auth);
  final FirebaseAuth _auth;

  @override
  Stream<Customer?> get customer => _auth.authStateChanges().map((u) => u == null ? null : (uid: u.uid, email: u.email));

  @override
  Future<void> sendSignInLink(String email, Uri continueUrl) => _auth.sendSignInLinkToEmail(
        email: email,
        actionCodeSettings: ActionCodeSettings(url: continueUrl.toString(), handleCodeInApp: true),
      );

  @override
  Future<bool> completeSignInLink(Uri link, String email) async {
    if (!_auth.isSignInWithEmailLink(link.toString())) return false;
    await _auth.signInWithEmailLink(email: email, emailLink: link.toString());
    return true;
  }

  @override
  Future<void> signInWithGoogle() => _auth.signInWithPopup(GoogleAuthProvider());

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
