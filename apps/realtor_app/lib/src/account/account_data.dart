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

  /// For customers who set a password in Edit Profile.
  Future<void> signInWithPassword(String email, String password);

  /// Emails a link to choose a new password.
  Future<void> sendPasswordReset(String email);
  Future<void> signOut();
}

/// What Edit Profile shows: the name, the WhatsApp number, and how the
/// customer signs in (Google, or email with or without a password).
typedef CustomerProfile = ({String? name, String? whatsapp, bool google, bool hasPassword});

/// The signed-in customer's own profile and account (My account).
abstract interface class ProfileRepository {
  Future<CustomerProfile> load();

  /// Through the saveMyProfile Function, which checks the number. [whatsapp]
  /// is E.164 (+2547…) or empty to clear it.
  Future<void> save({required String name, required String whatsapp});

  /// Sets or changes the password; SignInFailure('requires-recent-login')
  /// when the sign-in is too old for it.
  Future<void> setPassword(String password);

  /// Through the deleteMyAccount Function; signs out after.
  Future<void> deleteAccount();
}

abstract interface class AlertsRepository {
  Stream<List<SavedSearchRow>> searches(String uid);

  /// Saves what alerts can match on: purpose, types, areas, beds, top price,
  /// drawn area. False, and nothing saved, when the same search is already
  /// saved ([searchKey]).
  Future<bool> saveSearch(String uid, ListingFilters filters);
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
      // A drawn area as the search link writes it ("lat,lng~lat,lng~..."), to 6 places at most.
      if (f.polygon.length >= 3) 'poly': f.polygon.take(20).map((p) => '${_place(p.lat)},${_place(p.lng)}').join('~'),
    };

/// What makes two saved searches the same: the filters alerts match on,
/// with the lists in one order (Kilimani, Westlands is Westlands, Kilimani).
String searchKey(ListingFilters f) {
  final m = alertFilters(f);
  return [
    m['purpose'],
    ([...?(m['types'] as List?)]..sort()).join(','),
    ([...?(m['areas'] as List?)]..sort()).join(','),
    m['minBeds'] ?? '',
    m['maxPriceKES'] ?? '',
    m['poly'] ?? '',
  ].join('|');
}

/// The saved search's document id: the person and the search, so saving the
/// same search twice (a double tap) lands on one document, which the rules
/// then refuse to write again.
String savedSearchId(String uid, ListingFilters f) {
  final key = searchKey(f);
  // Two small hashes, safe in JavaScript numbers on the web.
  var a = 7, c = 11;
  for (final u in key.codeUnits) {
    a = (a * 31 + u) % 2147483647;
    c = (c * 131 + u) % 2147483629;
  }
  return '$uid-${a.toRadixString(36)}${c.toRadixString(36)}';
}

String _place(double v) => v.toStringAsFixed(6).replaceFirst(RegExp(r'\.?0+$'), '');

ListingFilters filtersFromAlert(Map<Object?, Object?> m) {
  final area = [
    for (final c in '${m['poly'] ?? ''}'.split('~'))
      if (c.split(',').map(double.tryParse).toList() case [final double lat, final double lng] when lat.abs() <= 90 && lng.abs() <= 180) GeoPoint(lat, lng),
  ];
  return ListingFilters(
    purpose: Purpose.values.firstWhere((p) => p.value == m['purpose'], orElse: () => Purpose.rent),
    types: [for (final t in (m['types'] as List?) ?? const []) '$t'],
    areas: [for (final a in (m['areas'] as List?) ?? const []) '$a'],
    minBeds: (m['minBeds'] as num?)?.toInt(),
    maxPriceKES: (m['maxPriceKES'] as num?)?.toInt(),
    polygon: area.length >= 3 && area.length <= maxPolygonPoints ? area : const [],
  );
}

/// Demo: one pretend account, everything in memory.
class DemoAccount implements CustomerAccount, AlertsRepository, ProfileRepository {
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
  Future<void> signInWithPassword(String email, String password) async {
    if (password != _password) throw const SignInFailure('wrong-password');
    _set((uid: 'demo-customer', email: email));
  }

  @override
  Future<void> sendPasswordReset(String email) async => sentResets.add(email);

  @override
  Future<void> signOut() async => _set(null);

  String? _name, _whatsapp, _password;
  final sentResets = <String>[];
  var deleted = false;

  @override
  Future<CustomerProfile> load() async => (name: _name, whatsapp: _whatsapp, google: _current?.email == 'demo@example.com', hasPassword: _password != null);

  @override
  Future<void> save({required String name, required String whatsapp}) async {
    if (name.trim().length < 2) throw const SignInFailure('invalid-argument');
    if (whatsapp.isNotEmpty && normaliseKenyanPhone(whatsapp) != whatsapp) throw const SignInFailure('invalid-argument');
    _name = name.trim();
    _whatsapp = whatsapp.isEmpty ? null : whatsapp;
  }

  @override
  Future<void> setPassword(String password) async => _password = password;

  @override
  Future<void> deleteAccount() async {
    deleted = true;
    _name = _whatsapp = _password = null;
    _searches.clear();
    _alerts.clear();
    _set(null);
  }

  Stream<T> _watch<T>(T Function() read) async* {
    yield read();
    yield* _changed.stream.map((_) => read());
  }

  @override
  Stream<List<SavedSearchRow>> searches(String uid) => _watch(() => [..._searches]);

  @override
  Future<bool> saveSearch(String uid, ListingFilters filters) async {
    if (_searches.any((s) => searchKey(s.filters) == searchKey(filters))) return false;
    _searches.add((id: 'search-${_searches.length + 1}', filters: filtersFromAlert(alertFilters(filters)), lastNotifiedAt: null));
    _changed.add(null);
    return true;
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
final profileRepositoryProvider = Provider<ProfileRepository>((ref) => ref.watch(demoAccountProvider));

final customerProvider = StreamProvider<Customer?>((ref) => ref.watch(customerAccountProvider).customer);

/// The signed-in customer's profile (for their name in the menu); null when
/// signed out or while it cannot be read.
final profileProvider = FutureProvider<CustomerProfile?>((ref) async {
  if (ref.watch(customerProvider).value == null) return null;
  try {
    return await ref.read(profileRepositoryProvider).load();
  } on Object {
    return null;
  }
});

final savedSearchesProvider = StreamProvider.family<List<SavedSearchRow>, String>((ref, uid) => ref.watch(alertsRepositoryProvider).searches(uid));
final alertsProvider = StreamProvider.family<List<AlertRow>, String>((ref, uid) => ref.watch(alertsRepositoryProvider).alerts(uid));
