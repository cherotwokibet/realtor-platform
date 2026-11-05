import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:realtor_core/realtor_core.dart';

/// A signed-in customer (D18): an account only for saved-search alerts.
typedef Customer = ({String uid, String? email});

/// A saved search as the account page lists it.
typedef SavedSearchRow = ({String id, ListingFilters filters, DateTime? lastNotifiedAt});

/// A new home that matched a saved search (users/{uid}/alerts).
typedef AlertRow = ({String id, String slug, String title, int priceKES, Purpose purpose, String area, DateTime createdAt, bool read});

/// Why sign-in failed, with the provider's code (e.g. auth/unauthorized-continue-uri),
/// so a failure on a phone can be reported precisely.
class SignInFailure implements Exception {
  const SignInFailure(this.code);
  final String code;
  @override
  String toString() => 'SignInFailure($code)';
}

/// The emailed link inside a link that opened the app: Firebase sends
/// `https://<app site>/__/auth/links?link=<the sign-in link>`.
Uri emailLinkFrom(Uri opened) {
  final inner = opened.queryParameters['link'];
  return inner == null ? opened : Uri.parse(inner);
}

abstract interface class CustomerAccount {
  Stream<Customer?> get customer;

  /// Emails a one-time sign-in link that opens [continueUrl].
  Future<void> sendSignInLink(String email, Uri continueUrl);

  /// Completes sign-in when [link] is one of those links; false otherwise.
  Future<bool> completeSignInLink(Uri link, String email);

  /// Google sign-in, where the project has it switched on.
  Future<void> signInWithGoogle();
  Future<void> signOut();
}

abstract interface class AlertsRepository {
  Stream<List<SavedSearchRow>> searches(String uid);

  /// Saves what alerts can match on: purpose, types, areas, beds, top price.
  Future<void> saveSearch(String uid, ListingFilters filters);
  Future<void> deleteSearch(String id);
  Stream<List<AlertRow>> alerts(String uid);
  Future<void> markRead(String uid, String alertId);
  Future<void> clear(String uid, String alertId);
}

/// The part of [f] alerts match on (firestore.rules allow just these).
Map<String, Object?> alertFilters(ListingFilters f) => {
      'purpose': f.purpose.value,
      if (f.types.isNotEmpty) 'types': f.types.take(12).toList(),
      if (f.areas.isNotEmpty) 'areas': f.areas.take(20).toList(),
      if (f.minBeds != null) 'minBeds': f.minBeds,
      if (f.maxPriceKES != null) 'maxPriceKES': f.maxPriceKES,
    };

ListingFilters filtersFromAlert(Map<Object?, Object?> m) => ListingFilters(
      purpose: Purpose.values.firstWhere((p) => p.value == m['purpose'], orElse: () => Purpose.rent),
      types: [for (final t in (m['types'] as List?) ?? const []) '$t'],
      areas: [for (final a in (m['areas'] as List?) ?? const []) '$a'],
      minBeds: (m['minBeds'] as num?)?.toInt(),
      maxPriceKES: (m['maxPriceKES'] as num?)?.toInt(),
    );

/// Demo: one pretend account, everything in memory.
class DemoAccount implements CustomerAccount, AlertsRepository {
  final _customer = StreamController<Customer?>.broadcast();
  Customer? _current;
  final _searches = <SavedSearchRow>[];
  final _alerts = <AlertRow>[];
  final _changed = StreamController<void>.broadcast();
  final sentLinks = <String>[];

  void _set(Customer? c) {
    _current = c;
    _customer.add(c);
  }

  @override
  Stream<Customer?> get customer async* {
    yield _current;
    yield* _customer.stream;
  }

  @override
  Future<void> sendSignInLink(String email, Uri continueUrl) async => sentLinks.add(email);

  @override
  Future<bool> completeSignInLink(Uri link, String email) async {
    if (emailLinkFrom(link).queryParameters['mode'] != 'signIn') return false;
    _set((uid: 'demo-customer', email: email));
    return true;
  }

  @override
  Future<void> signInWithGoogle() async => _set((uid: 'demo-customer', email: 'demo@example.com'));

  @override
  Future<void> signOut() async => _set(null);

  Stream<T> _watch<T>(T Function() read) async* {
    yield read();
    yield* _changed.stream.map((_) => read());
  }

  @override
  Stream<List<SavedSearchRow>> searches(String uid) => _watch(() => [..._searches]);

  @override
  Future<void> saveSearch(String uid, ListingFilters filters) async {
    _searches.add((id: 'search-${_searches.length + 1}', filters: filtersFromAlert(alertFilters(filters)), lastNotifiedAt: null));
    _changed.add(null);
  }

  @override
  Future<void> deleteSearch(String id) async {
    _searches.removeWhere((s) => s.id == id);
    _changed.add(null);
  }

  /// Demo: what the 5-minute sweep would add.
  void addAlert(AlertRow a) {
    _alerts.insert(0, a);
    _changed.add(null);
  }

  @override
  Stream<List<AlertRow>> alerts(String uid) => _watch(() => [..._alerts]);

  @override
  Future<void> markRead(String uid, String alertId) async {
    final i = _alerts.indexWhere((a) => a.id == alertId);
    if (i >= 0) {
      final a = _alerts[i];
      _alerts[i] = (id: a.id, slug: a.slug, title: a.title, priceKES: a.priceKES, purpose: a.purpose, area: a.area, createdAt: a.createdAt, read: true);
      _changed.add(null);
    }
  }

  @override
  Future<void> clear(String uid, String alertId) async {
    _alerts.removeWhere((a) => a.id == alertId);
    _changed.add(null);
  }
}

final demoAccountProvider = Provider<DemoAccount>((ref) => DemoAccount());
final customerAccountProvider = Provider<CustomerAccount>((ref) => ref.watch(demoAccountProvider));
final alertsRepositoryProvider = Provider<AlertsRepository>((ref) => ref.watch(demoAccountProvider));

final customerProvider = StreamProvider<Customer?>((ref) => ref.watch(customerAccountProvider).customer);

final savedSearchesProvider = StreamProvider.family<List<SavedSearchRow>, String>((ref, uid) => ref.watch(alertsRepositoryProvider).searches(uid));
final alertsProvider = StreamProvider.family<List<AlertRow>, String>((ref, uid) => ref.watch(alertsRepositoryProvider).alerts(uid));
