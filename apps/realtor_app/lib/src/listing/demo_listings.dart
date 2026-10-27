import 'package:realtor_core/realtor_core.dart';

import '../search/demo_search.dart';

const _agents = [
  ListingAgent(id: 'agent-wanjiku', name: 'Wanjiku Mwangi', phone: '+254700000101', whatsapp: '+254700000101'),
  ListingAgent(id: 'agent-otieno', name: 'Brian Otieno', phone: '+254700000102', whatsapp: '+254700000102'),
  ListingAgent(id: 'agent-achieng', name: 'Achieng Odhiambo', phone: '+254700000103', whatsapp: '+254700000103'),
];

/// Listing details for the demo listings, until the app reads Firestore.
class DemoListingRepository implements ListingRepository {
  @override
  Future<ListingDetail?> bySlug(String slug) async {
    for (final (i, l) in demoListings.indexed) {
      if (l.slug == slug) {
        return ListingDetail(
          summary: l,
          depositMonths: l.purpose == Purpose.rent ? (l.type == 'hostel' ? 1 : 2) : null,
          agent: _agents[i % _agents.length],
        );
      }
    }
    return null;
  }
}

/// Keeps leads in memory until the app calls the Functions. Nothing leaves
/// the phone, so no personal data is stored anywhere.
class DemoLeadRepository implements LeadRepository {
  final enquiries = <Map<String, String?>>[];
  final taps = <String>[];
  final viewings = <Map<String, String>>[];

  @override
  Future<void> enquire({required String listingId, required String phone, String? name, String? message}) async =>
      enquiries.add({'listingId': listingId, 'phone': phone, 'name': name, 'message': message});

  @override
  Future<void> logTap({required String listingId, required String channel}) async => taps.add('$listingId/$channel');

  @override
  Future<void> bookViewing({required String listingId, required String slot, required String name, required String phone}) async =>
      viewings.add({'listingId': listingId, 'slot': slot, 'name': name, 'phone': phone});
}
