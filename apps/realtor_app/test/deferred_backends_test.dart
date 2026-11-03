import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:realtor_app/src/account/account_data.dart';
import 'package:realtor_app/src/firebase/deferred_backends.dart';
import 'package:realtor_app/src/search/demo_search.dart';
import 'package:realtor_core/realtor_core.dart';

void main() {
  test('calls wait for the backend, then go to it', () async {
    final start = Completer<ListingSearch>();
    final search = DeferredListingSearch(start.future);
    var done = false;
    final result = search.search(const ListingFilters(purpose: Purpose.rent)).then((r) {
      done = true;
      return r;
    });
    await Future<void>.delayed(Duration.zero);
    expect(done, isFalse, reason: 'still starting');
    start.complete(DemoListingSearch(demoListings));
    expect((await result).hits, isNotEmpty);
  });

  test('a backend that fails to start fails each call, not the app', () async {
    final repo = DeferredListingRepository(Future<ListingRepository>.error(StateError('no network'))..ignore());
    await expectLater(repo.bySlug('x'), throwsStateError);
    await expectLater(repo.areas(), throwsStateError);
    final leads = DeferredLeadRepository(Future<LeadRepository>.error(StateError('no network'))..ignore());
    await expectLater(leads.logTap(listingId: 'l', channel: 'call'), throwsStateError);
  });

  test('streams start once the backend is ready', () async {
    final demo = DemoAccount();
    final start = Completer<DemoAccount>();
    final account = DeferredCustomerAccount(start.future);
    final alerts = DeferredAlertsRepository(start.future);
    final first = account.customer.first;
    final searches = alerts.searches('demo-customer').first;
    start.complete(demo);
    expect(await first, isNull);
    expect(await searches, isEmpty);
    await account.signInWithGoogle();
    expect(await account.customer.first, isNotNull);
  });
}
