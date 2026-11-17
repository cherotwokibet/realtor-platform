import 'package:realtor_core/realtor_core.dart';

import '../account/account_data.dart';
import '../account/push.dart';

/// Backends that are still starting. On the web, starting Firebase downloads
/// and runs its SDK, seconds on a mid-range phone; the app draws its first
/// screen without waiting, and each call waits for its backend here instead
/// (P3-s01). A backend that fails to start fails each call, so the screens
/// show their usual error state.

class DeferredListingSearch implements ListingSearch {
  DeferredListingSearch(this._inner);
  final Future<ListingSearch> _inner;

  @override
  Future<SearchResult> search(ListingFilters filters) async => (await _inner).search(filters);
}

class DeferredListingRepository implements ListingRepository {
  DeferredListingRepository(this._inner);
  final Future<ListingRepository> _inner;

  @override
  Future<ListingDetail?> bySlug(String slug) async => (await _inner).bySlug(slug);
  @override
  Future<AreaGuide?> area(String slug) async => (await _inner).area(slug);
  @override
  Future<AgentProfile?> agent(String id) async => (await _inner).agent(id);
  @override
  Future<List<ListingSummary>> live({String? area, String? agentId, int limit = 30}) async =>
      (await _inner).live(area: area, agentId: agentId, limit: limit);
  @override
  Future<List<AreaGuide>> areas() async => (await _inner).areas();
  @override
  Future<List<OffPlanProject>> projects() async => (await _inner).projects();
  @override
  Future<OffPlanProject?> project(String slug) async => (await _inner).project(slug);
}

class DeferredLeadRepository implements LeadRepository {
  DeferredLeadRepository(this._inner);
  final Future<LeadRepository> _inner;

  @override
  Future<void> enquire({required String listingId, required String phone, String? name, String? message}) async =>
      (await _inner).enquire(listingId: listingId, phone: phone, name: name, message: message);
  @override
  Future<void> logTap({required String listingId, required String channel}) async =>
      (await _inner).logTap(listingId: listingId, channel: channel);
  @override
  Future<void> logRecommendation({required String listingId, required String event}) async =>
      (await _inner).logRecommendation(listingId: listingId, event: event);
  @override
  Future<List<String>?> openTimes({required String listingId, required String day}) async =>
      (await _inner).openTimes(listingId: listingId, day: day);
  @override
  Future<BookedViewing> bookViewing({required String listingId, required String slot, required String name, required String phone}) async =>
      (await _inner).bookViewing(listingId: listingId, slot: slot, name: name, phone: phone);
  @override
  Future<void> payViewingFee({required String viewingId, required String phone}) async =>
      (await _inner).payViewingFee(viewingId: viewingId, phone: phone);
}

class DeferredCustomerAccount implements CustomerAccount {
  DeferredCustomerAccount(this._inner);
  final Future<CustomerAccount> _inner;

  @override
  Stream<Customer?> get customer => Stream.fromFuture(_inner).asyncExpand((a) => a.customer);
  @override
  Future<void> sendSignInLink(String email, Uri continueUrl) async => (await _inner).sendSignInLink(email, continueUrl);
  @override
  Future<bool> completeSignInLink(Uri link, String email) async => (await _inner).completeSignInLink(link, email);
  @override
  Future<void> signInWithGoogle() async => (await _inner).signInWithGoogle();
  @override
  Future<void> signOut() async => (await _inner).signOut();
}

class DeferredAlertsRepository implements AlertsRepository {
  DeferredAlertsRepository(this._inner);
  final Future<AlertsRepository> _inner;

  @override
  Stream<List<SavedSearchRow>> searches(String uid) => Stream.fromFuture(_inner).asyncExpand((r) => r.searches(uid));
  @override
  Future<void> saveSearch(String uid, ListingFilters filters) async => (await _inner).saveSearch(uid, filters);
  @override
  Future<void> deleteSearch(String id) async => (await _inner).deleteSearch(id);
  @override
  Stream<List<AlertRow>> alerts(String uid) => Stream.fromFuture(_inner).asyncExpand((r) => r.alerts(uid));
  @override
  Future<void> markRead(String uid, String alertId) async => (await _inner).markRead(uid, alertId);
  @override
  Future<void> clear(String uid, String alertId) async => (await _inner).clear(uid, alertId);
}

class DeferredPushAlerts implements PushAlerts {
  DeferredPushAlerts(this._inner);
  final Future<PushAlerts> _inner;

  @override
  Future<bool> enable(String uid) async => (await _inner).enable(uid);
  @override
  Future<void> resume(String uid) async => (await _inner).resume(uid);
  @override
  Future<void> disable(String uid) async => (await _inner).disable(uid);
  @override
  Stream<String> get opened => Stream.fromFuture(_inner).asyncExpand((p) => p.opened);
}

class DeferredListingReviews implements ListingReviews {
  DeferredListingReviews(this._inner);
  final Future<ListingReviews> _inner;

  @override
  Future<List<ListingReview>> forListing(String listingId) async => (await _inner).forListing(listingId);

  @override
  Future<void> submit({required String listingId, required int rating, required String comment, String? name}) async =>
      (await _inner).submit(listingId: listingId, rating: rating, comment: comment, name: name);
}
